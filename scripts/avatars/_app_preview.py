#!/usr/bin/env python3
"""アプリ(SwiftUI LayeredAvatarView)と同じ見た目の合成プレビューを作る QA ツール。

アプリは manifest の zOrder どおりに base + パーツを ZStack 重ね、canvas(1024x1536)を
aspectRatio fit で表示する。つまり **フルキャンバスを z-order で重ねた合成画像 = アプリの見た目**。
このスクリプトは out/ の素材を使い、(1)着せ替え例 (2)髪一覧グリッド を PNG 出力し、
macOS の Preview で開けるようにする(`--open`)。

使い方:
  python3 _app_preview.py            # PNG生成のみ
  python3 _app_preview.py --open     # 生成して Preview で開く

素材は out/ から探す(cut_*.png 優先、無ければ素の名前)。base は out/base_*.png か
同梱(../../iPadPrototype/Resources/avatars/)から。z-order は spec.json の layers.z_order。
"""
import json, os, sys, subprocess
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
SHIP = os.path.abspath(os.path.join(HERE, "..", "..", "iPadPrototype", "Resources", "avatars"))
CANVAS = (1024, 1536)

with open(os.path.join(HERE, "spec.json"), encoding="utf-8") as f:
    SPEC = json.load(f)
ZORDER = SPEC["layers"]["z_order"]  # back_hair..accessory


def _label_font(size):
    """日本語も出るフォントを探す(macOS)。無ければデフォルト。"""
    for path in ("/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc",
                 "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
                 "/System/Library/Fonts/Hiragino Sans GB.ttc",
                 "/Library/Fonts/Arial Unicode.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()


def _find(name):
    """素材PNGを探す: 同梱(SHIP)/<name> を最優先(=アプリが実際に使う物)。無ければ out/。"""
    for cand in (os.path.join(SHIP, "%s.png" % name),
                 os.path.join(OUT, "cut_%s.png" % name),
                 os.path.join(OUT, "%s.png" % name)):
        if os.path.exists(cand):
            return cand
    return None


def compose(base_file, layers):
    """base + {slot_or_z: part_name} を z-order で重ねたフルキャンバス合成を返す。

    layers: list of (z_key, part_name)。z_key は zOrder のいずれか(bottom/shoes/top/front_hair…)。
    base は base_body として常に最初に置く。
    """
    canvas = Image.new("RGBA", CANVAS, (255, 255, 255, 0))
    # base_body をパーツと同じ z-order ソートに含める(アプリの AvatarComposer と一致させる:
    # back_hair は base_body より後ろに来る)。
    all_layers = [("base_body", base_file)] + list(layers)
    ordered = sorted(all_layers, key=lambda kv: ZORDER.index(kv[0]) if kv[0] in ZORDER else len(ZORDER))
    for _z, name in ordered:
        p = _find(name) or (os.path.join(SHIP, name + ".png") if _z == "base_body" else None)
        if p and os.path.exists(p):
            canvas.alpha_composite(Image.open(p).convert("RGBA"))
    return canvas


def on_card(img, label, cell=(360, 540), bg=(245, 246, 250, 255)):
    """合成を子画面ぽい白カードに乗せてラベルを焼く(一覧用サムネ)。"""
    th = img.resize((cell[0], int(cell[0] * CANVAS[1] / CANVAS[0])), Image.LANCZOS)
    card = Image.new("RGBA", cell, bg)
    card.alpha_composite(th, (0, 0))
    d = ImageDraw.Draw(card)
    font = _label_font(22)
    d.rectangle([0, cell[1] - 30, cell[0], cell[1]], fill=(0, 0, 0, 140))
    d.text((8, cell[1] - 27), label, fill=(255, 255, 255, 255), font=font)
    return card


def grid(cards, cols=4, pad=10, bgcolor=(255, 255, 255, 255)):
    if not cards:
        return None
    cw, ch = cards[0].size
    rows = (len(cards) + cols - 1) // cols
    W = cols * cw + (cols + 1) * pad
    H = rows * ch + (rows + 1) * pad
    g = Image.new("RGBA", (W, H), bgcolor)
    for i, c in enumerate(cards):
        r, cc = divmod(i, cols)
        g.alpha_composite(c, (pad + cc * (cw + pad), pad + r * (ch + pad)))
    return g


def _manifest():
    with open(os.path.join(SHIP, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def hairs_for_base(baseID):
    """同梱 manifest の hair パーツを baseID で絞る(base=='*' か一致)。アプリの出し分けと一致。"""
    m = _manifest()
    out = []
    for p in m.get("parts", []):
        if p.get("slot") == "hair" and p.get("base", "*") in ("*", baseID):
            f = (p.get("layers") or [{}])[0].get("file", "")
            if f:
                out.append(f[:-4] if f.endswith(".png") else f)
    return out


def main():
    do_open = "--open" in sys.argv
    outputs = []

    # (1) 着せ替え例: 女/男 それぞれフル装備
    examples = [
        ("base_female", "hair_twin_tails", "女の子 / ツインテール + パーカー"),
        ("base_male", "hair_m_twoblock_black", "男の子 / ツーブロック + パーカー"),
    ]
    cards = []
    for base, hair, label in examples:
        img = compose(base, [("front_hair", hair), ("top", "top_blue_hoodie"),
                             ("bottom", "bottom_blue_shorts"), ("shoes", "shoes_white_sneakers")])
        full = os.path.join(OUT, "preview_%s.png" % base)
        img.save(full); outputs.append(full)
        cards.append(on_card(img, label, cell=(460, 690)))
    g = grid(cards, cols=2)
    gp = os.path.join(OUT, "preview_outfits.png"); g.save(gp); outputs.append(gp)

    # (2) 髪一覧グリッド(女の子・男の子ベース それぞれ + 各髪)
    for base in ("base_female", "base_male"):
        baseID = base.replace("base_", "")
        cards = []
        for h in hairs_for_base(baseID):
            img = compose(base, [("front_hair", h)])
            cards.append(on_card(img, h.replace("hair_", ""), cell=(300, 450)))
        g = grid(cards, cols=4)
        if g:
            gp = os.path.join(OUT, "preview_hair_grid_%s.png" % base.replace("base_", ""))
            g.save(gp); outputs.append(gp)

    for p in outputs:
        print("wrote", p)
    if do_open and outputs:
        subprocess.run(["open"] + outputs)


if __name__ == "__main__":
    main()
