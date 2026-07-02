import XCTest
@testable import SpellingSyncCore

/// 「今日まだ学習していない朝でも、昨日までの連続日数を不当に0にしない」ための連続日数計算のテスト。
/// `LearningReportBuilder.currentStreakDays`（末日=今日に学習が無ければ即0）とは意味論が異なる別ロジック。
final class CurrentStreakTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func ev(_ word: String, _ date: Date) -> LearningEvent {
        LearningEvent(word: word, date: date, cleared: true, kind: .practice)
    }

    func testEmptyEventsYieldsZero() {
        let today = at(2026, 6, 27)
        let r = CurrentStreakCalculator.compute(events: [], today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 0, activeToday: false))
    }

    func testActiveTodayCountsFromToday() {
        // 6/25,26,27（今日）と連続3日 → days=3, activeToday=true
        let today = at(2026, 6, 27, 9)
        let events = [
            ev("a", at(2026, 6, 25)),
            ev("a", at(2026, 6, 26)),
            ev("a", at(2026, 6, 27, 8)),
        ]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 3, activeToday: true))
    }

    func testNoActivityTodayButStreakThroughYesterday() {
        // 今日(6/27)は無いが、6/24,25,26 まで3日連続 → days=3, activeToday=false
        let today = at(2026, 6, 27, 9)
        let events = [
            ev("a", at(2026, 6, 24)),
            ev("a", at(2026, 6, 25)),
            ev("a", at(2026, 6, 26)),
        ]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 3, activeToday: false))
    }

    func testGapBeforeYesterdayYieldsZero() {
        // 学習は一昨日(6/25)までしか無い（昨日6/26が空白）→ 昨日から遡ると0日連続 → days=0
        let today = at(2026, 6, 27, 9)
        let events = [ev("a", at(2026, 6, 25))]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 0, activeToday: false))
    }

    func testSingleDayTodayOnly() {
        let today = at(2026, 6, 27, 9)
        let events = [ev("a", at(2026, 6, 27, 3))]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 1, activeToday: true))
    }

    func testStreakBreaksBeforeTodayButNotAtYesterday() {
        // 今日は無い。昨日(6/26)・一昨日(6/25)は連続だが、6/24は空白。6/23はある（無視される）。
        let today = at(2026, 6, 27, 9)
        let events = [
            ev("a", at(2026, 6, 23)),
            ev("a", at(2026, 6, 25)),
            ev("a", at(2026, 6, 26)),
        ]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: cal)
        XCTAssertEqual(r, CurrentStreak(days: 2, activeToday: false))
    }

    func testDSTMidnightTransitionStreak() {
        // ブラジル 2018-11-04 に夏時間入り（深夜が無い日）でも、連続日数計算が崩れないこと。
        var spa = Calendar(identifier: .gregorian)
        spa.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        func d(_ mo: Int, _ da: Int, _ h: Int) -> Date {
            spa.date(from: DateComponents(year: 2018, month: mo, day: da, hour: h))!
        }
        let today = d(11, 5, 9)
        let events = [ev("a", d(11, 3, 12)), ev("a", d(11, 4, 12)), ev("a", d(11, 5, 3))]
        let r = CurrentStreakCalculator.compute(events: events, today: today, calendar: spa)
        XCTAssertEqual(r, CurrentStreak(days: 3, activeToday: true))
    }
}
