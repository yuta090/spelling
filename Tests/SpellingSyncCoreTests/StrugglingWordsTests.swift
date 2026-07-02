import XCTest
@testable import SpellingSyncCore

/// 「よくまちがえる単語」集計（親が子の苦手を単語粒度で見る）のテスト。
final class StrugglingWordsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func ev(_ word: String, _ date: Date, _ cleared: Bool, kind: LearningEvent.Kind = .test(graded: true)) -> LearningEvent {
        LearningEvent(word: word, date: date, cleared: cleared, kind: kind)
    }

    func testEmptyEventsYieldsEmptyList() {
        let r = StrugglingWordsBuilder.build(events: [], from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r, [])
    }

    func testOnlyGradedIncorrectTestsCountAsMisses() {
        // 練習・未採点テストのまちがいは数えない。採点確定テストの不正解だけがまちがい。
        let events = [
            ev("cat", at(2026, 6, 10), false, kind: .practice),               // 練習：数えない
            ev("dog", at(2026, 6, 10), false, kind: .test(graded: false)),    // 未採点：数えない
            ev("sun", at(2026, 6, 10), false, kind: .test(graded: true)),     // 採点確定＆不正解：数える
            ev("moon", at(2026, 6, 10), true, kind: .test(graded: true)),     // 採点確定だが正解：数えない
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.map(\.word), ["sun"])
        XCTAssertEqual(r[0].missCount, 1)
    }

    func testOrdersByMissCountDescendingThenByRecency() {
        let events = [
            // "cat": 1回まちがい（6/10）
            ev("cat", at(2026, 6, 10), false),
            // "dog": 2回まちがい（6/11, 6/12）
            ev("dog", at(2026, 6, 11), false),
            ev("dog", at(2026, 6, 12), false),
            // "sun": 2回まちがい（6/9, 6/13）← dog と同数だが最終まちがいが新しい
            ev("sun", at(2026, 6, 9), false),
            ev("sun", at(2026, 6, 13), false),
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.map(\.word), ["sun", "dog", "cat"], "件数降順→同数なら最終まちがいが新しい順")
        XCTAssertEqual(r[0].missCount, 2)
        XCTAssertEqual(r[0].lastMissDate, at(2026, 6, 13))
    }

    func testOrdersByWordAscendingWhenMissCountAndLastMissDateAreEqual() {
        // missCount・lastMissDate が完全一致するとき、Dictionary 由来で順序が起動ごとに揺れないよう
        // 最終タイブレークとして word 昇順にする。
        let sameDate = at(2026, 6, 10)
        let events = [
            ev("zebra", sameDate, false),
            ev("apple", sameDate, false),
            ev("mango", sameDate, false),
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.map(\.word), ["apple", "mango", "zebra"])
    }

    func testLimitTruncatesResults() {
        let events = (0..<10).map { i in ev("w\(i)", at(2026, 6, 10), false) }
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 3, calendar: cal)
        XCTAssertEqual(r.count, 3)
    }

    func testWordsWithZeroMissesAreExcluded() {
        let events = [
            ev("cat", at(2026, 6, 10), true, kind: .test(graded: true)),   // 正解のみ
            ev("dog", at(2026, 6, 10), false, kind: .practice),           // 練習のみ
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r, [])
    }

    func testClearedAfterLastMissIsTrueWhenLaterClearedTestExists() {
        let events = [
            ev("cat", at(2026, 6, 10), false), // まちがい
            ev("cat", at(2026, 6, 11), true),  // その後クリア
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].lastMissDate, at(2026, 6, 10))
        XCTAssertTrue(r[0].clearedAfterLastMiss)
    }

    func testClearedAfterLastMissIsFalseWhenNoLaterClear() {
        let events = [
            ev("cat", at(2026, 6, 10), true),   // 先にクリア
            ev("cat", at(2026, 6, 11), false),  // その後まちがい（最後がまちがいのまま）
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].lastMissDate, at(2026, 6, 11))
        XCTAssertFalse(r[0].clearedAfterLastMiss)
    }

    func testClearedAfterLastMissIgnoresPracticeAndUngradedEvents() {
        // 最後のまちがいより後に「練習でクリア扱い」や「未採点テスト」があっても、
        // clearedAfterLastMiss は採点確定テストのクリアだけを見る。
        let events = [
            ev("cat", at(2026, 6, 10), false, kind: .test(graded: true)),
            ev("cat", at(2026, 6, 11), true, kind: .practice),
            ev("cat", at(2026, 6, 12), true, kind: .test(graded: false)),
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertFalse(r[0].clearedAfterLastMiss)
    }

    func testEventsOutsideRangeAreExcluded() {
        let events = [
            ev("cat", at(2026, 5, 31), false),  // 範囲外（前）
            ev("dog", at(2026, 6, 15), false),  // 範囲内
            ev("owl", at(2026, 7, 1), false),   // 範囲外（後）
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1, 0), to: at(2026, 6, 30, 23), calendar: cal)
        XCTAssertEqual(r.map(\.word), ["dog"])
    }

    func testClearedAfterLastMissOnlyConsidersEventsWithinRange() {
        // 期間内では「まちがい」が最後の記録。期間外（範囲後）にクリアがあっても、
        // 期間内イベントだけを見て集計するので clearedAfterLastMiss は false のまま。
        let events = [
            ev("cat", at(2026, 6, 10), false),
            ev("cat", at(2026, 7, 1), true), // 範囲外
        ]
        let r = StrugglingWordsBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), limit: 5, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertFalse(r[0].clearedAfterLastMiss)
    }
}
