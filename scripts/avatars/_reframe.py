#!/usr/bin/env python3
"""アバター素材を一律アフィン変換して『頭上の余白』を作る再フレームツール(2026-06-29)。

問題: base の頭頂が y≈35(キャンバス上端ギリギリ)で、ボリュームのある髪が潰れる/描けない。
解決: base と全パーツに **同じ縮小+平行移動** をかけて頭頂を y≈SKULL_TARGET へ下げ、頭上に余白を作る。
全素材に同一変換なので相互の整列は保たれる。フルキャンバス(1024x1536)透過PNG前提。

変換: 中心 x=CENTER_X を固定、scale=S で縮小、頭頂 OLD_SKULL→SKULL_TARGET に来るよう y 平行移動。
  x_new = CENTER_X + (x-CENTER_X)*S
  y_new = OLD_SKULL*S + ty,  ty = SKULL_TARGET - OLD_SKULL*S
PIL の AFFINE は出力→入力の逆写像係数で渡す。

使い方: python3 _reframe.py f1.png f2.png ...   (各ファイルを上書き変換)
"""
import sys
from PIL import Image

CANVAS = (1024, 1536)
CENTER_X = 509
OLD_SKULL = 35
SKULL_TARGET = 170
S = 0.85

TX = CENTER_X * (1 - S)
TY = SKULL_TARGET - OLD_SKULL * S


def reframe(img):
    img = img.convert("RGBA")
    # 出力(x',y') = 入力(x,y) の逆: x = (x'-TX)/S, y = (y'-TY)/S
    coeffs = (1.0 / S, 0.0, -TX / S,
              0.0, 1.0 / S, -TY / S)
    return img.transform(CANVAS, Image.AFFINE, coeffs, resample=Image.BICUBIC)


if __name__ == "__main__":
    files = sys.argv[1:]
    if not files:
        print("usage: python3 _reframe.py <png> [<png> ...]")
        sys.exit(1)
    for f in files:
        reframe(Image.open(f)).save(f)
        print("reframed", f)
    print("S=%.3f skull %d->%d  TX=%.1f TY=%.1f" % (S, OLD_SKULL, SKULL_TARGET, TX, TY))
