---
name: nakama-character-gen
description: >
  SpellingTrainer の「なかま」(cast/仲間＝親が登録する仲間が選ぶ、カタログの1枚絵キャラ) を新規に作るスキル。
  作りたいものが既存173種と被らないか重複チェックし、agy で案を量産→選定→①SwiftUI高品質描画 か ②透過WebP画像 に仕上げてアプリに載せる。
  トリガー:「なかまを作りたい」「なかま追加」「新しいなかま」「なかまキャラ」「なかま画像」「なかまを量産」「なかまの画質上げて」「なかま重複チェック」「なかまをプレビューで確認」「なかまをシミュレータで見たい」。
  ⚠ 服や髪を着せ替える“アバター/着せ替え”は別スキル avatar-dressup-gen。こちらは“なかま(完成した1枚絵キャラ)”専用で、着せ替えパーツは扱わない。
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, mcp__codex__codex
---

# なかまキャラ生成（nakama-character-gen）

SpellingTrainer の「**なかま**」(親が登録する仲間・`CastPerson.avatarCharacterID` が参照する `HomeRewardCharacter`) のキャラを、**案出し → 選定 → 仕上げ → アプリ搭載** まで効率よく回すスキル。

## 大方針（必ず守る）

- **量産は agy が主役**。速くて枚数を稼げる。**agy は本物の透過(アルファ)を直接は出せない**（透過指定すると JPEG＋偽チェッカー柄になる／実機検証 2026-06-28）が、**マゼンタ単色背景の不透過画像なら量産できる**。
  - **探索**：白背景で案出し（`explore_agy.sh`）。どんなキャラにするか選ぶ用途。
  - **透過素材の量産**：agy にマゼンタ地で生成させ、**こちら側で自動クロマキー切り抜き**して透過 WebP にする（`cutout_agy.sh`）。実機検証 2026-06-28＝縁にマゼンタのハロも無く綺麗に抜けた。**画像ルートも codex 無しで agy の量産力だけで回せる**。
- **codex は任意のフォールバック**。codex image_gen は単色クロマキー背景で生成→自前で本物のアルファに変換できる（RGBA・実機検証 2026-06-28）。少数精鋭・より高精細・直接アルファが欲しいときに使う。
- **画風の一貫性 = reference + repeated-preserve-list**。`spec.json` の `house_style` を毎回プロンプトに再掲し、`candidates.csv` の1行（concept/色）だけ差し替える。
- **出力は2モード（モードS=従来のSwiftUI描画 / モードW=WebP画像）**。指定が無ければ着手前に必ずどちらか確認し、**着手時に「今どちらのモードか・なぜか・違い（色変え可否/容量/配線要否）」を必ず説明してから作る**（詳細は「どう頼むか」「作成時の説明ルール」）。
- **codex の呼び出しは Claude（このセッション）が `mcp__codex__codex` で行う**（OpenAI APIキー不要・サブスク内）。agy は Bash から `script -q /dev/null` 経由で呼ぶ。
- **アプリのコード/CSV を触る統合フェーズは、必ずブランチ/ワークツリーを切ってから**（`main` で作業しない／CLAUDE.md 準拠）。このスキル本体は `.claude/`（git 管理外）なのでスキル編集自体は `main` でも可。

## 2つの出力モード（探索は共通・出力で分岐）

| | モードS：SwiftUI 描画 | モードW：WebP 画像 |
|---|---|---|
| 成果物 | `XxxCharacterFace` View（既存173種と同流儀） | 透過 WebP（@1x/2x/3x 可） |
| 利点 | アセット0・**hex 再着色OK**・無限スケール・**セットが揃う** | 1枚の画質が高い・写実寄りも可 |
| 難所 | SwiftUI 表現に上限 | 画風統一が難・hex 再着色不可・サイズ増 |
| 仕上げ | codex が View を著作 → Claude がレビュー | **agy がマゼンタ地で量産 → 自動切り抜き → WebP**（`cutout_agy.sh`）。codex も可 |

