# python-lottie チートシート（このスキル用の実証済みメモ）

バージョン: `lottie 0.7.2`（スキル同梱 `.venv`）。ここに書いてあるAPIは**実機で確認済み**。
新しい動きを作るときは `scripts/build_lottie.py` を import して組む。

## 座標系・単位
- 原点は**左上 (0,0)**、+x→右、+y→**下**。中心は `(width/2, height/2)`。
- 時間は**フレーム**。`anim.out_point` が総フレーム数。秒は `out_point / frame_rate`。
- 回転は**度**。scale は**パーセント**（100 = 等倍、`Point(100,100)`）。

## ⚠ ハマりどころ（重要・実証済み）
1. **描画順は「先に add した shape が前面」**（Illustrator のレイヤー順と同じ）。
   背景を後、主役を先に add する。例: チェック✓を先・丸◯を後 → チェックが上に出る。
2. **transform の anchor_point 既定は (0,0)**。そのまま `scale`/`rotation` を付けると
   “キャンバス左上を中心に”変形して要素が画面外へ飛ぶ。要素の中心で回す/脈打たせるには
   `pivot(group, center)`（= anchor=position=center）を必ず呼ぶ。中の shape も同じ中心に置く。
3. **Trim（線を描き進める表現）は cairosvg プレビュー(gif/png)に出ない**。
   実機 lottie-web / lottie-ios では動く。検証GIFで確認したい動きには Trim を使わず、
   scale/opacity で“出す”。どうしても draw-on したいなら `--output-format html`（lottie-web）
   か実機で確認する。
4. **乱数禁止**（再現性のため）。ばらけさせたいときは index ベースで決定論的に（`i % 5` など）。

## 最小レシピ
```python
from build_lottie import new_anim, save, COLORS, filled_ellipse, anim_scale, anim_opacity, pivot
a = new_anim(512, 512, fps=30, duration=0.8)
from lottie.objects import ShapeLayer
layer = a.add_layer(ShapeLayer())
dot = filled_ellipse(layer, (256, 256), (200, 200), COLORS["sky"])
pivot(dot, (256, 256))                      # 中心で変形させる
n = a.out_point
anim_scale(dot, [0, n*0.5, n*0.7, n], [0, 115, 92, 100])  # ポンと出る
anim_opacity(dot, [0, n*0.3], [0, 100])
save(a, "out.json")
```

## 図形（lottie.objects）
| 図形 | クラス | 主なフィールド |
|---|---|---|
| 円/楕円 | `Ellipse` | `.position.value=Point(x,y)`, `.size.value=Point(w,h)` |
| 四角 | `Rect` | `.position`, `.size`, `.rounded.value`（角丸半径） |
| 星/多角形 | `Star` | `.position`, `.outer_radius`, `.inner_radius`, `.points`, `.star_type` |
| 自由線 | `Path` | `.shape.value` が `Bezier`。`bez.closed=False; bez.add_point(NVector(x,y))` |
| 塗り | `Fill(Color(r,g,b))` | `.opacity.value`(0-100) |
| 線 | `Stroke(Color, width)` | `.line_cap=LineCap.Round`, `.line_join=LineJoin.Round` |

`Color(r,g,b)` は 0..1。`from lottie.objects.shapes import LineCap, LineJoin`。
`from lottie.nvector import NVector`。

## アニメ（キーフレーム）
どのプロパティも `prop.add_keyframe(frame, value)` で打つ。`build_lottie.py` のラッパ:
- `anim_scale(group, frames, scale_pcts)` — `Point(s,s)` を打つ
- `anim_opacity(group, frames, vals)` — 0..100
- `anim_position(group, frames, [(x,y),...])`
- `anim_rotation(group, frames, degs)`

“バネっぽさ”はオーバーシュートで作る: `[0, 115, 92, 100]`（行き過ぎてから戻る）。

## プレビュー / 変換（CLI: `.venv/bin/lottie_convert.py`）
| 出力 | 用途 | cairo要否 |
|---|---|---|
| `.gif` | ぱっと見・Read で確認 | 要（cairosvg・同梱済み） |
| `.png --frame N` | 静止1フレーム確認 | 要 |
| `.html` | lottie-web で実再生（Trimも動く） | 不要 |
| `.json` | Lottie 本体（成果物） | — |
| `.tgs` | Telegram ステッカー | — |

`scripts/preview.sh anim.json` で gif+html を作って開く。

## iOS への載せ方（参考・未配線）
本リポジトリはまだ Lottie を使っていない。実装するなら
[lottie-ios](https://github.com/airbnb/lottie-ios)（SwiftPM）を追加し、`LottieView(animation: .named("xxx"))`。
`.json` を bundle に入れる（`.lottie`/dotLottie でも可）。導入時は別ブランチ/ワークツリーで。
