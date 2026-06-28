#!/usr/bin/env bash
# =============================================================================
# test.sh — Supabase 非依存の SQL/RLS テストランナー（Docker 不要）
#
#   素の Postgres に「Supabase スタブ(auth.uid 等) → 本番 migrations → テストSQL」を
#   順に流し、psql の ON_ERROR_STOP と DO ブロックの ASSERT で検証する。
#
#   * ローカル: postgres が入っていれば使い捨てクラスタを自動で initdb→起動→破棄。
#   * CI:       TEST_DATABASE_URL を渡せば、その DB に対して実行（postgres service 想定）。
#
# 使い方:
#   scripts/db/test.sh                 # ローカル使い捨てクラスタで実行
#   TEST_DATABASE_URL=postgres://... scripts/db/test.sh   # 既存DBに対して実行(CI)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
TESTS_DIR="$REPO_ROOT/supabase/tests"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
inf()  { printf '%s\n' "$*"; }

TMP_CLUSTER=""
PG_STARTED=0

cleanup() {
  if [ "$PG_STARTED" = "1" ] && [ -n "$TMP_CLUSTER" ]; then
    pg_ctl -D "$TMP_CLUSTER/data" stop -m immediate >/dev/null 2>&1 || true
  fi
  [ -n "$TMP_CLUSTER" ] && rm -rf "$TMP_CLUSTER" 2>/dev/null || true
}
trap cleanup EXIT

# --- 接続先を決める ---
if [ -n "${TEST_DATABASE_URL:-}" ]; then
  CONN="$TEST_DATABASE_URL"
  inf "Using TEST_DATABASE_URL"
else
  command -v initdb >/dev/null || { red "initdb が見つかりません（postgres を入れるか TEST_DATABASE_URL を指定）"; exit 1; }
  TMP_CLUSTER="$(mktemp -d)"
  inf "Spinning up throwaway Postgres cluster at $TMP_CLUSTER ..."
  initdb -D "$TMP_CLUSTER/data" -U postgres --no-locale -E UTF8 >/dev/null
  PORT=$(( (RANDOM % 2000) + 54000 ))
  pg_ctl -D "$TMP_CLUSTER/data" \
    -o "-k $TMP_CLUSTER -p $PORT -c listen_addresses=''" \
    -l "$TMP_CLUSTER/log" -w start >/dev/null
  PG_STARTED=1
  createdb -h "$TMP_CLUSTER" -p "$PORT" -U postgres spelling_test
  CONN="host=$TMP_CLUSTER port=$PORT user=postgres dbname=spelling_test"
fi

PSQL=(psql "$CONN" -v ON_ERROR_STOP=1 -X -q)

# --- 1) スタブ ---
inf "==> Applying Supabase stub"
"${PSQL[@]}" -f "$TESTS_DIR/harness/00_supabase_stub.sql"

# --- 2) 本番 migrations（ファイル名順） ---
inf "==> Applying migrations"
for f in $(ls "$MIGRATIONS_DIR"/*.sql | sort); do
  "${PSQL[@]}" -f "$f"
done

# --- 3) テスト（harness 配下を除く *.sql をファイル名順に） ---
inf "==> Running tests"
shopt -s nullglob
fail=0
for t in $(ls "$TESTS_DIR"/*.sql 2>/dev/null | sort); do
  inf "--- $(basename "$t")"
  if "${PSQL[@]}" -f "$t"; then
    grn "    ok"
  else
    red "    FAILED: $t"
    fail=1
  fi
done

if [ "$fail" = "0" ]; then
  grn "ALL TESTS PASSED"
else
  red "TESTS FAILED"
  exit 1
fi
