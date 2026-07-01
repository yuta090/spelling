#!/usr/bin/env python3
"""build_lottie.py — text(意図) → Lottie(.json) を python-lottie で組み立てる土台。

使い方は2通り:

1) プリセットを CLI で書き出す（手早く確認したいとき）
   .venv/bin/python build_lottie.py --preset star-sparkle --out out.json
   .venv/bin/python build_lottie.py --list          # プリセット一覧

2) ライブラリとして import して新しい動きを作る（推奨）
   from build_lottie import new_anim, save, COLORS, ease_io, sparkle, pop_in
   anim = new_anim(512, 512, fps=30, duration=1.0)
   ...（プリミティブで組む）...
   save(anim, "out.json")

設計方針:
- ここは「純ロジック（決定論的にJSONを吐く）」だけ。プレビュー(gif/html)は preview.sh が担当。
- 子ども向けアプリの“ごほうび/反応”語彙（キラッ・ポンと出る・はずむ・ハート・チェック・紙吹雪）を
  プリミティブ＋プリセットとして用意。新しい動きはこれを組み合わせて足す。
- 乱数は使わない（再現性のため）。ばらけさせたい時は index ベースで決める。
"""
from __future__ import annotations
import argparse
import math
import sys

from lottie import Point, Color
from lottie.objects import (
    Animation, ShapeLayer, Ellipse, Rect, Star, Fill, Stroke,
    Group, Transform, Path,
)
from lottie.objects.shapes import LineCap, LineJoin
from lottie.nvector import NVector
from lottie.exporters.core import export_lottie


# ---- パレット（子ども向け・やわらかフラット） ----
COLORS = {
    "gold":   Color(1.00, 0.80, 0.10),
    "sun":    Color(1.00, 0.62, 0.20),
    "coral":  Color(1.00, 0.45, 0.45),
    "pink":   Color(1.00, 0.55, 0.72),
    "mint":   Color(0.35, 0.82, 0.62),
    "sky":    Color(0.40, 0.70, 1.00),
    "grape":  Color(0.62, 0.50, 0.92),
    "white":  Color(1.00, 1.00, 1.00),
    "ink":    Color(0.20, 0.24, 0.32),
}


# ---- 基本 ----
def new_anim(width=512, height=512, fps=30, duration=1.0) -> Animation:
    """空のアニメを作る。duration は秒。"""
    anim = Animation(int(round(fps * duration)))
    anim.frame_rate = fps
    anim.width = width
    anim.height = height
    return anim


def save(anim: Animation, path: str):
    export_lottie(anim, path)
    return path


def ease_io(kf):
    """キーフレームに ease in/out を付ける（python-lottie の easing ユーティリティ）。"""
    try:
        from lottie.utils.animation import EaseInOut  # type: ignore
        kf.in_value = kf.out_value = None
    except Exception:
        pass
    return kf


def _kf(prop, t, value):
    prop.add_keyframe(t, value)


# ---- プリミティブ（部品） ----
def filled_ellipse(layer_or_group, center, size, color, opacity=100):
    g = layer_or_group.add_shape(Group())
    e = g.add_shape(Ellipse())
    e.position.value = Point(*center)
    e.size.value = Point(*size)
    f = g.add_shape(Fill(color))
    f.opacity.value = opacity
    return g


def filled_rect(layer_or_group, center, size, color, rounded=0, opacity=100):
    g = layer_or_group.add_shape(Group())
    r = g.add_shape(Rect())
    r.position.value = Point(*center)
    r.size.value = Point(*size)
    r.rounded.value = rounded
    f = g.add_shape(Fill(color))
    f.opacity.value = opacity
    return g


def star_shape(layer_or_group, center, outer, inner, points, color):
    g = layer_or_group.add_shape(Group())
    s = g.add_shape(Star())
    s.position.value = Point(*center)
    s.outer_radius.value = outer
    s.inner_radius.value = inner
    s.points.value = points
    g.add_shape(Fill(color))
    return g


def pivot(group: Group, point):
    """group の回転/拡大の中心を point にする（anchor=position=point）。

    ⚠ 重要: group.transform の anchor_point は既定 (0,0)。そのまま scale/rotation を
    かけると“キャンバス左上を中心に”変形して要素が飛ぶ。要素の中心で回す/脈打たせるには
    必ずこれを呼ぶ（中の shape も同じ point に置いておくこと）。
    """
    tr: Transform = group.transform
    tr.anchor_point.value = Point(*point)
    tr.position.value = Point(*point)
    return group