**どちらが上ということはない。用途で選ぶ（「おすすめ」と誘導しない）。**
- **モードS が向くのは**：シンプルな絵でよく、**同じ形で色違いをたくさん**作りたい／軽くしたい／見た目を**統一**したいとき。
- **モードW が向くのは**：**1体ずつ凝った/リッチな絵**にしたい／写実寄りにしたいとき（色変え不可・容量増・アプリ配線が要る）。

### どう頼むか（頼み方で切り替わる）

| こう言われたら | 作るもの | ひとことで言うと |
|---|---|---|
| 「なかまを作って」「**いつもの方式**で」「**描画**で」「**SwiftUI**で」「**軽い**やつ」「**色が変えられる**やつ」「従来型」 | **モードS＝従来型（SwiftUI描画）** | 既存173種と同じ“コードで描く”キャラ。アセット0・色変え可・セットが揃う |
| 「なかまを**画像**で作って」「**WebP**で」「**画像ベース**で」「**絵**で」「**写実**っぽく」「**凝った**見た目で」 | **モードW＝WebP画像** | AIが描いた1枚絵を透過WebPに。見た目リッチだが色変え不可・容量増・アプリ配線が要る |

### 作成時の説明ルール（必ず守る）

- **モード指定がなければ、Claude は着手前に必ず確認する**。その際「おすすめ」と誘導せず、**両モードのメリットを並べて**用途で選んでもらう：「**シンプルな絵で色違いをたくさん作るなら『描画（モードS）』、1体ずつ凝った絵にするなら『画像WebP（モードW）』。どちらにしますか？**」
- **どちらで作るか決まったら、着手時に必ず1〜2行で説明してから始める**。最低限つぎを言う：
  1. 今 **どちらのモード**か（モードS＝SwiftUI描画 / モードW＝WebP画像）
  2. **なぜそれ**か（ユーザー指定／用途に合うから。「おすすめ」とは言わない）
  3. **違いの要点**：色変え（hex再着色）可否・容量・**アプリ配線の要否**（モードWは配線が未実装で要設計）
- 例:「これは**モードS（SwiftUI描画）**で作ります。既存と同じ方式なので色変更でき・容量0・すぐ使えます（WebP画像にすると絵は豪華ですが色変更不可＋アプリ側の配線が必要です）。」

### 迷っていそうなら案内を出す（必ず守る）

ユーザーが**作り方を分かっていなさそう**なとき（例:「なかま作りたいけどどうやるの？」、作りたい中身が曖昧、モードも名前も決まっていない、「おまかせ」等）は、**いきなり質問だけ返さず、まず下の短い案内を出す**。そのうえで「何を・どっちのモードで」を一緒に決める。

> **なかま作りのながれ（かんたん3ステップ）**
> 1. **何を作る？** 動物・乗りもの・食べもの…作りたいものを教えて（例：アルパカ）。→ 私が**既にあるか重複チェック**します。
> 2. **どっちで作る？**（どちらが上ではなく、用途で選んでね）
>    - **A. 描画（モードS）**…シンプルな絵が中心。**色違いをたくさん**・軽く・統一して作りたいならこっち。色変更でき・容量0・すぐ使える。
>    - **B. 画像（モードW・WebP）**…AIの絵で**1体ずつ凝った/豪華な見た目**にしたいならこっち。ただし色変更できず・容量が増え・**アプリ側の追加作業**が要る。
> 3. **おまかせ可**…「おまかせ」と言えば、重複しない案を私が提案します。

迷いが無く具体的（名前＋モードが明確）なら、この案内は省いてすぐ着手してよい。

---

## 使い方（フロー）

