# 残作業ハンドオフ — 本筋B（リモート採点の同期）＋ Apple登録後タスク

最終更新: 2026-06-28
対象: 次セッション（別セッション）でそのまま着手するための引き継ぎ1枚。

> 前提イベント: **Apple Developer 登録が 2026-06-28 に完了予定**。これにより「Apple待ち」だったタスクが解禁される。

---

## 0. いま何が終わっているか（着手前に把握）

### 本筋B = リモート採点の同期（親が別端末で採点）— **純粋ロジック層は完成**
`SpellingSyncCore`（SwiftPM・`swift test`）に、pull→merge→push の判断ロジックを全てテスト付きで実装済み。PR #62 / #63 / #64（すべて main マージ済み、各 codex APPROVE、CI 緑、テスト +48）。

| ファイル | 役割 |
|---|---|
| `ReviewSync.swift` | `ReviewRecord`/`ReviewPayload`/`ReviewDecision`/`ReviewIdentity`。review の決定的ID。 |
| `ReviewWire.swift` | `ReviewRow` ⇄ `ReviewRecord`（壊れ行ドロップ・削除復活防止・id整合検証）。 |
| `ReviewSidecar.swift` | `LocalReview`＋`ReviewSidecarStore`（採点し直し=dirty／採点取消=tombstone／クロックbump／世帯スコープ）。 |
| `ReviewSyncReducer.swift` | reviews の pull→merge→push 計画（echo抑制＋high-water）。 |
| `AttemptSync.swift` | `AttemptSyncPayload`/`AttemptSyncRecord`（append-only）。 |
| `AttemptWire.swift` | `AttemptRow` ⇄ `AttemptSyncRecord`。 |
| `AttemptSyncReducer.swift` | attempts の push 計画（サーバ未保持分のみ・サイドカー無し）。 |
| `RFC3339.swift` | 日付の共有ヘルパ。 |

汎用基盤（再利用済み・触る必要なし）: `SyncMetadata`/`SyncableRecord`/`LastWriteWins`/`SyncScope`/`OutboundSync`/`SyncCursors`/`DeterministicID`。

### 既存（参考）
- Phase1（課金・ペイウォール・10語/日・StoreKit2・E2E・CI）= 実装済み。
- words の同期は `WordSync`/`WordWire`/`WordSyncReducer`/`WordSyncRunner`/`WordSyncPorts` が**配線まで含めて存在**。本筋Bの配線はこれを「お手本」にできる。
- AI-OCRベンチ「暫定A」（端末ローカル書き出し＋`scripts/ocr-bench/bench.py`）= 実装済み。実データ計測待ち。

---

## 1. 残作業（依存関係つき）

### A. 本筋B アプリ配線（純粋ロジックの上に I/O を載せる）— **Apple登録とは独立だが共有ファイルに触る**
words の `WordSyncRunner`/`WordSyncPorts`/`WordSyncCoordinator`（アプリ側薄I/O）と同じ構成を reviews/attempts にも作る。

1. **DTO 層**: PostgREST の行 ⇄ `ReviewRow`/`AttemptRow` の写し替え（`ReviewDTO`/`AttemptDTO`）。判断ロジックは既にコアにあるので**単純な写し替えのみ**。
2. **Ports/Runner/Coordinator**: pull（`sync_version` カーソル）→ `ReviewSyncReducer.plan`/`AttemptSyncReducer.plan` → push（upsert）→ サイドカー/カーソル永続化（UserDefaults）。`SyncCursors` を流用。
3. **AppModel 反映**: `LastWriteWins.live(merged)` を UI に反映。採点 UI（親ゲート）の状態を `LocalReview` に射影。
   - ⚠️ **`AppModel.swift` 等の共有ファイルに触れる**。複数エージェントが同じファイルを触ると衝突するので、**並行作業が落ち着いたタイミングで**、範囲を絞って着手すること。
4. **手書き画像**: attempt の `drawing_path` と review の `parent_example_path` は Storage/R2 キー。アップロード/署名URL取得は Edge Function（下の D）経由。

### B. ペアリング（子iPad ⇄ 親）— **サーバ＋クライアントAPI 完成（RPC方式）。残りは UI＋実環境設定**
> **方式の決定（2026-06-28・codex Architect 助言）**: 当初「Edge Function」予定だったが **SECURITY DEFINER の SQL RPC** に変更。
> 理由: 消費を `auth.uid()` に束縛でき（呼び出し元IDを Postgres/GoTrue が暗号検証）、Edge+service_role より攻撃面が小さい。
> 単回消費の原子性も1トランザクションのCTEで堅く、既存 `create_household()` RPC と一貫。将来の Edge（App Store通知/APNs/署名URL）はこの RPC を呼べばよい。

