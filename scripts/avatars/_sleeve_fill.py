#!/usr/bin/env python3
"""長袖トップスの「前腕フチ隙間」を決定論で埋めるヘルパ。

codex image_gen は袖をうでの対角に沿わせても、前腕エッジに数px幅の素肌スリバーを残すことがある
(2026-06-30 top_blue_hoodie で発生: 594px)。本スクリプトは base のうで素肌に重なる隙間だけを、
最近接の袖色で塗って alpha=255 にし、袖をうで輪郭まで太らせる。袖以外(フード/胴/裾)は触らない。

使い方:
    python3 _sleeve_fill.py out/cut_new_hoodie.png out/cut_new_hoodie_v2.png \
        ../../iPadPrototype/Resources/avatars/base_female.png

QA: 実行後に compose して「うで帯の素肌px」が ≈0 か、マゼンタ残渣0 かを必ず再確認する。
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

# うで(袖)帯。胴/裾/フードを避け、肩下〜手首だけを対象にする。
ARM_BANDS = [(230, 470), (560, 800)]
ARM_Y = (620, 915)
MAX_GROW_PX = 10  # この距離内の隙間だけ埋める(袖を新規に生やさない安全弁)


def skin_mask(base_rgba: np.ndarray) -> np.ndarray:
    r, g, b, a = base_rgba[..., 0], base_rgba[..., 1], base_rgba[..., 2], base_rgba[..., 3]
    return (a > 128) & (r > 205) & (g > 150) & (g < 225) & (b > 120) & (b < 205)


def fill_forearm_gaps(garment: np.ndarray, base: np.ndarray) -> np.ndarray:
    out = garment.copy()
    opaque = out[..., 3] > 128
    skin = skin_mask(base)
    region = np.zeros(skin.shape, bool)
    for x0, x1 in ARM_BANDS:
        region[ARM_Y[0]:ARM_Y[1], x0:x1] = True
    exposed = region & skin & (~opaque)
    dist, (iy, ix) = ndi.distance_transform_edt(~opaque, return_indices=True)
    fillable = exposed & (dist <= MAX_GROW_PX)
    ys, xs = np.where(fillable)
    for ch in range(3):
        out[ys, xs, ch] = out[..., ch][iy, ix][ys, xs]
    out[ys, xs, 3] = 255
    return out, int(exposed.sum()), int(fillable.sum())


def main():
    src, dst, base_path = sys.argv[1], sys.argv[2], sys.argv[3]
    garment = np.array(Image.open(src).convert("RGBA"))
    base = np.array(Image.open(base_path).convert("RGBA"))
    out, before, filled = fill_forearm_gaps(garment, base)
    Image.fromarray(out).save(dst)
    print("exposed before=%d  filled=%d  -> %s" % (before, filled, dst))


if __name__ == "__main__":
    main()
