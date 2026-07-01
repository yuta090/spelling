#!/usr/bin/env python3
"""背景PNGを 1448x1086 に整え、Assets.xcassets/bg_<id>.imageset/ に配置する(image モードの統合)。

- 入力画像を 1448x1086 に cover(中央 crop) または contain でリサイズ
- bg_<id>.imageset/ を作り、bg_<id>.png と Contents.json を書く
- backgrounds.csv の編集と generate_backgrounds.py の実行は行わない(SKILL.md の手順参照)

使い方:
  python3 place_asset.py <src.png> --id zoo
  python3 place_asset.py <src.png> --id zoo --fit contain   # 余白を入れて全体を残す
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageOps

SHIP = (1448, 1086)


def find_assets_dir(repo=""):
    # --repo 指定時はその worktree/リポジトリの Assets.xcassets を使う(統合は worktree 上で行うため)
    if repo:
        cand = Path(repo).expanduser().resolve() / "iPadPrototype" / "Assets.xcassets"
        if cand.is_dir():
            return cand
        raise SystemExit(f"--repo に Assets.xcassets が無い: {cand}")
    here = Path(__file__).resolve()
    for base in here.parents:
        cand = base / "iPadPrototype" / "Assets.xcassets"
        if cand.is_dir():
            return cand
    raise SystemExit("Assets.xcassets が見つからない（リポジトリ内で実行して）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--id", required=True)
    ap.add_argument("--fit", choices=["cover", "contain"], default="cover")
    ap.add_argument("--bg", default="#FFFFFF", help="contain 時の余白色")
    ap.add_argument("--repo", default="", help="対象リポジトリ/worktree のルート(統合は worktree 上で)。未指定なら自動検出")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.exists():
        raise SystemExit(f"not found: {src}")

    im = Image.open(src).convert("RGB")
    if args.fit == "cover":
        out = ImageOps.fit(im, SHIP, method=Image.LANCZOS, centering=(0.5, 0.5))
    else:
        out = ImageOps.contain(im, SHIP, method=Image.LANCZOS)
        canvas = Image.new("RGB", SHIP, args.bg)
        canvas.paste(out, ((SHIP[0] - out.width) // 2, (SHIP[1] - out.height) // 2))
        out = canvas

    assets = find_assets_dir(args.repo)
    name = f"bg_{args.id}"
    iset = assets / f"{name}.imageset"
    iset.mkdir(parents=True, exist_ok=True)
    png = iset / f"{name}.png"
    out.save(png)
    contents = {
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (iset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {png}  ({out.width}x{out.height}, fit={args.fit})")
    print(f"次: backgrounds.csv に render=image, image={name}.png 行を足して generate_backgrounds.py を実行")


if __name__ == "__main__":
    main()
