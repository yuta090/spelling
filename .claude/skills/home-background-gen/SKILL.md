---
name: home-background-gen
description: >
  SpellingTrainer の「ホーム背景」(HomeBackgroundTheme＝子のホーム画面の背景。中央にキャラを乗せる舞台) を新規に作るスキル。
  既存33種と被らないか重複チェック→2方式(image=PNG / procedural=SwiftUI手描き)から選ぶ→生成→中央セーフゾーン検証→アプリに載せる。
  生成した画像は macOS の Preview で開いて確認する。
  トリガー:「背景を作りたい」「はいけい追加」「新しい背景」「ホーム背景」「背景を量産」「背景の重複チェック」「背景をプレビューで見たい」。
  ⚠ キャラ(なかま)を作るのは別スキル nakama-character-gen、着せ替えは avatar-dressup-gen。こちらは“ホーム背景(舞台)”専用。
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, mcp__codex__codex
---

# ホーム背景生成（home-background-gen）

SpellingTrainer の「**ホーム背景**」(`HomeBackgroundTheme`／子のホーム画面で**キャラの後ろに敷く舞台**) を、**重複チェック → 方式選定 → 生成 → 中央セーフゾーン検証 → アプリ搭載** まで回すスキル。

## 大方針（必ず守る）

- **背景は『舞台』。主役はキャラ。** アプリは背景の**中央にキャラ＋UIを `.scaledToFill()` で乗せる**。だから背景づくりの第一原則は **「中央を開ける」**（中央はディテール薄め・明度ミドル〜ライト・低コントラスト）。`spec.json` の `center_open_rule` を毎回プロンプトに再掲する。
- **🚫 中央に人物・キャラを描かせない（絶対）。** アプリが自前キャラを中央に乗せるので、背景の中央は必ず“無人”。**プロンプトに `for a character` と書くとモデルが人物（マイクラのSteve等）を中央に描いてしまう**ので使わない。代わりに **`a flat EMPTY open area in the foreground center — do NOT draw any person/character/figure, leave it empty`** と明示する。生成後は中央に人物が紛れていないか必ず目視確認、いたら再生成。
- **透過はしない（なかまとの最大の違い）。** 背景は不透過のフルフレーム。**マゼンタ地クロマキー/切り抜き/WebP化は一切不要**。出荷は **1448×1086 の不透過 PNG**。
- **画像生成は agy 優先・1コール=1枚・並列で回す。** 背景画像はまず **agy** に投げる。鉄則は **1コール=1枚**（複数枚を1プロンプトに詰めない＝そのほうがレスポンスが速く・落ちにくい）。その単枚コールを**並列で同時実行**してスループットを稼ぐ：**既定 5 並列**（小バッチはまとめて5本同時でOK。`xargs -P5` か `&`＋`wait`）。**空出力/レート制限/kill が出たら 3 に落とす**。agy はバックグラウンドが脆いので各本は `script` 擬似TTYのフォアグラウンド＋`tee` でログ保存、落ちたら再投入。**agy の品質が足りない／正寸で清書したいときだけ codex にフォールバック**（codex はまとめ投げ・並列OK）。既存の一部は codex 製。
- **画風の一貫性 = house_style 再掲。** `spec.json` の `house_style` を毎回再掲し、`candidates.csv` の1行（concept/art_prompt）だけ差し替える。
- **生成物は macOS の Preview で開いて見せる。** コンタクトシート・セーフゾーンプレビューは `open -a Preview <png>`（スクリプトが自動で開く）。Claude も Read で確認する（agy/codex の完了報告を鵜呑みにしない・実体を `find`/`ls` で確認）。
- **アプリのコード/CSV/アセットを触る統合フェーズは、必ずブランチ/ワークツリーを切ってから**（`main` で作業しない／CLAUDE.md 準拠）。スキル本体は `.claude/`（git 管理外）なのでスキル編集自体は `main` でも可。

## 2つの方式（用途で選ぶ・どちらが上ではない）

