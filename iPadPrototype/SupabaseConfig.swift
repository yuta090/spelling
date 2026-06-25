import Foundation

/// Supabase の接続設定。
///
/// ⚠️ ここに置いてよいのは **公開可** の値だけ（`URL` と `anon` キー）。
/// anon キーは RLS で保護される前提でクライアントに埋め込んでよい公開値。
/// `service_role` キーや DB パスワードは **絶対にここに置かない**（Edge Function / サーバー専用）。
///
/// 設計: docs/supabase-sync-design.md / 接続情報: docs/supabase-setup.md
enum SupabaseConfig {
    static let url = URL(string: "https://iygptyalwmfwtproixfr.supabase.co")!

    /// public anon key（公開可・RLSで保護）。
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml5Z3B0eWFsd21md3Rwcm9peGZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MDU3NDgsImV4cCI6MjA5Nzk4MTc0OH0." +
        "8vt82xc-YwLxWqmI5NG9t1GSSYIPdwr9ttBBbntyIOs"
}
