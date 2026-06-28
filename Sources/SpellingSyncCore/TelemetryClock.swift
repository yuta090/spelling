import Foundation

/// イベントの `occurredAt` を **厳密単調増加** にするスタンパ（純粋ロジック）。
///
/// 同一ミリ秒に複数イベントが発生しても時刻が等しくならないようにする。
/// 理由: 送信順序の決定性と、将来 occurredAt をカーソル/整列キーに使う際の取りこぼし防止
/// （`OutboundSync` の strict `>` 比較が同時刻行を落とすのと同種の問題を、発生時点で潰しておく）。
///
/// 解像度はミリ秒（1ms）。連投時は直前値に 1ms ずつ積む。
public struct MonotonicStamper: Sendable {
    /// 直近に発行した時刻。初期は nil（最初の stamp はそのまま通す）。
    private var last: Date?
    /// 連投時に積む最小刻み（秒）。
    private let step: TimeInterval

    public init(last: Date? = nil, step: TimeInterval = 0.001) {
        precondition(step > 0, "step must be > 0")
        self.last = last
        self.step = step
    }

    /// `proposed`（多くは現在時刻）を、直前発行値より必ず後になるよう補正して返す。
    public mutating func stamp(_ proposed: Date) -> Date {
        let next: Date
        if let last, proposed <= last {
            next = last.addingTimeInterval(step)
        } else {
            next = proposed
        }
        last = next
        return next
    }

    /// 直近に発行した値（永続化して次回起動へ引き継ぐ用途）。
    public var lastIssued: Date? { last }
}
