#!/usr/bin/env python3
"""Split a shoe-pair part into L/R and snap each shoe onto the base foot centers.

Solves the 'nudging the combined layer moves both shoes' problem: we cut the pair
at the magenta gap, then translate each shoe independently so its center matches
the measured base foot center and its sole sits at the base sole line.
"""
import numpy as np
from PIL import Image
import avatar_lib as al

OUT = "out"
# measured from base_female.png
FOOT_CENTERS = (438, 577)   # (left, right) image-x
SOLE_Y = 1459               # base sole bottom

def runs_of(cols):
    rs, inrun = [], False
    for x, on in enumerate(cols):
        if on and not inrun: st, inrun = x, True
        elif not on and inrun: rs.append((st, x - 1)); inrun = False
    if inrun: rs.append((st, len(cols) - 1))
    return rs

def align_shoes(src):
    rgba = al.chroma_key_defringe(Image.open(f"{OUT}/{src}"))
    arr = np.asarray(rgba)
    a = arr[..., 3]
    H, W = a.shape
    cols = a.any(0)
    rs = [r for r in runs_of(cols) if r[1] - r[0] > 20]
    rs = sorted(rs, key=lambda r: r[0])[:2]
    if len(rs) != 2:
        print(f"  WARN: found {len(rs)} shoe runs, expected 2 -> using as-is")
        return rgba
    out = np.zeros_like(arr)
    for (s, e), cx_target in zip(rs, FOOT_CENTERS):
        # tight crop of this shoe (full height span of its columns)
        sub = arr[:, s:e + 1, :]
        srows = sub[..., 3].any(1)
        ys = np.where(srows)[0]
        top, bot = ys.min(), ys.max()
        shoe = arr[top:bot + 1, s:e + 1, :]
        sh_h, sh_w = shoe.shape[:2]
        cx_cur = (s + e) // 2
        dx = cx_target - cx_cur
        new_left = s + dx
        new_top = SOLE_Y - sh_h + 1            # snap sole to base sole line
        # paste into out
        x0 = max(0, new_left); y0 = max(0, new_top)
        sx0 = x0 - new_left; sy0 = y0 - new_top
        x1 = min(W, new_left + sh_w); y1 = min(H, new_top + sh_h)
        seg = shoe[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0), :]
        # alpha-aware paste
        dst = out[y0:y1, x0:x1, :]
        am = seg[..., 3:4] / 255.0
        dst[:] = (seg * am + dst * (1 - am)).astype(np.uint8)
        print(f"  shoe x={s}-{e} (c{cx_cur}) -> center {cx_target} (dx{dx:+d}), w={sh_w} h={sh_h} top->{new_top}")
    res = Image.fromarray(out, "RGBA")
    res.save(f"{OUT}/cut_shoes_white_v2.png")
    return res

if __name__ == "__main__":
    print("[align shoes]")
    shoes = align_shoes("part_shoes_white_v2.png")
    base = Image.open(f"{OUT}/base_female.png").convert("RGBA")
    top = al.chroma_key_defringe(Image.open(f"{OUT}/part_top_red_tee.png"))
    bottom = al.chroma_key_defringe(Image.open(f"{OUT}/part_bottom_blue_shorts.png"))
    hair = al.chroma_key_defringe(Image.open(f"{OUT}/part_hair_short_v2.png"))
    # z-order: base, bottom, shoes, top, front_hair
    out = al.compose(base, [bottom, shoes, top, hair])
    out.convert("RGB").save(f"{OUT}/dressed_shoes_v2.png")
    print("[compose] dressed_shoes_v2.png")
