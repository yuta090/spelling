import Foundation

/// サーバ `public.profiles` へ子プロファイルを provisioning するためのネットワーク境界（port）。
///
/// `words.profile_id → profiles(id)` の FK 制約上、ある profile_id を持つ words を push する **前に**、
/// 対応する `profiles` 行がサーバに存在している必要がある（Phase 5b）。`WordSyncCoordinator` は
/// 同期サイクルの冒頭で **捕捉したアクティブプロファイルを provision** してから words を同期する。
///
/// アプリは Supabase（`SyncEngine.push([ProfileUpsert])`）で実装し、テストはフェイクで差し替える。
/// provisioning は親認証時のみ意味を持つ（`is_household_member` が全プロファイルの upsert を許す）。
/// 子端末（匿名・単一プロファイル）経路では words 同期自体が走らない（`configureSync` が世帯を返さない）。
public protocol ProfileProvisioner: Sendable {
    /// 指定プロファイルをサーバへ upsert する（冪等）。既に存在すれば LWW ガードが古い更新を無視する。
    func provision(_ profile: ProvisionedProfile) async throws
}

/// provisioning に必要な値（wire 非依存）。ローカル `ChildProfile.id` を **そのままサーバ `profiles.id`**
/// として使う（クライアント権威 ID・未リリースゆえ採用可）。
public struct ProvisionedProfile: Sendable, Equatable {
    public let id: UUID
    public let householdID: UUID
    public let displayName: String
    public let appLanguage: String
    /// LWW 時刻。provisioning は冪等なので **安定値**（プロファイルの生成時刻）を使う。
    /// これで再送のたびに新しい時刻を送らず、サーバ LWW ガード（古い更新は無視・同時刻は通す）に
    /// 対して常に同じ版を提示する（真に新しい `display_name` を後退させない）。なお `profiles` は
    /// 現状どのコーディネータも pull しないので、再送で server_changed_at/sync_version が動いても実害はない。
    public let updatedAt: Date

    public init(
        id: UUID,
        householdID: UUID,
        displayName: String,
        appLanguage: String,
        updatedAt: Date
    ) {
        self.id = id
        self.householdID = householdID
        self.displayName = displayName
        self.appLanguage = appLanguage
        self.updatedAt = updatedAt
    }

    /// ローカル `ChildProfile` ＋世帯から provisioning 値を組む。`updatedAt` は生成時刻（安定）。
    public static func make(
        from profile: ChildProfile,
        householdID: UUID,
        appLanguage: String = "japanese"
    ) -> ProvisionedProfile {
        ProvisionedProfile(
            id: profile.id,
            householdID: householdID,
            displayName: profile.displayName,
            appLanguage: appLanguage,
            updatedAt: profile.createdAt
        )
    }
}
