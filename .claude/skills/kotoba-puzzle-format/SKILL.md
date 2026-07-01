---
name: kotoba-puzzle-format
description: SpellingTrainer「ことばパズル」に新しい出題形式を再現性よく追加するスキル。1メニューからランダム出題する統一セッション(PuzzleSessionView)へ、共通UI(PuzzleKit)とコア(PuzzleFormat/各Generator/Grader)を使って形式を1つ足す手順。「ことばパズル」「パズル形式追加」「新しいクイズ形式」「ぶんづくり/あなうめ/リスニングに形式追加」「手書き穴埋め/英作文を有効化」「出題形式を増やす」等で使用。
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, mcp__codex__codex
---

# ことばパズル 形式追加（kotoba-puzzle-format）

「ことばパズル」(子)＝「文法/sentence-builder」(親) は、**1つのメニューから複数形式をランダム出題**する。
このスキルは、その統一セッションに**新しい出題形式を1つ足す**作業を、毎回同じ手順で再現するためのもの。

設計の正本: `docs/kotoba-puzzle-spec-2026-06-28.md` /
`docs/exercise-formats-and-distractors-2026-06-28.md`

## 大方針（必ず守る）

- **ロジックはコア(`SpellingSyncCore`)に・UIは薄く**。出題生成と採点は純粋ロジックとして `Sources/SpellingSyncCore/` に置き、`swift test` で回す（CLAUDE.md 準拠）。
- **TDD**：コアは テスト先(RED)→最小実装(GREEN)→リファクタ。
- **見た目は共通部品(`PuzzleKit`)を使う**。新形式ごとに色・ボタン・レイアウトを複製しない（複製がこの機能の元々の負債だった）。
- **形式の有効化は1スイッチ**：`PuzzleFormat.isPlayable` を `true` にすると `playablePool` に入り、ホームの「ことばパズル」から自動でランダム出題される。配線の追加作業は不要。
- **作業は必ずブランチ/ワークツリーを切る**（`main` で作業しない）。このスキル本体は `.claude/`(git管理外)なので編集は `main` でも可。
- **実装後は必ず codex Code Reviewer にレビューさせる**（CLAUDE.md 準拠）。

## アーキテクチャ（現状の地図）

| 層 | ファイル | 役割 |
|---|---|---|
| コア・形式列挙 | `Sources/SpellingSyncCore/PuzzleFormat.swift` | `PuzzleFormat`(形式)・`isPlayable`/`requiresAudio`・`playablePool`・`PuzzleFormatScheduler`(連続同形式なしの決定論スケジュール) |
| コア・出題/採点 | `Sources/SpellingSyncCore/SentenceExercise.swift`(並べ替え) / `ClozeChoice.swift`(あなうめ) / `ListeningCloze.swift` / `WordListening.swift` | `XxxGenerator.make(...)` と `XxxGrader.grade(...)`。**新形式はここに Generator/Grader を足す** |
| UI・共通部品 | `iPadPrototype/PuzzleKit.swift` | `PuzzleTheme`(配色)・`PuzzlePrimaryButton`・`PuzzleVerdictLabel`・`PuzzleFormatBadge`・`PuzzleOptionButton`・`PuzzleListenButton`・`PuzzleSoundGate`・`PuzzleFlowLayout` |
| コア・出題プール組立 | `Sources/SpellingSyncCore/PuzzleContentBuilder.swift` | 文バンク＋音類似おとりから各形式のプールを決定論で組む（空所選び・おとり選定の判断はここ）。あなうめのおとり＝同じか下の学年の内容語 |
| UI・統一セッション | `iPadPrototype/PuzzleSessionView.swift` | 音ゲート→`PuzzleFormatScheduler`でランダム並び→`PuzzleStepView`が形式ごとに出題ボディを出し分け。`PuzzleContent` は `PuzzleContentBuilder` を `SentenceBankBundle`＋`ConfusablesBundle` に対して呼ぶだけ（**ハードコードしない**）。出題はプールを sessionSeed で混ぜ、形式ごとの通し番号で消費＝全プールに行き渡る／「もういちど」で別問 |
| ホーム導線 | `iPadPrototype/HomeView.swift` | `ChildMissionPanel` の 🧩「ことばパズル」ボタン → `PuzzleSessionView()` を fullScreenCover |
| テスト | `Tests/SpellingSyncCoreTests/PuzzleFormatSchedulerTests.swift` ほか各形式テスト | |

**ランダム出題の流れ**：`PuzzleSessionView` が `pool`(音設定で audio必須形式を出し入れ) → `PuzzleFormatScheduler.schedule` で並び → 各 `PuzzleStepView` が `format` を見て `content`(出題ボディ)を描画 → 採点 → せいかい「つぎへ」/まちがい「もういちど」。

---

## 形式を1つ追加する手順（再現フロー）

例：新形式 `multipleChoice`(3択・正誤) を足す場合。

