# トップス カバレッジ表（系統別の充足/不足）

単一ソースは `scripts/avatars/tops.csv`。これはその要約ビュー。
`status=shipped`=出荷済み / `status=planned`=未生成（素材集め＆生成の対象）。
参考画像は `ref` 列のパス（`refs/<kei>/...`）に置く。**画像本体は .gitignore（著作権/容量）**、構成と .md/.csv だけ git 管理。

## 系統 × 充足状況（2026-06-30 時点）

| 系統(kei) | 対象 | shipped | planned（不足を埋める） |
|---|---|---|---|
| ガーリー girly | 女 | pink_puff(パフ半袖), lavender_knit(ニット長) | cream_cardigan(カーデ), gingham_blouse(ギンガム半袖) |
| スポカジ sporty | 女/共用 | red_tee(半袖), mint_star(星半袖) | yellow_raglan_tee(ラグラン長), pink_windbreaker(ウィンドブレーカー) |
| ナチュラル natural | 女/共用 | navy_border(ボーダー長) | beige_shirt(リネンシャツ), oatmeal_knit_vest(ニットベスト) |
| ストリート street | 男/共用 | blue_hoodie, green_hoodie, black_bolt(半袖) | purple_graphic_tee(グラフィック半袖), gray_anorak(アノラック) |
| アメカジ amekaji | 男 | mustard_sweat(トレーナー) | red_flannel(ネルシャツ), navy_varsity(スタジャン) |
| スポーツ sport | 男/共用 | blue_track(トラックJK) | red_colorblock_jersey(半袖), black_tank(タンク) |

## 偏りメモ（次に足すと良い方向）
- **半袖↔長袖**: 女スポカジは半袖に偏り→長袖(ラグラン)を planned 済。
- **アウター**: カーデ/ウィンドブレーカー/アノラック/スタジャン/ベストを planned で各系統に分散。
- **難所**（GENERATION_LOG 参照）= ジャケット類/カラーブロック/ニット/タンク。**これらは ref 画像必須**にして生成短縮する（planned の ref 列にパス記入済み）。

## 進め方
1. agy に `refs/TOPS_COLLECTION_PROMPT.md` を渡して系統別に参考画像を収集（`ref` のパスへ保存）。
2. 集まったら難所優先で生成（`_top_finish.py` の自動QA＋目視）。
3. 出荷したら tops.csv の status を shipped に更新＋ `GENERATION_LOG.md` にラウンド経過を追記。
