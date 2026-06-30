# OCR ベンチ

候補ビジョンモデルを **同一画像セットで横並び比較**し、手書きスペル採点の精度・誤受理・判読不能の捏造・レイテンシを測る（§7 の方法論）。
詳細方針: `docs/ai-ocr-handwriting-research-2026-06-27.md`

## 何を測るか
- **OCR精度**: 書かれた文字を正しく読めたか
- **誤受理(FA)**: スペルミスを「正解」にしてしまう ← **最重要・0が理想**
- **誤拒否(FR)**: 正しいのに「不正解」
- **判読不能の検出 / 捏造**: 読めない字を捏造せず「読めない」と返せるか
- **丁寧さ neatness(1〜4)**: 字の整いを段階で返せるか。分布が飽和しない（＝4段に使える）かと、人手ラベルとの一致を見る → 「ていねいに書けたらボーナス」導線の可否判定。綴り正誤とは独立
- **コメント品質**: 安いモデルで一言コメントが出せるか（CSVを目視評価）
- **レイテンシ**: OpenRouter経由の上限値の目安

## セットアップ
```sh
pip install requests
export OPENROUTER_API_KEY=sk-or-...
```

`bench.py` 冒頭の `MODELS` を編集。slug と「画像入力対応」は https://openrouter.ai/models で必ず確認。

## サンプル画像の置き方（2通り）

### A. Supabase（推奨・本命）
1. `schema.sql` を Supabase SQL Editor で実行（`ocr_bench_samples` テーブル + `ocr-bench` バケット作成）。
   - アプリの同期スキーマとは**分離した専用テーブル**。同期ロジックを汚さない。
2. 画像を `ocr-bench` バケットにアップロード（例パス: `messy/becuase_01.png`）。
3. `ocr_bench_samples` に1行ずつラベル登録:
   - `storage_path` = バケット内パス
   - `target` = 出題語（書くべき単語）
   - `ground_truth` = 実際に書かれた文字（人が読んだ正解）
   - `legible` = 人が読めるか（判読不能サンプルは false）
   - `neatness` = 字の丁寧さ 1〜4（任意・綴り正誤と無関係。1=読みにくい 2=ふつう 3=きれい 4=お手本級）。
     埋めるとモデルの neatness 判定の人手一致率が出る。空でも分布（飽和チェック）は取れる
4. 実行:
   ```sh
   export SUPABASE_URL=https://xxx.supabase.co
   export SUPABASE_SERVICE_KEY=eyJ...   # service_role キー（RLSバイパス）
   python3 bench.py
   ```

### B. ローカル（手早く試す）
- `samples/` に画像を置き、`labels.csv` にラベルを書く（テンプレ同梱）。
- SUPABASE 環境変数を設定しなければ自動でローカルモードになる。
   ```sh
   python3 bench.py
   ```

### C. 暫定A：アプリのデバッグ書き出し（親判定ラベルに相乗り・最速）
[docs/HANDOFF-ai-ocr-2026-06-27.md](../../docs/HANDOFF-ai-ocr-2026-06-27.md)。バックエンド不要で「実使用＋実親ラベル」を得る。
1. DEBUG ビルドのアプリ → 親メニュー → デバッグ → **「ベンチ用に書き出す」** → zip を共有/保存。
2. zip を解凍し、中の `samples/`(PNG群) と `labels.csv` を `scripts/ocr-bench/` に置く（既存を置換）。
3. `python3 bench.py`（ローカルモード）。`labels.csv` に `verdict` 列があれば**親判定ラベル形式**として自動処理：
   - `verdict` = correct / incorrect（unreviewed は対象外）。**FA/FR を親判定で測る**。
   - `recognized_text` = ローカルOCRベースライン → AIがこれを上回るか比較表示。
   - OCR精度/判読不能は `-`（正確な綴り真値が無いため。必要なら少数を別途文字起こし）。

## サンプル設計のコツ（§7）
- **同じ画像を全モデルに通す**（都度書かせて別々に試さない）。まず30〜50枚。
- 3種類を必ず混ぜる:
  - 正しく書けた語（`target == ground_truth`）
  - スペルミス（例 `target=because, ground_truth=becuase`）← 誤受理を測る
  - **判読不能**（`legible=false`）← 捏造を測る
- 低学年の汚い字を厚めに。可能なら複数人・年齢バラけ。

## 出力
- `results-YYYYMMDD-HHMMSS.csv`: 全呼び出しの明細（predicted/verdict/comment/latency/tokens）
- 標準出力にモデル別サマリ（OCR精度・FA・FR・判読不能検出・捏造・平均遅延）

## コスト
1呼び出し ≈ 入力300〜400 / 出力20トークン。50枚×3モデル×3回でも数百呼び出し＝**実費 $1 未満**。
OpenRouter のチャージは **$10 で十分**（何度も回せる）。
