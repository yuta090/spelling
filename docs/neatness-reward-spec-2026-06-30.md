# ていねいさ報酬（NeatnessReward）— 仕様＆再開ガイド

> ステータス: **一旦クローズ（2026-06-30）**。Core 純ロジックは実装・マージ済（PR#160）。
> 残り（app 配線）は**子どもの実手書きデータ収集→可否確定**待ちでブロック中。
> データが集まったら本ドキュメントの「再開手順」から続行する。

関連メモリ: `memory/neatness-reward-feature.md`（要約版）。本ドキュメントが正本（恒久）。
旧ドラフトは session scratchpad にあったが揮発するため、ここに統合した。

---

## 1. 目的（最重要・ブレさせない軸）

ごほうび付与そのものより、**子どもに「ていねいに書こう」という意識づけ**をすること。
報酬は手段であって目的ではない。日本人の子ども向け iPad 英単語スペル練習アプリ
（SwiftUI / iOS17 / Swift6）。

## 2. 子どもの体験（ゴール像）

れんしゅう（手書きでスペルを書く）後、字のていねいさに応じて
**4段の称賛＋最後にボーナスコイン**を出す。段階表示：

1. よく書けたね
2. 上手に書けたね
3. すごく上手！
4. 完璧！

---

## 3. 設計の確定事項（codex Architect / Code Reviewer 検証済）

### 3.1 ていねいさの「出所」= 外部VLM採点に相乗り
- **Apple Vision の confidence は丁寧さティアに使えない**。値が 1.0 に飽和して
  分散がほぼ無く、4段はおろか 2段の安定分けも困難。
  - 実データ: `scripts/ocr-bench/` の `EXPERIMENT_REPORT.md` / `generated/results.json`
    に飽和の証拠（`cat`→`cot` のように崩した字でも 1.0）。→ **この案は破棄**。
- **採用案: 丁寧さは外部VLM採点レスポンスに相乗りで取得する**。
  どのみち手書き正誤を VLM で採点する（[[ai-ocr-and-age-ceiling]] /
  `docs/ai-ocr-handwriting-research-2026-06-27.md`）ので、**同じ採点リクエストの
  レスポンスに `neatness: 1〜4` を1フィールド足すだけ**＝追加コスト・追加レイテンシ
  ほぼ 0。VLM は字の整いを直接判定でき、confidence のような飽和をしない（仮説。
  §6 の bench で実証する）。**綴り正誤とは独立軸**。

### 3.2 純ロジックは Core に実装済（PR#160 マージ済）
ファイル: `Sources/SpellingSyncCore/NeatnessReward.swift`
テスト: `Tests/SpellingSyncCoreTests/NeatnessRewardTests.swift`（12件・全742件グリーン・codex APPROVE）

API:
- `enum NeatnessTier: Int { nice=1, good=2, great=3, perfect=4 }`（`Comparable`/`Sendable`）
- `NeatnessReward.tier(neatnessScore: Int) -> NeatnessTier`（1〜4にクランプ。範囲外も安全）
- `NeatnessReward.bonusCoins(for: NeatnessTier) -> Int`（**2 / 4 / 6 / 10**）
- `NeatnessReward.sessionBonusCoins(tiers: [NeatnessTier]) -> Int`
  （合算＋上限 `sessionBonusCap = 50`・**加点のみで常に 0 以上**）
- `NeatnessReward.sessionTier(tiers: [NeatnessTier]) -> NeatnessTier?`
  （平均の四捨五入・端数は上寄り＝ポジティブ寄り・空なら `nil`）

**この層は「ティアの出所（VLM neatness）」にも「UX方式（A/C）」にも非依存**。
だから viability 未確定でも安全に先行実装した（純粋関数・整数演算のみ）。

### 3.3 設計ガード（このアプリの哲学・絶対に崩さない）
- **罰しない**：最低ティアでも 100% ポジティブ（+2コイン）。「ざんねん」系を出さない。
  能力でなく「ていねいさ＝プロセス/努力」への称賛。
  CLAUDE.md「評価で優劣を意識させない」と両立する前提。
- **本筋（スペル）を邪魔しない**：丁寧さは**加点ボーナスのみ**。基礎コイン（30/語）は
  減らさない。正解なら字が雑でも必ず正解＆基礎コイン満額。丁寧さで合否を分けない。
- **怖がらせない**：丁寧意識が「遅く緊張」「なぞり書き」に化けないよう軽く・寛容に。

---

## 4. UX 方式（意識づけ3点セット）

1. **書く前**：初回/たまにだけ「ていねいに書くと さいごにボーナス✨」
   （毎回出さない・出しっぱなしにしない。→ [[control-repeating-animated-ui]]）。
2. **書いてる最中（意識づけ本体）**：空きスペースに**ポジティブ専用の「いい感じ！」メーター**。
   - 下げない・現在の1語を採点中には見せない・全体の vibe を見せる。
3. **最後**：`PracticeReviewView` で「きょうのていねい度 ⭐︎⭐︎⭐︎ ＋Nコイン」を合算付与。

