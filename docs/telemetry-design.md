# SpellingTrainer ログ／テレメトリ 確定設計（v1 実装済み）

作成: 2026-06-29 / 種別: 設計＋v1実装記録 / 対象: 不具合発見・機能改善に効く計測
チーム: CTO/バックエンド視点・マーケッター/グロース視点・iOSテレメトリ視点 → codex(Architect) レビューで収束。

> 前提（揺るがない軸）
> - **児童向けアプリ**。個人を特定できる生データは送らない（COPPA / 改正個情法 / Apple Kids Category）。
> - **Supabase に負荷をかけない**（端末アウトボックス＋バッチ送信。1イベント=1リクエストにしない）。
> - **「数えると意思決定が変わるか？」**を満たさないイベントは入れない。

---

## 0. 結論（Bottom line）

- 「負荷をかけず・確実に」の答えは **端末アウトボックスに溜める → 折を見てバッチで write-only テーブルに INSERT** の一点。送信回数=flush 回数で、イベント数に比例させない。
- **v1 は「運用ログ＋低頻度セッション要約」だけ**。日次集計(系統B)・パーティション・Storage NDJSON・学習イベント生ログは **v2 以降**（今やると過剰）。
- `event_log` は **同期テーブルではなく送信専用テーブル**（pull しない・更新しない・tombstone しない・`sync_version` を持たない）。**クライアントからは読めない**（テーブル権限を一切与えない）。
- 送信は **SECURITY DEFINER RPC `log_events(jsonb)`**（バッチ・冪等 `ON CONFLICT DO NOTHING`）。
  - 直接 `upsert(ignoreDuplicates)` を使わない理由（実測で確認）: `ON CONFLICT DO NOTHING` は SELECT 権限を要求し、さらに RLS 下では「競合した既存行が SELECT で可視」でないと `new row violates RLS` を投げる。送信専用（SELECT ポリシ無し）と両立しないため、再送＝冪等が壊れる。RPC なら RLS をバイパスしつつ関数内 `has_access` で自世帯限定を担保でき、テーブルは読めないまま保てる。

---

## 1. 2系統の考え方（v1 はAのみ）

| | 系統A: 運用ログ＋要約（**v1**） | 系統B: 行動集計（v2+） |
|---|---|---|
| 目的 | 不具合発見・品質・低頻度マイルストーン | 継続率・NSM・単語別改善・長期分析 |
| 置き場所 | `event_log`（送信専用・append-only） | 端末日次集計→集計行 ／ 必要時のみ Storage NDJSON |
| 量 | 少（失敗時・1セッション1件） | 多（行動の生イベント） |
| いま作る | ✅ | ❌（過剰。やりたくなったら設計し直す） |

**線引き（codex）**: `event_log` = 障害・品質・低頻度マイルストーン・セッション要約。
`word_attempt_graded` のような **児童の学習履歴そのもの**は入れない（`attempts`/`reviews` から導出可・件数多・センシティブ）。

---

## 2. `event_log` スキーマ（v1・単一テーブル）

マイグレーション: `supabase/migrations/20260629000001_event_log_telemetry_4t7k.sql`

| 列 | 型 | 備考 |
|---|---|---|
| `event_id` | uuid PK | 端末生成。再送の冪等キー（`ON CONFLICT DO NOTHING`） |
| `household_id` | uuid not null | RLS 境界（`app.has_access`） |
| `profile_id` | uuid null | **既定 NULL**。行動分析目的で安易に付けない |
| `device_id` | uuid not null | 非秘密の端末識別子 |
| `occurred_at` | timestamptz | 端末でのイベント時刻（UTC） |
| `received_at` | timestamptz default now() | サーバ受信。クライアントは送らない |
| `severity` | smallint | 20 info / 30 warn / 40 error / 50 fatal（CHECK） |
| `category` | text | allowlist: sync/ocr/crash/telemetry/session（CHECK） |
| `code` | text | **allowlist の6コードのみ**（CHECK）。拡張はマイグレーション必須 |
| `app_version` / `os_version` | text | |
| `payload` | jsonb | 低カーディナリティ値のみ・**≤2KB**（CHECK） |

- 索引: `(household_id, occurred_at desc)` ＋ `severity>=40` の部分索引 `(code, occurred_at desc)`。
- **クライアントにテーブル権限を一切与えない**（`revoke all`）。SELECT/INSERT/UPDATE/DELETE すべて不可＝真の送信専用 append-only。
- 書き込みは **RPC `log_events(jsonb)` のみ**（`grant execute … to authenticated`）。RPC は SECURITY DEFINER で、関数内 `app.has_access(household_id, profile_id)` により**呼び出し元が自世帯にだけ**書けることを行ごとに検証（`auth.uid()` は定義者実行でも呼び出し元のまま）。
- 直接 INSERT 用 RLS ポリシ（`with check (app.has_access(...))`）も残す（多層防御。万一 grant が付いても他世帯には書けない）。
- パーティション無し・`sync_version`/`updated_at`/`deleted_at` 無し（送信専用のため）。

---

## 3. 端末側の仕組み（pure / I/O 分離）

純粋ロジックは `SpellingSyncCore`（`swift test` で検証）、I/O はアプリ薄層（`iPadPrototype/Telemetry.swift`）。

| 役割 | 置き場所 | 内容 |
|---|---|---|
| イベント定義・allowlist・バケット | `TelemetryEvent.swift` | `TelemetryCode`(6種)・`TelemetrySeverity`・`TelemetryValue`・`TelemetryBucket` |
| capped ring buffer | `EventOutbox.swift` | 上限500・drop-oldest（落とした件数を返す）・dedup(eventID)・FIFO・ack |
| 単調クロック | `TelemetryClock.swift` | 同時刻連投でも `occurredAt` を厳密単調増加（取りこぼし防止） |
| 行変換・検証 | `TelemetryWire.swift` | event→DB行。allowlist/payload≤2KB を満たさない行は弾く |
| 送信・永続化・MetricKit | `Telemetry.swift`(app) | `TelemetryUploader`(RPC `log_events`) ＋ `TelemetryCoordinator` |

