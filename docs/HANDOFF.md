# 引き継ぎ（最新・新セッション用）

最終更新: 2026-06-26 / main: 全マージ済み（PR #13–#19）

## いまの状態
- **Supabaseバックエンド完成・検証済み**：スキーマ＋RLS（migrations 0001–0006）を本番DBに適用。
  世帯(household)隔離・ペアリング・LWWガード・`sync_version`（同期カーソル）・RLSハードニング済み。
- **iOSアプリ**：supabase-swift 統合済（ビルド成功）。
  - `SupabaseService`（認証：親メールOTP送信+検証／子匿名、`create_household` RPC、`profileCount`）
  - `SyncEngine`（pull：`sync_version`カーソル差分／push：upsert＋サーバーLWWガード）
  - `SyncDTO`（Profile/Word の DTO＋Upsertペイロード）
- **SpellingSyncCore（SwiftPM・TDD・53テスト/100%）**：`SyncMetadata`(tombstone)・`LastWriteWins`・
  `ReviewProgress`・`Migration`・`SRSScheduler`・`OutboundSync`・`DeterministicID`(UUIDv5)。

## 環境
- リポジトリ: `/Users/takahashiyuuta/scripts/ipad-spelling-ocr-lab`
- Supabase: ref `iygptyalwmfwtproixfr` / region `ap-northeast-1`
- `.env.local`（gitignore）：**pooler接続必須**（direct/IPv6はNG）。
  `SUPABASE_DB_URL=postgresql://postgres.iygptyalwmfwtproixfr:<PW>@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres`
- マイグレーション: `scripts/db/migrate.sh status|up|baseline`（CLI不要）

## 次にやること（#2：ローカルキャッシュ統合）
**pull→merge→push を `AppModel` に結線する**のが本丸。
1. 親サインイン＋世帯作成の**デバッグ導線**（最小UI）を作り、#3 の疎通を叩けるようにする。
2. `AppModel` のローカルデータ ⇄ DTO ⇄ `SyncableRecord` のマッピング。
3. pull(`SyncEngine.pullAll`) → `LastWriteWins.reconcile` でローカルとマージ → `OutboundSync.pending` で
   未送信を選び push。カーソル/high-water を永続化。
4. `srs_cards`等の論理一意行は **`DeterministicID.uuidV5`** で採番してから push 対象に追加。
- 設計の詳細: `docs/supabase-adapter-design.md`

## あなたの事前作業（#3 疎通の前提）
- Supabase ダッシュボード → Authentication → Email テンプレートに **`{{ .Token }}`（6桁コード）** を含める
  （OTPコード方式でサインインを完結させるため）。

## 開発ルール（CLAUDE.md・必読）
- **TDDで開発**（純粋ロジックは `SpellingSyncCore`＝`swift test`、アプリI/Oは薄く）。
- **`main`に直接コミットしない**。必ずブランチを切る。**実装後はCodex Code Reviewerでレビュー**してからマージ。
- 指示外ファイルを触らない。

## 参照
- 全体決定/経緯: `docs/multi-user-and-strategy-decisions.md`
- スキーマ設計: `docs/supabase-sync-design.md` / アダプタ設計: `docs/supabase-adapter-design.md`
- 接続/移行: `docs/supabase-setup.md` / `docs/migrations.md`
- 旧詳細引き継ぎ: `docs/HANDOFF-2026-06-26.md`
