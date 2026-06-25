import Foundation
import Supabase

/// Supabase クライアントの薄いラッパー。
///
/// 認証（親=メールOTP、子=匿名）と、世帯作成RPCなどの最小操作を提供する。
/// 同期本体（プル/プッシュ）は今後 SyncEngine として段階的に追加する（docs/supabase-adapter-design.md）。
///
/// ⚠️ サインイン完了の前提（どちらか）:
///  - **OTPコード方式**: `sendParentSignInEmail` → 届いた6桁コードを `verifyParentOTP` で検証。
///    Supabase の Auth メールテンプレートに `{{ .Token }}`（コード）を含める設定が必要。
///  - **マジックリンク方式**: アプリのURLスキーム登録＋`client.auth.session(from:)`等でコールバックURLを処理する実装が別途必要（未実装）。
/// 現状は **OTPコード方式**を前提に実装している。
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    // MARK: - 認証

    /// 親：メールにサインイン用メール（OTPコード/リンク）を送る。
    func sendParentSignInEmail(email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    /// 親：メールで届いた6桁コードを検証してサインインを完了する。
    func verifyParentOTP(email: String, token: String) async throws {
        _ = try await client.auth.verifyOTP(email: email, token: token, type: .email)
    }

    /// 子端末：匿名サインイン（後でペアリングして世帯に紐づける）。
    /// 既にサインイン済みなら新しい匿名ユーザーを作らない（冪等）。
    func signInChildAnonymouslyIfNeeded() async throws {
        if client.auth.currentUser != nil { return }
        try await client.auth.signInAnonymously()
    }

    /// サインアウト。
    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// 表示用の現在ユーザーID（キャッシュ値。認可判定には使わずサーバー/RLSのエラーで判断する）。
    var displayUserID: UUID? {
        client.auth.currentUser?.id
    }

    // MARK: - 世帯

    /// 親が世帯を作成しオーナーになる（SECURITY DEFINER RPC。匿名ユーザーはサーバー側で拒否）。
    /// - Returns: 作成された household の id
    @discardableResult
    func createHousehold(title: String) async throws -> UUID {
        try await client
            .rpc("create_household", params: ["p_title": title])
            .execute()
            .value
    }

    // MARK: - 疎通確認（開発用）

    /// プロファイル件数（HEAD + count で本体を取得しない）。接続/RLSの動作確認に使う。
    func profileCount() async throws -> Int {
        let response = try await client
            .from("profiles")
            .select(head: true, count: .exact)
            .execute()
        return response.count ?? 0
    }
}