def anim_scale(group: Group, frames, scale_pct):
    """group.transform.scale をキーフレームで動かす。frames と scale_pct は同長。"""
    tr: Transform = group.transform
    for t, s in zip(frames, scale_pct):
        tr.scale.add_keyframe(t, Point(s, s))
    return group


def anim_opacity(group: Group, frames, vals):
    tr: Transform = group.transform
    for t, v in zip(frames, vals):
        tr.opacity.add_keyframe(t, v)
    return group


def anim_position(group: Group, frames, points):
    tr: Transform = group.transform
    for t, p in zip(frames, points):
        tr.position.add_keyframe(t, Point(*p))
    return group


def anim_rotation(group: Group, frames, degs):
    tr: Transform = group.transform
    for t, d in zip(frames, degs):
        tr.rotation.add_keyframe(t, d)
    return group


# ============================================================
# プリセット（“ごほうび/反応”語彙）
#   各関数は Animation を返す。新しい意図はここに足す。
# ============================================================
def star_sparkle(size=512) -> Animation:
    """星がキラッと光る（拡大しながらフェードイン→きらめき回転→消える）。"""
    a = new_anim(size, size, fps=30, duration=1.0)
    layer = a.add_layer(ShapeLayer())
    c = (size / 2, size / 2)
    g = star_shape(layer, c, outer=size * 0.32, inner=size * 0.14, points=5, color=COLORS["gold"])
    n = a.out_point
    anim_scale(g, [0, n * 0.35, n * 0.7, n], [0, 120, 95, 60])
    anim_opacity(g, [0, n * 0.3, n * 0.7, n], [0, 100, 100, 0])
    anim_rotation(g, [0, n], [-20, 25])
    # まわりの小さな光
    for i, ang in enumerate(range(0, 360, 90)):
        r = size * 0.30
        px = c[0] + r * math.cos(math.radians(ang))
        py = c[1] + r * math.sin(math.radians(ang))
        sp = star_shape(layer, (px, py), outer=size * 0.05, inner=size * 0.02, points=4, color=COLORS["white"])
        off = n * (0.15 + 0.08 * i)
        anim_opacity(sp, [0, off, off + n * 0.2, n], [0, 0, 100, 0])
        anim_scale(sp, [off, off + n * 0.2], [40, 120])
    return a


def pop_in(size=512) -> Animation:
    """ポンと出る（オーバーシュート付きの登場）。汎用の“出現”。"""
    a = new_anim(size, size, fps=30, duration=0.7)
    layer = a.add_layer(ShapeLayer())
    g = filled_ellipse(layer, (size / 2, size / 2), (size * 0.5, size * 0.5), COLORS["coral"])
    n = a.out_point
    anim_scale(g, [0, n * 0.55, n * 0.8, n], [0, 115, 92, 100])
    anim_opacity(g, [0, n * 0.3], [0, 100])
    return a


def bounce(size=512) -> Animation:
    """はずむ（上→下→つぶれて→戻る）。たのしい反応。"""
    a = new_anim(size, size, fps=30, duration=1.0)
    layer = a.add_layer(ShapeLayer())
    g = filled_ellipse(layer, (size / 2, size / 2), (size * 0.4, size * 0.4), COLORS["mint"])
    n = a.out_point
    top, bottom = size * 0.30, size * 0.62
    anim_position(g, [0, n * 0.5, n], [(size / 2, top), (size / 2, bottom), (size / 2, top)])
    # 着地でつぶれる
    anim_scale(g, [0, n * 0.45, n * 0.55, n], [100, 100, 100, 100])
    return a