### 0. まず重複チェック（必須・既存173種と被らせない）
新しいなかまは「**既にあるもの**」と被ってはいけない。作りたいものが決まったら、まず既存カタログ（`scripts/characters.csv`・本物の171種）と照合する。
```bash
cd /Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab/.claude/skills/nakama-character-gen
python3 scripts/check_duplicate.py アルパカ あざらし          # 作りたい名前を渡す(日本語/英語どちらでも)
python3 scripts/check_duplicate.py --category animal          # そのカテゴリの既存を一覧で見る
python3 scripts/check_duplicate.py --all                      # 全カテゴリの既存一覧
python3 scripts/check_duplicate.py --tags                     # 付いている全タグを件数つきで一覧(ジャンル把握)
python3 scripts/check_duplicate.py --tag sea,fish             # タグで絞り込み(カンマ=AND)
python3 scripts/check_duplicate.py --tag swift                # 描画(モードS)のなかまだけ / --tag webp で画像(モードW)だけ
```
- 重複チェックの一致表示には**そのキャラの tags も出る**（何のジャンルか・swift/webp かが一目で分かる）。`--catalog <path>` で参照する characters.csv を明示もできる（worktree のCSVを見る等）。

> **タグ設計（ジャンル分け）**：本体 `scripts/characters.csv` に `tags` 列があり、既存全キャラに付与済み（背景スキルと同方式・`;`区切り）。並びは **①描画モード（`swift`=モードS / `webp`=モードW）→ ②category 由来のベース（animal/sea/vehicle…）→ ③横断属性（land/marine/europe/sweet 等）**。people は髪型を `hair-<style>`（hair-short / hair-afro …）で持つ。`category` は単一の大分類、`tags` は横断的に複数。**新規キャラを足すときは必ず `tags` を付ける**（先頭に swift/webp を必ず入れる）。`generate_characters.py` は列名読み（DictReader）で `tags` を無視するのでカタログ生成は壊れない。
- `⛔ 既に存在` が出たら**作らない**（別のキャラにする）。`⚠ 名前が近い`/`似てるかも` は要注意、被ってないか人が判断。`✅ 新規` なら OK。
- 重複が1つでもあると終了コード 1（スクリプトから検知できる）。
- **ユーザーが「○○を作って」と言ったら、Claude はまず必ずこの重複チェックを実行**し、既存と被らないことを確認してから次へ進む。

### 1. 準備（新規と分かったキャラを登録）
作りたいキャラを `candidates.csv` に追記する（列: `id,category,ja_name,en_name,tags,concept,primary_hex,secondary_hex,accent_hex,variations`）。
- `id`/`ja_name`/`en_name` は既存カタログと**重複しない**もの（上のチェック済み）。
- **説明とタグは必ず残す**（あとでジャンル分け・検索するため）：
  - `concept` に見た目を具体的に（1キャラ作るごとに必ず記入。あとから何のキャラか分かるように）、色は3色を hex で。
  - `tags` = `;`（セミコロン）区切りの自由タグ。将来のジャンル分け用。例: `animal;land;mammal;fluffy`／`sea;marine;baby`。`category`（単一の大分類）とは別に、横断的な属性を複数付ける。
- `category` は `scripts/characters.csv` の有効カテゴリに合わせる。
- **統合時はこの説明・タグをリポジトリの `characters.csv` にも引き継いでよい**：`generate_characters.py` は `DictReader`（列名読み）で必要列しか見ず**余分な列は無視する**ので、`characters.csv` に `tags`（必要なら `concept`）列を足してもカタログ生成は壊れない（列を足す変更は worktree 上で）。
```bash
python3 scripts/build_prompt.py --list                 # candidates.csv 一覧
```

### 2. 探索（agy で案を量産 → 選ぶ）
```bash
scripts/explore_agy.sh <id> [variations]     # 例: scripts/explore_agy.sh sample_hamster 4
```
- `out/explore/<id>/v1..vN.png` と `_contact_sheet.png` ができる。
- Claude は `_contact_sheet.png` を Read で見せ、ユーザーに採用案（例 `v3`）を選んでもらう。
- agy が scratch に書く癖があるのでスクリプトが自動回収するが、**`out/explore/<id>/` の中身は必ず目視確認**（agy の完了報告を鵜呑みにしない）。
- もっと欲しい/方向を変えたい → `candidates.csv` の concept を調整して再実行。

