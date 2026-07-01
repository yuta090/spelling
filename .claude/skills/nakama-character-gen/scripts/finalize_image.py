#!/usr/bin/env python3
"""codex が出した『なかま』完成画像を、アプリ搭載用の透過 WebP(+任意PNG/複数倍率) に仕上げる。

入力は次のどちらでもよい:
  - 既に透過済みの RGBA PNG (codex が自前でアルファ化したもの) → そのまま trim/pad/resize
  - マゼンタ単色背景の不透過画像                              → --chroma でクロマキー透過してから処理

使い方:
  python3 finalize_image.py IN.png --id hamster --out OUTDIR [--chroma] \
      [--size 512] [--scales 1,2,3] [--png] [--webp-quality 90]

出力:
  OUTDIR/<id>.webp                 (--scales 未指定時, size px)
  OUTDIR/<id>@1x.webp / @2x / @3x  (--scales 1,2,3 指定時; base = size)
  OUTDIR/<id>.png                  (--png も付けたとき)
"""
import argparse
import os
from PIL import Image

import nakama_lib as nl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--id", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--chroma", action="store_true", help="単色背景をクロマキー透過する")
    ap.add_argument("--autokey", action="store_true",
                    help="背景色を四隅から自動推定してキーする(agyのマゼンタ色ドリフトに強い)。--chroma と併用")
    ap.add_argument("--key", default="", help="キー色を hex で明示(例 #FF00FF)。--chroma と併用、--autokey 優先")
    ap.add_argument("--size", type=int, default=512, help="基準サイズ(正方形, px)")
    ap.add_argument("--scales", default="", help="例 '1,2,3' で @1x/@2x/@3x を出力(base=size)")
    ap.add_argument("--png", action="store_true", help="PNG も併せて出力")
    ap.add_argument("--webp-quality", type=int, default=95)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    img = Image.open(args.input).convert("RGBA")

    if args.chroma:
        if args.autokey:
            key = nl.detect_bg_color(img)
            print(f"  autokey bg = {key}")
        elif args.key:
            h = args.key.lstrip("#")
            key = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
        else:
            key = (255, 0, 255)
        img = nl.chroma_key_to_alpha(img, key=key)

    img = nl.autotrim(img)
    img = nl.pad_to_square(img)

    scales = [int(s) for s in args.scales.split(",") if s.strip()]
    if scales:
        for s in scales:
            out = nl.resize(img, args.size * s)
            nl.save_webp(out, os.path.join(args.out, f"{args.id}@{s}x.webp"), args.webp_quality)
            if args.png:
                nl.save_png(out, os.path.join(args.out, f"{args.id}@{s}x.png"))
        base = args.size
    else:
        out = nl.resize(img, args.size)
        nl.save_webp(out, os.path.join(args.out, f"{args.id}.webp"), args.webp_quality)
        if args.png:
            nl.save_png(out, os.path.join(args.out, f"{args.id}.png"))
        base = args.size

    # サイズ報告
    for f in sorted(os.listdir(args.out)):
        if f.startswith(args.id):
            p = os.path.join(args.out, f)
            kb = os.path.getsize(p) / 1024
            print(f"  {f}: {kb:.1f} KB")
    print(f"done: {args.id} (base {base}px)")


if __name__ == "__main__":
    main()
