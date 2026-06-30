#!/usr/bin/env python3
"""トップス決定論フィニッシャ＋QAゲート（2026-06-30）。

生成(マゼンタ地 out/new_<id>.png)を受け取り、出荷形に仕上げて自動QAする:
  1. chroma_key_defringe で透過抽出
  2. マゼンタ残渣ゲート(=0 を assert)
  3. 首クリップ: y < NECK_CLIP_Y の服アルファを 0 にする
     → 襟/フード裏が首の後ろ・頭の上に飛び出す問題を決定論的に除去
       (base_red_tee は元から topY=632 なので無傷。首の付け根/頭の幾何は base 実測)
  4. 長袖は _sleeve_fill で前腕フチ隙間を埋める
  5. base に合成して **色非依存**の腕被覆QA:
       exposed = base_skin & (garment_alpha<128)  ← 服の色に左右されない
       覆うべき腕帯に素肌が残る = 袖が腕を通っていない/袖口が腕とズレてNG
  6. 胸の肌着(グレー肩ひも)露出QA
base="*" は female/male 両方でQA。--apply で Resources へ書き出し。

使い方:
  python3 _top_finish.py <id> <base female|male|*> <sleeve short|long> [--apply]
  python3 _top_finish.py --clip-existing <id> <base> <sleeve> --apply  # 既存PNGを首クリップのみ
"""
import sys
import numpy as np
import scipy.ndimage as ndi
from PIL import Image
import avatar_lib as al
from _sleeve_fill import fill_forearm_gaps

R = "../../iPadPrototype/Resources/avatars/"
NECK_CLIP_Y = 632  # これより上の服アルファは消す(首の付け根=630/頭の上=飛び出し)

# base 実測の腕帯。内側端(torso隣の脇すき間=自然な素肌)を除外するため inner を絞る。
# (face<600 / torso中央 / 脚>950 / 手の広がり>888 を除外)
ARM_BANDS = {"L": (300, 445), "R": (579, 724)}
ARM_Y_TOP = 790    # 長袖ゲートは前腕(y790-888)のみ見る。脇/二の腕の自然なすき間を除外し
                   # 「腕が袖からはみ出る」実害だけを検出する。
ELBOW_Y = 888      # (短袖は arm を informational 扱い。下の qa 参照)
WRIST_Y = 888      # 長袖はここまで被覆を要求
CHEST_STRAP = ((600, 632), (430, 595))  # グレー肩ひもの覗き帯 (y,x)

PASS_ARM = 120     # 腕帯の許容素肌px(アンチエイリアス端のみ)
PASS_STRAP = 60


def base_skin(b):
    r, g, bl, a = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return (a > 128) & (r > 200) & (g > 140) & (g < 230) & (bl > 110) & (bl < 210)


def base_gray(b):
    r, g, bl, a = b[..., 0].astype(int), b[..., 1].astype(int), b[..., 2].astype(int), b[..., 3]
    mx = np.maximum(np.maximum(r, g), bl); mn = np.minimum(np.minimum(r, g), bl)
    return (a > 128) & (mx - mn < 22) & (mx > 150) & (mx < 225)


def neck_clip(garr):
    out = garr.copy()
    out[:NECK_CLIP_Y, :, 3] = 0
    return out


def zero_magenta(garr):
    """残ったマゼンタ画素(縁フリンジ/テクスチャ隙間)のアルファを0にする安全弁。"""
    out = garr.copy()
    r, g, bl, a = out[..., 0], out[..., 1], out[..., 2], out[..., 3]
    mask = (a > 0) & (r > 180) & (g < 90) & (bl > 180)
    out[mask, 3] = 0
    return out


def finish(garr, base_arr, sleeve):
    """garr(生のkey済 RGBA np), base_arr(np) -> (finished garr, info)"""
    garr = neck_clip(garr)
    garr = zero_magenta(garr)
    if sleeve == "long":
        garr, _, _ = fill_forearm_gaps(garr, base_arr)
        garr = neck_clip(garr)  # fill が上に伸ばさないよう再クリップ
    return garr


