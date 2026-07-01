#!/usr/bin/env bash
# agy で『なかま』デザイン案を量産する(探索フェーズ・白背景)。
# agy は本物の透過を出せないので、ここは「案を見て選ぶ」のが目的。
#
# 使い方:
#   scripts/explore_agy.sh <id> [variations]
#   例: scripts/explore_agy.sh sample_hamster 4
#
# 出力: out/explore/<id>/v1.png .. vN.png  ＋ _contact_sheet.png
#
# 注意(agy 既知の癖, memory: agy-cli-reliable-invocation):
#  - 非TTYだと stdout が消える → script -q /dev/null で pseudo-TTY 化
#  - alias を当てにせず実バイナリ＋ --dangerously-skip-permissions を明示
#  - cwd を無視して ~/.gemini/antigravity-cli/scratch に書く → そこから回収する
set -euo pipefail

ID="${1:?usage: explore_agy.sh <id> [variations]}"
N="${2:-4}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(dirname "$HERE")"
OUT="$SKILL/out/explore/$ID"
AGY="/Users/takahashiyuuta/.local/bin/agy"
SCRATCH="$HOME/.gemini/antigravity-cli/scratch"
mkdir -p "$OUT"

PROMPT_BODY="$(python3 "$HERE/build_prompt.py" --id "$ID" --mode explore)"

for i in $(seq 1 "$N"); do
  fname="explore_${ID}_v${i}.png"
  echo "=== [$i/$N] generating $fname ==="
  FULL="$PROMPT_BODY

組み込みの image_gen ツールで上記を生成し、カレントに '$fname' という名前の PNG で保存して。
保存後に 'file $fname' を実行して寸法を報告して。バリエーション #$i なので、前のとは少しポーズや表情を変えて。"

  script -q /dev/null "$AGY" --dangerously-skip-permissions --print-timeout 300s \
    -p "$FULL" 2>&1 | tr -d '\r' | tail -8 || true

  # scratch から回収(報告を鵜呑みにせず実体を探す)
  found="$(find "$SCRATCH" -name "$fname" -type f 2>/dev/null | head -1 || true)"
  if [ -z "$found" ]; then
    # 名前が違う可能性 → 直近1分の新しい png を拾う
    found="$(find "$SCRATCH" -name '*.png' -type f -mmin -2 2>/dev/null | sort | tail -1 || true)"
  fi
  if [ -n "$found" ]; then
    cp "$found" "$OUT/v${i}.png"
    echo "  collected -> $OUT/v${i}.png"
  else
    echo "  ⚠ 生成物が scratch に見つからない。agy の出力を手動確認: $SCRATCH"
  fi
done

echo "=== building contact sheet ==="
python3 "$HERE/contact_sheet.py" "$OUT" --cols "$N" || true
echo "done. 確認: $OUT/_contact_sheet.png"