### 0. 準備
```bash
cd /Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab
git branch --list | grep kotoba          # 名前衝突チェック
git worktree add ../SpellingTrainer-wt/kotoba-puzzle-<form>-<suffix> -b feat/kotoba-puzzle-<form>-<suffix>
```

### 1. コア：出題生成＋採点（TDD）
- `Sources/SpellingSyncCore/<NewFormat>.swift` に `XxxExercise`(出題データ)・`XxxGenerator.make(...)`(seed決定論)・`XxxGrader.grade(...)`(決定的採点 or AI採点の口) を追加。
- `Tests/SpellingSyncCoreTests/<NewFormat>Tests.swift` を**先に**書く：生成が seed 決定論か／選択肢に正解が含まれるか／採点の正誤。
- `swift test --filter <NewFormat>` でGREEN。

### 2. コア：形式を列挙に登録
`PuzzleFormat.swift` を編集：
- `enum PuzzleFormat` に `case <newFormat>` を追加（`CaseIterable` なので宣言順がプール順）。
- `isPlayable`：**完成するまで `false`**（手書き/英作文のように採点が未完成なら false のまま隠れる）。
- `requiresAudio`：音が本体なら `true`（「おとなし」設定で自動的にプールから外れる）。
- `PuzzleFormatSchedulerTests` の `testPlayablePoolIs...` を新しいプール内容に更新（RED→修正）。

### 3. UI：出題ボディを共通部品で描く
`PuzzleSessionView.swift` の `PuzzleStepView`：
- `content` の `switch format` に `case .<newFormat>:` を追加し、出題ボディ View を実装。
- **必ず `PuzzleKit` を使う**：選択肢は `PuzzleOptionButton`、確定/つぎへは `PuzzlePrimaryButton`、判定見出しは `PuzzleVerdictLabel`、音は `PuzzleListenButton`、タイル折返しは `PuzzleFlowLayout`、配色は `PuzzleTheme`。新しい色やボタンを足さない。
- `seedSalt` と `childTitle`(子ども向け表示名・ふりがな) の `switch` に新 case を追加。
- 採点後の `correctAnswerText`・`canListenBack`・`listenBack`・`setup` の `switch` にも新 case を反映。
- 出題コンテンツの組み立ては**コア `PuzzleContentBuilder`** に足す（同梱データ＝倉庫から決定論で組む）。`PuzzleContent`(UI)はそれを呼ぶだけにし、デモ文をハードコードしない。文そのものを増やすのは倉庫2＝`kotoba-sentence-add`。

### 4. 有効化（1スイッチ）
採点とUIが完成したら `PuzzleFormat.<newFormat>.isPlayable` を `true` にする。
→ `playablePool` に入り、ホームの「ことばパズル」から**自動でランダム出題**される(配線追加不要)。

### 5. 検証
```bash
cd <worktree>
swift test                                # コア全green
xcodebuild -project SpellingTrainer.xcodeproj -scheme SpellingTrainer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO           # ビルド成功
```
DEBUG 試遊は `PuzzleSessionDebugLauncher`(puzzlepiece アイコン) から。

### 6. レビュー＆クローズ
- codex Code Reviewer にレビュー依頼 → 指摘対応。
- コミット/PR/マージ/後片付けは**ユーザー確認の上で**(CLAUDE.md)。

---

## 新規ファイルを Xcode プロジェクトに登録（重要・忘れやすい）

`SpellingTrainer.xcodeproj` は **同期グループではなく明示参照**。`iPadPrototype/` に .swift を足したら `project.pbxproj` の**4箇所**に追記する（未追記だとビルドに含まれない）。既存行(例:`ClozeChoiceView.swift`)を雛形に、未使用の `FACE00...` ID を採番：
1. `PBXBuildFile`（`... in Sources */ = {isa = PBXBuildFile; fileRef = ...}`）
2. `PBXFileReference`（`... */ = {isa = PBXFileReference; ... path = Xxx.swift; ...}`）
3. グループ children（`... /* Xxx.swift */,`）
4. `Sources` ビルドフェーズ（`... Xxx.swift in Sources */,`）

`Sources/SpellingSyncCore/` は SwiftPM が自動 glob するので pbxproj 編集は**不要**。

## 設計上の約束（破らない）
- **子に専門用語を出さない**：バッジ/タイトルは「ぶんづくり」「あなうめ」等ふりがな語。Lv/CEFR/採点語はNG(CLAUDE.md UI/UX)。
- **テストでなくゲーム**：間違えてOK・何度でも(「もういちど」)。
- **音は公共の場対応**：audio必須形式は `requiresAudio=true`、冒頭 `PuzzleSoundGate` で一括ゲート。「おとなし」でも遊べる形式は残す。
- **未完成形式は `isPlayable=false`** で隠す。プレースホルダの空 case を `content` に置いても落とさない。
