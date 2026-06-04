from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "generated"
BIN = ROOT / ".build" / "release" / "spelling-ocr-lab"


def run_case(image: Path, expected: str, correction: bool) -> dict:
    cmd = [
        str(BIN),
        "--expected",
        expected,
        "--language",
        "en-US",
        "--language-correction",
        "true" if correction else "false",
        "--custom-word",
        expected,
        str(image),
    ]
    completed = subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)
    return json.loads(completed.stdout)


def main() -> None:
    rows = []
    for line in (GENERATED / "stroke_manifest.tsv").read_text().splitlines():
        image_name, expected = line.split("\t")
        image = GENERATED / image_name
        for correction in [False, True]:
            result = run_case(image, expected, correction)
            rows.append(
                {
                    "image": image.name,
                    "expected": expected,
                    "best": result["normalizedBestText"],
                    "raw": result["bestText"],
                    "confidence": round(result["bestConfidence"], 3),
                    "distance": result.get("editDistance"),
                    "classification": result["classification"],
                    "correction": correction,
                    "top_candidates": [
                        {
                            "text": c["text"],
                            "confidence": round(c["confidence"], 3),
                        }
                        for c in result["candidates"][:3]
                    ],
                }
            )

    (GENERATED / "stroke_results.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

    print("image\texpected\tbest\tconfidence\tdistance\tclassification\tcorrection")
    for row in rows:
        print(
            f"{row['image']}\t{row['expected']}\t{row['best']}\t{row['confidence']}\t"
            f"{row['distance']}\t{row['classification']}\t{row['correction']}"
        )


if __name__ == "__main__":
    main()