> 探索を **codex でやりたい**とき（少数精鋭・透過つきで見たい）は、`build_prompt.py --id <id> --mode finalize` のプロンプトを `mcp__codex__codex`（`sandbox: workspace-write`, `cwd` = `out/explore/<id>`）に渡して数枚出してもよい。枚数が要るなら agy。

### 3A. 仕上げ：モードS（SwiftUI 描画）
1. 採用案 `out/explore/<id>/vK.png` を Read して目標デザインを掴む。
2. `mcp__codex__codex`（`sandbox: read-only` でよい＝コードは Claude が貼る）に、**目標画像の説明＋`spec.json` の `finalize_swiftui.convention`＋既存 `BearCharacterFace`/`CatCharacterFace` の実例**を渡し、
   `private struct <Name>CharacterFace: View { var character: HomeRewardCharacter; ... }` を著作させる。
   - 色は必ず `character.primary/secondary/accent`（固定色を焼き込まない＝hex 再着色のため）。
   - `Circle/Capsule/Triangle/RoundedRectangle` を `ZStack`+`offset` で合成。描画域 ≈100×100pt。目は共有 `CharacterEyes(color:)` 流用可。
   - 複雑な形は `Path`/`Canvas`/`GraphicsContext` を使う。**SwiftUI の API は `swiftui` スキル（ローカルの公式リファレンス：`canvas.md`/`graphicscontext.md`/`geometryreader.md`/`color.md` 等を grep）で確認しながら書くと速い**。
3. **Claude がレビュー**：規約準拠・色の使い方・ビルド（下記）・見た目が目標に寄っているか。気に入らなければ指摘を全部含めて codex に再依頼。
4. 統合（ブランチ上で）：
   - `iPadPrototype/HomeView.swift`：`HomeRewardCharacterStyle` enum に case 追加 → `RewardCharacterAvatar` の `switch` に `case .<style>: <Name>CharacterFace(character:)` 追加 → View 本体を追記。
   - `scripts/generate_characters.py` の `VALID_STYLES` に `<style>` 追加。
   - `scripts/characters.csv` に行追加 → `python3 scripts/generate_characters.py` 実行。

### 3B. 仕上げ：モードW（透過 WebP 画像）

**2段構え：① agy で案を量産して選ぶ → ② 採用1体は codex で“清書”して出荷アセットにする。**

⚠ **重要な学び（実機 2026-06-28）**：agy の image_gen は内部で **JPEG を作ってから PNG 化**するため、**元画像に JPEG ノイズが焼き込まれる**（目・口など暗い輪郭まわりのモスキートノイズ、平面のブロック/バンディング）。拡大やや大きめ表示だと「荒れ」が見える。**agy 出力は“デザインを選ぶ”には十分だが、出荷アセットの画質には向かない。** codex は PNG を直接出すので**クリーン**。→ 当たりは agy、清書は codex。

#### ① 探索（agy・荒くてOK、デザインを選ぶ用）
```bash
scripts/cutout_agy.sh <id> [variations] [size]     # 例: scripts/cutout_agy.sh alpaca 4 512
```
- `out/final/<id>/<id>_v1.webp .. _vN.webp`＋`_contact_sheet.png`。自動キー（`--autokey`）が四隅から実背景色を推定して抜く（agy のマゼンタは純 #FF00FF でなく (228,60,192)〜(253,51,250) 等にドリフトするため）。
- Claude は `_contact_sheet.png` を Read で見せ、ユーザーに**デザインを1つ選んで**もらう（画質はまだ気にしない）。

