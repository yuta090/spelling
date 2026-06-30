import XCTest
@testable import SpellingSyncCore

final class DailyPlayLimiterTests: XCTestCase {
    // fixture の日付は Asia/Tokyo で作る（下記 day(...)）。比較カレンダーの TZ を未指定にすると
    // マシン TZ 依存になり、UTC ランナー(CI)では JST の朝/夜の時刻が UTC で前日に倒れて
    // 「日付ロールオーバー」判定がずれてテストが落ちる。fixture と同じ TZ に固定して決定論にする。
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    private let limiter = DailyPlayLimiter(dailyLimit: 2)

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testFreshDayHasFullAllowance() {
        let today = day(2026, 6, 30)
        XCTAssertEqual(limiter.playsToday(lastPlayedDay: nil, storedCount: 0, today: today, calendar: cal), 0)
        XCTAssertEqual(limiter.remaining(lastPlayedDay: nil, storedCount: 0, today: today, calendar: cal), 2)
        XCTAssertTrue(limiter.canPlay(lastPlayedDay: nil, storedCount: 0, today: today, calendar: cal))
    }

    func testSameDayCountsDecrementRemaining() {
        let today = day(2026, 6, 30)
        // 1回遊んだ後。
        XCTAssertEqual(limiter.playsToday(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 1, today: today, calendar: cal), 1)
        XCTAssertEqual(limiter.remaining(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 1, today: today, calendar: cal), 1)
        XCTAssertTrue(limiter.canPlay(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 1, today: today, calendar: cal))
    }

    func testReachingLimitBlocks() {
        let today = day(2026, 6, 30)
        XCTAssertEqual(limiter.remaining(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 2, today: today, calendar: cal), 0)
        XCTAssertFalse(limiter.canPlay(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 2, today: today, calendar: cal))
    }

    func testOverLimitClampsToZero() {
        let today = day(2026, 6, 30)
        XCTAssertEqual(limiter.remaining(lastPlayedDay: day(2026, 6, 30, 9), storedCount: 5, today: today, calendar: cal), 0)
    }

    func testDayRolloverResets() {
        // 昨日2回遊んでいても、今日は満タンに戻る。
        let yesterday = day(2026, 6, 29, 20)
        let today = day(2026, 6, 30, 8)
        XCTAssertEqual(limiter.playsToday(lastPlayedDay: yesterday, storedCount: 2, today: today, calendar: cal), 0)
        XCTAssertEqual(limiter.remaining(lastPlayedDay: yesterday, storedCount: 2, today: today, calendar: cal), 2)
        XCTAssertTrue(limiter.canPlay(lastPlayedDay: yesterday, storedCount: 2, today: today, calendar: cal))
    }

    func testRecordingCompletionIncrementsSameDay() {
        let today = day(2026, 6, 30, 10)
        let r1 = limiter.recordingCompletion(lastPlayedDay: nil, storedCount: 0, today: today, calendar: cal)
        XCTAssertEqual(r1.count, 1)
        XCTAssertTrue(cal.isDate(r1.day, inSameDayAs: today))

        let r2 = limiter.recordingCompletion(lastPlayedDay: r1.day, storedCount: r1.count, today: day(2026, 6, 30, 18), calendar: cal)
        XCTAssertEqual(r2.count, 2)
    }

    func testRecordingCompletionResetsOnNewDay() {
        let yesterday = day(2026, 6, 29, 20)
        // 昨日2回 → 今日1回目を記録すると count は1から数え直し。
        let r = limiter.recordingCompletion(lastPlayedDay: yesterday, storedCount: 2, today: day(2026, 6, 30, 8), calendar: cal)
        XCTAssertEqual(r.count, 1)
    }
}
