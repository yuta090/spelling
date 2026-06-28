# Spelling Trainer

日本人の子ども向け 英語学習 iPad アプリ（SwiftUI / iOS 17 / Swift 6）。
週次スペル練習に加え、文法を遊びながら覚える **ことばパズル** を開発中。

開発者・AI 向けのプロジェクト規約は [`CLAUDE.md`](CLAUDE.md)、機能仕様は [`docs/`](docs/) を参照。

## 2人ユーザー設計

| | 子ども（やる人） | 親（管理する人） |
|---|---|---|
| 見せるもの | 今やること＋ごほうび/反応 | 単語・レベル・採点・記録・設定 |
| 専門用語 | ❌ 出さない | ⭕️ OK |

## 機能

### スペル練習（MVP）
The app lets a child:

- listen to a spelling word
- write it directly on the iPad with Apple Pencil or finger
- practice with the word visible
- take a test with the word hidden
- review words that need more work

The parent can:

- edit the weekly word list
- change speech and test settings
- review uncertain OCR answers
- see recent results

### ことばパズル（文法練習 / sentence-builder）

文を作りながら語順・文法を遊んで覚える。**テストではなくゲーム**（間違えてOK・何度でも）。
詳細仕様: [`docs/kotoba-puzzle-spec-2026-06-28.md`](docs/kotoba-puzzle-spec-2026-06-28.md)（正本）。

- **並べ替え**（和訳→単語タイルを正しい順に）✅ 名前入り例文で動作
- **穴埋め（選択）** ✅ / **混合セッション**（形式を自動ミックス）✅
- **単語リスニング**（音を聞いて綴りを選ぶ）✅ 音ON/OFFゲート付き / **リスニング穴埋め**（設問中は無音→回答後に音）🟡 計画
- 学年の壁は二軸（語彙=NGSL バンド / 文法=CEFR-J）。未習語タップ→スペル練習へ復習導線。
- 純粋ロジックは SwiftPM パッケージ `SpellingSyncCore`（TDD・`swift test`）、アプリ本体は薄く保つ。

## Current MVP

- SwiftUI iPad app
- PencilKit handwriting canvas
- four-line handwriting guide
- Apple TTS via `AVSpeechSynthesizer`
- Apple Vision OCR via `VNRecognizeTextRequest`
- local persistence using `UserDefaults`
- parent word-list editor
- parent OCR review screen
- test timer and replay limit
- OCR grading buckets:
  - `Correct`
  - `Try Again`
  - `Check Later`
  - `Rewrite`
  - `Time Up`

## Open in Xcode

Open:

```text
SpellingTrainer.xcodeproj
```

Then choose an iPad simulator and press play.

For detailed instructions, see `TESTING.md`.

## Build from Terminal

```bash
xcodebuild -project SpellingTrainer.xcodeproj -scheme SpellingTrainer -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```

## OCR Experiment Tools

This repo also contains small local OCR experiments used to validate the grading approach.

```bash
python3 scripts/generate_samples.py
swift build -c release
python3 scripts/run_experiments.py
```

Generated files are written to `generated/` and are ignored by Git.
