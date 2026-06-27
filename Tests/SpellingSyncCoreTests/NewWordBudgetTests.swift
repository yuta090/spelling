import XCTest
@testable import SpellingSyncCore

/// 1日の新規語「導入」予算の純粋ロジックのテスト。
/// 課金とは無関係（free/paid 共通の学習リズム）。「登録」ではなく
/// 「未練習語が当日の練習へ新規導入される数」を最大 10 に絞る。
final class NewWordBudgetTests: XCTestCase {
    // 決定的にするため UTC の Gregorian カレンダーを使う。
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: - 既定の上限

    func testDailyLimitIsTen() {
        XCTAssertEqual(NewWordBudget.dailyLimit, 10)
    }

    // MARK: - 残り枠

    func testRemainingSlots() {
        XCTAssertEqual(NewWordBudget.remainingSlots(introducedToday: 0), 10)
        XCTAssertEqual(NewWordBudget.remainingSlots(introducedToday: 3), 7)
        XCTAssertEqual(NewWordBudget.remainingSlots(introducedToday: 10), 0)
        XCTAssertEqual(NewWordBudget.remainingSlots(introducedToday: 99), 0, "超過しても負にならない")
    }

    func testRemainingSlotsRespectsCustomLimit() {
        XCTAssertEqual(NewWordBudget.remainingSlots(introducedToday: 2, dailyLimit: 5), 3)
    }

    // MARK: - 当日導入数のカウント（日付ロジックは純粋側でテスト）

    func testIntroducedCountCountsOnlyToday() {
        let dates: [Date?] = [
            day(2026, 6, 27),    // 今日
            day(2026, 6, 27, 0), // 今日（深夜）
            day(2026, 6, 26),    // 昨日
            nil,                 // 未導入
            day(2026, 6, 28)     // 未来
        ]
        let count = NewWordBudget.introducedCount(firstIntroducedDates: dates,
                                                  today: day(2026, 6, 27), calendar: cal)
        XCTAssertEqual(count, 2)
    }

    func testIntroducedCountEmpty() {
        XCTAssertEqual(NewWordBudget.introducedCount(firstIntroducedDates: [],
                                                     today: day(2026, 6, 27), calendar: cal), 0)
    }

    func testIntroducedCountAllNil() {
        XCTAssertEqual(NewWordBudget.introducedCount(firstIntroducedDates: [nil, nil, nil],
                                                     today: day(2026, 6, 27), calendar: cal), 0)
    }

    func testIntroducedCountIsTimezoneAware() {
        // JST 6/27 00:30 は UTC では 6/26 15:30。UTC カレンダーでは「今日(6/27)」に含めない。
        var jst = Calendar(identifier: .gregorian)
        jst.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let jstMidnight = jst.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 0, minute: 30))!

        XCTAssertEqual(NewWordBudget.introducedCount(firstIntroducedDates: [jstMidnight],
                                                     today: day(2026, 6, 27), calendar: cal), 0)
        // 同じ瞬間でも JST カレンダーなら「今日」に入る。
        let jstToday = jst.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 12))!
        XCTAssertEqual(NewWordBudget.introducedCount(firstIntroducedDates: [jstMidnight],
                                                     today: jstToday, calendar: jst), 1)
    }

    // MARK: - 新規語の選択（残り枠ぶんだけ先頭から）

    func testSelectNewWordsTakesRemainingSlots() {
        let candidates = Array(1...20)
        let picked = NewWordBudget.selectNewWords(candidates: candidates, introducedToday: 7)
        XCTAssertEqual(Array(picked), [1, 2, 3])  // 残り 3 枠
    }

    func testSelectNewWordsNoneWhenFull() {
        let picked = NewWordBudget.selectNewWords(candidates: ["a", "b"], introducedToday: 10)
        XCTAssertTrue(picked.isEmpty)
    }

    func testSelectNewWordsCappedByCandidates() {
        let picked = NewWordBudget.selectNewWords(candidates: ["a", "b"], introducedToday: 0)
        XCTAssertEqual(Array(picked), ["a", "b"], "候補が少なければ候補数まで")
    }

    func testSelectNewWordsRespectsCustomLimit() {
        let picked = NewWordBudget.selectNewWords(candidates: Array(1...20), introducedToday: 2, dailyLimit: 5)
        XCTAssertEqual(Array(picked), [1, 2, 3])  // 残り 3 枠（5 - 2）
    }

    func testSelectNewWordsEmptyCandidates() {
        let picked = NewWordBudget.selectNewWords(candidates: [Int](), introducedToday: 0)
        XCTAssertTrue(picked.isEmpty)
    }

    // MARK: - cappedIndices（既存語は常に含み、新規候補は残り枠まで）

    func testCappedIndicesKeepsAllNonCandidates() {
        // 全て既習/導入済み（新規候補なし）→ 全部含む
        let idx = NewWordBudget.cappedIndices(isNewCandidate: [false, false, false], introducedToday: 0)
        XCTAssertEqual(idx, [0, 1, 2])
    }

    func testCappedIndicesLimitsNewCandidatesToRemaining() {
        // 並び: 既習, 新規, 新規, 既習, 新規。introducedToday=8 → 残り 2 枠。
        // 新規はインデックス 1,2,4 のうち先頭 2 つ（1,2）まで。4 は落ちる。
        let flags = [false, true, true, false, true]
        let idx = NewWordBudget.cappedIndices(isNewCandidate: flags, introducedToday: 8)
        XCTAssertEqual(idx, [0, 1, 2, 3])
    }

    func testCappedIndicesDropsAllNewWhenFull() {
        let flags = [true, false, true]
        let idx = NewWordBudget.cappedIndices(isNewCandidate: flags, introducedToday: 10)
        XCTAssertEqual(idx, [1], "枠ゼロなら新規は全部落とし、既習だけ残す")
    }

    func testCappedIndicesKeepsAllNewWhenUnderBudget() {
        let flags = [true, true, false]
        let idx = NewWordBudget.cappedIndices(isNewCandidate: flags, introducedToday: 0)
        XCTAssertEqual(idx, [0, 1, 2], "新規が残り枠以下なら全部含む")
    }

    func testCappedIndicesEmpty() {
        XCTAssertEqual(NewWordBudget.cappedIndices(isNewCandidate: [], introducedToday: 0), [])
    }

    func testCappedIndicesRespectsCustomLimit() {
        let flags = [true, true, true]
        let idx = NewWordBudget.cappedIndices(isNewCandidate: flags, introducedToday: 1, dailyLimit: 2)
        XCTAssertEqual(idx, [0], "上限2・既導入1 → 残り1枠で先頭の新規のみ")
    }
}
