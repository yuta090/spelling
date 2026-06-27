# リモート採点 現状仕様（SpellingTrainer）

最終更新: 2026-06-27

「**親が別端末で、子の書き取り（手書き＋スペル）を採点する**」機能（リモート採点）の現状仕様。
別エージェント／実装担当への引き継ぎ用。**実装済み(BUILT)** と **設計のみ(PLANNED)** を明確に分ける。

関連: [supabase-sync-design.md](./supabase-sync-design.md) / [supabase-adapter-design.md](./supabase-adapter-design.md) / [parent-web-cloud-design.md](./parent-web-cloud-design.md) / [monetization-spec-2026-06-27.md](./monetization-spec-2026-06-27.md)

## 0. 結論（最重要）

- 採点ロジック・データモデル・DBスキーマは**設計済み**。**ローカル（同一iPad内）の採点フローは実装済み**。
- ただし **採点に必要なデータ（attempts / reviews / 手書き画像）の同期が未実装**。現状 Supabase 同期は **`words` / `profiles` のみ**。
- ⇒ **別端末でのリモート採点は現時点では成立しない**（採点結果はローカル保存のみ）。
- リモート採点は **有料機能の想定**だが、**権利ゲートは未実装**。

## A. データモデル（実装済み / `iPadPrototype/Models.swift`）

- `GradeDecision`（自動判定）: `autoCorrect / autoIncorrect / needsReview / rewrite / timeExpired`
- `ParentReviewDecision`（親の採点）: `unreviewed → approved / needsPractice`
- `SpellingAttempt`（テスト1問）と `PracticeSample`（練習1回）が共通で保持:
  - `parentReviewDecision`, `parentExampleDrawingData: Data?`（親が描くお手本）, `parentReviewedAt: Date?`
  - 子の手書きは `drawingData: Data`（PencilKit）＋ `canvasSize`
- 「クリア(正解)」判定: 親 `approved` → true、`needsPractice` → false、未レビューなら `decision == .autoCorrect`。

## B. ローカル採点フロー（実装済み / `iPadPrototype/ParentDashboardView.swift` 〜6478）

- 親メニュー「採点」タブ（`ParentSection.grading`）。未レビューの attempts/practice を一覧（子の手書き＋OCR結果）。
- 親が「OK＝approved／直そう＝needsPractice」を選択。needsPractice 時は**お手本を手描き**して添付。
- 下書き（`decisionDrafts`）→「採点完了」で確定 → `AppModel.updateAttemptParentReview(...)` / `updatePracticeSampleParentReview(...)` でローカル永続化。

## C. 同期状況（リモートの肝 / 未実装が核心）

| データ | 同期 | 根拠 |
|---|---|---|
| words / profiles | ✅ 実装 | `WordDTO` / `ProfileDTO`, `WordSyncCoordinator` |
| **attempts（子の解答・手書き）** | ❌ 未 | `iPadPrototype/SyncDTO.swift` に `AttemptDTO` 無し |
| **reviews（親の採点結果）** | ❌ 未 | `ReviewDTO` 無し |
| **practiceSamples / 手書き画像** | ❌ 未 | DTO・アップロード経路無し |

- `iPadPrototype/SyncEngine.swift` は **「複合 unique 制約のないテーブル（現状 profiles / words）に限定」**と明記。attempts/reviews は将来対応。
- ⇒ **採点データはローカルのみ。端末変更・初期化で消失。別端末から子の解答は見られない。**

## D. Supabase スキーマ（作成済み・未配線 / `supabase/migrations/20260626000002_learning_data.sql`）

- `attempts`（追記専用）: `household_id, profile_id, session_id, word_id, expected_word, mode, recognized_text, auto_decision, drawing_path(text=Storageキー), submitted_at`。RLS: SELECT / INSERT のみ（UPDATE/DELETE 不可）。
- `reviews`（親採点）: `attempt_id(FK), parent_decision(unreviewed/approved/needsPractice), parent_example_path(text), reviewed_by, reviewed_at`。RLS: 参照=世帯全員 / 追加・更新=親のみ。
- `review_requests`（通知トリガ用）: `session_id, pending_count`。
- ※ 手書きは**バイナリではなく Storage キー(text)** で持つ設計。

