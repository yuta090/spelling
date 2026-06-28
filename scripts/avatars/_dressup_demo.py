#!/usr/bin/env python3
"""Full dress-up vertical slice: same outfit + fixed shoes, swapping the 4 hairs."""
from PIL import Image
import avatar_lib as al

OUT = "out"
base   = Image.open(f"{OUT}/base_female.png").convert("RGBA")
top    = al.chroma_key_defringe(Image.open(f"{OUT}/part_top_red_tee.png"))
bottom = al.chroma_key_defringe(Image.open(f"{OUT}/part_bottom_blue_shorts.png"))
shoes  = Image.open(f"{OUT}/cut_shoes_white_v2.png")  # already aligned by _shoe_align.py

HAIRS = ["short_v2", "bob", "long_straight", "twin_high"]
LABELS = {"short_v2": "ショート", "bob": "ボブ", "long_straight": "ロング", "twin_high": "ツイン高"}

tiles = []
for name in HAIRS:
    hair = al.chroma_key_defringe(Image.open(f"{OUT}/part_hair_{name}.png"))
    out = al.compose(base, [bottom, shoes, top, hair])
    out.convert("RGB").save(f"{OUT}/dressup_{name}.png")
    tiles.append(out.convert("RGB"))
    print(f"[compose] dressup_{name}.png")

# montage 1x4
w, h = tiles[0].size
s = 0.4
tw, th = int(w * s), int(h * s)
sheet = Image.new("RGB", (tw * 4, th), "white")
for i, t in enumerate(tiles):
    sheet.paste(t.resize((tw, th)), (i * tw, 0))
sheet.save(f"{OUT}/dressup_grid.png")
print("[montage] dressup_grid.png", sheet.size)
