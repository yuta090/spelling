#!/usr/bin/env python3
"""Self-contained tests for avatar_lib.chroma_key_defringe (no pytest needed).

Run: python3 test_avatar_lib.py   (exit 0 = all pass, 1 = failure)

The chroma-key must
  - remove the real magenta paint (backdrop + enclosed PURE-magenta gaps between strands),
  - remove only a BOUNDED antialiased halo around that paint,
  - KEEP near-magenta FOREGROUND (pink/purple clothing) opaque, whether enclosed OR
    exposed to the backdrop (an exposed pink part only loses its thin halo rim, not its body),
  - and only de-spill the foreground edge ring next to the backdrop (not interiors).
"""
import sys
import numpy as np
from PIL import Image
import avatar_lib as al

MAG = (255, 0, 255)
_fails = []


def check(cond, msg):
    print(("  ok  " if cond else "FAIL  ") + msg)
    if not cond:
        _fails.append(msg)


def img(arr):
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def fill(arr, r0, r1, c0, c1, color):
    arr[r0:r1 + 1, c0:c1 + 1] = color


# ---------- 1. basic backdrop key ----------
a = np.zeros((12, 12, 3), np.uint8); a[:] = MAG
fill(a, 4, 7, 4, 7, (0, 200, 0))                 # green object, not touching border
out = np.asarray(al.chroma_key_defringe(img(a), erode_px=0, decontaminate=False))
check(out[0, 0, 3] == 0, "backdrop magenta -> transparent")
check(out[5, 5, 3] == 255, "green object -> opaque")

# ---------- 2/3. enclosed pure gap removed, enclosed pink kept ----------
a = np.zeros((24, 24, 3), np.uint8); a[:] = MAG
fill(a, 4, 19, 4, 19, (0, 180, 0))               # green body
fill(a, 6, 7, 6, 7, (255, 0, 255))               # enclosed PURE magenta (a gap)
fill(a, 14, 16, 14, 16, (255, 80, 255))          # enclosed PINK foreground (dist 80), far from gap
out = np.asarray(al.chroma_key_defringe(img(a), erode_px=0, decontaminate=False))
check(out[0, 0, 3] == 0, "border backdrop -> transparent")
check(out[11, 11, 3] == 255, "green body -> opaque")
check(out[6, 6, 3] == 0, "enclosed PURE-magenta gap -> transparent")
check(out[15, 15, 3] == 255, "enclosed PINK foreground -> KEPT opaque")

# ---------- 3b. EXPOSED pink touching backdrop: body kept, only halo rim eaten ----------
a = np.zeros((24, 24, 3), np.uint8); a[:] = MAG
fill(a, 8, 15, 8, 15, (255, 80, 255))            # pink part directly on magenta (no outline)
out = np.asarray(al.chroma_key_defringe(img(a), erode_px=0, decontaminate=False, halo_px=3))
check(out[12, 12, 3] == 255, "exposed PINK body (>halo_px from backdrop) -> KEPT opaque (bug fix)")
check(out[8, 8, 3] == 0, "exposed PINK rim (within halo_px) -> eaten as halo")

# ---------- 4. decontamination is edge-only ----------
a = np.zeros((20, 20, 3), np.uint8); a[:] = MAG
fill(a, 5, 14, 5, 14, (200, 50, 200))            # magenta-tinted object (dist 160, solid fg)
out = np.asarray(al.chroma_key_defringe(img(a), erode_px=0, decontaminate=True, ring_px=3))
check(tuple(out[9, 9, :3]) == (200, 50, 200), "interior spill color preserved (not desaturated)")
check(tuple(out[5, 9, :3]) == (75, 50, 75), "edge spill next to backdrop is tamed (g+25)")

# ---------- 5. erode shrinks foreground ----------
a = np.zeros((10, 10, 3), np.uint8); a[:] = MAG
fill(a, 3, 6, 3, 6, (0, 200, 0))
out = np.asarray(al.chroma_key_defringe(img(a), erode_px=1, decontaminate=False))
check(out[3, 3, 3] == 0, "erode removes 1px corner")
check(out[4, 4, 3] == 255, "erode keeps interior")

# ---------- 6. all-magenta -> fully transparent, no crash ----------
a = np.zeros((8, 8, 3), np.uint8); a[:] = MAG
res = al.chroma_key_defringe(img(a))
check(al.bbox(res) is None, "all-magenta -> empty bbox (fully transparent)")

print()
if _fails:
    print(f"{len(_fails)} FAILED")
    sys.exit(1)
print("ALL PASS")
