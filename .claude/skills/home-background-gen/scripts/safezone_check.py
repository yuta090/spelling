#!/usr/bin/env python3
"""ホーム背景の『中央セーフゾーン』を検証する。

背景はアプリが中央にキャラ＋UIを乗せる『舞台』。中央が混みすぎ/暗すぎ/明るすぎ/
コントラスト過多だとキャラが埋もれる。この스크립트は中央の楕円ゾーンを測り、
合否を出し、キャラのシルエットを仮合成したプレビューPNGを作って Preview で開く。

測るもの(spec.json の safezone.thresholds と照合):
  - busy_edge_ratio : 中央のエッジ量 / 全体のエッジ量 (中央が混んでいるほど大)
  - busy_edge_abs   : 中央のエッジ平均(絶対値)
  - luma            : 中央の平均輝度(暗すぎ/明るすぎ警告)
  - contrast_std    : 中央の輝度ばらつき(高いとガチャつき)

使い方:
  python3 safezone_check.py <image.png> [--out preview.png] [--no-open]
  python3 safezone_check.py <image.png> --cx 0.5 --cy 0.56 --w 0.46 --h 0.60
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageStat

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent / "spec.json"


def ellipse_mask(size, cx, cy, w, h):
    W, H = size
    bx0, by0 = (cx - w / 2) * W, (cy - h / 2) * H
    bx1, by1 = (cx + w / 2) * W, (cy + h / 2) * H
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse([bx0, by0, bx1, by1], fill=255)
    return m, (bx0, by0, bx1, by1)


def main():
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    sz = spec["safezone"]
    th = sz["thresholds"]

    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--out", default="")
    ap.add_argument("--cx", type=float, default=sz["cx_ratio"])
    ap.add_argument("--cy", type=float, default=sz["cy_ratio"])
    ap.add_argument("--w", type=float, default=sz["w_ratio"])
    ap.add_argument("--h", type=float, default=sz["h_ratio"])
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    path = Path(args.image)
    if not path.exists():
        raise SystemExit(f"not found: {path}")

    im = Image.open(path).convert("RGB")
    W, H = im.size
    gray = im.convert("L")
    edges = gray.filter(ImageFilter.FIND_EDGES)

    mask, box = ellipse_mask(im.size, args.cx, args.cy, args.w, args.h)

    edge_center = ImageStat.Stat(edges, mask).mean[0]
    edge_all = ImageStat.Stat(edges).mean[0] or 1e-6
    edge_ratio = edge_center / edge_all

    cstat = ImageStat.Stat(gray, mask)
    luma = cstat.mean[0]
    contrast = cstat.stddev[0]

    # 判定
    warns = []
    if edge_ratio > th["busy_edge_ratio_warn"]:
        warns.append(f"中央が周囲より混んでいる (edge_ratio={edge_ratio:.2f} > {th['busy_edge_ratio_warn']})")
    if edge_center > th["busy_edge_abs_warn"]:
        warns.append(f"中央のディテールが多い (edge_abs={edge_center:.1f} > {th['busy_edge_abs_warn']})")
    if luma < th["luma_dark_warn"]:
        warns.append(f"中央が暗い (luma={luma:.0f} < {th['luma_dark_warn']})")
    if luma > th["luma_bright_warn"]:
        warns.append(f"中央が明るすぎ (luma={luma:.0f} > {th['luma_bright_warn']})")
    if contrast > th["contrast_std_warn"]:
        warns.append(f"中央のコントラストが強い (std={contrast:.0f} > {th['contrast_std_warn']})")

    verdict = "✅ OK（中央は静か。キャラが乗せられる）" if not warns else "⚠ 要確認"
    print(f"画像: {path}  ({W}x{H})")
    print(f"  edge_center={edge_center:.1f}  edge_all={edge_all:.1f}  ratio={edge_ratio:.2f}")
    print(f"  luma={luma:.0f}  contrast_std={contrast:.0f}")
    print(f"  判定: {verdict}")
    for w in warns:
        print(f"    - {w}")
    if W != 1448 or H != 1086:
        print(f"  ℹ 寸法が出荷規格(1448x1086)と違う。place_asset.py で揃う。")

    # プレビュー: セーフゾーン枠 ＋ キャラのシルエット仮合成
    prev = im.copy().convert("RGBA")
    ov = Image.new("RGBA", prev.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.ellipse(box, outline=(255, 60, 60, 220), width=max(3, W // 360))
    # キャラの仮シルエット(中性グレー＋白フチ): 頭の円＋体の楕円
    chx = args.cx * W
    chy = args.cy * H
    ch_h = args.h * H * 0.92
    head_r = ch_h * 0.22
    body_w = ch_h * 0.52
    body_top = chy - ch_h * 0.18
    body_bot = chy + ch_h * 0.46
    fill = (150, 154, 160, 235)
    line = (255, 255, 255, 235)
    lw = max(3, W // 400)
    d.ellipse([chx - body_w / 2, body_top, chx + body_w / 2, body_bot], fill=fill, outline=line, width=lw)
    head_cy = body_top - head_r * 0.5
    d.ellipse([chx - head_r, head_cy - head_r, chx + head_r, head_cy + head_r], fill=fill, outline=line, width=lw)
    out = Image.alpha_composite(prev, ov).convert("RGB")
    out_path = Path(args.out) if args.out else path.with_name(path.stem + "_safezone.png")
    out.save(out_path)
    print(f"  プレビュー: {out_path}")

    if not args.no_open:
        try:
            subprocess.run(["open", "-a", "Preview", str(out_path)], check=False)
        except Exception:
            pass

    sys.exit(0 if not warns else 2)


if __name__ == "__main__":
    main()
