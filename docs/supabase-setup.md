# Supabase 接続セットアップ手順

Status: 手順（あなたが値を記入）
Date: 2026-06-26
関連: `.env.local`（記入先・コミットされない）／`.env.local.example`（雛形）

---

## 0. いま記入してほしいもの（フェーズ1だけでOK）
`.env.local` の以下5つ。**まずは接続できれば十分**です。

| 変数 | 種別 | どこで取る |
|---|---|---|
| `SUPABASE_URL` | 公開可 | ダッシュボード → **Project Settings → API → Project URL** |
| `SUPABASE_ANON_KEY` | 公開可 | 同上 → **Project API keys → `anon` `public`** |
| `SUPABASE_PROJECT_REF` | 公開可 | URLのサブドメイン（例 `https://abcd.supabase.co` の `abcd`）。または Settings → General |
| `SUPABASE_SERVICE_ROLE_KEY` | **秘密** | 同 API画面 → **`service_role`**（“Reveal”） |
| `SUPABASE_DB_PASSWORD` | **秘密** | プロジェクト作成時に設定したDBパスワード（忘れたら Settings → Database → Reset） |

> 記入したら「入れた」と教えてください。こちらで接続確認（CLIリンク／簡単なクエリ）まで進めます。

---

## 1. 「公開可」と「秘密」の違い（重要）
- **`anon` key と URL は公開して安全**。アプリ（iOS）に埋め込んでよい。データの保護は **RLS（Row Level Security）** で行う（世帯ごとに行を隔離）。
- **`service_role` と DBパスワードは全権限の鍵**。**アプリには絶対に入れない**。サーバー／Supabase Edge Function／管理スクリプト／マイグレーションでのみ使う。
- `.env.local` と `*.p8` は `.gitignore` 済み。**実値をコミットしない**（GitHubに出たら即ローテーション）。

---

## 2. iOS アプリへの渡し方（後でこちらが実装）
iOSアプリ自体は `.env.local` を直接読みません。`.env.local` は「**唯一の真実**」として、
- **アプリ向け（公開可の `SUPABASE_URL` / `SUPABASE_ANON_KEY`）** は、ビルド設定（xcconfig）または生成した Swift 設定に流し込む（こちらでビルド手順を用意）。
- **秘密鍵（service_role / R2 / APNs / App Store）** は Edge Function や CLI 側の環境変数として使い、**アプリには出しません**。

---

## 3. このあとの流れ（こちらで進めます）
1. スキーマ設計の現行版化（英検セット・SRS・採点・親メニュー反映）→ `docs/` 。
2. Supabase マイグレーション（テーブル＋**RLS**）作成。`SUPABASE_DB_PASSWORD`/`PROJECT_REF` を使用。
3. `UserDataStore` の **Supabase アダプタ**実装（既存の同期コアを活用）。
4. 手書き保存（まず Supabase Storage、のちに R2）／確実通知／StoreKit課金。

---

## 4. 任意：Supabase CLI（マイグレーション用）
ローカルでマイグレーションを回すなら CLI が便利です（後で使います）。
```bash
brew install supabase/tap/supabase     # 未導入なら
supabase login                          # アクセストークンでログイン
supabase link --project-ref "$SUPABASE_PROJECT_REF"
```
※ これらは**あなたの操作（ログイン）**が要るので、必要になったらご案内します。
