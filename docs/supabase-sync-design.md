# Supabase 同期設計（現行版）

Status: 設計確定版（実装の土台）
Date: 2026-06-26
前身: `parent-web-cloud-design.md`（2026-06-07・親Web前提）を**現行版に格上げ・更新**したもの。
変更点: 親は**ネイティブiPhoneアプリ**／**英検セット・SRS・検索練習テスト・親メニュー5分類**を反映／手書きは**R2 or Supabase Storage**／課金は**StoreKit**／**確実プッシュ**。
再利用: `SpellingSyncCore`（`SyncMetadata`/`LastWriteWins`/`ReviewProgress`/`Migration`/`SRSScheduler`）はそのまま使う。`UserDataStore` 境界に **Supabaseアダプタ**を挿す。

---

## 1. 役割分担（1系統＝Supabase主役）
- **Supabase Postgres**：家族の学習データの真実の源（同期）。
- **RLS**：世帯（household）単位で行を隔離。親はメンバー、子端末は匿名/デバイス認証。
- **Storage（手書き）**：まず Supabase Storage、コスト最適化で **Cloudflare R2（転送無料）** へ。署名URLで配信。
- **Edge Functions**：トランザクション処理（ペアリング、学校テストupsert、レビュー確定）、**StoreKit課金の検証**、**確実プッシュ**のfan-out。
- **iOSアプリ**：オフラインファースト（ローカルキャッシュ＝既存の保存層）→ オンライン時に同期。

---

## 2. 認証・世帯・ペアリング
- **親**：Supabase Auth（MVPはメールのマジックリンク。後でApple/Google）。初回ログインで `household` を自動作成しオーナーに。
- **子**：**アプリログインなし**。子端末は**匿名認証(anonymous)**でデバイスIDを持ち、ペアリングで世帯に紐づく。
- **ペアリング**：親アプリが6桁コード/QR発行 → 子iPadが入力 → Edge Functionが検証し `devices` に登録。以後その端末は**自分の世帯の自分のプロファイルのみ**読み書き可（RLS）。失効も親から。

---

## 3. データモデル（同期メタデータ共通）
全テーブルに `SpellingSyncCore.SyncMetadata` と対応する共通列を持たせる：

```
id uuid primary key,            -- 端末側でオフライン採番(既存方針)
household_id uuid not null,     -- 世帯スコープ(RLSキー)
profile_id uuid,               -- 子スコープ(該当する場合)
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),  -- 後勝ち(LWW)の基準
deleted_at timestamptz          -- tombstone(論理削除)。NULLでなければ削除済み
```

> 競合は **record単位 last-write-wins**（`updated_at`）。`Attempt`は不変、親採点は別行`Review`（衝突面を最小化＝Architect方針）。`SpellingSyncCore.LastWriteWins` と意味論を一致させる。

### 主要テーブル（抜粋・現行モデル）
| テーブル | 主な列（共通列＋） | 役割 |
|---|---|---|
| `households` | title | 世帯（オーナー＝親） |
| `household_members` | user_id, role(owner/parent) | 親メンバー（RLSの基点） |
| `profiles` | display_name, app_language, active_step_id | 子プロファイル（ログインなし） |
| `devices` | device_public_id, auth_user_id, paired_at, revoked_at | ペアリング済み端末 |
| `pairing_codes` | code_hash, expires_at(15分), consumed_at | 単回・短命のペアリングコード |
| `steps` | number, title, registered_date, is_child_step, sort_order | 出題ステップ |
| `words` | step_id, text(正規化), prompt_text, source(parent/child), display_order, **eiken_grade, ngsl_rank, dolch** | 単語（英検級ラベルは親のみ） |
| `step_word_memberships` | step_id, word_id, sort_index | **配列の代替join**（Architect指摘） |
| `attempts`（不変） | session_id, step_id, word_id, expected_word(スナップ), mode, recognized_text, ocr_confidence, auto_decision, drawing_path, submitted_at | 子の答案。append-only |
| `reviews`（別行） | attempt_id, parent_decision, parent_example_path, reviewed_by, reviewed_at | 親採点（Attemptと分離） |
| `review_requests` | session_id, pending_count | **通知トリガ**（`ReviewProgress.pendingCount`を保存） |
| `srs_cards` | word_id, box(1-5), last_reviewed_at, due_at | **定着状態**（`SRSScheduler`と一致） |
| `school_tests` / `school_test_items` | test_date, score, total / word_id, result | 学校テストと項目 |
| `review_queue_items` | word_id, source_type, status, reason | 復習持ち越し |
| `goals` | kind(eiken/exam), target_grade, target_date, daily_goal | **英検/試験ゴール**（出題逆算） |
| `reward_wallets` / `character_unlocks` / `child_settings` | （旧設計書のまま） | 報酬・設定 |
| `entitlements` | product_id, status, expires_at, original_transaction_id | **課金状態**（StoreKit→Edge検証） |