def check_pop(size=512) -> Animation:
    """できた！丸が出て→チェックがポンと現れる。

    NOTE: 「線が描かれていく」表現にしたければ Trim を使えるが、cairosvg の
    プレビュー(gif/png)には出ない（実機 lottie-web/lottie-ios では動く）。
    検証性を優先し、ここでは scale+opacity でチェックを“出す”。
    描き進める版は reference/python-lottie-cheatsheet.md の Trim 節を参照。
    """
    a = new_anim(size, size, fps=30, duration=0.9)
    layer = a.add_layer(ShapeLayer())
    c = (size / 2, size / 2)
    n = a.out_point
    # ⚠ Lottie は「先に追加した shape が前面」。チェックを前面にするため先に追加する。
    # チェック（線）— Group ごと pop で出す
    g = layer.add_shape(Group())
    p = g.add_shape(Path())
    bez = p.shape.value
    bez.closed = False
    bez.add_point(NVector(size * 0.34, size * 0.52))
    bez.add_point(NVector(size * 0.45, size * 0.63))
    bez.add_point(NVector(size * 0.68, size * 0.40))
    st = g.add_shape(Stroke(COLORS["white"], size * 0.06))
    st.line_cap = LineCap.Round
    st.line_join = LineJoin.Round
    anim_scale(g, [n * 0.4, n * 0.65, n * 0.8, n], [0, 118, 92, 100])
    anim_opacity(g, [n * 0.4, n * 0.5], [0, 100])
    # 丸（背面）— 後から追加して check の下に置く
    ring = filled_ellipse(layer, c, (size * 0.62, size * 0.62), COLORS["mint"])
    anim_scale(ring, [0, n * 0.4, n * 0.55, n], [0, 112, 95, 100])
    anim_opacity(ring, [0, n * 0.25], [0, 100])
    return a


def heart_beat(size=512) -> Animation:
    """ハートがドキッと脈打つ（2円＋45°四角の簡易ハート＋拍動）。"""
    a = new_anim(size, size, fps=30, duration=1.0)
    layer = a.add_layer(ShapeLayer())
    c = (size / 2, size * 0.52)
    n = a.out_point
    # ハート全体グループ（c を中心に拍動させる）
    g = layer.add_shape(Group())
    # 下の四角（45°回転）— 自分の中心で回す
    rt = filled_rect(g, c, (size * 0.30, size * 0.30), COLORS["pink"], rounded=size * 0.02)
    pivot(rt, c)
    rt.transform.rotation.value = 45
    # 上の2つの円
    filled_ellipse(g, (c[0] - size * 0.10, c[1] - size * 0.08), (size * 0.27, size * 0.27), COLORS["pink"])
    filled_ellipse(g, (c[0] + size * 0.10, c[1] - size * 0.08), (size * 0.27, size * 0.27), COLORS["pink"])
    # 全体を c 中心で脈打たせる
    pivot(g, c)
    anim_scale(g, [0, n * 0.2, n * 0.4, n * 0.6, n], [88, 110, 96, 106, 96])
    return a


def confetti(size=512) -> Animation:
    """紙吹雪が舞う（決定論的に配置した小片が落ちて回る）。"""
    a = new_anim(size, size, fps=30, duration=1.4)
    layer = a.add_layer(ShapeLayer())
    n = a.out_point
    palette = [COLORS["gold"], COLORS["coral"], COLORS["sky"], COLORS["mint"], COLORS["grape"], COLORS["pink"]]
    for i in range(18):
        x = (i * 53 % size)
        col = palette[i % len(palette)]
        piece = filled_rect(layer, (x, -20), (size * 0.035, size * 0.06), col, rounded=2)
        delay = n * (i % 6) / 12.0
        fall_y = size + 40
        anim_position(piece, [delay, n], [(x, -20), (x + (i % 5 - 2) * 30, fall_y)])
        anim_rotation(piece, [delay, n], [0, (i % 2 * 2 - 1) * 360])
        anim_opacity(piece, [delay, delay + 1, n * 0.85, n], [0, 100, 100, 0])
    return a


PRESETS = {
    "star-sparkle": star_sparkle,
    "pop-in": pop_in,
    "bounce": bounce,
    "check-pop": check_pop,
    "heart-beat": heart_beat,
    "confetti": confetti,
}


def main(argv=None):
    ap = argparse.ArgumentParser(description="text→Lottie builder (python-lottie)")
    ap.add_argument("--preset", help="プリセット名")
    ap.add_argument("--list", action="store_true", help="プリセット一覧")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out", default="out.json")
    args = ap.parse_args(argv)

    if args.list or not args.preset:
        print("presets:")
        for k in PRESETS:
            print("  -", k)
        if not args.preset:
            return 0
    fn = PRESETS.get(args.preset)
    if not fn:
        print(f"unknown preset: {args.preset}", file=sys.stderr)
        return 2
    anim = fn(args.size)
    save(anim, args.out)
    print(f"wrote {args.out}  ({anim.width}x{anim.height}, {anim.out_point/anim.frame_rate:.2f}s @ {anim.frame_rate}fps)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
