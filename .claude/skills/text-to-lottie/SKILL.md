---
name: text-to-lottie
description: >
  テキストの意図（「星がキラッと光る」「できた！のチェック」「紙吹雪」等）から Lottie アニメ(.json)を
  python-lottie で組み立てて作るスキル。生成→GIF/HTMLでプレビュー検証→.json を出す。
  子ども向けアプリの“ごほうび/反応”語彙のプリセット(star-sparkle / pop-in / bounce / check-pop /
  heart-beat / confetti)を同梱、新しい動きはプリミティブを組み合わせて足す。
  トリガー:「Lottieを作りたい」「ロッティ」「lottie」「アニメJSON」「ごほうびアニメ」
  「キラッと光る/ポンと出る/はずむ/チェック/紙吹雪のアニメ」。
  ⚠ ラスター画像(PNG/背景)は home-background-gen、キャラは nakama-character-gen。こちらは“ベクターアニメ(Lottie)”専用。
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# text → Lottie 生成（text-to-lottie）

テキストで言った動きを **Lottie アニメ（`.json`）** にする。エンジンは **python-lottie**（同梱 `.venv`）。
Lottie には「文章→アニメ」の生成モデルが無いので、**python でパラメトリックに組み立てる**のがこのスキルの方式。

## 大方針（必ず守る）
- **純ロジックで決定論的に作る。** `scripts/build_lottie.py` を import して組む。**乱数禁止**（再現性のため、ばらけは index ベース）。
- **作ったら必ずプレビューで目視検証する。** `scripts/preview.sh` で GIF（ぱっと見・Read で確認）と HTML（lottie-web で実再生）を出す。**完了報告を鵜呑みにせず、Claude も Read で実体を見る**。
- **子ども向けのトーン**（やわらかフラット・原色やや明るめ・大きい動き・オーバーシュートで“バネっぽさ”）。パレットは `COLORS`。
- **新しい見た目を不用意に増やさない。** まず既存プリセット／プリミティブの組み合わせで作れないか考える。
- スキル本体は `.claude/`（git 管理外）なので編集に PR は不要。**アプリ本体（Swift/アセット）に Lottie を載せる統合フェーズだけは別ブランチ/ワークツリーで**（`main` で作業しない／CLAUDE.md 準拠）。

## セットアップ（初回・済んでいれば不要）
同梱 venv に python-lottie + cairosvg を入れてある。壊れていたら再構築:
```bash
cd .claude/skills/text-to-lottie
python3 -m venv .venv
.venv/bin/pip install lottie pillow cairosvg
```
GIF/PNG プレビューは cairosvg（→ Homebrew の cairo）に依存。macOS は `brew install cairo` 済み前提。
HTML プレビューは cairo 不要。

## 手順
1. **意図を1つに絞る**（1ファイル=1アニメ）。「いつ・何が・どう動く」を言語化（例: 正解時に緑の丸が出てチェックがポンと付く＝`check-pop`）。
2. **プリセットで足りるか確認**: `.venv/bin/python scripts/build_lottie.py --list`
   - 足りる → 書き出す: `.venv/bin/python scripts/build_lottie.py --preset check-pop --out /path/out.json`
   - 足りない → **3 へ**（新規作成）。
3. **新規作成**: `scripts/build_lottie.py` を import して python スクリプトを書く（`reference/python-lottie-cheatsheet.md` のレシピ／ハマりどころを必ず読む）。
   - 中心で回す/脈打たせる物は `pivot(group, center)` を呼ぶ（既定 anchor=(0,0) で飛ぶ）。
   - 前面に出したい物は**先に** add する（描画順は先＝前面）。
   - draw-on（線が描かれていく）は Trim だが **GIFプレビューに出ない**→ html か実機で確認、または scale/opacity で“出す”。
   - 汎用的で再利用しそうなら **プリセットとして `PRESETS` に登録**する。
4. **プレビュー検証**: `bash scripts/preview.sh /path/out.json`（gif+html を生成して開く）。
   - 静止確認だけなら `.venv/bin/lottie_convert.py out.json frame.png --frame N` → Read で見る。
   - 意図どおりか目視。崩れていたら 3 に戻る（よくある原因＝描画順・pivot・Trim、cheatsheet参照）。
5. **成果物の置き場所を確認してから配置**。指示が無ければ出力先を聞く（勝手にアプリ配下へ置かない）。

## プリセット（同梱・“ごほうび/反応”語彙）
| name | 意図 | 主な技法 |
|---|---|---|
| `star-sparkle` | 星がキラッと光る | star + scale/opacity/rotation + 周囲のきらめき |
| `pop-in` | ポンと出る（汎用の登場） | オーバーシュート scale |
| `bounce` | はずむ | position の上下往復 |
| `check-pop` | できた！丸＋チェックが出る | 描画順(チェックを前面)＋pop |
| `heart-beat` | ハートが脈打つ | 2円+45°四角、pivot で中心拍動 |
| `confetti` | 紙吹雪が舞う | index で決定論配置→落下+回転+フェード |

## 出力フォーマット
- **`.json`** … Lottie 本体（成果物。これを納品/アプリに載せる）
- **`.html`** … lottie-web で実再生（Trim も動く・cairo 不要）
- **`.gif` / `.png`** … 確認用（Read で見える・cairo 必須）
- **`.tgs`** … Telegram ステッカー（必要なら）

## 注意事項
- **iOS 統合は未配線**。本リポジトリはまだ Lottie 未使用。載せるなら lottie-ios(SwiftPM) を別ブランチで追加（cheatsheet 末尾参照）。
- `.venv` はこのスキル専用。サイズが大きいので他所へコピーしない。
- 詳細 API・ハマりどころは **`reference/python-lottie-cheatsheet.md`**（実証済み）。
