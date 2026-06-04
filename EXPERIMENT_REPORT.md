# iPad Spelling OCR Experiment Report

Date: 2026-06-05

## What I Tried

- Built a Swift CLI that calls Apple Vision OCR (`VNRecognizeTextRequest`).
- Generated 24 rendered spelling-answer samples:
  - guide lines vs no guide lines
  - multiple handwriting-like fonts
  - small, light, blurred, shifted, rotated writing
  - correct words, one-letter mistakes, missing letters, non-dictionary words
- Generated 8 stroke-based pseudo-handwriting samples with drawn letter strokes.
- Tested OCR with:
  - language correction off
  - language correction on
  - `customWords` using the expected spelling word
  - both correction and custom words
- Created an iPad SwiftUI/PencilKit prototype and type-checked it against the iOS simulator SDK.

## Results

Font-style samples:

- Total OCR runs: 96
- `autoCorrect`: 54
- `needsReview`: 33
- `autoIncorrect`: 4
- `rewrite`: 5

Stroke-style pseudo-handwriting samples:

- Total OCR runs: 16
- `autoCorrect`: 8
- `needsReview`: 5
- `autoIncorrect`: 2
- `rewrite`: 1

## Findings

1. Four-line guide lines did not break OCR in the clean samples.

   The guide-line samples and no-guide samples both recognized `cat` correctly with high confidence. This supports using notebook-style lines in the MVP.

2. Font-like writing is too easy for Vision.

   Even handwriting-like fonts such as Bradley Hand, Marker Felt, and Comic Sans were recognized almost perfectly. These are useful smoke tests, but not enough to prove child handwriting accuracy.

3. Stroke-like writing exposed real risks.

   The smaller stroke `cat` was recognized as `cot` with confidence `1.0`. That is the important failure mode for this app: Vision can be very confident and still wrong when the letter shape is ambiguous.

4. One-letter differences should not be auto-failed.

   Cases like `cot` vs `cat`, `cut` vs `cat`, `kat` vs `cat`, `frend` vs `friend`, and `freind` vs `friend` all land in `needsReview`. This is the right MVP behavior because one-letter errors are exactly where OCR and spelling assessment are easiest to confuse.

5. `rn` / `m` is unstable.

   The `rn` and `m` tests produced misreads or OCR failure. This kind of shape confusion should always go to review or rewrite, never full auto-grading.

6. Language correction should probably stay off for grading.

   Language correction did not falsely turn the tested misspellings into the expected word, but it changed confidence behavior and changed `skool` to `shool` in one case. For a spelling test, correction can hide mistakes or alter OCR behavior, so the grading path should default to `usesLanguageCorrection = false`.

7. `customWords` is useful but should be used cautiously.

   Adding the expected word as a custom word did not corrupt the tested obvious misspellings. It can help unusual weekly spelling words, but it should not be treated as proof of correctness.

## Implementation Direction

The MVP should use this grading pipeline:

1. Capture iPad handwriting with PencilKit.
2. Render the drawing onto a white background before OCR.
3. Run Vision OCR with `recognitionLevel = .accurate`.
4. Keep `usesLanguageCorrection = false` for grading.
5. Optionally pass the expected word in `customWords`.
6. Normalize OCR text to lowercase letters only.
7. Compare OCR result with expected word using:
   - exact match
   - Vision confidence
   - edit distance
   - strong alternative candidates
8. Classify as:
   - `autoCorrect`
   - `autoIncorrect`
   - `needsReview`
   - `rewrite`

## Practical MVP Rule

OCR is feasible, but the app should not promise full automatic marking at first.

The safe rule is:

- Exact match + high confidence + no strong alternative: auto-correct.
- One-letter difference: parent review.
- Low confidence or no OCR: rewrite.
- Clearly different result with good confidence: auto-incorrect.

## Created Files

- `Sources/SpellingOCRLab/main.swift`: Vision OCR CLI and grading logic.
- `scripts/generate_samples.py`: font-style sample generation.
- `scripts/run_experiments.py`: batch OCR experiment runner.
- `scripts/generate_stroke_samples.py`: pseudo-handwriting sample generation.
- `scripts/run_stroke_experiments.py`: stroke sample OCR runner.
- `generated/results.json`: font-style OCR results.
- `generated/stroke_results.json`: stroke-style OCR results.
- `iPadPrototype/`: SwiftUI/PencilKit/Vision prototype files.

## Next Best Test

The next useful test is not more synthetic images. It is 20-50 actual iPad handwritten samples from the child:

- 10 correctly written words
- 10 one-letter wrong words
- 5 small/fast/sloppy words
- 5 `b/d/p/q`, `g/y`, `rn/m`, `t/l/i` style cases

Run those through the same CLI or iPad prototype and tune thresholds from the real data.
