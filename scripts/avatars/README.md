# 着せ替えアバター生成パイプライン（B方式：レイヤー合成）

SpellingTrainer の着せ替えキャラを「**坊主マネキン base（男女2種）＋透過パーツ**」のレイヤー合成で作る仕組み。
各パーツ（髪/トップス/ボトムス/靴/表情/小物）を **codex の `image_gen` でマゼンタ背景に生成 → クロマキー透過 →
base に z-order で重ねる**。位置はベース参照で自動整列し、アプリ側（SwiftUI ZStack）は座標計算なしで合成できる。

> 運用ガイド（生成プロンプトの作法・改善バックログ含む）はグローバル skill
> `~/.claude/skills/avatar-dressup-gen/SKILL.md` にある。仕様の唯一のソースは `spec.json`。

## 構成
```
spec.json            ← 唯一の仕様ソース：style / bases(female/male) / preserve / constraints /
                       layers.z_order / placement / base_landmarks / hair_rules / shoe_rules /
                       slots(hair/top/bottom/shoes/expression/accessory) / tech(chroma_key 等)
avatar_lib.py        ← 純粋ロジック：chroma_key_defringe / bbox / crop_with_offset / compose
test_avatar_lib.py   ← avatar_lib のテスト（pytest不要・`python3 test_avatar_lib.py`）
_shoe_align.py       ← 靴ペアをL/R分割し base の足中心へスナップ
_dressup_demo.py     ← base+服+靴に髪をswapして合成グリッド(dressup_grid.png)を出力（QA）
_hair_test.py        ← 髪パーツ単体の合成確認
_compose_demo.py     ← 抽出→合成の最小デモ
refs/                ← 参考シート（髪型リファレンス等）
out/                 ← 生成物（git管理外）。base_*.png=凍結ベース, part_*.png=各パーツ
```

## z-order（下→上）
`back_hair → base_body → bottom → shoes → top → outer → face → front_hair → accessory`

## クロマキー（重要）
背景＝純マゼンタ(dist≤`bg_seed_threshold`=40)＋有界ハロー(pure_magを`halo_px`=3膨張 ∩ near_mag(dist≤`dist_threshold`=120))。
near_mag を無制限フラッドしないので、**露出したピンク/紫の前景も本体は残り**外周~`halo_px`だけ削れる。
enclosed な純マゼンタ隙間（毛束の間など）は除去。`erode_px`=2でαを収縮、decontaminate は背景隣接 ring(`ring_px`=3) のみ。
**前景アートは #FF00FF から距離40以内の色を使わない**（#FF00FF は背景専用。通常のピンク#FF69B4等はOK）。

## 使い方
```bash
cd scripts/avatars
python3 test_avatar_lib.py        # ロジックのテスト
# パーツ生成は codex image_gen（sandbox: workspace-write, cwd=out, マゼンタ地・1024x1536・base整列）
python3 _shoe_align.py            # 靴をL/Rスナップ → out/cut_shoes_white_v2.png
python3 _dressup_demo.py          # 合成グリッド out/dressup_grid.png を目視QA
```

## 運用フロー
1. `spec.json` の base_landmarks / hair_rules / shoe_rules を基準にパーツ生成プロンプトを作る。
2. codex image_gen でマゼンタ地パーツ生成 → 透過 → 合成グリッドを**目視** → 気に入るまで再生成。
3. 採用パーツを Assets に取り込み、SwiftUI ZStack で着せ替え（将来）。

> 旧A方式（anchors×variations の焼き込み生成: avatar_prompt.py / generate_avatars_* / variations.csv）は
> このB方式へ置換し削除済み。