#### ② 清書（codex・採用デザインをクリーンに描き直す＝出荷アセット）
- 採用案 `out/final/<id>/_raw/vK.png` を**リファレンスとして** `mcp__codex__codex`（`sandbox: workspace-write`, `cwd`=`out/final/<id>/_raw`）に渡す。プロンプト要点：
  - 「この参照画像を**同じキャラ・同じ色・同じ構図のままクリーンなフラットベクターで描き直す**」
  - 「**JPEGノイズ/モスキートノイズ/バンディングを出さない・輪郭くっきり・平面はソリッド**」
  - 「背景は**完全均一の純マゼンタ #FF00FF**・被写体にマゼンタを使わない」「PNG で `codex_<id>.png` に保存」
- 透過＆WebP 化：
  ```bash
  python3 scripts/finalize_image.py out/final/<id>/_raw/codex_<id>.png --id <id> --out out/final/<id> --chroma --autokey --size 512
  ```
- **画質の目安（実測）**：清書したフラット絵は **512px / WebP `quality=95` で ~20–30KB が最適バランス**。可逆(`--lossless` 相当)はシェーディングがあると逆に重くなる（1024で200KB超）ことがあるので、**まずは q95**。`finalize_image.py` の既定 `--webp-quality 90` は出荷時 **95 推奨**。
- 仕上がりは Read で確認（縁ハロ・荒れ・透過）。OK なら `<id>.webp` を出荷アセットに。

> 少数で良い・最初から高画質が欲しいなら、①を飛ばして②の codex だけで作ってもよい（その場合 `build_prompt.py --id <id> --mode finalize` のプロンプトを使う）。

#### ②' codex を“CLI 並列”でクリーン量産（`cutout_codex.sh`・MCP直列の遅さを回避）
codex のクリーン PNG は出荷向きだが、**MCP（`mcp__codex__codex`）経由は直列がボトルネック**で枚数を出すと激遅（実機 ~109s/枚×直列＝20枚で ~36分）。**codex には CLI（`codex exec`）があり、別プロセスで並列起動できる**ので、清書ルートでも枚数を回せる。
```bash
scripts/cutout_codex.sh <id> [variations] [size] [concurrency]   # 例: scripts/cutout_codex.sh hamster 6 512 5
```
- `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -c model_reasoning_effort=low` で built-in `image_gen` を呼び、各ワーカーが生成→`finalize_image.py` まで完結。出力は `cutout_agy.sh` と同じ（`out/final/<id>/<id>_vK.webp` ＋ `_contact_sheet.png`）。
- **必須の落とし穴対策（実機 2026-06-29 で判明）**：codex の生成画像は **共有ディレクトリ** `~/.codex/generated_images/<session>/ig_*.png` に出る。「最新PNGをcp」させると**並列で別セッションの画像を掴むレース**が起きる（テストで3枚目が無関係な画像になった）。→ スクリプトは**保存先の絶対パスを渡し『このセッションで今生成した画像だけ』をそこへ cp**させ、グローバル検索を禁止している。ログの `generated_images/...png` を拾う回収フォールバックも実装済。
- **effort=low ＋「後処理（PIL再合成/sips/再生成）をするな」をプロンプトで厳命**する（既定 `xhigh` だとエージェントが背景を厳密マゼンタにしようと自走し数分かかる）。macOS に `timeout` が無いので**自前 watchdog（既定360s/体・`CODEX_MAX_SECS` で可変）**で暴走1体を kill する。
- ⚠ **速度は image_gen API 側のスループット律速でブレる**：好条件で 3枚=126s（=ほぼ1枚分）だが、混むと 3枚で ~6分のことも。**並列しても頭打ち**になりうる。→ **速さ最優先・小表示主体なら agy（22s/枚・`cutout_agy.sh`）が依然最速**。codex CLI 並列は「**出荷アセットをクリーンPNGで枚数欲しい**」とき（agyのJPEGノイズが気になる用途）の選択肢。