詳細な列は旧 `parent-web-cloud-design.md` §6 をベースに、上記の delta（共通同期列・eiken列・srs_cards・review_requests・goals・entitlements・step_word_memberships）を適用する。

---

## 4. RLS（行レベルセキュリティ）方針
- 親：`auth.uid()` が当該行の `household_id` の `household_members` に居るとき read/write 可。
- 子端末：`auth.uid()` が `devices.auth_user_id` に一致し、行の `household_id`/`profile_id` がその端末の紐づけと一致するとき read/write 可。`revoked_at` 済みは不可。
- Storage：`households/{household_id}/profiles/{profile_id}/...` のプレフィックスで隔離。親は署名URLで閲覧、子端末は自分のプレフィックスのみ書き込み。
- 多重レコード検証が要る操作（ペアリング・学校テストupsert・レビュー確定）は **Edge Function（service_role）** で実施。
- ポリシーの具体形は旧設計書 §11 を踏襲（family→household に読み替え）。

---

## 5. 同期戦略（UserDataStore アダプタ）
- **オフラインファースト**：UIはローカルを見る。オンライン時にプル/プッシュ。
- **プッシュ**：ローカルの未送信レコードを upsert（`updated_at` で後勝ち）。`attempts` は append-only。
- **プル**：`updated_at > 最終同期カーソル` の差分を取得し、`LastWriteWins.reconcile` でマージ、tombstone は除外して表示（`live`）。
- **手書き**：`attempts.drawing_path` はストレージのキー。本体はStorage/R2へ、メタはDBへ。
- 既存 `SpellingSyncCore` の純粋ロジック（LWW/tombstone/SRS/採点待ち）を**そのまま再利用**。アダプタは「Supabaseとの送受信＋DTO↔ドメイン変換」に集中。

---

## 6. 確実プッシュ（課金の目玉）
- 子がセッション完了 → `attempts` 追加 ＋ `review_requests`（pending_count）作成。
- DBトリガ or Edge Function が **親デバイスへ APNs** を送る（best-effortのCloudKitと違い**確実**）。
- 親アプリは通知タップ → 採点画面（該当`attempts`の`drawing_path`を署名URLで表示 → `reviews` 追加）。
- Android対応時は FCM を追加するだけ（同じイベント経路）。

---

## 7. 課金（StoreKit）
- iOSは **StoreKit2** で購読（家族プラン ¥580/月・¥4,800/年・7日無料＝D3案）。
- **App Store Server Notifications v2 → Edge Function** が受け、`entitlements` を更新。
- アプリは `entitlements`（同期される）で**プレミアム機能（同期/遠隔採点/レポート）を解放**。
- 無料: ローカルのみ・1人。プレミアム: 同期・遠隔採点・英検セット・レポート・複数子。

---

## 8. プライバシー（子ども・日本/COPPA）
- 子のPIIは**ニックネームのみ**。メール/電話/学校名/音声は収集しない。
- 手書き・学習履歴は世帯スコープでRLS隔離＋署名URL。保存は最小権限。
- 公開時は COPPA / 日本APPI の確認（旧設計書 §11 参照）。

---

## 9. 実装フェーズ
1. **スキーマ＋RLS マイグレーション**（`supabase/migrations/`）— households/members/profiles/devices/pairing_codes/steps/words/memberships/attempts/reviews/review_requests/srs_cards/goals/school_tests/entitlements。
2. **UserDataStore Supabaseアダプタ**（オフラインファースト・差分同期）。
3. **ペアリングUX**（親コード発行→子受諾）。
4. **手書きStorage**（まずSupabase Storage、のちR2）。
5. **確実プッシュ**（review_requests→APNs）。
6. **StoreKit課金＋entitlements**。
7. **移行**（既存ローカルJSON→Supabase。`SpellingSyncCore.Migration`活用）。

---

## 10. 旧設計書との関係
- `parent-web-cloud-design.md` は**スキーマ/RLS/ペアリングの詳細リファレンス**として活用（family=household 読み替え）。
- 相違点：親=**ネイティブiPhone**（Webではない）／**英検・SRS・検索練習テスト・親メニュー5分類**を新設／用語 family→household。
