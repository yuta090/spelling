import Foundation

/// サーバ側（Supabase `entitlements`）の権利ステータス。rawValue は DB の check 値に対応。
public enum EntitlementStatus: String, Codable, Equatable, Sendable {
    case none
    case trial
    case active
    case grace
    case expired
    case revoked
}

/// サーバ権利レコード 1 件の**純粋な有効判定**ロジック（Phase 2 サーバゲートの土台）。
///
/// I/O（Supabase からの取得・App Store 検証）はサーバ/アプリ側。ここは「今この時刻で有効か」を
/// 決定的に判断するだけ。サーバ側ゲートもクライアントの UX 表示もこの意味論に揃える。
public struct ServerEntitlement: Equatable, Sendable {
    public let productID: String
    public let status: EntitlementStatus
    /// 現在の課金期間の終了時刻。
    public let expiresAt: Date?
    /// 課金リトライ猶予(grace)の終了時刻。grace 状態の有効期限に使う（無ければ通常期限で代替）。
    public let graceExpiresAt: Date?

    public init(
        productID: String,
        status: EntitlementStatus,
        expiresAt: Date? = nil,
        graceExpiresAt: Date? = nil
    ) {
        self.productID = productID
        self.status = status
        self.expiresAt = expiresAt
        self.graceExpiresAt = graceExpiresAt
    }

    /// 指定時刻でこの権利が有効か。
    /// - none / expired / revoked: 常に無効。
    /// - active: 期限があれば `now < expiresAt`、無ければ有効（無期限扱い）。
    /// - trial: トライアルは必ず期限がある前提。期限不明は安全側で無効（fail-closed）。
    /// - grace: 猶予期限（無ければ通常期限）まで有効。どちらも無ければ安全側で無効（fail-closed）。
    public func isActive(now: Date) -> Bool {
        switch status {
        case .none, .expired, .revoked:
            return false
        case .active:
            if let expiresAt { return now < expiresAt }
            return true
        case .trial:
            guard let expiresAt else { return false }
            return now < expiresAt
        case .grace:
            if let graceExpiresAt { return now < graceExpiresAt }
            if let expiresAt { return now < expiresAt }
            return false
        }
    }
}

/// 世帯（household）の実効権利。月/年・複数親など複数レコードのうち **1 つでも有効なら世帯は有効**。
public enum HouseholdEntitlement {
    public static func isEntitled(_ entitlements: [ServerEntitlement], now: Date) -> Bool {
        entitlements.contains { $0.isActive(now: now) }
    }
}