#### はみ出し対策（縦長キャラ）
- `finalize_image.py` は必ず **autotrim → 正方形パディング（余白8%）** する。**縦長キャラ（アルパカ等）も正方形キャンバスの中央に収まる**ので、アプリ側で**正方形枠/円に aspect-fit（`.scaledToFit()`）**すれば**カードからはみ出さない**（実機デモで確認）。
- アプリ表示は `aspect-fill`/`.scaledToFill()` にしない（縦長が枠を超える）。**fit＋中央**が原則。

最後に統合（ブランチ上で・**設計要相談**／下記「画像モードの統合」）。

---

## 画像モードの統合（モードW）— ✅ 配線済み（既存の仕組みに乗せるだけ）

**WebP なかまは既にアプリに配線済み**（人物ポートレート/アルパカ/ボクセル等で稼働・catalog に webp 多数）。新規追加は次の手順だけ：

1. webp を `iPadPrototype/Assets.xcassets/nakama_<id>.dataset/` に置く（`<id>.webp` ＋ `Contents.json`。Contents.json は既存 dataset をコピーして `filename` を変えるだけ）。**Asset 名は `nakama_<id>` 固定**（id がそのまま参照キー）。
2. `scripts/characters.csv` に行追加し **`style` 列を `imageAsset`** にする（primary/secondary/accent はフォールバック用に入れておく）→ `python3 scripts/generate_characters.py` でカタログ再生成。
   - ⚠ `generate_characters.py` は **imageAsset 行に対応する dataset が無いとエラーで停止**する。先に手順1で webp を置くこと。

仕組み（`HomeView.swift`）：
- `enum HomeRewardCharacterStyle` に `case imageAsset`（共通・1つだけ）。
- `RewardCharacterAvatar` の render switch の `case .imageAsset:` が `NakamaImageView(character:)` を描く。
- `NakamaImageView` が `NSDataAsset(name: "nakama_<id>")` で WebP を読み、**96pt 固定・aspect-fit＋中央**で表示（縦長キャラもはみ出さない）。デコードは `NSCache` でキャッシュ。画像が無ければ絵文字フォールバック。

注意点：
- 画像モードは **hex 再着色が効かない**（webp は固定絵）。色違いを量産したいなら mode-S を選ぶ。
- imageset は WebP 非対応だが **Data Set なら WebP を直接置ける**（変換不要・上の dataset 方式）。

## ビルド確認（統合後）
```bash
xcodebuild -scheme SpellingTrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build CODE_SIGNING_ALLOWED=NO
```
※ scheme は **`SpellingTrainer`**（`iPadPrototype` ではない）。`-destination` の端末名は環境で変わるので、`xcodebuild -scheme SpellingTrainer -showdestinations 2>/dev/null` か `xcrun simctl list devices available` で実在する iPad 名/ID を確認して使う。

## プレビュー（Mac・シミュレータで目視確認）— 統合したら必ず

**Mac では、コミット前に必ず実機シミュレータでなかまを目視チェックする**（特にモードS＝手続き描画は崩れやすい：アフロ/ツンツン/みつあみ等の前髪・後ろ髪の重なり、縦長キャラのはみ出し、画像なかまのサイズ/透過）。下のヘルパーが **ビルド→iPad シミュレータ起動→インストール→アプリ起動** を1コマンドで行う。

```bash
cd /Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab/.claude/skills/nakama-character-gen
scripts/preview_sim.sh                      # CWD から上方向に *.xcodeproj を自動探索
scripts/preview_sim.sh /path/to/worktree    # 統合をワークツリーでやっている時はそのパスを渡す
```
- 起動済み iPad シミュレータがあればそれを使い、無ければ利用可能な iPad を1台選んで起動する。`SCHEME`/`SIM_NAME` 環境変数で上書き可。
- 起動後、**子のショップ→「ひと」カテゴリ**（人物）／**親→なかま管理** で新キャラを目視する。Claude はユーザーに「シミュレータで確認してください」と促す（このスキルは見た目品質が肝なので、`BUILD SUCCEEDED` だけで完了にしない）。
- チェックが済んだら Simulator は閉じてよい（`xcrun simctl shutdown <UDID>` でも可）。
- **Mac 以外**ではこのスクリプトは終了コード2で「ビルド確認のみ」を促す。スクショ確認したい場合は `xcrun simctl io <UDID> screenshot out.png` でも撮れる。

