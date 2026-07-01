#!/usr/bin/env bash
# agy で『なかま』透過素材を量産する(画像/WebPルート・codex不要)。
# agy は真のアルファを出せないが、マゼンタ単色背景の不透過画像なら量産できる。
# → agy がマゼンタ地で生成 → こちらで自動クロマキー切り抜き → 透過 WebP。
#
# 使い方:
#   scripts/cutout_agy.sh <id> [variations] [size]
#   例: scripts/cutout_agy.sh sample_hamster 6 512
#
# 出力: out/final/<id>/<id>_v1.webp .. _vN.webp (+ _vN.png) ＋ _contact_sheet.png
#       気に入った1枚を <id>.webp として採用(リネーム)する。
#
# 注意(memory: agy-cli-reliable-invocation):
#  - 非TTYで stdout が消える → script -q /dev/null で pseudo-TTY 化
#  - 実バイナリ＋ --dangerously-skip-permissions を明示・alias に頼らない
#  - cwd 無視で ~/.gemini/antigravity-cli/scratch に書く → そこから回収・実体を find で確認
set -euo pipefail

ID="${1:?usage: cutout_agy.sh <id> [variations] [size]}"
N="${2:-6}"
SIZE="${3:-512}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(dirname "$HERE")"
RAW="$SKILL/out/final/$ID/_raw"
OUT="$SKILL/out/final/$ID"
AGY="/Users/takahashiyuuta/.local/bin/agy"
SCRATCH="$HOME/.gemini/antigravity-cli/scratch"
mkdir -p "$RAW" "$OUT"

# build_prompt --mode finalize がマゼンタ背景指定込みのプロンプトを出す
PROMPT_BODY="$(python3 "$HERE/build_prompt.py" --id "$ID" --mode finalize)"

for i in $(seq 1 "$N"); do
  fname="cutout_${ID}_v${i}.png"
  echo "=== [$i/$N] agy generating $fname (magenta bg) ==="
  FULL="$PROMPT_BODY

組み込みの image_gen ツールで上記を生成し、必ず PNG 形式でカレントに '$fname' として保存して(JPEGで作ったら sips でPNGに変換)。
背景は #FF00FF の完全に均一なマゼンタべた塗り・グラデや影を入れない・被写体にマゼンタを使わない(後で切り抜く)。
バリエーション #$i なので前回と少しポーズ/表情を変えて。保存後 'file $fname' を実行して報告。"

  script -q /dev/null "$AGY" --dangerously-skip-permissions --print-timeout 300s \
    -p "$FULL" 2>&1 | tr -d '\r' | tail -6 || true

  found="$(find "$SCRATCH" -name "$fname" -type f 2>/dev/null | head -1 || true)"
  [ -z "$found" ] && found="$(find "$SCRATCH" -name '*.png' -type f -mmin -2 2>/dev/null | sort | tail -1 || true)"
  if [ -z "$found" ]; then
    echo "  ⚠ scratch に生成物が無い。手動確認: $SCRATCH"; continue
  fi
  cp "$found" "$RAW/v${i}.png"
  # 自動キーで切り抜き → WebP
  python3 "$HERE/finalize_image.py" "$RAW/v${i}.png" --id "${ID}_v${i}" --out "$OUT" \
    --chroma --autokey --size "$SIZE" --png || true
done

echo "=== building cutout contact sheet ==="
python3 "$HERE/contact_sheet.py" "$OUT" --cols "$N" || true
echo "done. 確認: $OUT/_contact_sheet.png"
echo "採用するなら: mv $OUT/${ID}_vK.webp $OUT/${ID}.webp"
