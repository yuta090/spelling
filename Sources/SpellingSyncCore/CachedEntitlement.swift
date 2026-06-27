import Foundation

/// 課金権利の**オフライン用キャッシュ**（純粋ロジック）。
///
/// StoreKit2 の `Transaction.currentEntitlements` はオンラインで失効・取消を反映するが、
/// 起動直後やオフラインでは即座に得られない。そこで「直近に検証した権利」を端末に保存し、
/// **失効時刻を超えない範囲でのみ**有効とみなす（「永久に subscribed」を避ける／審査要件）。
/// I/O（保存）はアプリ側。ここは「今この時刻で有効か」の判断だけを決定的に行う。
public struct CachedEntitlement: Codable, Equatable, Sendable {
    /// 直近の検証時点で購読が有効だったか。
    public var isSubscribed: Bool
    /// 失効時刻（自動更新サブスクの現在の期間終了）。`nil` は失効情報なし（無期限扱い）。
    public var expiresAt: Date?

    public init(isSubscribed: Bool, expiresAt: Date? = nil) {
        self.isSubscribed = isSubscribed
        self.expiresAt = expiresAt
    }

    /// 権利なしの既定値。
    public static let none = CachedEntitlement(isSubscribed: false, expiresAt: nil)

    /// 指定時刻で権利が有効か。
    /// - 未購読なら常に false。
    /// - 失効時刻があるなら `now < expiresAt` のときだけ有効（失効時刻ちょうど以降は無効）。
    /// - 失効時刻が nil なら有効（無期限）。
    public func isActive(now: Date) -> Bool {
        guard isSubscribed else { return false }
        if let expiresAt { return now < expiresAt }
        return true
    }
}
