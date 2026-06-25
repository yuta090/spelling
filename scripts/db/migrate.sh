#!/usr/bin/env bash
# =============================================================================
# migrate.sh — Supabase CLI に依存しない汎用マイグレーション・ランナー
#
#   psql だけで動く。.env.local から接続情報を読み、supabase/migrations/*.sql を
#   ファイル名順に「未適用のものだけ」トランザクションで適用し、schema_migrations に記録する。
#   他プロジェクトへも環境変数の上書きだけで流用可。
#
# 使い方:
#   scripts/db/migrate.sh status     # 適用済み/未適用を一覧
#   scripts/db/migrate.sh up         # 未適用を順に適用（既定）
#   scripts/db/migrate.sh baseline   # 既存DBに合わせ「全ファイルを“流さず”適用済みとして記録」
#
# 接続（優先順位）:
#   1) SUPABASE_DB_URL（フル接続文字列。例: postgresql://postgres:PW@host:5432/postgres?sslmode=require）
#   2) SUPABASE_PROJECT_REF + SUPABASE_DB_PASSWORD（direct: db.<ref>.supabase.co:5432 を組み立て）
#
# 上書き可能な環境変数:
#   ENV_FILE         (default: <repo>/.env.local)
#   MIGRATIONS_DIR   (default: <repo>/supabase/migrations)
# =============================================================================
set -euo pipefail

CMD="${1:-up}"

# --- パス解決（このスクリプトの2つ上をリポジトリルートとみなす） ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env.local}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$REPO_ROOT/supabase/migrations}"

err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }
inf() { printf '%s\n' "$*"; }

[ -f "$ENV_FILE" ] || { err "ENV_FILE が見つかりません: $ENV_FILE"; exit 1; }
[ -d "$MIGRATIONS_DIR" ] || { err "MIGRATIONS_DIR が見つかりません: $MIGRATIONS_DIR"; exit 1; }

# --- .env.local を安全に読み込む（KEY=VALUE のみ。実行はしない） ---
load_env() {
  local key val
  while IFS='=' read -r key val; do
    case "$key" in ''|\#*) continue;; esac
    val="${val%$'\r'}"                       # 末尾CR除去
    export "$key=$val"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE")
}
load_env

# --- 接続の決定 ---
PSQL_CONN=""
if [ -n "${SUPABASE_DB_URL:-}" ]; then
  PSQL_CONN="$SUPABASE_DB_URL"
elif [ -n "${SUPABASE_PROJECT_REF:-}" ] && [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
  export PGPASSWORD="$SUPABASE_DB_PASSWORD"
  PSQL_CONN="host=db.${SUPABASE_PROJECT_REF}.supabase.co port=5432 user=postgres dbname=postgres sslmode=require connect_timeout=10"
else
  err "接続情報が不足: SUPABASE_DB_URL か (SUPABASE_PROJECT_REF + SUPABASE_DB_PASSWORD) を .env.local に設定してください"
  exit 1
fi

psqlc() { psql "$PSQL_CONN" -w -v ON_ERROR_STOP=1 --no-psqlrc -qtA "$@"; }

# --- 接続確認 ---
if ! psqlc -c "select 1" >/dev/null 2>&1; then
  err "DBに接続できません（再起動中/一時停止/接続情報ミスの可能性）。少し待って再実行してください。"
  exit 1
fi

# --- 追跡テーブル（API非公開のため RLS 有効＋ポリシー無し＝anon/authenticated は読めない） ---
ensure_table() {
  psqlc <<'SQL' >/dev/null
create table if not exists public.schema_migrations (
  version    text primary key,
  checksum   text,
  applied_at timestamptz not null default now()
);
alter table public.schema_migrations enable row level security;
SQL
}

checksum_of() { shasum -a 256 "$1" | awk '{print $1}'; }

applied_versions() { psqlc -c "select version from public.schema_migrations order by version"; }

list_files() { find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' | sort; }

cmd_status() {
  ensure_table
  local applied; applied="$(applied_versions || true)"
  inf "== migrations =="
  local f v
  for f in $(list_files); do
    v="$(basename "$f")"
    if grep -qx "$v" <<<"$applied"; then ok "  [applied] $v"; else inf "  [pending] $v"; fi
  done
}

cmd_up() {
  ensure_table
  local applied; applied="$(applied_versions || true)"
  local f v sum count=0
  for f in $(list_files); do
    v="$(basename "$f")"
    sum="$(checksum_of "$f")"
    if grep -qx "$v" <<<"$applied"; then
      # ドリフト検知（適用済みファイルが後から変わっていないか）
      local rec; rec="$(psqlc -c "select checksum from public.schema_migrations where version='$v'")"
      [ "$rec" = "$sum" ] || err "  ⚠ drift: $v は適用済みだが内容が変わっています（記録:$rec / 現在:$sum）"
      continue
    fi
    inf "  applying $v ..."
    # 1ファイル=1トランザクション。失敗で全ロールバック（記録も入らない）。
    psql "$PSQL_CONN" -w -v ON_ERROR_STOP=1 --no-psqlrc -q <<SQL
begin;
\i $f
insert into public.schema_migrations(version, checksum) values ('$v', '$sum');
commit;
SQL
    ok "  ✅ $v"
    count=$((count+1))
  done
  ok "done. applied $count migration(s)."
}

cmd_baseline() {
  ensure_table
  local f v sum
  for f in $(list_files); do
    v="$(basename "$f")"; sum="$(checksum_of "$f")"
    psqlc -c "insert into public.schema_migrations(version,checksum) values ('$v','$sum') on conflict (version) do nothing" >/dev/null
    ok "  marked applied (no run): $v"
  done
  inf "baseline 完了。以後は up で差分のみ適用されます。"
}

case "$CMD" in
  status)   cmd_status ;;
  up)       cmd_up ;;
  baseline) cmd_baseline ;;
  *) err "unknown command: $CMD（status | up | baseline）"; exit 1 ;;
esac