| | 方式I：image（PNG） | 方式P：procedural（SwiftUI手描き） |
|---|---|---|
| 成果物 | `bg_<id>.imageset` の 1448×1086 PNG | `HomeBackgroundScene` の新 case＋シーン描画コード |
| **良さ** | **具体的な“場所/世界”を写実・作り込んだ1枚絵でリッチに**（パリ・水族館・サーキット）。質感・情報量を盛れる。生成→即載る | **アセット0KB・無限スケール**（全解像度でくっきり）。**時間帯/季節/アニメ（雲が流れる・星が瞬く）を後付けできる**。中央オープンをコードで構造的に保証。画風が完全に揃う |
| **難所** | 容量増（数百KB〜）／色・時間帯変更・解像度固定／中央オープンは人が担保（→セーフゾーン検証）／統一は house_style 頼み | 具体的な場所・写実は描けない／新シーンごとに SwiftUI 描画コードが要る |
| **向く** | 「行ってみたい具体的な場所/世界」を見せたいとき | 抽象・幾何・グラデ主体の空気感（よぞら・ゆうやけ・うちゅう・草原・にじ）。背景を**動かしたい/軽くしたい/色や時間帯で派生**させたいとき |
| 生成 | codex 清書（量産が要れば agy 案出し→codex） | codex が SwiftUI 著作 → Claude レビュー |
| 配線 | PNG→imageset＋CSV→`generate_backgrounds.py` | `HomeBackgroundScene` case＋シーン描画＋`proceduralThemes` を手書き |

**方式指定がなければ着手前に必ず確認**（誘導しない）：「**具体的な場所をリッチに見せるなら『画像（方式I）』、抽象的な空気感で軽く・あとで時間帯やアニメも足したいなら『手描き（方式P）』。どちらにしますか？**」。決まったら着手時に1〜2行で「今どちら・なぜ・違い（容量/色変え/配線）」を説明してから始める。

---

## トーン（画風タッチ）を必ず決める（方式Iで重要）

**同じ場所でもトーンで別物になる。** 例：`shibuya` は既存が **夜のシネマ調（semi-real-cinematic）**、今回足した `shibuyaday` は **昼の可愛いフラット（cute-flat）**。だから **生成前に必ずトーンを確認**し、`candidates.csv`／`backgrounds.csv` の `tags` に **`tone:<key>` を必ず付ける**。

**既存カタログのトーン2系統（`spec.json` の `tones`／`tone_survey` が単一ソース）:**

| tone キー | タッチ | 既存例 | 向く題材 |
|---|---|---|---|
| **`cute-flat`**（既定） | やわらかフラット・絵本タッチ。明るいパステル・写実なし・暗所なし | forest, candyland, sakura, park, zoo, cakeshop, dinomuseum | 自然/季節/ファンタジー/動物/子ども施設/お店/職業 |
| **`semi-real-cinematic`** | 写実寄り・シネマ調。フォトリアル/3D風・高彩度・**暗め/夜もOK**。プレミアム上位ティア | shibuya(夜), gamingroom, soccerfield, musicstudio, arcade, beachresort | 都市夜景/観光/スポーツ/音楽/車/テック/ファッション |
| **`voxel`** | マイクラ風キューブ世界。原色・段々のブロック・キューブ雲。中央は平らなブロック広場 | blockworld（＋森/砂漠/海/雪原/火山/街…量産可） | “作る”ゲーム世界観。**人気カテゴリなので色んな風景を複数パターンOK** |

- **トーン指定がなければ必ず確認**：「**やさしい絵本タッチ（cute-flat）と、本物っぽいシネマ調（semi-real-cinematic）、どちらのトーンにしますか？**」。`house_style`（spec.json）は **cute-flat の定義**。`build_prompt.py --mode image` は house_style を再掲するので **cute-flat 前提**。
- **`semi-real-cinematic` で作るときは house_style の must/ng を再掲しない**（フォトリアル/暗めを禁止しているのは cute-flat 用）。代わりに「フォトリアル/シネマティック・リッチなライティング」を指定しつつ、**『中央オープン』と『文字・ロゴを入れない』だけは必ず維持**する。暗い/混むと `safezone_check` が ⚠ を出しやすいので、**中央だけは明度ミドル・低ディテール**に。
- どちらのトーンでも、決めたら **`tags` に `tone:cute-flat` か `tone:semi-real-cinematic` を必ず記録**（後でトーン別に絞り込めるように）。

---

## 使い方（フロー）

### 0. まず重複チェック（必須・既存33種と被らせない）
```bash
cd /Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab/.claude/skills/home-background-gen
python3 scripts/check_duplicate.py どうぶつえん zoo     # 作りたい名前(日/英)
python3 scripts/check_duplicate.py --category nature   # カテゴリ既存一覧
python3 scripts/check_duplicate.py --all               # 全件
```
`⛔ 既に存在`→作らない。`⚠/似てるかも`→人が判断。`✅ 新規`→OK。重複1件で exit 1。

