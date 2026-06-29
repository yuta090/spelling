#!/usr/bin/env python3
"""Generate the HomeRewardCharacter catalog in HomeView.swift from characters.csv.

characters.csv is the source of truth for the selectable home characters.
This script rewrites only the region between the CATALOG-GENERATED-BEGIN and
CATALOG-GENERATED-END markers; everything else in HomeView.swift is untouched.

The `style` column must reference an existing HomeRewardCharacterStyle case and
`category` an existing HomeRewardCharacterCategory case — those are drawing code
and live in HomeView.swift. This script only manages the data rows.

Usage:
    python3 scripts/generate_characters.py
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "scripts" / "characters.csv"
HOME_VIEW = ROOT / "iPadPrototype" / "HomeView.swift"

BEGIN = "    // CATALOG-GENERATED-BEGIN"
END = "    // CATALOG-GENERATED-END"

VALID_CATEGORIES = {
    "starter", "animal", "sea", "people", "vehicle", "building", "landmark",
    "japan", "food", "sports", "instruments", "insect", "dinosaur", "space",
    "cosme", "fantasy",
}
VALID_STYLES = {
    "bear", "cat", "dog", "rabbit", "panda", "penguin", "lion", "fox", "koala",
    "sheep", "elephant", "giraffe", "owl", "turtle", "whale", "bird",
    "car", "train", "rocket", "plane", "bus", "ship", "helicopter", "bicycle",
    "tractor", "balloon",
    "monkey", "pig",
    "personShort", "personLong", "personCurly", "personBun", "personBuzz",
    "personPonytail", "personTwintails", "personBob", "personAfro",
    "personSpiky", "personBraids", "personWavy",
    "robot", "ghost", "star", "unicorn", "dragon",
    "excavator", "crane", "dumpTruck",
    "house", "school", "castle", "tower",
    "lipstick", "perfume", "compact", "nailPolish",
    "octopus", "crab", "fish", "dolphin", "shark", "jellyfish", "starfish",
    "strawberry", "cake", "iceCream", "donut", "riceBall", "sushi", "hamburger",
    "soccerBall", "baseball", "basketball", "tennisBall", "trophy",
    "eiffel", "tokyoTower", "liberty", "pyramid", "pisa", "bigBen",
    "tajMahal", "fuji", "torii", "moai", "windmill", "colosseum",
    "greatWall", "operaHouse", "stonehenge", "christRedeemer", "sagrada",
    "goldenGate", "towerBridge", "ferrisWheel", "kinkaku", "sphinx",
    "angkor", "matterhorn",
    "libertyBell", "whiteHouse", "notreDame", "burjKhalifa", "archTriomphe",
    "skytree", "japaneseCastle", "pagoda", "daibutsu", "gasshou",
    "stBasil", "parthenon", "machuPicchu", "mosque", "montStMichel",
    "capitol", "petra", "kiyomizu", "tokyoStation", "templeHall",
    "duomo", "euroCastle", "mayanPyramid", "skyscraper", "starFort",
    "guitar", "piano", "drum", "trumpet", "violin",
    "butterfly", "beetle", "ladybug", "bee", "ant",
    "trex", "triceratops", "stegosaurus", "brachiosaurus", "pteranodon",
    "astronaut", "ufo", "saturn", "moon", "alien",
    "alienBlob", "alienTriclops", "alienSquid", "alienWorm", "alienMushroom",
    "alienBugeye", "alienCrystal", "alienHover",
    "velociraptor", "ankylosaurus", "spinosaurus", "parasaurolophus",
    "plesiosaurus", "dinoEgg",
    "mouse", "cow", "horse", "wolf", "kangaroo", "bat", "goat",
    "otter", "orca", "seahorse", "shrimp",
    "duck", "flamingo", "parrot", "swan",
    "snail", "dragonfly",
    "banana", "taiyaki", "cookie",
    # 画像ベースの「なかま」共通スタイル。画像は id から nakama_<id>(WebP DataSet) で引く。
    "imageAsset",
}


def hex_to_color(value: str) -> str:
    h = value.strip().lstrip("#")
    if len(h) != 6:
        raise ValueError(f"Bad hex color: {value!r}")
    r = int(h[0:2], 16) / 255
    g = int(h[2:4], 16) / 255
    b = int(h[4:6], 16) / 255
    return f"Color(red: {r:.4f}, green: {g:.4f}, blue: {b:.4f})"


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def load_rows():
    with CSV_PATH.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit("characters.csv has no rows.")

    seen_ids = set()
    for i, row in enumerate(rows, start=2):  # header is line 1
        cid = (row.get("id") or "").strip()
        if not cid:
            raise SystemExit(f"Row {i}: missing id")
        if cid in seen_ids:
            raise SystemExit(f"Row {i}: duplicate id {cid!r}")
        seen_ids.add(cid)
        if row["category"] not in VALID_CATEGORIES:
            raise SystemExit(f"Row {i} ({cid}): unknown category {row['category']!r}")
        if row["style"] not in VALID_STYLES:
            raise SystemExit(f"Row {i} ({cid}): unknown style {row['style']!r}")
        if row["style"] == "imageAsset":
            # 画像ベースは Assets の Data Set `nakama_<id>` が必須（無いとアプリで 🐾 に化ける）
            ds = ROOT / "iPadPrototype" / "Assets.xcassets" / f"nakama_{cid}.dataset" / "Contents.json"
            if not ds.exists():
                raise SystemExit(
                    f"Row {i} ({cid}): style=imageAsset だが画像が無い → "
                    f"iPadPrototype/Assets.xcassets/nakama_{cid}.dataset/ を作って WebP を入れて"
                )
        int(row["price"])  # validate
    return rows


def render(rows) -> str:
    lines = [BEGIN]
    default_id = next((r["id"] for r in rows if r["category"] == "starter"), rows[0]["id"])
    lines.append(f'    static let defaultID = "{swift_string(default_id)}"')
    lines.append("")
    unlocked = [
        r["id"] for r in rows if (r.get("default_unlocked", "").strip().lower() == "true")
    ]
    unlocked_literal = ", ".join(f'"{swift_string(u)}"' for u in unlocked)
    lines.append(f"    static let defaultUnlockedIDs: Set<String> = [{unlocked_literal}]")
    lines.append("")
    lines.append("    static let catalog: [HomeRewardCharacter] = [")

    for index, row in enumerate(rows):
        trailing = "," if index < len(rows) - 1 else ""
        lines.append("        HomeRewardCharacter(")
        lines.append(f'            id: "{swift_string(row["id"])}",')
        lines.append(f'            category: .{row["category"]},')
        lines.append(f'            japaneseName: "{swift_string(row["ja_name"])}",')
        lines.append(f'            englishName: "{swift_string(row["en_name"])}",')
        lines.append(f'            price: {int(row["price"])},')
        lines.append(f'            style: .{row["style"]},')
        lines.append(f'            primary: {hex_to_color(row["primary_hex"])},')
        lines.append(f'            secondary: {hex_to_color(row["secondary_hex"])},')
        lines.append(f'            accent: {hex_to_color(row["accent_hex"])}')
        lines.append(f"        ){trailing}")

    lines.append("    ]")
    lines.append(END)
    return "\n".join(lines)


def main() -> None:
    rows = load_rows()
    text = HOME_VIEW.read_text(encoding="utf-8")
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    updated = text[:start] + render(rows) + text[end:]
    HOME_VIEW.write_text(updated, encoding="utf-8")
    print(f"Regenerated catalog: {len(rows)} characters → {HOME_VIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
