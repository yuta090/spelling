# HANDOFF — AI手書きOCR採点（1枚まとめ）

2026-06-27 / 次の担当へ。詳細は [ai-ocr-handwriting-research-2026-06-27.md](./ai-ocr-handwriting-research-2026-06-27.md)、依存は [remote-grading-spec.md](./remote-grading-spec.md)。

## 決定事項（確定）
- **クラウドVLM一択**。ローカルVLM（Qwen等）はアプリ肥大・遅延で原則不採用（オフライン必須 等の固い要件が出たときだけ）。
- **エスカレーション設計**：①ローカルVision(無料)で自信高&綴り一致→そのまま採点 / ②割れた難字だけクラウドVLM課金 / ③読めない→「きれいに書き直そう」コーチング。**API送りは2〜3割**に圧縮。
- **リフレーム**：AIでも読めない字＝直すべき字。**100%認識を追わない**（認識失敗を教育課題に反転）。
- **コスト**：保護者プラン月数百円に対し API原価は**誤差**（nano/Flash-Liteなら全件送りでも月〜十数円）。**回数制限は見せない**。例外は「Haiku×全件送り≈月120円」だけ。
- **収集方針**：専用ラベル収集は作らず、**リモート採点（親採点）データに相乗り**。`parentReviewDecision`(approved/needsPractice)=正誤の真値ラベル、`expected_word`=target、`recognized_text`=ローカルOCRベースライン。**手入力ゼロ**。
- 純粋ロジック（確信度判定・綴り一致・エスカレーション可否・採点）は **`SpellingSyncCore` に純粋関数＋TDD**。アプリは薄く。
- ターゲット年齢上限＝**中学受験〜高校受験**（高校生は別ブランド案）。手書きOCRの価値は低年齢ほど高い。

## モデル候補（2026-06 / OpenRouter）
| モデル | 入/出 $/1M | 位置づけ |
|---|---|---|
| **google/gemini-2.5-flash-lite** | 0.10 / 0.40 | ◎ 最安vision・第一候補 |
| **openai/gpt-5.4-nano** | 0.20 / 1.25 | ○ 対抗（無印 gpt-5-nano は**vision非対応**で不可） |
| anthropic/claude-haiku-4.5 | 1.00 / 5.00 | △ **フォールバック**。安いモデルで足りれば外す |
| claude-sonnet-4.6 | 3.00 / 15.00 | 最難ケースのエスカレ先候補のみ |

> ⚠️ **「コメント生成にはHaikuが要る」は未検証の決めつけ。排除。** まず nano/Flash-Lite で**採点＋一言コメントを1呼び出し兼用**で実測し、品質が落ちた場合のみ Haiku／コメント分離を検討。

## ベンチharnessの現状（`scripts/ocr-bench/`・実装済み）
- `bench.py`：同一画像を全候補モデルに横並び投入（OpenRouter）。JSON `{predicted_word, legible, matches_target, comment}` を返させ、**採点＋コメントを1呼び出しで検証**。指標：OCR精度・**誤受理(FA)**・誤拒否(FR)・判読不能の捏造・レイテンシ・コメント品質→ `results-*.csv`。
- 画像源2系統：**Supabase**（`ocr_bench_samples`＋`ocr-bench`バケット／`schema.sql`）か **ローカル**（`samples/`＋`labels.csv`）。SUPABASE未設定で自動ローカル。
- `.env`（OPENROUTER_API_KEY 等）は**コミットしない**（.gitignore済み）。`.env.example` 参照。
- ※ 先に作った独立 `ocr_bench_samples` は「相乗り方針」決定で**暫定/参考に格下げ**。

## 次の一手（この順で）
1. **暫定A：テスト端末ローカル書き出し**（バックエンド不要・最速で実データ）。アプリに `#if DEBUG` のエクスポートを追加：`practiceSamples`/`attempts` を **PNG（PencilKit描画をレンダ）＋ `labels.csv`（target, ground_truth相当=親判定, recognized_text）** で書き出す → `scripts/ocr-bench/samples/` へ投入 → `bench.py` で初回計測。
2. **bench.py のデータ源を相乗りデータに差し替え**（暫定Aの書き出し or 将来のSupabase `attempts`/`reviews`）。`parentReviewDecision`→正誤の真値、`recognized_text`→ローカルOCRベースライン。
3. **初回計測 → メイン判定エンジン選定**：nano/Flash-Lite で**採点もコメントも**実用域か。FA最小を最優先で比較。
4. （本筋B）同期DTO(`AttemptDTO`/`ReviewDTO`)＋手書きStorage(`storage-sign`)が実装されたら、ベンチは Supabase の `attempts`/`reviews` を直接読む（製品としてどのみち作る部分）。
5. エスカレーション/確信度ロジックを `SpellingSyncCore` に純粋実装（TDD）。画像はタイトにクロップ。

## 注意点
- **誤受理(False Accept)＝スペルミスを正解にする が最重要**（親の信頼が即死）。0を目指す指標。
- **親判定ラベルは「正誤」のみで正確な綴り文字列ではない**。FA/FRは正誤で測れる。文字列レベルOCR精度だけ必要なら少数を別途文字起こし。
- **依存：attempts/reviews/手書きの同期は未実装**（現状 words/profiles のみ）。だから初回は**暫定A（ローカル書き出し）**で回す。Supabase直読は本筋Bで。
- 画像は**必ずタイトな単語クロップ**（ページ全体を送ると画像トークン増でコスト前提が崩れる）。
- プライバシーは**訴求でなく地雷除去**：送るなら 親同意・画像最小化・非保存 を明記。第三者API送信は審査説明義務あり。
- コメント生成は**独立の検証項目**（モデル選定を分ける根拠）。Haiku固定にしない。