### 1. 準備（候補を登録）
`candidates.csv` に追記（列: `id,category,ja_name,en_name,render,price,default_unlocked,tags,concept,art_prompt`）。
- **説明とタグは必ず残す**（あとでジャンル分け・検索するため）：
  - `concept` = 日本語の説明（何の場所か・中央の開け方）。`art_prompt` = 生成に使う英語プロンプト。**1枚作るごとに両方を必ず記入**（あとから何の絵か分かるように）。
  - `tags` = `;`（セミコロン）区切りの自由タグ。将来のジャンル分け用。例: `city;japan;urban;daytime`／`space;scifi;cosmos`。`category`（単一の大分類）とは別に、横断的な属性を複数付ける。
  - **`tags` には画風トーンを必ず入れる**：`tone:cute-flat` か `tone:semi-real-cinematic`（上の「トーンを必ず決める」参照）。あとでトーン別に絞り込むため。
- `category` は既存（city/nature/sea/season/fantasy/sports/music/fashion/tech/travel/vehicle 等）に合わせる。
- **統合時はこの説明・タグをリポジトリの `backgrounds.csv` にも引き継ぐ**：`generate_backgrounds.py` は `DictReader`（列名読み）で id/ja_name/en_name/price/render/image しか見ず**余分な列は無視する**ので、`backgrounds.csv` に `tags`（必要なら `concept`）列を足してもカタログ生成は壊れない（列を足す変更は worktree 上で）。
```bash
python3 scripts/build_prompt.py --list
```

### 2A. 生成：方式I（image・本命）
プロンプトは共通：`python3 scripts/build_prompt.py --id <id> --mode image`。

- **agy で生成（優先・1枚ずつ）**：プロンプトを **1 ID = 1 agy コール**で投げる（まとめない＝レスポンスが速く落ちにくい）。agy は pseudo-TTY 必須＆出力は scratch に出る（[[agy-cli-reliable-invocation]]）：
  ```bash
  P="$(python3 scripts/build_prompt.py --id <id> --mode image)"
  script -q /dev/null /Users/takahashiyuuta/.local/bin/agy --dangerously-skip-permissions --print-timeout 240s \
    -p "$P 4:3 landscape PNG, save as bg_<id>.png" 2>&1 | tr -d '\r' | tee out/final/<id>/agy.log | tail -30
  # 生成物を scratch から回収:
  cp ~/.gemini/antigravity-cli/scratch/**/bg_<id>.png out/final/<id>/ 2>/dev/null
  ```
  複数 ID は **1コール=1枚を並列実行**（既定 **5 並列**＝`xargs -P5` か `&`＋`wait`。空出力/レート制限/kill が出たら 3 に落とす）。各ワーカーは `tee` でログを残し、落ちたら再投入。
- **codex はフォールバック/清書**：agy の質が足りない・正寸で清書したいときだけ `mcp__codex__codex`（`sandbox: workspace-write`, `cwd`=`out/final/<id>`）に同じプロンプトを渡す（codex は**まとめ投げ・並列OK**）。
- どちらも **報告を鵜呑みにせず実体を `ls`/Read で確認**。背景は不透過、透過処理は不要。

### 2B. 生成：方式P（procedural）
- `python3 scripts/build_prompt.py --id <id> --mode procedural` のブリーフを `mcp__codex__codex`（`read-only` 可＝コードは Claude が貼る）に渡し、`HomeBackgroundScene` の case／シーン描画／`proceduralThemes` 行を著作させる。
- **アニメーション前提で作る**：procedural 背景は**動かせるようにする**。雲の流れ・星の瞬き・水面の揺れ・光のパルス等を `TimelineView(.animation)` か `withAnimation(.easeInOut(...).repeatForever())` で**時間駆動**。動きは**ゆっくり・控えめ・中央は静か**（キャラの邪魔をしない）。`accessibilityReduceMotion` で**止められる**形にする（動きはあくまで装飾）。
- **Claude がレビュー**：規約準拠・色は `theme.skyTop/...accent` を使っているか・中央が静かか・アニメが控えめで reduce-motion 対応か・ビルド。SwiftUI API（`TimelineView`/`Canvas`/`animation`）は `swiftui` スキルで確認。

