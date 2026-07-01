#!/usr/bin/env python3
"""探索画像をグリッド1枚にまとめて『選ぶ』ためのコンタクトシートを作る。

使い方:
  python3 contact_sheet.py DIR [--out sheet.png] [--cols 4] [--cell 320]

DIR 内の *.png/*.jpg を名前順に並べ、ファイル名ラベル付きで格子に配置する。
白背景に並べるので透過/白背景どちらでも見やすい。
"""
import argparse
import glob
import os
from PIL import Image, ImageDraw, ImageFont


def load_font(size: int):
    for p in [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--out", default="")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--cell", type=int, default=320)
    args = ap.parse_args()

    files = sorted(
        f for ext in ("*.png", "*.jpg", "*.jpeg", "*.webp")
        for f in glob.glob(os.path.join(args.dir, ext))
    )
    if not files:
        print(f"no images in {args.dir}")
        return

    cell, cols = args.cell, args.cols
    label_h = 26
    rows = (len(files) + cols - 1) // cols
    W = cols * cell
    H = rows * (cell + label_h)
    sheet = Image.new("RGB", (W, H), (245, 245, 245))
    draw = ImageDraw.Draw(sheet)
    font = load_font(16)

    for i, f in enumerate(files):
        r, c = divmod(i, cols)
        x0, y0 = c * cell, r * (cell + label_h)
        try:
            im = Image.open(f).convert("RGBA")
        except Exception:
            continue
        im.thumbnail((cell - 12, cell - 12), Image.LANCZOS)
        bg = Image.new("RGBA", (cell, cell), (255, 255, 255, 255))
        bg.paste(im, ((cell - im.width) // 2, (cell - im.height) // 2), im)
        sheet.paste(bg.convert("RGB"), (x0, y0))
        draw.text((x0 + 6, y0 + cell + 4), os.path.basename(f), fill=(40, 40, 40), font=font)

    out = args.out or os.path.join(args.dir, "_contact_sheet.png")
    sheet.save(out)
    print(f"wrote {out}  ({len(files)} images, {cols}x{rows})")


if __name__ == "__main__":
    main()
