#!/usr/bin/env python3
"""tops バッチの透過抽出→ゲート→合成→QA計測→プレビュー。一時QA用(out/, git管理外)。"""
import numpy as np
from PIL import Image
import avatar_lib as al
from _sleeve_fill import fill_forearm_gaps

R = "../../iPadPrototype/Resources/avatars/"
TOPS = [
    # id, base_for_preview, sleeve
    ("top_g_pink_puff_tee", "female", "short"),
    ("top_g_lavender_knit", "female", "long"),
    ("top_g_mint_star_tee", "female", "short"),
    ("top_b_black_bolt_tee", "male", "short"),
    ("top_b_mustard_sweat", "male", "long"),
    ("top_b_blue_track", "male", "long"),
    ("top_u_green_hoodie", "female", "long"),
    ("top_u_navy_border_tee", "female", "long"),
]


def skin_mask(b):
    r, g, bl, a = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return (a > 128) & (r > 205) & (g > 150) & (g < 225) & (bl > 120) & (bl < 205)


def gray_mask(b):
    # base のグレー肌着(チェスト/ショーツ)。low-sat 中明度グレー。
    r, g, bl, a = b[..., 0].astype(int), b[..., 1].astype(int), b[..., 2].astype(int), b[..., 3]
    mx = np.maximum(np.maximum(r, g), bl); mn = np.minimum(np.minimum(r, g), bl)
    return (a > 128) & (mx - mn < 22) & (mx > 150) & (mx < 225)


def main():
    bases = {g: np.array(Image.open(R + "base_%s.png" % g).convert("RGBA")) for g in ("female", "male")}
    comps = []
    print("%-26s %-6s %-8s %s" % ("id", "mag", "sleeveQA", "chest_gray"))
    for tid, pbase, sleeve in TOPS:
        cut = al.chroma_key_defringe(Image.open("out/new_%s.png" % tid))
        garr = np.array(cut)
        # magenta gate
        r, g, bl, a = garr[..., 0], garr[..., 1], garr[..., 2], garr[..., 3]
        op = a > 0
        mag = int((op & (r > 180) & (g < 90) & (bl > 180)).sum())
        base = bases[pbase]
        if sleeve == "long":
            garr, _, _ = fill_forearm_gaps(garr, base)
        Image.fromarray(garr).save("out/cut_%s.png" % tid)
        comp = Image.alpha_composite(Image.fromarray(base), Image.fromarray(garr))
        ca = np.array(comp)
        skin = skin_mask(ca)
        # sleeve QA
        if sleeve == "long":
            m = np.zeros(skin.shape, bool)
            for x0, x1 in [(230, 470), (560, 800)]:
                m[620:915, x0:x1] = True
            qa = "fore=%d" % int((skin & m).sum())
        else:
            # short: 袖hem下端y(=肩〜上腕で garment が切れる位置)。各腕で hoodie/garment alpha 最下端
            ga = garr[..., 3] > 128
            hems = []
            for x0, x1 in [(300, 430), (590, 720)]:
                cols = ga[:, x0:x1]
                rows = np.where(cols.any(axis=1))[0]
                rows = rows[(rows > 640) & (rows < 880)]
                hems.append(int(rows.max()) if rows.size else -1)
            qa = "hemY=%s" % hems  # 二の腕被覆の目安 ~750-790
        # chest gray (underwear) exposure in chest band y 640-860 x 380-640
        cg = gray_mask(ca)
        cband = np.zeros(cg.shape, bool); cband[640:860, 380:640] = True
        chest = int((cg & cband).sum())
        print("%-26s %-6d %-8s %d" % (tid, mag, qa, chest))
        # crop for grid (whole figure scaled)
        bgc = Image.new("RGBA", comp.size, (255, 255, 255, 255)); bgc.alpha_composite(comp)
        comps.append((tid, bgc.convert("RGB")))
    # grid 4 cols x 2 rows, each scaled to 256x384
    from PIL import ImageDraw
    cw, chh = 256, 384
    cols, rows = 4, 2
    grid = Image.new("RGB", (cw * cols, (chh + 22) * rows), (245, 245, 245))
    d = ImageDraw.Draw(grid)
    for i, (tid, im) in enumerate(comps):
        c, rr = i % cols, i // cols
        x, y = c * cw, rr * (chh + 22)
        grid.paste(im.resize((cw, chh)), (x, y + 22))
        d.text((x + 4, y + 6), tid.replace("top_", ""), fill=(20, 20, 20))
    grid.save("out/preview_tops_grid.png")
    print("saved out/preview_tops_grid.png")


if __name__ == "__main__":
    main()
