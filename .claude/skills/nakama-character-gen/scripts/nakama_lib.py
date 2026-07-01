#!/usr/bin/env python3
"""なかまキャラ画像の後処理ユーティリティ。

- chroma_key_to_alpha: 単色(マゼンタ)背景を本物のアルファに変換＋縁の色被り除去(defringe)
- autotrim:            アルファの bbox で余白を切る
- pad_to_square:       正方形にパディング(均等余白)
- resize:              指定サイズへ縮小(高品質)
- save_png / save_webp

依存: Pillow, numpy。avatar pipeline の avatar_lib.py の手法を踏襲。
"""
from __future__ import annotations
import numpy as np
from PIL import Image


def chroma_key_to_alpha(
    img: Image.Image,
    key=(255, 0, 255),
    dist_thresh: int = 90,
    soft: int = 30,
    defringe: bool = True,
) -> Image.Image:
    """単色 key 背景を透過にする。

    dist_thresh 以内の色を完全透過、dist_thresh..(dist_thresh+soft) を半透過にして縁を滑らかに。
    defringe=True で『マゼンタ被りの縁ピクセル』のみ色を中和する(服や肌の赤青は残す)。
    """
    rgba = img.convert("RGBA")
    arr = np.asarray(rgba).astype(np.int32)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    kr, kg, kb = key
    dist = np.sqrt((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2)

    alpha = np.clip((dist - dist_thresh) / max(soft, 1) * 255.0, 0, 255)
    alpha = np.minimum(alpha, a)  # 元のアルファも尊重

    if defringe:
        # マゼンタ被り(R>G かつ B>G)の縁だけ G を引き上げて中和。赤(R大B小)・青(B大R小)は守る。
        fringe = (r > g + 25) & (b > g + 25) & (alpha > 0) & (alpha < 255)
        new_g = np.where(fringe, np.minimum(255, (r + b) // 2), g)
        g = new_g

    out = np.stack([r, g, b, alpha], axis=-1).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def detect_bg_color(img: Image.Image, patch: int = 24):
    """四隅の小パッチの中央値から背景色を推定する。

    agy のマゼンタ背景は純 #FF00FF でなく (253,39,249) 等にドリフトする(JPEG由来)。
    固定キーでなく実際の背景色でキーすると縁が綺麗に抜ける。
    """
    rgb = np.asarray(img.convert("RGB"))
    h, w, _ = rgb.shape
    p = min(patch, h // 4, w // 4)
    corners = np.concatenate([
        rgb[:p, :p].reshape(-1, 3),
        rgb[:p, w - p:].reshape(-1, 3),
        rgb[h - p:, :p].reshape(-1, 3),
        rgb[h - p:, w - p:].reshape(-1, 3),
    ])
    med = np.median(corners, axis=0)
    return (int(med[0]), int(med[1]), int(med[2]))


def alpha_bbox(img: Image.Image, alpha_min: int = 8):
    a = np.asarray(img.convert("RGBA"))[..., 3]
    ys, xs = np.where(a > alpha_min)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def autotrim(img: Image.Image, alpha_min: int = 8) -> Image.Image:
    box = alpha_bbox(img, alpha_min)
    return img.crop(box) if box else img


def pad_to_square(img: Image.Image, margin_ratio: float = 0.08) -> Image.Image:
    w, h = img.size
    side = int(round(max(w, h) * (1 + 2 * margin_ratio)))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return canvas


def resize(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def save_png(img: Image.Image, path: str):
    img.convert("RGBA").save(path, "PNG")


def save_webp(img: Image.Image, path: str, quality: int = 90):
    img.convert("RGBA").save(path, "WEBP", quality=quality, method=6)