### 待ち時間の扱い（重要）
1語ごと同期VLMだと 1〜3秒待たされる。解決＝**採点を「書いてる時間」に重ねる（非同期
パイプライン）**。1語描き終わるたび fire → 次を描く間に採点完了 → 最後の「判定中」表示は
ほぼ一瞬。丁寧さ表示はどのみち最後でいいので待ち圧ゼロ。
レイテンシは `ContinuousClock` で壁時計実測し p50/p95 で方式を決める：
- **方式A**：1語ごと採点＋メーター（リアルタイム寄り）
- **方式C**：最後に並列採点（待ちを最後に集約）

---

## 5. 正誤判定モデル候補（speed最優先・安い順）

`docs/ai-ocr-handwriting-research-2026-06-27.md` §4 参照。

| モデル | 価格(in/out per M) | 備考 |
|---|---|---|
| `google/gemini-2.5-flash-lite` | $0.10 / $0.40 | ◎ 第一候補 |
| `openai/gpt-5.4-nano` | $0.20 / $1.25 | 次点 |
| `anthropic/claude-haiku-4.5` | $1 / $5 | フォールバック |
| （最難ケース）Sonnet | — | 必要時のみ |

neatness フィールドは同一レスポンスに相乗りなので、モデル選定は正誤判定の speed/精度で決める。

---

## 6. 計測ハーネス（実装済・データ投入待ち）

`scripts/ocr-bench/`（`bench.py` + `schema.sql`、PR#158 マージ済）に **neatness 評価を追加済**：
- VLM プロンプトに `neatness: 1-4` を追加
- `clamp_neatness`（Python の bool は int サブクラスなので混入を弾くガード入り）
- CSV 出力に neatness 列
- summarize に**分布（飽和チェック）・人手一致・ペア比較**
- `schema.sql` に `neatness smallint`（check 制約）＋ ALTER

これで「**子ども手書きテストのついでに、VLM が丁寧さを4段で安定して返せるか
（飽和チェック＋人手一致）**」が測れる状態。

---

## 7. 進行順（全体ロードマップ）

| # | ステップ | 担当 | 状態 |
|---|---|---|---|
| ① | 子ども手書きテスト（neatness込み）を回す：画像アップロード＋人手ラベル付け（`ground_truth`/`legible`/`neatness`）→ `bench.py` | **ユーザー** | **未（ブロック元）** |
| ② | 飽和/一致を見て**丁寧さ機能の可否確定** | 私（データ後） | 待ち |
| ③ | 本番モデル決定 | 私（データ後） | 待ち |
| ④ | 直API で p50/p95 レイテンシ測定 | 私（データ後） | 待ち |
| ⑤ | UX方式 A/C 確定 | 私（データ後） | 待ち |
| ⑥ | `NeatnessReward`（Core 純ロジック）TDD 実装 | 私 | **✅ 済（PR#160）** |
| ⑦ | app 側の配線 | 私（可否確定後） | 待ち |

①〜⑤はユーザー作業待ちでブロック中（画像収集＋人手ラベルは私には実行不可）。

---

## 8. 再開手順（データが集まったら、ここから）

1. **bench を回した結果を見る**（`scripts/ocr-bench/` の出力）：
   - neatness の**分布**（1〜4 にバラけているか＝飽和していないか）
   - **人手ラベルとの一致**（VLM neatness が人の感覚とずれていないか）
   - → ②可否確定。**飽和 or 不一致なら機能を見送る**（このアプリでは無理に出さない方針）。
2. 使えるなら ③本番モデル決定 → ④直APIで p50/p95 → ⑤方式 A/C 確定。
3. **⑦ app 側の配線**（Core はもう在る）：
   - 採点リクエストのレスポンスから `neatness` を取り出す
     （正誤採点と同じ VLM 呼び出し。新規の往復は足さない）。
   - `NeatnessReward.tier(neatnessScore:)` でティア化 →
     `SpellingSessionView` の称賛オーバーレイ（既存 `PracticeCelebrationStyle`）を
     ティアで出し分け＋「いい感じ！」メーター更新。
   - セッション終了時、`NeatnessReward.sessionTier` / `sessionBonusCoins` で
     合算 → `PracticeReviewView` でボーナス付与（`AppModel.awardPracticeCoins` とは
     別経路の加点）。
   - UI 文言（「よく書けたね」等）は **app 層に置く**（Core はティア番号までしか持たない）。
   - **TDD**：配線ロジックで純化できる部分（neatness 抽出のパース等）は Core/テスト可能側へ。

### 既存コードの接続ポイント（配線時の地図）
- 手書き採点: `iPadPrototype/VisionTextRecognizer.swift` の
  `VisionSpellingOCR.recognize(_:expected:)`（現状 Apple Vision。VLM 経路は AI-OCR 側）。
- 採点純ロジック: `iPadPrototype/Models.swift` の `OCRGrader.grade(...)`。
- 練習フロー: `SpellingSessionView.swift`（grade 呼び出し → 称賛オーバーレイ →
  1語ごと `awardPracticeCoins(30)` → 最終語 → `PracticeReviewView`）。
- コイン純ロジック: `Sources/SpellingSyncCore/CoinRewards.swift`（満点ボーナス/ログイン
  ストリーク）。NeatnessReward はこれと同じスタイルで実装済。

---

## 9. 履歴
- 2026-06-30: bench に neatness 評価追加（PR#158 マージ）。
- 2026-06-30: `NeatnessReward` Core 純ロジック実装（PR#160 マージ・テスト12件）。
- 2026-06-30: 一旦クローズ。本ドキュメントを正本として作成（scratchpad ドラフトを統合）。
