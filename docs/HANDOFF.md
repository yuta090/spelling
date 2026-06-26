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

## 完了（#2 の一部）: 親サインイン/世帯作成のデバッグ導線
- `iPadPrototype/SyncSession.swift`：認証＋**active household_id の端末永続化**（push スコープの前提）。
- `iPadPrototype/SyncDebugView.swift`：メールOTPサインイン→世帯作成→profiles件数の疎通UI。
  `SpellingTrainerApp` に **DEBUG限定**の起動ボタン（左下のアンテナ）を overlay。製品UIには出ない。
- `SupabaseService` に `displayIsAnonymous` / `ownedHouseholds()` を追加。
- ビルド成功（iPad sim）／`swift test` 53件グリーン。

## 次にやること（#2 本丸：サイドカー同期ストア）
**方針は決定済み＝「サイドカー同期ストア」**（UIモデル `SpellingWord` は触らず、id→SyncMetadata を別ストアで
保持し DTO⇄`SyncableRecord` に射影。まず `words` だけ疎通。詳細と理由は `docs/supabase-adapter-design.md` §7.5）。
1. サイドカーストア（id→SyncMetadata: updatedAt/deletedAt/household/profile）を実装し、`SpellingWord` と射影する。
2. pull(`SyncEngine.pullAll`) → `LastWriteWins.reconcile` でマージ → `OutboundSync.pending` で未送信を push。
   カーソル(`sync_version`)/high-water を永続化（`SyncSession` の active household をスコープに）。
3. `stepID(String) → step_id(UUID)` は当面**別管理のマップ**。論理一意行は `DeterministicID.uuidV5` で採番。
- 純粋ロジックは `SpellingSyncCore` に足して **TDD**（射影・dirty抽出・カーソル前進）。

## あなたの事前作業（OTP疎通テストの前提）
- Supabase ダッシュボード → Authentication → Email テンプレートに **`{{ .Token }}`（6桁コード）** を含める。
- 実機/シミュレータでアプリを起動 → **左下のアンテナボタン**（DEBUGビルドのみ）→ メール入力→コード送信→
  6桁コードで検証→「世帯を作成」→「profiles件数を取得」で疎通確認。

## 開発ルール（CLAUDE.md・必読）
- **TDDで開発**（純粋ロジックは `SpellingSyncCore`＝`swift test`、アプリI/Oは薄く）。
- **`main`に直接コミットしない**。必ずブランチを切る。**実装後はCodex Code Reviewerでレビュー**してからマージ。
- 指示外ファイルを触らない。

## 参照
- 全体決定/経緯: `docs/multi-user-and-strategy-decisions.md`
- スキーマ設計: `docs/supabase-sync-design.md` / アダプタ設計: `docs/supabase-adapter-design.md`
- 接続/移行: `docs/supabase-setup.md` / `docs/migrations.md`
- 旧詳細引き継ぎ: `docs/HANDOFF-2026-06-26.md`
