#!/usr/bin/env python3
"""Extract the 4 new hair parts and composite each over base_female for review."""
from PIL import Image
import avatar_lib as al

OUT = "out"
base = Image.open(f"{OUT}/base_female.png").convert("RGBA")

HAIRS = [
    ("short_v2",      "part_hair_short_v2.png"),
    ("bob",           "part_hair_bob.png"),
    ("long_straight", "part_hair_long_straight.png"),
    ("twin_high",     "part_hair_twin_high.png"),
]

for name, src in HAIRS:
    rgba = al.chroma_key_defringe(Image.open(f"{OUT}/{src}"))
    rgba.save(f"{OUT}/cut_hair_{name}.png")
    box = al.bbox(rgba)
    print(f"{name:14s} bbox={box}")
    out = al.compose(base, [rgba])
    out.convert("RGB").save(f"{OUT}/hairtest_{name}.png")
print("done")