def qa(garr, base_arr, sleeve):
    comp = np.array(Image.alpha_composite(Image.fromarray(base_arr), Image.fromarray(garr)))
    gop = garr[..., 3] > 128
    # 服マスクを TOL_PX 膨張してから素肌を数える=AA縁/スナッグ袖の縁スリバーを許容し、
    # 「腕が袖から本当にはみ出ている」実害ギャップだけを検出する。
    TOL_PX = 6
    garm_dil = ndi.binary_dilation(garr[..., 3] >= 128, iterations=TOL_PX)
    exposed = base_skin(comp) & (~garm_dil)
    cover_y = ELBOW_Y if sleeve == "short" else WRIST_Y
    res = {}
    arm_total = 0
    for side, (x0, x1) in ARM_BANDS.items():
        m = np.zeros(exposed.shape, bool); m[ARM_Y_TOP:cover_y, x0:x1] = True
        n = int((exposed & m).sum()); res["arm_" + side] = n; arm_total += n
    # 胸の肩ひも(グレー)露出
    (y0, y1), (x0, x1) = CHEST_STRAP
    sm = np.zeros(exposed.shape, bool); sm[y0:y1, x0:x1] = True
    res["strap"] = int((base_gray(comp) & sm).sum())
    # マゼンタ残渣
    r, g, bl = garr[..., 0], garr[..., 1], garr[..., 2]
    res["magenta"] = int((gop & (r > 180) & (g < 90) & (bl > 180)).sum())
    res["arm_total"] = arm_total
    # ⚠半袖の腕被覆pxは“良い半袖でも前腕が出る”ので有効なゲートにならない(手本 red_tee も多い)。
    #   半袖は arm を informational 扱いにし、magenta/strap＋目視(手本 red_tee)で判定する。
    #   長袖のみ forearm 被覆px(脇すき間を除外)を強くゲートする。
    arm_ok = True if sleeve == "short" else (arm_total <= PASS_ARM)
    res["pass"] = arm_ok and (res["strap"] <= PASS_STRAP) and (res["magenta"] == 0)
    return res, comp, exposed


def debug_overlay(comp, exposed, path):
    img = comp.copy()
    img[exposed] = [255, 0, 0, 255]  # 露出素肌を赤
    bg = Image.new("RGBA", (1024, 1536), (255, 255, 255, 255)); bg.alpha_composite(Image.fromarray(img))
    bg.convert("RGB").save(path)


def run(tid, base_kind, sleeve, src, apply, prekeyed=False):
    bases = ["female", "male"] if base_kind == "*" else [base_kind]
    img = Image.open(src).convert("RGBA")
    raw = img if prekeyed else al.chroma_key_defringe(img)
    garr0 = np.array(raw)
    # base毎にfinish(長袖fillはbase依存)してQA。書き出しは1枚(*はfemaleでfill)
    out_garr = None
    allpass = True
    print("id=%s base=%s sleeve=%s src=%s" % (tid, base_kind, sleeve, src))
    for bk in bases:
        b = np.array(Image.open(R + "base_%s.png" % bk).convert("RGBA"))
        g = finish(garr0.copy(), b, sleeve)
        res, comp, exposed = qa(g, b, sleeve)
        verdict = "PASS" if res["pass"] else "FAIL"
        print("  [%s] %s arm(L=%d R=%d tot=%d) strap=%d magenta=%d"
              % (bk, verdict, res["arm_L"], res["arm_R"], res["arm_total"], res["strap"], res["magenta"]))
        debug_overlay(comp, exposed, "out/qa_%s_%s.png" % (tid, bk))
        bgc = Image.new("RGBA", (1024, 1536), (255, 255, 255, 255)); bgc.alpha_composite(Image.fromarray(comp))
        bgc.convert("RGB").save("out/comp_%s_%s.png" % (tid, bk))
        if out_garr is None:
            out_garr = g
        allpass = allpass and res["pass"]
    Image.fromarray(out_garr).save("out/cut_%s.png" % tid)
    if apply:
        Image.fromarray(out_garr).save(R + tid + ".png")
        print("  applied -> %s%s.png" % (R, tid))
    print("  RESULT:", "ALL PASS" if allpass else "FAIL (see out/qa_*.png red=exposed skin)")
    return allpass


def main():
    a = sys.argv[1:]
    apply = "--apply" in a
    a = [x for x in a if x != "--apply"]
    clip_existing = False
    if a and a[0] == "--clip-existing":
        clip_existing = True; a = a[1:]
    tid, base_kind, sleeve = a[0], a[1], a[2]
    src = (R + tid + ".png") if clip_existing else ("out/new_%s.png" % tid)
    run(tid, base_kind, sleeve, src, apply, prekeyed=clip_existing)


if __name__ == "__main__":
    main()
