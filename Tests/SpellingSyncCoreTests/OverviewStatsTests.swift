import XCTest
@testable import SpellingSyncCore

/// 保護者「ようす」タブの純粋集計ロジックのテスト。
/// 日別利用時間バケット（UsageLog）／正答率バンド（AccuracyBand）／日別取り組み数（DailyActivity）。
final class OverviewStatsTests: XCTestCase {

    // MARK: - UsageLog（日別秒の純粋操作）

    func testAddSecondsAccumulatesOnSameDay() {
        var log: [String: Int] = [:]
        log = UsageLog.add(log, dayKey: "2026-06-28", seconds: 30)
        log = UsageLog.add(log, dayKey: "2026-06-28", seconds: 45)
        XCTAssertEqual(log["2026-06-28"], 75)
    }

    func testAddSecondsIgnoresNonPositive() {
        var log: [String: Int] = ["2026-06-28": 10]
        log = UsageLog.add(log, dayKey: "2026-06-28", seconds: 0)
        log = UsageLog.add(log, dayKey: "2026-06-28", seconds: -5)
        XCTAssertEqual(log["2026-06-28"], 10)
    }

    func testSecondsOnDay() {
        let log: [String: Int] = ["2026-06-28": 120, "2026-06-27": 60]
        XCTAssertEqual(UsageLog.seconds(log, on: "2026-06-28"), 120)
        XCTAssertEqual(UsageLog.seconds(log, on: "2026-06-26"), 0)
    }

    func testTotalOverDays() {
        let log: [String: Int] = ["2026-06-28": 120, "2026-06-27": 60, "2026-06-20": 999]
        let week = ["2026-06-22", "2026-06-23", "2026-06-24", "2026-06-25", "2026-06-26", "2026-06-27", "2026-06-28"]
        XCTAssertEqual(UsageLog.total(log, days: week), 180)
    }

    func testSeriesPreservesOrderAndFillsZero() {
        let log: [String: Int] = ["2026-06-28": 120, "2026-06-26": 30]
        let week = ["2026-06-26", "2026-06-27", "2026-06-28"]
        XCTAssertEqual(UsageLog.series(log, days: week), [30, 0, 120])
    }

    func testPrunedKeepsOnlyGivenKeys() {
        let log: [String: Int] = ["2026-06-28": 1, "2026-06-01": 2, "2026-05-01": 3]
        let pruned = UsageLog.pruned(log, keeping: ["2026-06-28", "2026-06-01"])
        XCTAssertEqual(pruned, ["2026-06-28": 1, "2026-06-01": 2])
    }

    // MARK: - AccuracyBand（正答率の調子分類）

    func testAccuracyBandNoneWhenNoEvents() {
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0, totalEvents: 0), .none)
    }

    func testAccuracyBandNoneBelowMinimumSample() {
        // サンプルが少ないと調子がブレるので、既定の最小件数(5)未満は .none。
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.95, totalEvents: 4), .none)
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.0, totalEvents: 3), .none)
    }

    func testAccuracyBandGoodAtThreshold() {
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.8, totalEvents: 10), .good)
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.95, totalEvents: 10), .good)
    }

    func testAccuracyBandWatchBelowThreshold() {
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.59, totalEvents: 10), .watch)
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.0, totalEvents: 5), .watch)
    }

    func testAccuracyBandOkInMiddle() {
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.6, totalEvents: 10), .ok)
        XCTAssertEqual(AccuracyBand.classify(accuracy: 0.79, totalEvents: 10), .ok)
    }

    // MARK: - UsageInterval（暦日分割）

    func testIntervalWithinSameDay() {
        let cal = Calendar(identifier: .gregorian)
        let start = makeDateTime(2026, 6, 28, 10, 0, 0, cal: cal)
        let end = makeDateTime(2026, 6, 28, 10, 30, 0, cal: cal)
        let segments = UsageInterval.split(start: start, end: end, calendar: cal)
        XCTAssertEqual(segments, [UsageSegment(dayStart: cal.startOfDay(for: start), seconds: 1800)])
    }

    func testIntervalCrossingMidnightSplitsByDay() {
        let cal = Calendar(identifier: .gregorian)
        let start = makeDateTime(2026, 6, 28, 23, 50, 0, cal: cal)
        let end = makeDateTime(2026, 6, 29, 0, 10, 0, cal: cal)
        let segments = UsageInterval.split(start: start, end: end, calendar: cal)
        XCTAssertEqual(segments, [
            UsageSegment(dayStart: cal.startOfDay(for: start), seconds: 600),
            UsageSegment(dayStart: cal.startOfDay(for: end), seconds: 600),
        ])
    }

    func testIntervalEmptyWhenEndNotAfterStart() {
        let cal = Calendar(identifier: .gregorian)
        let t = makeDateTime(2026, 6, 28, 10, 0, 0, cal: cal)
        XCTAssertEqual(UsageInterval.split(start: t, end: t, calendar: cal), [])
    }

    // MARK: - DailyActivity（曜日バー用の日別件数）

    func testDailyCountsBucketsEventsByDay() {
        let cal = Calendar(identifier: .gregorian)
        let mon = makeDate(2026, 6, 22, cal: cal)
        let tue = makeDate(2026, 6, 23, cal: cal)
        let events = [
            LearningEvent(word: "cat", date: addingHours(mon, 1, cal: cal), cleared: true, kind: .test(graded: true)),
            LearningEvent(word: "dog", date: addingHours(mon, 5, cal: cal), cleared: false, kind: .test(graded: true)),
            LearningEvent(word: "sun", date: addingHours(tue, 9, cal: cal), cleared: true, kind: .test(graded: true)),
        ]
        let series = DailyActivity.counts(events: events, dayStarts: [mon, tue], calendar: cal)
        XCTAssertEqual(series, [2, 1])
    }

    func testDailyCountsZeroForEmptyDays() {
        let cal = Calendar(identifier: .gregorian)
        let mon = makeDate(2026, 6, 22, cal: cal)
        let tue = makeDate(2026, 6, 23, cal: cal)
        let series = DailyActivity.counts(events: [], dayStarts: [mon, tue], calendar: cal)
        XCTAssertEqual(series, [0, 0])
    }

    // MARK: - helpers

    private func makeDate(_ y: Int, _ m: Int, _ d: Int, cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 0; c.minute = 0
        return cal.startOfDay(for: cal.date(from: c)!)
    }

    private func addingHours(_ date: Date, _ h: Int, cal: Calendar) -> Date {
        cal.date(byAdding: .hour, value: h, to: date)!
    }

    private func makeDateTime(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return cal.date(from: c)!
    }
}