**完了（PR: 本ブランチ）**:
- migration `supabase/migrations/20260628000001_pairing_rpc_7k3m.sql`:
  - `public.create_pairing_code(household_id, profile_id?, ttl=900)` … 親が6桁コード発行（HMAC-SHA256+pepper 保存・15分・単回）。
  - `public.consume_pairing_code(code, device_public_id?)` … 子iPad(匿名)が消費 → `devices` 登録。返り status: `ok`/`invalid_or_expired`/`rate_limited`/`already_paired`。
  - 総当たり対策 `pairing_consume_limits`（匿名uid単位・15分10回・超過30分ロック）。
  - 既存潜在バグ修正: `pairing_codes` から `trg_aa_lww_guard` を除去（updated_at 列が無く消費の更新で落ちていた）。
- SQLテスト土台 `supabase/tests/`＋`scripts/db/test.sh`（Docker不要・素のpostgresで auth スタブ→migrations→assert）。**CI に `sql-tests` ジョブ追加**。
- iOS クライアントAPI: `SupabaseService.issuePairingCode` / `consumePairingCode`（薄いRPCラッパ）。

**残（このあと・実環境/Apple登録が要る）**:
1. **pepper を本番DBに設定**（必須・未設定だと発行/消費が fail-closed）:
   `ALTER DATABASE postgres SET app.pairing_pepper = '<32文字以上のランダム秘密>';`（ダッシュボードSQLで1回）。
2. **Supabase で匿名サインインを有効化**（Auth Providers → Anonymous）。`signInChildAnonymouslyIfNeeded()` の前提。
3. **UI**: 親「iPadをつなぐ」（コード/QR表示）／子「保護者とつなぐ」（コード入力→consume）。← アプリ共有ファイルに触るので A と同様 並行作業の谷間で。
4. **`app.cleanup_pairing()` の定期実行**を設定（pg_cron か scheduled Edge。期限切れコード/古い制限行/分バケットを掃除）。

**セキュリティ申し送り（Security Analyst レビュー・別タスク推奨）**:
- **device 失効の `deleted_at` 漏れ（既存migration 0004）**: `app.device_can_access`/`app.device_in_household` は `revoked_at` のみ確認し `deleted_at` を見ない。**失効を論理削除で実装する前に**両ヘルパに `d.deleted_at is null` を足すこと（今回は範囲外なので未修正）。
- 監査ログ（コード発行/消費成功/レート制限/失効）は将来追加（親サポート・インシデント対応用）。
- ペアリングイベントの本ブランチでの総当たり対策: 6桁・HMAC+pepper・匿名uid単位(15分10回/30分ロック)＋**グローバル60回/分**でクランプ。Security Analyst 評価＝対策後 MEDIUM/LOW（低トラフィックの家庭向けとして妥当）。
- 詳細: `docs/parent-web-cloud-design.md §4`、`docs/supabase-sync-design.md §2`。

### C. サーバ権利ミラー（課金を世帯共有に）— **Apple非依存の核 完成。Apple配線は登録待ち**
- **支払いは iPad のアプリ内 StoreKit（Apple IAP 必須）**。買った Apple ID にローカルで紐づく。
- 別の親のiPhone・親Web でも「課金済み」を知るには、iPadが購入→検証→世帯スコープで `entitlements` に記録 → 全端末が RLS `app.has_access()` で閲覧・サーバ機能解放。

**完了（PR: feat/entitlements-mirror-core-20260628-e8m2）— Apple非依存・SQLテスト付き**:
- migration `supabase/migrations/20260628000002_entitlements_mirror_e8m2.sql`:
  - `app.upsert_entitlement(household_id, product_id, status, expires_at, original_transaction_id, environment, event_at)` … **service_role(Edge)専用**の冪等upsert。
    - **単調ガード**: `event_at <= last_event_at` は replay として無視（逆順/重複通知で active→expired のダウングレードを防ぐ）。`last_event_at` 列を追加。
    - **なりすまし防止**: 確定済み `original_transaction_id` と食い違う更新は拒否。
    - unique_violation 競合は retry、lww_guard tie は newer timestamp で回避。
  - `app.household_has_active_entitlement(household_id)` … サーバ機能のゲート（trial/active/grace かつ未失効）。caller は service_role か世帯メンバー/端末のみ。
  - SQLテスト `supabase/tests/entitlements_test.sql`（PASS 0-15）。
- **どの取り込み経路でも最終的にこの upsert を呼ぶ**設計（下記2経路）。

**残（Apple登録 → App Store Connect 設定が前提）**:
1. **App Store Connect 設定**（※現状 Apple Developer 未登録 → まずここ）: サブスク商品(family.monthly/yearly)・Introductory Offer・**App Store Server API キー**(issuer/keyId/.p8)・**Server Notifications V2 の通知先URL**。
2. **取り込み Edge Function** `appstore-notify` — **先回り実装済み（PR: feat/appstore-notify-edge-20260628-n3p7）**:
   - `supabase/functions/appstore-notify/`：`assn.ts`（decode＋notificationType→status マッピング・**Denoテスト14件**）／`verify.ts`（JWS署名検証 ES256＋x5cチェーン→Apple Root CA G3）／`index.ts`（受信→検証→マッピング→`public.upsert_entitlement` を service_role で呼ぶ）。
   - public ラッパ migration `20260628000003_entitlements_public_rpc_n3p7.sql`（app スキーマは PostgREST 非公開のため public.upsert_entitlement / household_has_active_entitlement を追加）。
   - **登録後に必要な“鍵差し込み＋設定”だけ**: ① Edge secrets `APPLE_ROOT_CA_G3_PEM`(apple.com/certificateauthority)・`APPLE_BUNDLE_ID`・`SUPABASE_URL`・`SUPABASE_SERVICE_ROLE_KEY` ② ASC の Server Notifications V2 通知先に `…/functions/v1/appstore-notify` ③ **Sandbox 実通知で verify.ts を end-to-end 検証**（署名検証は実証明書/実payload 必須のため未検証）。
   - 任意 `entitlements-sync`: 購入直後に iPad が StoreKit2 の signedTransaction を渡し、Edge が App Store Server API で検証 → 同 upsert（即時反映）。同じ assn.ts/upsert を再利用。
