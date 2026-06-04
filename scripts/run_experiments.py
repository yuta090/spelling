from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "generated"
BIN = ROOT / ".build" / "release" / "spelling-ocr-lab"


def run_case(image: Path, expected: str, correction: bool, custom_word: bool) -> dict:
    cmd = [
        str(BIN),
        "--expected",
        expected,
        "--language",
        "en-US",
        "--language-correction",
        "true" if correction else "false",
    ]
    if custom_word:
        cmd += ["--custom-word", expected]
    cmd.append(str(image))

    completed = subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)
    return json.loads(completed.stdout)


def main() -> None:
    manifest = []
    for line in (GENERATED / "manifest.tsv").read_text().splitlines():
        image_name, expected = line.split("\t")
        manifest.append((GENERATED / image_name, expected))

    rows = []
    for image, expected in manifest:
        for correction, custom_word in [
            (False, False),
            (True, False),
            (False, True),
            (True, True),
        ]:
            result = run_case(image, expected, correction, custom_word)
            rows.append(
                {
                    "image": image.name,
                    "expected": expected,
                    "best": result["normalizedBestText"],
                    "raw": result["bestText"],
                    "confidence": round(result["bestConfidence"], 3),
                    "distance": result.get("editDistance"),
                    "classification": result["classification"],
                    "has_strong_alternative": result["hasStrongAlternative"],
                    "correction": correction,
                    "custom_word": custom_word,
                    "top_candidates": [
                        {
                            "text": c["text"],
                            "confidence": round(c["confidence"], 3),
                        }
                        for c in result["candidates"][:3]
                    ],
                }
            )

    (GENERATED / "results.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

    header = [
        "image",
        "expected",
        "best",
        "confidence",
        "distance",
        "classification",
        "has_strong_alternative",
        "correction",
        "custom_word",
    ]
    print("\t".join(header))
    for row in rows:
        print(
            "\t".join(
                [
                    str(row[key])
                    for key in header
                ]
            )
        )


if __name__ == "__main__":
    main()