**フラッシュ契機**: scenePhase が前面を離れた時（`SpellingTrainerApp` の `.onChange(scenePhase)` else 枝）。
**世帯未確定（未ペアリング/サインアウト中）は記録自体しない**（送信不能な event をキューに溜めて先頭で詰まらせない。codex 指摘 #1）。送信失敗は溜めたまま次回再送（テレメトリ送信失敗で別テレメトリを出してループにしない）。容量超過で落とした件数は永続カウンタに積み、空きができた時に `telemetry.dropped` 1 件へ集約（codex 指摘 #2）。

---

## 4. v1 で送るイベント（allowlist・これだけ）

| code | severity | 配線箇所（実装済み） |
|---|---|---|
| `sync.push_failed` | warn | `AppModel.syncNow` の catch |
| `sync.pull_failed` | warn | （allowlist 済み。pull を分離した時に配線） |
| `ocr.failed` | warn | `ParentDashboardView` の単語スキャン取り込み失敗 3 箇所 |
| `crash.mx_diagnostic` | fatal | MetricKit `didReceive(_:[MXDiagnosticPayload])`（クラッシュ件数のみ） |
| `telemetry.dropped` | info | outbox が容量超過で落とした件数を次 flush で 1 件に集約 |
| `session.practice_summary` | info | `AppModel.recordSpellingTestResults`（1セッション1件） |

`session.practice_summary` の payload: `result=completed` / `word_count_bucket` / `correct_count_bucket`（すべてバケット）。
**単語・氏名・手書き・自由入力・正確な年齢・生の数値や時刻は送らない。**

---

## 5. プライバシー方針（児童最優先）

1. `profile_id` は **既定 NULL**（障害切り分けに要る時だけ）。
2. payload は **低カーディナリティ**（`_bucket`・フラグ・列挙）。生値・自由テキスト・時刻は送らない。
3. 送らない: 氏名・なかま名・例文に入れた名前（件数のみ）／手書き答案の画像・ストローク／生年月日（帯のみ）／位置情報・連絡先・広告ID／端末跨ぎの永続追跡ID。
4. 子データは集計優先・短期保持。子の画面に計測UIは出さない。
5. 外部解析SDKを入れない方針は妥当（Apple Kids Category・第三者トラッキング規制）。

---

## 6. マーケ視点（v2 で測りたいこと・今は作らない）

> 系統B（行動集計）として、`attempts`/`reviews` ＋ セッション要約から **サーバ集計** で算出する。生イベントは送らない。

- **North Star**: 「週に3日以上、単語練習を完了した子の数」（習慣化＝コア価値）。
- ファネル: アクティベーション（初起動→初練習完了→親ペアリング）／親オンボーディング（ペアリング→初採点→初レポート閲覧）／D1/D7/D30 リテンション。
- 機能採用は「露出→試用→定着→習熟寄与」をコホート比較（専用フラグを増やさず既存信号の組合せで）。
- 習熟・難易度の質（単語別誤答率・沼単語・離脱誘発単語・レベル帯別の壁・OCR起因の誤判定切り分け）は v2 の主役だが、**`word_attempt_graded` の生送信ではなくサーバ集計**で実現する。

---

## 7. v2 以降のバックログ（やらないことの記録）

- 端末日次集計（系統B）＋ 集計テーブル。
- パーティション＋定期 DROP（量が増えたら）。生ログ化するなら同時に。
- `word_attempt_graded` 等の学習イベント（必要になってもまず集計で、生送信は最後の手段）。
- Storage への NDJSON 退避。
- `sync.pull_failed` の個別配線（pull/push を分離した時）。
- セッション `abandoned`（中断）の記録（scenePhase 背面化×セッション中で。今は completed のみ）。

---

## 8. 検証（v1）

- `swift test`（SpellingSyncCore）: `TelemetryTests` 20件 GREEN（コード/カテゴリ/severity・バケット・Codable・outbox drop/dedup/ack・単調クロック・wire 検証/サイズ上限/snake_case）。
- `scripts/db/test.sh`（SQL/RLS）: `event_log_test.sql` で 親INSERT可・子端末INSERT可・他人INSERT不可(RLS)・SELECT/UPDATE/DELETE 不可(append-only)・CHECK(category/code allowlist・severity・payload上限) を検証。既存 pairing/entitlements と合わせ **ALL TESTS PASSED**。
- `xcodebuild … build`: **BUILD SUCCEEDED**。

## 9. 主要リスク（codex）

- 最大: 「解析したくなって `profile_id` 付き生イベントを増やす」→ allowlist・送信専用経路・短期保持・要約で歯止め。
- 次点: 冪等送信と RLS の不整合（`ON CONFLICT DO NOTHING` が既存行の SELECT 可視を要求）→ SECURITY DEFINER RPC `log_events` で回避済み（テーブルは読めないまま）。

## 10. codex レビュー反映（v1）

codex(Code Reviewer) の指摘で次を修正済み:
1. 未ペアリング(household nil)の event をキューに溜めて先頭で詰まらせる不具合 → 記録時に弾く＋wire でも nil household を拒否。
2. `telemetry.dropped` 自己報告のループ＆カウンタ非永続 → 送信成功で空きができた後にのみ1件集約・カウンタを永続化。
3. 冪等送信パスの是正 → `upsert(ignoreDuplicates)` は RLS と両立しないため RPC へ（上記 §9）。SQL テストに冪等・write-only・CHECK を追加。
