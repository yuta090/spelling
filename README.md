# Spelling Trainer

iPad MVP for weekly English spelling-test practice.

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
