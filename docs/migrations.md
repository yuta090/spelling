# DBマイグレーション運用（Supabase CLI 非依存）

専用スクリプト `scripts/db/migrate.sh`（`psql` のみで動作）で適用する。他プロジェクトへも
`ENV_FILE` / `MIGRATIONS_DIR` / `SUPABASE_DB_URL` の上書きで流用できる。

## コマンド
```bash
scripts/db/migrate.sh status     # 適用済み / 未適用の一覧
scripts/db/migrate.sh up         # 未適用を順にトランザクション適用し schema_migrations に記録（既定）
scripts/db/migrate.sh baseline   # 既存DBに合わせ「全ファイルを“流さず”適用済みとして記録」
```

## 接続（優先順位）
1. **`SUPABASE_DB_URL`**（推奨）… ダッシュボード右上 **Connect** → **Session pooler**（IPv4・確実）の文字列。
   - 例: `postgresql://postgres.<ref>:<DB_PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require`
   - パスワードに `% # @` 等があれば **URLエンコード**（`%`→`%25`, `#`→`%23`, `@`→`%40`）。
2. `SUPABASE_PROJECT_REF` + `SUPABASE_DB_PASSWORD` … direct（`db.<ref>.supabase.co:5432` / IPv6）を自動組み立て。
   - direct/IPv6 が `Connection refused` になる環境では 1 を使うこと。

## 仕組み・安全性
- `schema_migrations(version, checksum, applied_at)` で適用済みを追跡。再実行は**未適用分のみ**。
- 各マイグレーションは **BEGIN/COMMIT で原子的**（`ON_ERROR_STOP`。失敗で全ロールバック＝記録も残さない）。
- 適用済みファイルの**内容が変わると drift 警告**（チェックサム比較）。
- 追跡テーブルは RLS 有効（ポリシー無し）＝ API から読めない。
- 接続は `postgres`（所有者）で行うため RLS をバイパス（マイグレーションには適切）。

## よくある運用
- **SQL Editor 等で先に手動適用した場合** → `migrate.sh baseline` で記録を同期 → 以後は `up` で差分のみ。
- **新しいマイグレーション追加** → `supabase/migrations/<timestamp>_name.sql` を置いて `up`。
