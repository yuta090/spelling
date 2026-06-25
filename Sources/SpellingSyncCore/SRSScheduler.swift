import Foundation

/// 1枚の学習カードの定着状態（Leitner 箱方式）。
public struct SRSCard: Equatable, Sendable {
    public var id: UUID
    /// 1〜5。大きいほど定着（復習間隔が長い）。5 は最長間隔を越えると mastered。
    public var box: Int
    /// 最後に学習した時刻。nil = 未学習（新出語）。
    public var lastReviewedAt: Date?

    public init(id: UUID = UUID(), box: Int = 1, lastReviewedAt: Date? = nil) {
        self.id = id
        self.box = box
        self.lastReviewedAt = lastReviewedAt
    }
}

/// 純粋な間隔反復スケジューラ。`asOf` を必ず引数で受け取り、`Date()` をロジックに埋めない（決定論）。
/// 設計: docs/srs-retention-design.md
public enum SRSScheduler {
    public static let minBox = 1
    public static let maxBox = 5

    private static func clampBox(_ box: Int) -> Int {
        min(max(box, minBox), maxBox)
    }

    /// box ごとの復習間隔（日）。box は 1...5 にクランプ。
    public static func intervalDays(box: Int) -> Int {
        switch clampBox(box) {
        case 1: return 0
        case 2: return 1
        case 3: return 3
        case 4: return 7
        default: return 16
        }
    }

    /// 正誤に応じた次の box。正解=+1（最大5）、不正解=1 に戻す。
    public static func nextBox(current: Int, correct: Bool) -> Int {
        guard correct else { return minBox }
        return clampBox(clampBox(current) + 1)
    }

    /// 次回の復習期日 = 最終学習時刻 + 間隔。
    public static func dueDate(box: Int, lastReviewedAt: Date) -> Date {
        lastReviewedAt.addingTimeInterval(TimeInterval(intervalDays(box: box)) * 86_400)
    }

    /// 復習期日が到来したか。未学習(nil)は「期日到来の復習」ではない（=false。新出語は別供給）。
    public static func isDue(box: Int, lastReviewedAt: Date?, asOf: Date) -> Bool {
        guard let last = lastReviewedAt else { return false }
        if isMastered(box: box, lastReviewedAt: last, asOf: asOf) { return false }
        return asOf >= dueDate(box: box, lastReviewedAt: last)
    }

    /// 習得済みか。box5 に到達し、その間隔を越えたら mastered（以後は出題しない）。
    public static func isMastered(box: Int, lastReviewedAt: Date?, asOf: Date) -> Bool {
        guard let last = lastReviewedAt, box >= maxBox else { return false }
        return asOf >= dueDate(box: maxBox, lastReviewedAt: last)
    }

    /// 復習すべきカード（期日到来・未習得・学習済み）を、期日の古い順に返す。
    public static func selectDue(cards: [SRSCard], asOf: Date) -> [SRSCard] {
        cards
            .filter { isDue(box: $0.box, lastReviewedAt: $0.lastReviewedAt, asOf: asOf) }
            .sorted { lhs, rhs in
                // isDue が真なので lastReviewedAt は non-nil。期日の古い順。
                dueDate(box: lhs.box, lastReviewedAt: lhs.lastReviewedAt!)
                    < dueDate(box: rhs.box, lastReviewedAt: rhs.lastReviewedAt!)
            }
    }
}
