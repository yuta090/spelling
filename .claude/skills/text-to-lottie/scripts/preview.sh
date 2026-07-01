#!/usr/bin/env bash
# preview.sh — Lottie(.json) を確認用に変換して開く。
#   ./preview.sh path/to/anim.json [--no-open]
# 生成物: 同じ場所に .gif（ぱっと見・Read で確認可）と .html（lottie-web で実再生）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/../.venv"
CONVERT="$VENV/bin/lottie_convert.py"

if [[ ! -x "$CONVERT" ]]; then
  echo "venv が見つかりません: $VENV  （SKILL.md のセットアップ手順を実行してください）" >&2
  exit 1
fi

IN="${1:?usage: preview.sh anim.json [--no-open]}"
OPEN=1
[[ "${2:-}" == "--no-open" ]] && OPEN=0

base="${IN%.json}"
GIF="$base.gif"
HTML="$base.html"

"$CONVERT" "$IN" "$GIF" >/dev/null 2>&1 && echo "gif : $GIF"
"$CONVERT" "$IN" "$HTML" >/dev/null 2>&1 && echo "html: $HTML"

if [[ "$OPEN" == "1" ]]; then
  # macOS: GIF は Preview、HTML は既定ブラウザで開く
  command -v open >/dev/null && open -a Preview "$GIF" 2>/dev/null || true
  command -v open >/dev/null && open "$HTML" 2>/dev/null || true
fi
