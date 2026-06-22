#!/usr/bin/env python3
"""One-time bootstrap: parse the existing HomeRewardCharacter.catalog block in
HomeView.swift and emit scripts/characters.csv.

After this runs, characters.csv is the source of truth and generate_characters.py
regenerates the Swift catalog from it. This bootstrap is only needed once.
"""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOME_VIEW = ROOT / "iPadPrototype" / "HomeView.swift"
OUT_CSV = ROOT / "scripts" / "characters.csv"

DEFAULT_UNLOCKED = {"bear", "cat", "dog"}

ENTRY_RE = re.compile(
    r"""HomeRewardCharacter\(\s*
        id:\s*"(?P<id>[^"]+)",\s*
        category:\s*\.(?P<category>\w+),\s*
        japaneseName:\s*"(?P<ja>[^"]*)",\s*
        englishName:\s*"(?P<en>[^"]*)",\s*
        price:\s*(?P<price>\d+),\s*
        style:\s*\.(?P<style>\w+),\s*
        primary:\s*(?P<primary>Color\([^)]*\)),\s*
        secondary:\s*(?P<secondary>Color\([^)]*\)),\s*
        accent:\s*(?P<accent>Color\([^)]*\))\s*
        \)""",
    re.VERBOSE,
)

COLOR_RE = re.compile(
    r"Color\(red:\s*([\d.]+),\s*green:\s*([\d.]+),\s*blue:\s*([\d.]+)\)"
)


def color_to_hex(color_literal: str) -> str:
    m = COLOR_RE.search(color_literal)
    if not m:
        raise ValueError(f"Unparseable color: {color_literal}")
    r, g, b = (round(float(v) * 255) for v in m.groups())
    return f"#{r:02X}{g:02X}{b:02X}"


def main() -> None:
    text = HOME_VIEW.read_text(encoding="utf-8")
    rows = []
    for m in ENTRY_RE.finditer(text):
        rows.append(
            {
                "id": m["id"],
                "category": m["category"],
                "ja_name": m["ja"],
                "en_name": m["en"],
                "price": m["price"],
                "style": m["style"],
                "primary_hex": color_to_hex(m["primary"]),
                "secondary_hex": color_to_hex(m["secondary"]),
                "accent_hex": color_to_hex(m["accent"]),
                "default_unlocked": "true" if m["id"] in DEFAULT_UNLOCKED else "false",
            }
        )

    if not rows:
        raise SystemExit("No catalog entries found — aborting.")

    fields = [
        "id",
        "category",
        "ja_name",
        "en_name",
        "price",
        "style",
        "primary_hex",
        "secondary_hex",
        "accent_hex",
        "default_unlocked",
    ]
    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} characters to {OUT_CSV.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
