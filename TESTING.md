# Testing Guide

This guide assumes you have never built an iPad app before.

## Open the App in Xcode

1. Open Xcode.
2. Choose `File > Open...`.
3. Open this file:

   `SpellingTrainer.xcodeproj`

4. At the top of Xcode, choose:

   - Scheme: `SpellingTrainer`
   - Device: `iPad Pro 13-inch (M5)` or another iPad simulator

5. Press the play button.

Xcode will build the app, open the iPad simulator, and launch the app.

## Basic Manual Test

1. Confirm the home screen shows:
   - `Today's Spelling`
   - `Practice`
   - `Test`
   - `Review`
   - the current word list

2. Tap `Parent`.

3. In `Words`, paste words separated by lines or spaces:

   ```text
   cat
   dog
   friend
   school
   ```

4. Tap `Save Words`.

5. In `Settings`, confirm:
   - Language is `US English`
   - Speed is around `0.42`
   - Replays is `2`
   - Seconds per word is `30`

6. Close the parent screen.

7. Tap `Practice`.

8. Tap `Play` and confirm the word is spoken.

9. Write the visible word in the four-line area.

10. Tap `Done`.

11. Confirm the app shows one of:
    - `Correct`
    - `Try Again`
    - `Check Later`
    - `Rewrite`

12. Tap `Next` and repeat.

13. Go back home and tap `Results`.

14. Confirm attempts are listed.

15. If an answer says `Check Later`, open `Parent > Review` and mark it as `Correct` or `Try Again`.

## Test Mode

1. Tap `Test`.
2. The word should not be shown.
3. Tap `Play`.
4. Write the word.
5. Confirm the timer counts down.
6. Tap `Done`.

## Real iPad Test

To run on an actual iPad:

1. Connect the iPad to the Mac with USB.
2. In Xcode's device picker, choose your iPad.
3. Open the project settings.
4. Select target `SpellingTrainer`.
5. Under `Signing & Capabilities`, choose your Apple Developer Team.
6. Press the play button.

The real iPad test is important because Apple Pencil behavior cannot be fully verified in the simulator.

## Command-Line Build Check

From Terminal:

```bash
cd /Users/takahashiyuuta/Documents/scripts/ipad-spelling-ocr-lab
xcodebuild -project SpellingTrainer.xcodeproj -scheme SpellingTrainer -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build
```

Expected result:

```text
** BUILD SUCCEEDED **
```

## OCR Experiment Check

The repo also includes a small Vision OCR experiment CLI.

```bash
cd /Users/takahashiyuuta/Documents/scripts/ipad-spelling-ocr-lab
python3 scripts/generate_samples.py
swift build -c release
python3 scripts/run_experiments.py
```

The output shows how Vision OCR classifies sample spelling images.
