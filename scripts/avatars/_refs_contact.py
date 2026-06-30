#!/usr/bin/env python3
"""参考画像(refs/)のコンタクトシートを一発で作るヘルパー（手動収集の確認用）。

手で `refs/<kei>/<id>__<n>.jpg` に画像をドロップ → このスクリプトを実行 →
`refs/_contact_sheet.png`(gitignore対象) に一覧グリッドを書き出し、`--open` で Preview 表示。
壊れファイル(HTMLをjpgで掴んだ等)は赤枠でフラグ。tops.csv の planned のうち
**まだ ref 画像が無いアイテム**もコンソールに列挙する（何を集めればいいか分かる）。

使い方:
  python3 _refs_contact.py [--open] [--refs <dir>] [--cols N]
"""
import argparse
import csv
import glob
import os

from PIL import Image, ImageDraw

KEIS = ["girly", "sporty", "natural", "street", "amekaji", "sport"]
EXTS = ("jpg", "jpeg", "png", "webp")


def valid_image(path):
    try:
        im = Image.open(path)
        im.load()
        return im.convert("RGB")
    except Exception:
        return None


def list_images(refs_dir):
    """{kei: {id: [paths...]}} と 壊れファイル一覧 を返す。"""
    by = {}
    broken = []
    for kei in KEIS:
        d = os.path.join(refs_dir, kei)
        if not os.path.isdir(d):
            continue
        for ext in EXTS:
            for p in sorted(glob.glob(os.path.join(d, "*." + ext))):
                fn = os.path.basename(p)
                iid = fn.split("__")[0] if "__" in fn else os.path.splitext(fn)[0]
                if valid_image(p) is None:
                    broken.append(p)
                    continue
                by.setdefault(kei, {}).setdefault(iid, []).append(p)
    return by, broken


def planned_without_ref(refs_dir, by):
    """tops.csv の planned で、ref 画像がまだ無い id を返す。"""
    csv_path = os.path.join(os.path.dirname(refs_dir.rstrip("/")), "tops.csv")
    if not os.path.exists(csv_path):
        return []
    have = {iid for items in by.values() for iid in items}
    missing = []
    for r in csv.DictReader(open(csv_path)):
        if r.get("status") == "planned" and r["id"] not in have:
            missing.append((r.get("kei", "?"), r["id"]))
    return missing


def build_sheet(by, refs_dir, cols):
    # 各 id の代表(先頭)画像を1枚ずつ並べる
    cells = []
    for kei in KEIS:
        for iid, paths in sorted(by.get(kei, {}).items()):
            cells.append((kei, iid, paths[0], len(paths)))
    if not cells:
        return None, 0
    cw = chh = 300
    pad = 26
    rows = (len(cells) + cols - 1) // cols
    grid = Image.new("RGB", (cw * cols, (chh + pad) * rows), (248, 248, 248))
    d = ImageDraw.Draw(grid)
    for i, (kei, iid, p, n) in enumerate(cells):
        c, rr = i % cols, i // cols
        x, y = c * cw, rr * (chh + pad)
        im = valid_image(p)
        im.thumbnail((cw - 8, chh - 8))
        grid.paste(im, (x + (cw - im.width) // 2, y + pad + (chh - im.height) // 2))
        d.text((x + 4, y + 6), "%s/%s  (%d)" % (kei, iid.replace("top_", ""), n), fill=(10, 10, 10))
    out = os.path.join(refs_dir, "_contact_sheet.png")
    grid.save(out)
    return out, len(cells)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--open", action="store_true", help="生成後に Preview で開く(macOS)")
    ap.add_argument("--refs", default="refs", help="refs ディレクトリ(既定: refs)")
    ap.add_argument("--cols", type=int, default=3)
    a = ap.parse_args()

    by, broken = list_images(a.refs)
    out, n = build_sheet(by, a.refs, a.cols)
    print("=== refs コンタクトシート ===")
    for kei in KEIS:
        items = by.get(kei, {})
        tot = sum(len(v) for v in items.values())
        print("  [%-8s] %d点 / %d枚: %s" % (kei, len(items), tot, ", ".join(sorted(items)) or "-"))
    if broken:
        print("\n⚠ 壊れ/非画像ファイル(削除推奨):")
        for p in broken:
            print("   -", p)
    miss = planned_without_ref(a.refs, by)
    if miss:
        print("\n📭 planned だが ref 画像がまだ無い(集める対象):")
        for kei, iid in miss:
            print("   - %s / %s  → %s/%s/%s__1.jpg" % (kei, iid, a.refs, kei, iid))
    if out:
        print("\n書き出し: %s (%d点)" % (out, n))
        if a.open:
            os.system("open '%s'" % out)
    else:
        print("\n(refs に有効な画像がありません)")


if __name__ == "__main__":
    main()
