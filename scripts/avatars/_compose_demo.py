#!/usr/bin/env python3
"""Demo: extract chroma parts and composite a dressed avatar (+ a hair swap)."""
from PIL import Image
import avatar_lib as al

OUT = "out"
base = Image.open(f"{OUT}/base_female.png").convert("RGBA")

def cut(name, src):
    rgba = al.chroma_key_defringe(Image.open(f"{OUT}/{src}"))
    rgba.save(f"{OUT}/cut_{name}.png")
    _, ox, oy = al.crop_with_offset(rgba)
    box = al.bbox(rgba)
    print(f"  {name:12s} bbox={box} offset=({ox},{oy})")
    return rgba

print("[extract]")
top    = cut("top_red_tee",     "part_top_red_tee.png")
bottom = cut("bottom_shorts",   "part_bottom_blue_shorts.png")
shoes  = cut("shoes_white",     "part_shoes_white.png")
hair_t = cut("hair_twin",       "part_hair_twin.png")
hair_s = cut("hair_short",      "test_hair_chroma.png")  # from the first test

# z-order: back_hair, base, bottom, shoes, top, outer, face, front_hair, accessory
def dress(hair, fname):
    out = al.compose(base, [bottom, shoes, top, hair])
    out.convert("RGB").save(f"{OUT}/{fname}")
    print(f"[compose] {fname}")

print("[compose]")
dress(hair_t, "dressed_twin.png")     # full outfit + twin tails
dress(hair_s, "dressed_short.png")    # same outfit, short hair (swap demo)
# outfit with no top (swap-off demo)
al.compose(base, [bottom, shoes, hair_s]).convert("RGB").save(f"{OUT}/dressed_notop.png")
print("[compose] dressed_notop.png")
