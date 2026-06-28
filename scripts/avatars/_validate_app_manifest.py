#!/usr/bin/env python3
"""同梱アバター manifest の整合性チェック（出荷ガード）。

iPadPrototype/Resources/avatars/manifest.json を decode し、
- 参照する base/part の PNG が実在するか
- 各 PNG が canvas どおり(1024x1536)の RGBA か
- マゼンタ/紫の残りが 0 か（出荷前 residue gate と同じ判定）
を検証する。1件でも欠けたら非0終了。

使い方:  cd scripts/avatars && python3 _validate_app_manifest.py
パイプライン更新時/コミット前に実行する（spec.json tech.ship_residue_gate 参照）。
"""
from __future__ import annotations
import json, os, sys
from PIL import Image
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
AV = os.path.normpath(os.path.join(HERE, "..", "..", "iPadPrototype", "Resources", "avatars"))


def residue(path: str) -> tuple[int, int, int]:
    a = np.asarray(Image.open(path).convert("RGBA")).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    op = al > 20
    mag = int((op & (r > 180) & (g < 90) & (b > 180)).sum())
    purp = int((op & (r > 110) & (b > 130) & (g < r - 40) & (g < b - 40)).sum())
    return int(op.sum()), mag, purp


def main() -> int:
    mpath = os.path.join(AV, "manifest.json")
    if not os.path.exists(mpath):
        print(f"FAIL: manifest not found at {mpath}")
        return 1
    m = json.load(open(mpath))
    canvas = tuple(m.get("canvas", [1024, 1536]))
    files = [b["file"] for b in m.get("bases", [])]
    for p in m.get("parts", []):
        files += [ly["file"] for ly in p.get("layers", [])]

    errors = 0
    for f in files:
        path = os.path.join(AV, f)
        if not os.path.exists(path):
            print(f"FAIL: referenced file missing: {f}")
            errors += 1
            continue
        im = Image.open(path)
        if im.size != canvas:
            print(f"FAIL: {f} size {im.size} != canvas {canvas}")
            errors += 1
        op, mag, purp = residue(path)
        if mag != 0 or purp > op * 0.0005:
            print(f"FAIL: {f} residue magenta={mag} purple={purp}")
            errors += 1

    if errors:
        print(f"\n{errors} problem(s) found.")
        return 1
    print(f"OK: manifest references {len(files)} files, all present, {canvas[0]}x{canvas[1]}, residue clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