### 3. 中央セーフゾーン検証（必須・キャラが乗っても見えるか）
```bash
python3 scripts/safezone_check.py <生成PNG>
```
- 中央の楕円ゾーンの **エッジ量（混み具合）/輝度/コントラスト** を測り、合否を出す。
- **キャラの仮シルエットを中央に合成したプレビュー PNG** を作り、**Preview で自動的に開く**（人の目でも確認）。
- `⚠` が出たら、中央が混んでいる/暗い等。プロンプトを直して再生成（しきい値は `spec.json` の `safezone.thresholds`・調整可）。
- 方式P でも、ホームを起動した画面を撮って同様に通してよい。

### 4. 値付け（price / 解放）
- `price` を既存分布に合わせる（無料=0／街・観光は高め）。
- **開始から無料解放したい背景は、`HomeView.swift` の `defaultUnlockedIDs` に id を足す**（CSV の `default_unlocked` 列は管理メモで、コードには反映されない＝下記注意）。

### 5. 統合（ブランチ上で）

**方式I（image）**
```bash
# (1) PNG を 1448x1086 に整えて imageset に配置（統合は worktree 上で → --repo で対象を明示）
python3 scripts/place_asset.py out/final/<id>/<file>.png --id <id> --repo <worktree-root>
# (2) <worktree>/scripts/backgrounds.csv に1行追加（末尾に tags 列。tone:<key> を必ず含める）:
#     <id>,<category>,<ja>,<en>,<price>,<default_unlocked>,image,bg_<id>.png,<art_prompt>,<tags>
# (3) カタログ再生成（worktree 側で）
cd <worktree-root> && python3 scripts/generate_backgrounds.py
# (4) 無料解放なら HomeView.swift の defaultUnlockedIDs に id を足す
```
> `place_asset.py --repo <worktree-root>` を付けないと本体リポジトリの Assets を触ってしまう（CLAUDE.md：本体は常に main・作業は worktree）。

**方式P（procedural）**
- `scripts/backgrounds.csv` に `render=procedural` の行（管理メモ）を足す＋ `HomeView.swift` を手書き（`HomeBackgroundScene` case／`HomeBackgroundScenery` 描画／`proceduralThemes` 行）。`generate_backgrounds.py` は **image 行しか再生成しない**ので procedural は手で配線する。

### 6. ビルド確認
```bash
xcodebuild -scheme SpellingTrainer -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
```

---

## ファイル
```
spec.json                  画風・中央オープン原則・セーフゾーン既定・倍率の単一ソース
candidates.csv             作る背景の一覧(id/category/名前/render/price/concept/art_prompt)
scripts/check_duplicate.py 既存 backgrounds.csv 33種と重複チェック
scripts/build_prompt.py    spec+候補 → 生成プロンプト(image=中央オープン / procedural=著作ブリーフ)
scripts/explore_agy.sh     agy で案を量産→コンタクトシート→Preview起動(任意・案出し用)
scripts/contact_sheet.py   案をグリッド1枚に
scripts/safezone_check.py  ★中央セーフゾーン検証＋キャラ仮合成プレビュー→Preview起動
scripts/place_asset.py     生成PNG→1448x1086→bg_<id>.imageset 配置(image統合)
out/                       生成物(git管理外)。explore/<id>/, final/<id>/
refs/                      画風リファレンス(任意)
```

## 既知のクセ / 教訓
- **`.scaledToFill()` で中央基準 crop**。四隅は機種により切れる前提 → 重要要素と“開けた余白”は必ず中央に。
- **解放は `defaultUnlockedIDs`（ハードコード）で制御**。`backgrounds.csv` の `default_unlocked` 列は現状コード未反映の管理メモ。無料配布は id を `defaultUnlockedIDs` に足すのを忘れない。
- `generate_backgrounds.py` は `BG-CATALOG-GENERATED` マーカー間の **image 行だけ**再生成する。procedural は手配線。
- agy は cwd 無視で `~/.gemini/antigravity-cli/scratch` に書く。報告を信じず実体確認（[[agy-cli-reliable-invocation]]）。生成は非決定的で seed 不可 → 多数を揃えるなら house_style 再掲＋採用案を絞る。
- 関連: キャラは `nakama-character-gen`、着せ替えは `avatar-dressup-gen`、agy運用は `agy` スキル。
- このスキル自体を更新して生成品質（プロンプト・セーフゾーン閾値・house_style）を継続改善する。
