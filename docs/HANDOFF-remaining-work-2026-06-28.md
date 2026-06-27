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

### B. ペアリング（子iPad ⇄ 親）の Edge Function — **Apple登録で解禁（匿名auth等の実環境が要る）**
スキーマ（`households`/`devices`/`pairing_codes`）と RLS は migration 済み。**処理本体（Edge Function）と UI が未実装**。
- `pairing-issue`: 親が6桁コード/QR発行（`code_hash` 保存・15分・単回）。
- `pairing-consume`: 子iPadが匿名authでコード消費 → `devices` 登録 → 初回同期。
- UI: 親「iPadをつなぐ」／子「保護者とつなぐ」。
- 詳細: `docs/parent-web-cloud-design.md §4`、`docs/supabase-sync-design.md §2`。

### C. サーバ権利ミラー（課金を世帯共有に）— **Apple登録で解禁（本物のレシート/環境が要る）**
- **支払いは iPad のアプリ内 StoreKit（Apple IAP 必須）**。買った Apple ID にローカルで紐づく。
- 別の親のiPhone・親Web でも「課金済み」を知るには、iPadが購入→レシート検証→`entitlements-sync`(Edge Function)で **`entitlements` テーブルに世帯=課金中** を記録 → 全端末が RLS `app.has_access()` で解放。
- 任意: App Store Connect で **ファミリー共有 ON** にすれば同一Appleファミリー内は StoreKit だけで共有可（サーバ不要）。ON/OFF は登録後に決める。

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