### モードS（SwiftUI 描画）はアプリ無しでも“プレビュー画像”にできる
「モードW（WebP）は画像ファイルだからそのまま見られるが、モードS（SwiftUI）はアプリを動かさないと見られない」——ではない。**macOS の `ImageRenderer` を使えば、SwiftUI の顔をアプリ無しで PNG コンタクトシートに書き出せる**。シミュレータ起動＋店まで辿るより圧倒的に速いので、**手続き描画の崩れ（前髪/後ろ髪の重なり順・はみ出し・トゲが浮く等）の修正イテレーションはまずこれで回す**。
```bash
cd /Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab/.claude/skills/nakama-character-gen
swift scripts/person_preview.swift out.png   # 全 PersonHair を1枚に
```
- **書き出した PNG は自動で macOS の Preview.app が開く**（背景スキルと同じ挙動）。ユーザーはそこで目視できる。Claude 側も `Read` で同じ PNG を見て一緒に確認する。
- ⚠ `person_preview.swift` 内の `PersonCharacterFace`/`PersonHair` は `HomeView.swift` と**手で同期**する（このツールが実機の見た目の代理なので、髪型を直したら両方を同じ内容にする）。
- 新しい SwiftUI フェイスを起こす時も、このハーネスに貼って描いてみる→PNG 確認→OK なら `HomeView.swift` に移植、が速い。最終確認だけ `preview_sim.sh` で実機。

### プレビューは必ず出す（必ず守る）
このスキルは**見た目品質が肝**。生成・修正したら**必ずプレビューを出してユーザーに見せる**（「`BUILD SUCCEEDED`」「`✅ wrote`」だけで完了にしない）。
- **モードW（画像）**：生成物/コンタクトシートを `open -a Preview <file>` で Preview.app に出す（`cutout_agy.sh`/`finalize_image.py` の出力 PNG/WebP）。Claude も `Read` で確認。
- **モードS（描画）**：`person_preview.swift` が PNG を Preview.app に自動で出す。アプリ全体を見たいときだけ `preview_sim.sh` でシミュレータ。

## ファイル
```
spec.json                 画風・制約・倍率の単一ソース(house_style を毎回再掲)
candidates.csv            作るキャラの一覧(id/名前/tags/concept/色/案数)
scripts/build_prompt.py   spec+csv → プロンプト生成(explore=白 / finalize=マゼンタ)
scripts/explore_agy.sh    agy で白背景の案量産→scratch回収→コンタクトシート(探索)
scripts/cutout_agy.sh     agy でマゼンタ地量産→自動切り抜き→透過WebP候補(モードW主役・速い)
scripts/cutout_codex.sh   codex CLI(codex exec)をeffort=low並列で叩きクリーンPNG量産→透過WebP(出荷品質・MCP直列回避)
scripts/contact_sheet.py  案/切り抜きをグリッド1枚に
scripts/finalize_image.py 生成物→(自動)クロマキー→trim/pad/resize→透過WebP(+PNG/倍率)
scripts/nakama_lib.py     背景色推定/クロマキー透過/defringe/trim/pad/resize/webp
scripts/preview_sim.sh    [Mac] ビルド→iPadシミュレータ起動→install→launch（目視チェック用）
scripts/person_preview.swift [Mac] モードSの人物顔をImageRendererでPNGコンタクトシート化（アプリ不要）
out/                      生成物(git管理外)。explore/<id>/, final/
refs/                     画風リファレンス(任意)
```

