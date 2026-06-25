#!/usr/bin/env python3
"""Generate the image-backed HomeBackgroundTheme catalog in HomeView.swift from backgrounds.csv.

backgrounds.csv is the source of truth for the *image* home backgrounds. The
procedural (hand-drawn SwiftUI) themes stay hand-written in HomeView.swift; this
script only manages the `imageThemes` array between the BG-CATALOG-GENERATED
markers. Everything else in HomeView.swift is untouched.

CSV columns:
    id,category,ja_name,en_name,price,default_unlocked,render,image,art_prompt

- render == "procedural": existing hand-drawn theme. Listed for management only;
  NOT emitted here (its colors/scene live in HomeView.swift).
- render == "image": emitted as a HomeBackgroundTheme(imageName:). The `image`
  column is the PNG file name of an imageset that must already exist in
  Assets.xcassets (e.g. "bg_forest.png" -> imageset "bg_forest").

Usage:
    python3 scripts/generate_backgrounds.py
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "scripts" / "backgrounds.csv"
HOME_VIEW = ROOT / "iPadPrototype" / "HomeView.swift"
ASSETS_DIR = ROOT / "iPadPrototype" / "Assets.xcassets"

BEGIN = "    // BG-CATALOG-GENERATED-BEGIN"
END = "    // BG-CATALOG-GENERATED-END"

VALID_RENDER = {"procedural", "image"}


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def load_rows():
    with CSV_PATH.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit("backgrounds.csv has no rows.")

    seen_ids = set()
    for i, row in enumerate(rows, start=2):  # header is line 1
        cid = (row.get("id") or "").strip()
        if not cid:
            raise SystemExit(f"Row {i}: missing id")
        if cid in seen_ids:
            raise SystemExit(f"Row {i}: duplicate id {cid!r}")
        seen_ids.add(cid)

        render = (row.get("render") or "").strip()
        if render not in VALID_RENDER:
            raise SystemExit(f"Row {i} ({cid}): unknown render {render!r}")
        try:
            price = int((row.get("price") or "").strip())
        except ValueError:
            raise SystemExit(f"Row {i} ({cid}): price {row.get('price')!r} is not an integer")
        if price < 0:
            raise SystemExit(f"Row {i} ({cid}): price must be >= 0, got {price}")

        if render == "image":
            image = (row.get("image") or "").strip()
            if not image:
                raise SystemExit(f"Row {i} ({cid}): render=image needs an image file name")
            imageset = ASSETS_DIR / f"{Path(image).stem}.imageset"
            if not imageset.is_dir():
                raise SystemExit(
                    f"Row {i} ({cid}): missing imageset {imageset.relative_to(ROOT)} "
                    f"(add the image to Assets.xcassets first)"
                )
            if not (imageset / image).is_file():
                raise SystemExit(
                    f"Row {i} ({cid}): {image} not found inside {imageset.relative_to(ROOT)}"
                )
    return rows


def render_block(rows) -> str:
    image_rows = [r for r in rows if (r.get("render") or "").strip() == "image"]
    lines = [
        BEGIN,
        "    // Image-backed themes. Source of truth: scripts/backgrounds.csv",
        "    // Regenerate with: python3 scripts/generate_backgrounds.py",
        "    static let imageThemes: [HomeBackgroundTheme] = [",
    ]
    for index, row in enumerate(image_rows):
        trailing = "," if index < len(image_rows) - 1 else ""
        name = Path((row.get("image") or "").strip()).stem
        lines.append(
            "        HomeBackgroundTheme("
            f'id: "{swift_string(row["id"].strip())}", '
            f'japaneseName: "{swift_string(row["ja_name"].strip())}", '
            f'englishName: "{swift_string(row["en_name"].strip())}", '
            f'price: {int(row["price"])}, '
            f'imageName: "{swift_string(name)}"'
            f"){trailing}"
        )
    lines.append("    ]")
    lines.append(END)
    return "\n".join(lines)


def main() -> None:
    rows = load_rows()
    text = HOME_VIEW.read_text(encoding="utf-8")
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise SystemExit("HomeView.swift must contain exactly one BG-CATALOG-GENERATED begin/end marker")
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    if start >= end:
        raise SystemExit("BG-CATALOG-GENERATED-BEGIN must come before END in HomeView.swift")
    updated = text[:start] + render_block(rows) + text[end:]
    HOME_VIEW.write_text(updated, encoding="utf-8")
    image_count = sum(1 for r in rows if (r.get("render") or "").strip() == "image")
    print(f"Regenerated imageThemes: {image_count} image backgrounds → {HOME_VIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