## E. 世帯・端末ペアリング（スキーマ済み・UI未 / `supabase/migrations/20260626000001_core_identity_rls.sql`）

- `households` / `household_members`（親=Supabase Auth, role owner/parent）/ `profiles`（子・ログイン無）/ `devices`（子iPad, 匿名auth, paired_at/revoked_at）/ `pairing_codes`（15分・ハッシュ・単回）。
- **世帯あたり親は最大2人**（トリガ実装済み: `20260627000001_two_parent_limit.sql`）。
- アプリ側は `SyncSession.activeHouseholdID` ＋ `createHousehold()` のみ。**6桁コード等のペアリングUIは未実装**。

## F. 手書き画像ストレージ（設計のみ・未実装 / `docs/supabase-adapter-design.md` §6, §9）

- 非公開バケット `households/{hh}/profiles/{pid}/attempts/{id}.pkdrawing`。
- Edge Function `storage-sign` が短TTLの**署名URL**を発行。アップロード/ダウンロードとも署名URL経由（クライアントは直接 list しない）。
- **未実装**。現状は手書きをローカルの `Data` blob で保持。

## G. 通知（設計のみ・未実装 / `docs/supabase-adapter-design.md` §5, `supabase-sync-design.md` §6）

- `review_requests` 挿入を契機に Edge Function `review-notify` が**親端末へ APNs プッシュ**（pending_count 付き）。**未実装**。
- APNs 利用には **Apple Developer 登録が前提**（現状未登録）。`SpellingTrainer.entitlements` に push 権限はあるがサーバ未接続。

## H. 意図する end-to-end フロー（設計 / docs）

```
1. 子がセッション終了 → attempts ＋ 手書き(Storage) を Supabase へ
2. review_requests 作成 → review-notify が親へ APNs
3. 親が別端末で pull → 手書きを署名URLで閲覧
4. 親が approved / needsPractice を reviews に INSERT（お手本も）
5. 子端末が reviews を pull → 結果反映（クリア or 練習に戻す）
```

- 同期の決定的ID: `reviews = uuidv5(attempt_id)`（多端末同時でも同一レコード）。
- 課金: リモート採点・マルチデバイス同期は**有料**想定（[monetization-spec](./monetization-spec-2026-06-27.md)）。**ゲート未実装**。

## I. リモート採点を成立させるために未実装で必要なもの

| # | 必要コンポーネント | 状態 | 規模感 |
|---|---|---|---|
| 1 | 同期DTO（`AttemptDTO`/`ReviewDTO`）＋ SyncEngine 拡張（複合unique・LWW） | ❌ | Medium |
| 2 | 手書き Storage 連携（`storage-sign` ＋ アップ/ダウンロード） | ❌ | High |
| 3 | `review-notify` Edge Function（APNs。※Apple登録必須） | ❌ | Medium |
| 4 | ペアリングUI（6桁コード/QR、device 登録） | ⚠️ スキーマ済・UI無 | Medium |
| 5 | 権利ゲート（サブスク確認。※サーバ権利ミラーは別途） | ❌ | Low |

> 補足: `docs/HANDOFF-2026-06-26.md` の整理でも「残りは iOS の SyncEngine 実装・Edge Functions・課金・手書き Storage」とされている。

## 主要ファイル参照

- データモデル: `iPadPrototype/Models.swift`（`GradeDecision`/`ParentReviewDecision`/`SpellingAttempt`/`PracticeSample`）
- ローカル採点UI: `iPadPrototype/ParentDashboardView.swift`（~6400–6549）
- 同期状況: `iPadPrototype/SyncDTO.swift`（Word/Profile のみ）, `iPadPrototype/SyncEngine.swift`
- スキーマ: `supabase/migrations/20260626000002_learning_data.sql`（attempts/reviews/review_requests）, `…0001_core_identity_rls.sql`（households/devices/pairing）
- 設計: `docs/supabase-sync-design.md`, `docs/supabase-adapter-design.md`, `docs/parent-web-cloud-design.md`
