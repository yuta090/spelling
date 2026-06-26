import Foundation

/// 認証と「現在の世帯」状態を保持する、同期用の薄いセッションストア（デバッグ導線の土台）。
///
/// 役割:
/// - 親のメールOTPサインイン／子の匿名サインイン／サインアウト（`SupabaseService` 経由）。
/// - `create_household` RPC でオーナー世帯を作り、その **active household_id を端末に永続化**する。
///   サインインしても「どの世帯か」は別途保持が必要で、push スコープ（words.household_id 等）の前提になる。
/// - サインイン済み親が所属する世帯の自動読み込み（再インストール/再サインイン時の復帰）。
/// - 接続/RLS の疎通確認（profiles件数）。
///
/// ⚠️ ここは I/O 主体（Supabase SDK）なので薄く保つ。競合解決などの純粋ロジックは
/// `SpellingSyncCore`（TDD済）に置く方針（CLAUDE.md）。
/// 設計: docs/supabase-adapter-design.md
@MainActor
final class SyncSession: ObservableObject {
    /// 表示用の現在ユーザーID（認可判定はサーバー/RLSで行う）。
    @Published private(set) var userID: UUID?
    /// 現在ユーザーが匿名（子端末）か。
    @Published private(set) var isAnonymous: Bool = false
    /// push スコープとなる現在の世帯。端末に永続化される。
    @Published private(set) var activeHouseholdID: UUID?
    /// サインイン済み親が所属する世帯（自動復帰・切替用）。
    @Published private(set) var ownedHouseholdIDs: [UUID] = []
    /// 最後に確認した疎通結果（profiles件数）。
    @Published private(set) var lastProfileCount: Int?

    private let service: SupabaseService
    private let defaults: UserDefaults
    private let activeHouseholdKey = "spellingTrainer.sync.activeHouseholdID"

    init(service: SupabaseService = .shared, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        if let stored = defaults.string(forKey: activeHouseholdKey),
           let id = UUID(uuidString: stored) {
            activeHouseholdID = id
        }
        refreshAuthState()
    }

    /// サインイン済みか（表示用）。
    var isSignedIn: Bool { userID != nil }

    /// SDK のキャッシュから現在の認証状態を読み直す。
    func refreshAuthState() {
        userID = service.displayUserID
        isAnonymous = service.displayIsAnonymous
    }

    // MARK: - 親サインイン（メールOTP）

    /// 親：サインイン用メール（6桁コード）を送る。
    func sendParentOTP(email: String) async throws {
        try await service.sendParentSignInEmail(email: normalized(email))
    }

    /// 親：届いた6桁コードを検証してサインインし、所属世帯を読み込む。
    func verifyParentOTP(email: String, code: String) async throws {
        try await service.verifyParentOTP(email: normalized(email), token: normalized(code))
        refreshAuthState()
        try await loadOwnedHouseholds()
    }

    // MARK: - 子サインイン（匿名）

    /// 子端末：匿名サインイン（既にサインイン済みなら冪等）。
    /// 親の active 世帯を引き継がないよう、世帯スコープはクリアする（子はペアリングで後から紐づく）。
    func signInChildAnonymously() async throws {
        try await service.signInChildAnonymouslyIfNeeded()
        refreshAuthState()
        ownedHouseholdIDs = []
        setActiveHousehold(nil)
    }

    // MARK: - サインアウト

    func signOut() async throws {
        try await service.signOut()
        refreshAuthState()
        ownedHouseholdIDs = []
        lastProfileCount = nil
        // 別ユーザーが前ユーザーの世帯を引き継がないよう、永続化した active もクリアする。
        setActiveHousehold(nil)
    }

    /// 画面表示時の軽い再同期（成功トーストは出さない）。
    /// 認証状態を読み直し、サインイン済みの親なら所属世帯を読み込む。
    func refreshOnAppear() async {
        refreshAuthState()
        if isSignedIn && !isAnonymous {
            try? await loadOwnedHouseholds()
        }
    }

    // MARK: - 世帯

    /// 親が世帯を作成しオーナーになる。作成した世帯を active として永続化する。
    func createHousehold(title: String) async throws {
        let id = try await service.createHousehold(title: normalized(title))
        setActiveHousehold(id)
        // メンバーシップ一覧にも反映（失敗しても致命的でないので握りつぶす）。
        try? await loadOwnedHouseholds()
    }

    /// サインイン済み親の所属世帯を読み込む。
    /// active が未設定、または読み込んだ世帯集合に**含まれない古い値**なら、先頭（無ければ nil）に置き換える。
    /// これで別の親でサインインし直したときに前ユーザーの世帯を引き継がない。
    func loadOwnedHouseholds() async throws {
        let ids = try await service.myHouseholdMemberships().map(\.householdId)
        ownedHouseholdIDs = ids
        if let active = activeHouseholdID, ids.contains(active) {
            return // 現在の active は有効。維持する。
        }
        setActiveHousehold(ids.first)
    }

    /// active な世帯を設定（nil でクリア）。端末に永続化する。
    func setActiveHousehold(_ id: UUID?) {
        activeHouseholdID = id
        if let id {
            defaults.set(id.uuidString, forKey: activeHouseholdKey)
        } else {
            defaults.removeObject(forKey: activeHouseholdKey)
        }
    }

    // MARK: - 疎通確認

    /// profiles 件数を取得（接続/RLS の動作確認）。
    func refreshProfileCount() async throws {
        lastProfileCount = try await service.profileCount()
    }

    // MARK: - private

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
