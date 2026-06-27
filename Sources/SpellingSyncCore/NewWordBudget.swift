import Foundation

/// 1日の新規語「導入」予算の**純粋ロジック**。
///
/// 重要: これは課金とは**無関係**な学習リズム（free/paid 共通）。「親が単語を登録できる数」
/// ではなく「**未練習語が当日の練習に新規導入される数**」を最大 10 に絞る。登録は無制限で、
/// 超過分はキューに待つ。当日導入数は永続スタンプ `firstIntroducedAt` から決定的に数える
/// （可変カウンタを持たない＝冪等・クラッシュ安全）。I/O はアプリ側。
public enum NewWordBudget {
    /// 1日に新規導入できる上限。
    public static let dailyLimit = 10

    /// 今日まだ新規導入できる残り枠（負にはならない）。
    public static func remainingSlots(introducedToday: Int, dailyLimit: Int = dailyLimit) -> Int {
        max(0, dailyLimit - introducedToday)
    }

    /// `firstIntroducedAt` の並びから「今日導入された語数」を数える。
    /// - `nil`（未導入）と当日以外は数えない。タイムゾーンは `calendar` に従う。
    public static func introducedCount(
        firstIntroducedDates: [Date?],
        today: Date,
        calendar: Calendar
    ) -> Int {
        firstIntroducedDates.reduce(into: 0) { acc, date in
            guard let date, calendar.isDate(date, inSameDayAs: today) else { return }
            acc += 1
        }
    }

    /// 当日の練習に新規導入する語を、残り枠ぶんだけ候補の先頭から選ぶ。
    /// - 候補は呼び出し側が「未練習語」を望む順（例: NGSL 頻度順）に並べて渡す。
    public static func selectNewWords<W>(
        candidates: [W],
        introducedToday: Int,
        dailyLimit: Int = dailyLimit
    ) -> ArraySlice<W> {
        candidates.prefix(remainingSlots(introducedToday: introducedToday, dailyLimit: dailyLimit))
    }
}
