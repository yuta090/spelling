# 定着エンジン（SRS）設計

Status: 設計＋コア実装（TDD）
Date: 2026-06-25
方針: **シンプルなライトニング箱方式（Leitner）**。`SM-2`のような複雑さは避け、子ども向けに分かりやすく・実装と検証が容易な形にする。
関連: `eiken-level-mapping.md`（セット生成）／`Sources/SpellingSyncCore/`（実装）

---

## 1. 目的
- 「テストで覚える（検索練習）」を**最適な間隔**で繰り返し、**定着**させる。
- 毎日の**今日のちょうせん**を自動生成（詰め込みでなく少量・継続）。
- 英検ゴール／試験日から**逆算**して出題量を決める。

## 2. モデル（Leitner 箱）
- 各単語カードは **box 1〜5** を持つ。box が大きいほど定着＝復習間隔が長い。
- **正解 → box+1**（最大5）。**不正解 → box1 に戻す**（やさしくリセット）。
- box5 に到達して期日を越えたら **mastered（習得）**＝出題対象から外す（セット生成で除外）。

### 復習間隔（初期値・調整可能）
| box | 間隔(日) | 意味 |
|---|---|---|
| 1 | 0 | その日のうち/次セッション |
| 2 | 1 | 翌日 |
| 3 | 3 | 数日後 |
| 4 | 7 | 1週間後 |
| 5 | 16 | 2週間超 → 以後 mastered 扱い |

`dueDate = lastReviewedAt + interval(box)`。`asOf >= dueDate` なら「**期日が来た（due）**」。

## 3. 今日の出題生成
入力：カード一覧（box/最終学習日）、`asOf`（今日）、`dailyGoal`（例: 10〜20）、新出語の供給（英検級セット §eiken-mapping）。
手順：
1. **due な復習カード**を優先的に集める（古い期日順）。
2. 残り枠を **新出語**で埋める（英検級セットから頻度順・未導入のもの）。
3. 合計が `dailyGoal` を超えない範囲で「今日のちょうせん」を構成。

→ 「復習を最優先、足りない分だけ新規」。**毎日少量・継続**を担保。

## 4. 英検ゴール逆算（任意機能）
- 「英検◯級まで」＝対象帯の語数（`eiken-level-mapping` の語数）。
- 「試験まで◯日」と `dailyGoal` から、**間に合うペース**を提示（足りなければ `dailyGoal` 引き上げを提案）。
- カウントダウン直前は **due 復習を増やす**（テスト前の総ざらい）。

## 5. データ（既存資産の拡張）
- 既存 `ReviewQueueItem`（復習キュー）に **box / lastReviewedAt / dueDate** 相当を持たせる、または単語学習状態として別管理。
- 同期は `SyncableRecord`（`SyncMetadata`）に載せ、端末間で box/due を共有（CloudKit/将来backend）。
- **純粋なスケジューリング計算は `SpellingSyncCore.SRSScheduler` に集約**（UI・永続化から独立、テスト容易）。

## 6. コア実装（`SpellingSyncCore.SRSScheduler`・TDD）
純粋関数（`asOf: Date` を必ず引数で受け、`Date()` をロジックに埋めない＝決定論）：
- `nextBox(current:correct:) -> Int`
- `intervalDays(box:) -> Int`
- `dueDate(box:lastReviewedAt:) -> Date`
- `isDue(box:lastReviewedAt:asOf:) -> Bool`
- `isMastered(box:lastReviewedAt:asOf:) -> Bool`
- `selectDue(cards:asOf:) -> [Card]`（期日到来を古い順）

UI/永続化はこの結果を使うだけ。`buildTodayQueue`（新規語の供給と合算）はアプリ層で `selectDue` ＋ 英検級セットを組み合わせて実装。

## 7. 子ども向け表現（非ラベリング堅持）
- box・期日・mastered は**内部値**。子には見せない。
- 子の画面は「**今日のちょうせん ◯もん**」「れんぞく◯日」「キャラが育つ」だけ。
- 親レポートでのみ box→「定着度」ヒートマップとして可視化。

## 8. 今回実装する範囲
- `SRSScheduler`（§6 の純粋関数）を **TDD** で実装（`swift test`）。
- `buildTodayQueue` のアプリ層統合・`ReviewQueueItem` 拡張・英検逆算UI は後続（実機・同期方針確定後の作業と整合）。
