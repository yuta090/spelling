import Foundation

/// 「今」時点で見せる連続学習日数。`LearningReportBuilder.currentStreakDays`（期間の末日ちょうどに
/// 学習が無ければ即0）とは意味論が異なる。朝など「今日はまだ学習していない」時間帯に見ても、
/// 昨日までの頑張りが不当に0日に見えないようにするための表示専用ロジック。
public struct CurrentStreak: Equatable, Sendable {
    /// 連続学習日数。今日から遡る場合と、昨日から遡る場合のどちらか。
    public let days: Int
    /// 今日すでに学習があったか（true なら `days` は今日を含む連続日数）。
    public let activeToday: Bool

    public init(days: Int, activeToday: Bool) {
        self.days = days
        self.activeToday = activeToday
    }
}

/// `CurrentStreak` の純粋な計算ロジック。
public enum CurrentStreakCalculator {
    /// - 今日学習があれば、今日から遡って連続している日数（activeToday=true）。
    /// - 今日は無いが昨日までは連続していれば、昨日から遡って連続している日数（activeToday=false）。
    /// - どちらでもなければ days=0, activeToday=false。
    public static func compute(events: [LearningEvent], today: Date, calendar: Calendar) -> CurrentStreak {
        let activeDaySet = Set(events.map { calendar.startOfDay(for: $0.date) })
        guard !activeDaySet.isEmpty else { return CurrentStreak(days: 0, activeToday: false) }

        let todayStart = calendar.startOfDay(for: today)
        if activeDaySet.contains(todayStart) {
            return CurrentStreak(days: countConsecutiveDays(from: todayStart, in: activeDaySet, calendar: calendar), activeToday: true)
        }

        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return CurrentStreak(days: 0, activeToday: false)
        }
        let yesterdayNormalized = calendar.startOfDay(for: yesterdayStart)
        guard activeDaySet.contains(yesterdayNormalized) else {
            return CurrentStreak(days: 0, activeToday: false)
        }
        return CurrentStreak(days: countConsecutiveDays(from: yesterdayNormalized, in: activeDaySet, calendar: calendar), activeToday: false)
    }

    /// `start`（暦日として正規化済み）から過去へ遡り、`activeDaySet` に含まれる連続日数を数える。
    /// 1日戻すたびに startOfDay で正規化する（DST で深夜が無い日でも前日の暦頭と一致させる）。
    private static func countConsecutiveDays(from start: Date, in activeDaySet: Set<Date>, calendar: Calendar) -> Int {
        var streak = 0
        var day = start
        while activeDaySet.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = calendar.startOfDay(for: prev)
        }
        return streak
    }
}
