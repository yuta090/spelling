#!/usr/bin/env bash
# なかまを目視チェックするための「プレビュー起動」ヘルパー（Mac 専用）。
# ビルド → iPad シミュレータを起動 → アプリをインストール → 起動 までを1コマンドで。
#
# 使い方:
#   scripts/preview_sim.sh [project_dir]
#     project_dir 省略時は CWD から上方向に *.xcodeproj を探し、無ければ本体リポジトリを使う。
#     統合作業中はワークツリーのパスを渡すと、その作業ツリーの内容でプレビューできる。
#       例: scripts/preview_sim.sh /Users/takahashiyuuta/scripts/SpellingTrainer-wt/<branch>
#
# 環境変数:
#   SCHEME   既定 "SpellingTrainer"
#   SIM_NAME 起動済みが無いとき選ぶ iPad シミュレータ名の部分一致（既定 "iPad"）
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "⛔ プレビュー起動は Mac (Darwin) 専用です。ここではビルド確認のみ行ってください。" >&2
  exit 2
fi

SCHEME="${SCHEME:-SpellingTrainer}"
SIM_NAME="${SIM_NAME:-iPad}"

# 1) プロジェクト位置を決める
PROJECT_DIR="${1:-}"
if [[ -z "${PROJECT_DIR}" ]]; then
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    if ls "$d"/*.xcodeproj >/dev/null 2>&1; then PROJECT_DIR="$d"; break; fi
    d="$(dirname "$d")"
  done
fi
PROJECT_DIR="${PROJECT_DIR:-/Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab}"
XCPROJ=$(ls -d "$PROJECT_DIR"/*.xcodeproj 2>/dev/null | head -1 || true)
if [[ -z "$XCPROJ" ]]; then
  echo "⛔ *.xcodeproj が見つかりません: $PROJECT_DIR" >&2
  exit 1
fi
echo "▶ project: $XCPROJ (scheme: $SCHEME)"

# 2) シミュレータを選ぶ（起動済み iPad 優先 → 無ければ利用可能な iPad の先頭）
udid_from() { grep -oE "\([0-9A-Fa-f-]{36}\)" | tr -d '()' | head -1; }
SIM=$(xcrun simctl list devices booted 2>/dev/null | grep -i "$SIM_NAME" | udid_from || true)
if [[ -z "$SIM" ]]; then
  SIM=$(xcrun simctl list devices available 2>/dev/null | grep -i "$SIM_NAME" | udid_from || true)
fi
if [[ -z "$SIM" ]]; then
  echo "⛔ '$SIM_NAME' に一致する iPad シミュレータが見つかりません。Xcode の Settings → Platforms で追加してください。" >&2
  exit 1
fi
echo "▶ simulator: $SIM"

# 3) ビルド（選んだ実機 ID 宛て＝destination ミスマッチを避ける）
echo "▶ building…"
xcodebuild -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator \
  -destination "id=$SIM" build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3

# 4) ビルド成果物(.app)の場所を build settings から確実に取得
APP_DIR=$(xcodebuild -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator \
  -destination "id=$SIM" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
APP="$APP_DIR/$SCHEME.app"
if [[ ! -d "$APP" ]]; then
  echo "⛔ ビルド成果物が見つかりません: $APP" >&2
  exit 1
fi

# 5) 起動 → インストール → ラウンチ
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
open -a Simulator
xcrun simctl install "$SIM" "$APP"
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl launch "$SIM" "$BID" >/dev/null
echo "✅ プレビュー起動: $BID （子のショップ→ひと／親→なかま管理 で目視チェック）"
echo "ℹ️ チェック後は Simulator を閉じてOK（xcrun simctl shutdown $SIM でも可）"
