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
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                // supabase-swift の次メジャーで既定になる新挙動に今から合わせる
                // （ローカル保存セッションを初期セッションとして常に emit する）。
                // 認証判定は currentUser を読む実装なので挙動差は実質無く、起動時の警告も消える。
                // 参考: https://github.com/supabase/supabase-swift/pull/822
                auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
            )
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

    /// 表示用：現在のユーザーが匿名（子端末）か（キャッシュ値）。
    var displayIsAnonymous: Bool {
        client.auth.currentUser?.isAnonymous ?? false
    }

    // MARK: - 世帯

    /// `household_members` の自分の行。
    struct HouseholdMembership: Decodable, Sendable {
        let householdId: UUID
        let role: String

        enum CodingKeys: String, CodingKey {
            case householdId = "household_id"
            case role
        }
    }

    /// 現在ユーザー自身の世帯メンバーシップ一覧。
    ///
    /// ⚠️ RLS の `members_access` は「同じ世帯のメンバーなら全員の行を読める」ポリシーなので、
    /// **自分の行に限定するには明示的に `user_id` で絞る必要がある**（RLS任せにすると他の親の行も返る）。
    /// 併せて論理削除済み行を除外する。未サインイン時は空配列。
    func myHouseholdMemberships() async throws -> [HouseholdMembership] {
        guard let userID = client.auth.currentUser?.id else { return [] }
        return try await client
            .from("household_members")
            .select("household_id, role")
            .eq("user_id", value: userID.uuidString)
            .is("deleted_at", value: nil)
            .execute()
            .value
    }

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

    // MARK: - ペアリング（子iPad ⇄ 親世帯）

    enum PairingError: Error { case noResult }

    /// 発行された6桁コード（平文はこの1回だけ受け取れる）。
    struct PairingCode: Decodable, Sendable {
        let code: String
        /// RFC3339 文字列（表示用。必要なら呼び出し側で解釈）。
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case code
            case expiresAt = "expires_at"
        }
    }

    /// 親：子iPadをつなぐための6桁コードを発行する（15分・単回）。
    /// サーバ側 `create_pairing_code` RPC（SECURITY DEFINER）が世帯メンバーであることを検証する。
    /// - Parameters:
    ///   - householdID: 対象世帯
    ///   - profileID: 紐づける子プロファイル（任意。省略時は世帯のみにスコープ）
    func issuePairingCode(householdID: UUID, profileID: UUID? = nil) async throws -> PairingCode {
        struct Params: Encodable {
            let p_household_id: String
            let p_profile_id: String?
        }
        let rows: [PairingCode] = try await client
            .rpc("create_pairing_code", params: Params(
                p_household_id: householdID.uuidString,
                p_profile_id: profileID?.uuidString))
            .execute()
            .value
        guard let first = rows.first else { throw PairingError.noResult }
        return first
    }

    /// 消費結果のステータス（サーバ `consume_pairing_code` の status 列）。
    enum PairingConsumeStatus: String, Decodable, Sendable {
        case ok
        case invalidOrExpired = "invalid_or_expired"
        case rateLimited = "rate_limited"
        case alreadyPaired = "already_paired"
    }

    struct PairingConsumeResult: Sendable {
        let status: PairingConsumeStatus
        let householdID: UUID?
        let profileID: UUID?
    }

    /// 子端末：6桁コードを消費して世帯に紐づく。
    /// 事前に `signInChildAnonymouslyIfNeeded()` で匿名サインインしておくこと
    /// （サーバ側は匿名セッション以外の消費を拒否する）。
    func consumePairingCode(_ code: String, devicePublicID: String? = nil) async throws -> PairingConsumeResult {
        struct Params: Encodable {
            let p_code: String
            let p_device_public_id: String?
        }
        struct Row: Decodable {
            let status: PairingConsumeStatus
            let householdId: UUID?
            let profileId: UUID?

            enum CodingKeys: String, CodingKey {
                case status
                case householdId = "household_id"
                case profileId = "profile_id"
            }
        }
        let rows: [Row] = try await client
            .rpc("consume_pairing_code", params: Params(
                p_code: code,
                p_device_public_id: devicePublicID))
            .execute()
            .value
        guard let row = rows.first else { throw PairingError.noResult }
        return PairingConsumeResult(
            status: row.status,
            householdID: row.householdId,
            profileID: row.profileId)
    }
}
