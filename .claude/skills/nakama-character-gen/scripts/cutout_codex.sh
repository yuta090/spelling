#!/usr/bin/env bash
# codex CLI(`codex exec`)の built-in image_gen で『なかま』完成画像をクリーンに量産する。
# codex は PNG 直出力でノイズが無い(出荷アセット向き)。弱点だった「遅い」を CLI 並列で解消する。
#
# 速度(実機計測 2026-06-29): codex は ~109s/枚だが MCP は直列がボトルネック。
#   CLI を別プロセスで並列起動すれば 3枚=126s(=ほぼ1枚分)。→ 並列度 C で N 枚 ≈ ceil(N/C)*~120s。
#   例: 20枚を並列度5 ≈ 5分(MCP直列なら ~36分)。速さ最優先・小表示主体なら agy(cutout_agy.sh)。
#
# 使い方:
#   scripts/cutout_codex.sh <id> [variations] [size] [concurrency]
#   例: scripts/cutout_codex.sh hamster 6 512 5
#
# 出力: out/final/<id>/_raw/vK.png (codex 生出力) → out/final/<id>/<id>_vK.webp(+png) ＋ _contact_sheet.png
#       気に入った1枚を <id>.webp として採用(リネーム)する。
#
# 落とし穴対策(実機 2026-06-29 で判明):
#  - codex の image_gen は ~/.codex/generated_images/<session>/ig_*.png に出る共有ディレクトリ。
#    「最新PNGをcp」させると並列で別セッションの画像を掴むレースが起きる(3枚目が無関係な画像になった)。
#  - 対策: 保存先の絶対パスをこちらが指定し、『このセッションで今あなたが生成した画像だけ』を
#    その絶対パスへ cp させる(グローバル検索させない)。生成後に file/ls で実体検証。
set -euo pipefail

ID="${1:?usage: cutout_codex.sh <id> [variations] [size] [concurrency]}"
N="${2:-6}"
SIZE="${3:-512}"
CONC="${4:-5}"
MAX_SECS="${CODEX_MAX_SECS:-360}"   # 1体あたりの上限秒。超えたら kill(暴走1体で全体が止まるのを防ぐ)
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(dirname "$HERE")"
RAW="$SKILL/out/final/$ID/_raw"
OUT="$SKILL/out/final/$ID"
CODEX="$(command -v codex || echo /Users/takahashiyuuta/.nvm/versions/node/v22.18.0/bin/codex)"
mkdir -p "$RAW" "$OUT"

# build_prompt --mode finalize がマゼンタ背景指定込みの本体プロンプトを出す(agy と共通)
PROMPT_BODY="$(python3 "$HERE/build_prompt.py" --id "$ID" --mode finalize)"

# 1体ぶんの生成(codex exec)→ finalize。バックグラウンドで並列起動する想定。
gen_one() {
  local i="$1"
  local dest="$RAW/v${i}.png"
  local log="$RAW/_codex_v${i}.log"
  rm -f "$dest"
  local full="$PROMPT_BODY

【保存(厳守・最短手順)】組み込みの image_gen ツールで上記キャラを1体だけ生成して。
- 背景は #FF00FF の均一なマゼンタべた塗り。グラデ/影なし。被写体にマゼンタ色を使わない(後でこちらがクロマキー透過する)。
- バリエーション #$i: 前回と少しポーズ/表情を変えて。
- ⚠ 余計な後処理は一切しない: PIL/sips での再合成・背景の作り直し・色の貼り直し・複数回生成・品質確認のための再生成はしない。背景が多少不均一でも後段で処理するので、image_gen が出した PNG を“そのまま”使う。
- 生成できたら『このセッションであなたが今生成した画像だけ』を、シェルの cp で必ず次の絶対パスへ保存して:
  $dest
  他のセッションや既存の生成画像・最新ファイル検索などは絶対に使わない(取り違え防止)。
- もし image_gen が JPEG しか返さない時だけ sips で1回 PNG 変換して上記パスへ。
- 最後に 'file $dest' を1回実行して終了。"

  echo "=== [v$i] codex generating -> $dest ==="
  # 画像生成に深い推論は不要。effort=low 固定で速度と所要時間のブレを抑える(既定 xhigh だと自走して数分かかる)。
  # macOS に timeout が無いので watchdog を自前で: codex をバックグラウンド起動→上限秒で kill。
  "$CODEX" exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \
    -c model_reasoning_effort="low" \
    -C "$RAW" "$full" >"$log" 2>&1 &
  local cpid=$!
  local waited=0
  while kill -0 "$cpid" 2>/dev/null; do
    sleep 3; waited=$((waited+3))
    if [ "$waited" -ge "$MAX_SECS" ]; then
      echo "  ⏱ [v$i] ${MAX_SECS}s 超過 → kill"; kill -TERM "$cpid" 2>/dev/null || true
      sleep 2; kill -KILL "$cpid" 2>/dev/null || true; break
    fi
  done
  wait "$cpid" 2>/dev/null || true

  if [ ! -f "$dest" ]; then
    # フォールバック: codex がログに残した生成元パスを拾って自分でコピー
    local src
    src="$(grep -oE '/Users/[^ ]*generated_images/[^ ]*\.png' "$log" 2>/dev/null | tail -1 || true)"
    if [ -n "$src" ] && [ -f "$src" ]; then
      cp "$src" "$dest"; echo "  [v$i] recovered from log: $src"
    else
      echo "  ⚠ [v$i] 生成物が見つからない。ログ確認: $log"; return 0
    fi
  fi
  # クリーンPNG前提でクロマキー→trim/pad→WebP(+png)
  python3 "$HERE/finalize_image.py" "$dest" --id "${ID}_v${i}" --out "$OUT" \
    --chroma --autokey --size "$SIZE" --png || true
  echo "  ✓ [v$i] done"
}

# 並列度 CONC でスロットル起動
for i in $(seq 1 "$N"); do
  gen_one "$i" &
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$CONC" ]; do sleep 1; done
done
wait

echo "=== building codex contact sheet ==="
python3 "$HERE/contact_sheet.py" "$OUT" --cols "$N" || true
echo "done. 確認: $OUT/_contact_sheet.png"
echo "採用するなら: mv $OUT/${ID}_vK.webp $OUT/${ID}.webp"
