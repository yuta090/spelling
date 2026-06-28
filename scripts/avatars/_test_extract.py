#!/usr/bin/env python3
"""One-off capability test: evaluate two hair-layer extraction strategies."""
import numpy as np
from PIL import Image, ImageFilter

OUT = "out"
base = Image.open(f"{OUT}/base_female.png").convert("RGB")
W, H = base.size
base_a = np.asarray(base).astype(np.int16)

# ---------- Strategy 1: chroma key the magenta part image ----------
chroma = Image.open(f"{OUT}/test_hair_chroma.png").convert("RGB").resize((W, H))
c = np.asarray(chroma).astype(np.int16)
# distance from pure magenta (255,0,255)
dist_mag = np.abs(c - np.array([255, 0, 255])).sum(axis=2)
hair_mask = dist_mag > 120          # not magenta => hair
alpha = (hair_mask * 255).astype(np.uint8)
hair_rgba = np.dstack([np.asarray(chroma).astype(np.uint8), alpha])
Image.fromarray(hair_rgba, "RGBA").save(f"{OUT}/test_hair_cut.png")
# composite cut hair over base
over = base.convert("RGBA")
over.alpha_composite(Image.fromarray(hair_rgba, "RGBA"))
over.convert("RGB").save(f"{OUT}/test_overlay_chroma.png")

# ----- defringe: erode alpha ~2px + decontaminate magenta-tinted edge pixels -----
alpha_img = Image.fromarray(alpha).filter(ImageFilter.MinFilter(5))  # shrink ~2px
alpha2 = np.asarray(alpha_img)
rgb = np.asarray(chroma).astype(np.int16)
# kill magenta spill: pull down red/blue where they exceed green (magenta cast)
g = rgb[..., 1]
rgb[..., 0] = np.minimum(rgb[..., 0], g + 25)
rgb[..., 2] = np.minimum(rgb[..., 2], g + 25)
hair_rgba2 = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), alpha2])
Image.fromarray(hair_rgba2, "RGBA").save(f"{OUT}/test_hair_cut_defringed.png")
over2 = base.convert("RGBA")
over2.alpha_composite(Image.fromarray(hair_rgba2, "RGBA"))
over2.convert("RGB").save(f"{OUT}/test_overlay_chroma_defringed.png")
hair_px = int(hair_mask.sum())
# bbox of hair
ys, xs = np.where(hair_mask)
bbox1 = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())) if hair_px else None
print(f"[chroma] hair pixels = {hair_px} ({100*hair_px/(W*H):.1f}% of canvas), bbox={bbox1}")

# ---------- Strategy 2: diff composite vs base ----------
comp = Image.open(f"{OUT}/test_composite_hair.png").convert("RGB").resize((W, H))
d = np.abs(np.asarray(comp).astype(np.int16) - base_a).sum(axis=2)
changed = d > 40
ch_px = int(changed.sum())
# how much change is in the TOP third (head/hair zone) vs lower 2/3 (body = should be unchanged)
top = changed[: H // 3].sum()
bottom = changed[H // 3 :].sum()
print(f"[diff]  changed pixels = {ch_px} ({100*ch_px/(W*H):.1f}%), top-third={int(top)}, lower-two-thirds={int(bottom)}")
print(f"[diff]  base-drift indicator = {100*bottom/max(ch_px,1):.1f}% of changes are on the BODY (lower 2/3) => high = base NOT preserved")
# visualize diff
heat = np.zeros((H, W, 3), np.uint8)
heat[..., 0] = (np.clip(d, 0, 255)).astype(np.uint8)
Image.fromarray(heat).save(f"{OUT}/test_diff_heat.png")
# extracted hair via diff (composite where changed) over base
mask3 = np.dstack([changed] * 3)
extracted = np.where(mask3, np.asarray(comp), np.asarray(base))
Image.fromarray(extracted.astype(np.uint8)).save(f"{OUT}/test_diff_extracted.png")