## 速度の指針（agy で量産が速い・実測 2026-06-29）
- **agy は1体 ~22秒。codex は1体 ~1.5〜2分（プロンプト解釈＋画像生成＋後処理）＝ agy が約4〜5倍速。** codex は MCP 経由で**直列**になりがち（並列投げても順番待ち）。
- **小表示（カード/アイコン ~96px）が主なら agy で十分**：agy の JPEG 由来ノイズはこのサイズでは codex と**区別がつかない**（実測比較済）。**“小さく出すなら agy で量産、荒れた個体だけ codex で清書”** のハイブリッドが最速。
- **agy をアニメ顔等の任意画風で量産するときは `build_prompt.py` を通さず agy に直接プロンプト**を投げる（build_prompt はマスコット house_style 固定のため）。マゼンタ地で生成 → `finalize_image.py --chroma --autokey` で透過WebP。codex の後処理（リサイズ/検証）は不要と明記すると軽くなる。
- **実績(PR#102 2026-06-29)**: 人間ポートレート20体を agy 主体で量産（15体を ~6-7分）。`out/agytest`/`out/_all20*` 参照。

## 人間ポートレートのサブ画風（flat + 日本アニメ調・斜め45°）
マスコット(正面フラット)とは別系統の人間なかま。house_style 要点を毎回再掲して画風を揃える：
- 「**Japanese anime illustration, FLAT cel-shading**（くっきり線・フラット塗り・軽い陰影まで・写実NG）」「やさしい微笑み・子ども向け」
- 「**face turned ~45 degrees（three-quarter view）**」
- **フェイスフォーカス構図（必須）**：**顔/頭が枠の 80–85% を占める**・肩は下端に少しだけ・余白は均等・中央。これで **96px の小表示でも顔が潰れない**（頭+肩の引き構図だと顔が小さくなり小表示で破綻＝実機指摘で判明）。
- マゼンタ地・被写体にマゼンタ近傍を使わない（トレンド色は**青/シルバーは安全**、ピンク/紫は #FF00FF と干渉しやすいので避けるか距離を取る）。

## ボクセル風のサブ画風（モードW・agy量産）
立体ブロック（キューブ）のボクセルキャラも agy で量産できる（PR#108・20体）。house_style 要点：
- 「**Voxel art, blocky 3D made of cubes**」「**CHUNKY low-res voxels（大きいキューブ・粗いグリッド・シンプルな形）**」（細かいボクセルにしない＝ユーザー要望）。「3/4 isometric view」「whole character centered, fills ~80%（小表示で読める）」。マゼンタ地→自動クロマキー。
- **IP回避（必須）**: 「**NOT Minecraft**（Steve/Creeper/公式モブ・スキン・ブロック・ロゴを真似ない・オリジナル設計）」を明示。**乗り物に顔を付けない**（顔つき機関車＝きかんしゃトーマス想起でNG→ "NO face, NOT Thomas the Tank Engine" を明示して再生成した実績）。生成物は IP 類似が無いか必ず目視。
- カタログ配置は各キャラの**自然なカテゴリ**(animal/vehicle/fantasy/space/food)＋ `tags=webp;voxel;blocky;...`。

## 既知のクセ / 教訓
- **agy = 真アルファ不可だが量産可**。白背景=探索／**マゼンタ地→自動切り抜きで透過WebPも量産できる**（`cutout_agy.sh`・実機検証 2026-06-28＝縁綺麗）。codex は任意の高精細フォールバック（が遅い・上の「速度の指針」参照）。
- agy のマゼンタは純 #FF00FF でなくドリフトする → 切り抜きは `--autokey`（四隅から実背景色を推定）が安全。
- agy は cwd 無視で `~/.gemini/antigravity-cli/scratch` に書く。報告を信じず `find` で実体確認（[[agy-cli-reliable-invocation]]）。
- 生成は非決定的で seed 不可。画風一貫性は house_style 再掲＋採用案を絞ることで担保。多数キャラを揃えるなら**モードS が安全**。
- このスキル自体を更新して生成品質を継続改善する（プロンプト・defringe 閾値・house_style）。
- 関連: 着せ替えは別スキル `avatar-dressup-gen`、量産レビュー運用は `agy` スキル。