3. **取引→世帯の束縛**: 購入時に StoreKit2 `Purchase.Option.appAccountToken(=household_id)` を付与 → ASSN/トランザクションの `appAccountToken` で世帯解決。**購入前に世帯が存在している必要**（親サインイン/ペアリング後に課金導線）。
4. **クライアント反映**: アプリは `entitlements`（RLSで閲覧可）を読んで `AppModel.applyEntitlement` 済みのプレミアム解放に反映（Phase1ローカルStoreKitに加えサーバ権利でも解放）。
- 任意: App Store Connect で **ファミリー共有 ON** にすれば同一Appleファミリー内は StoreKit だけで共有可（サーバ不要）。別Apple IDの2親はこのミラーで解決。ON/OFF は登録後に決める。

### D. その他 Edge Function / 通知 — **Apple登録で解禁**
- `review-notify`: セッション完了で `review_requests` 作成 → 親へ通知。
- 親通知（APNs）: ユーザー要望あり。**APNs キー発行＝Apple登録が前提**だった。登録後に着手可。
- `storage-sign`: 手書き画像の署名URL発行。

### E. AI-OCRベンチ 実データ計測 — **Apple非依存・ユーザー操作待ち**
DEBUGアプリで採点→親ゲート「ベンチ用に書き出す」→ zip → `scripts/ocr-bench/` に展開＋`OPENROUTER_API_KEY` → `python3 bench.py`。nano/Flash-Lite が採点＋コメントを兼ねられるか判定。詳細: `docs/HANDOFF-ai-ocr-2026-06-27.md`。

---

## 2. 必ず守る契約（バグ源・落とし穴）

1. **review の決定的ID**: `reviews.id = uuidv5(namespace, attempt_id)`。
   - namespace = `8F2B0E14-1C3A-4D5E-9A6B-7C8D9E0F1A2B`（`ReviewIdentity.namespace`）。
   - name は **attempt_id の小文字・ハイフン区切り正準形**。Swift `UUID.uuidString` は大文字、Postgres `uuid::text` は小文字なので、**サーバ Edge Function 側でも必ず小文字 attempt_id ＋ 同じ namespace で uuidv5** を計算すること。食い違うと別IDになり `unique(attempt_id)` を活かせない。
   - `DeterministicID.uuidV5` は RFC4122 互換（Python `uuid.uuid5` と一致をテスト済み）＝Postgres `uuid_generate_v5` とも一致する。
2. **high-water 前進の契約**（`OutboundSync`）: push high-water は **対象テーブルの pending 全件を push 成功してから** 進める。部分送信途中で進めると同時刻の未送信行が strict `>` で恒久除外される。
3. **壊れ行は取り込まない**: `*Wire.record(from:)` は `updatedAt`/`deletedAt` 解釈不能・未知 decision の行を**行ごと落とす**（削除復活防止）。サーバから来る行が常に正しい形であることを担保すること。
4. **attempts は append-only**: 内容不変・ローカル削除しない前提。もしユーザー削除可能にするなら `AttemptSyncReducer` に tombstone 意味論を足す必要あり。
5. **支払いの所在**: iPad アプリ内（StoreKit）のみ。親Webでは課金しない（C のミラーで状態だけ共有）。

---

## 3. 着手順の推奨

1. **登録完了を確認** → B/C/D の Apple前提が解ける。
2. まず **C（権利ミラー）or B（ペアリング）** のどちらか、ユーザーが価値を感じる方から。※同期を無料で出す方針なら B が先（[[monetization-feature-direction]] 参照）。
3. **A（本筋B 配線）** は `AppModel` 共有ファイルに触るので、**並行作業の谷間**で範囲を絞って。words の Runner/Ports を雛形に。
4. E（OCR計測）はユーザーが zip を出したタイミングで随時。

---

## 4. 参照ドキュメント
- `docs/remote-grading-spec.md` — リモート採点の BUILT/PLANNED。
- `docs/supabase-sync-design.md` / `docs/parent-web-cloud-design.md` — スキーマ/RLS/ペアリング/同期の詳細。
- `docs/supabase-adapter-design.md §7.5` — wire/サイドカー/カーソルの設計。
- `docs/HANDOFF-ai-ocr-2026-06-27.md` — OCRベンチ。
- `docs/apple-developer-enrollment-guide.html` — 登録手順（完了予定）。
