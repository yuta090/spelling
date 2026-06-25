import XCTest
@testable import SpellingSyncCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }

final class SRSIntervalTests: XCTestCase {
    func testIntervalsPerBox() {
        XCTAssertEqual(SRSScheduler.intervalDays(box: 1), 0)
        XCTAssertEqual(SRSScheduler.intervalDays(box: 2), 1)
        XCTAssertEqual(SRSScheduler.intervalDays(box: 3), 3)
        XCTAssertEqual(SRSScheduler.intervalDays(box: 4), 7)
        XCTAssertEqual(SRSScheduler.intervalDays(box: 5), 16)
    }

    func testIntervalClampsOutOfRange() {
        XCTAssertEqual(SRSScheduler.intervalDays(box: 0), SRSScheduler.intervalDays(box: 1))
        XCTAssertEqual(SRSScheduler.intervalDays(box: 99), SRSScheduler.intervalDays(box: 5))
    }
}

final class SRSNextBoxTests: XCTestCase {
    func testCorrectIncrementsCappedAtMax() {
        XCTAssertEqual(SRSScheduler.nextBox(current: 1, correct: true), 2)
        XCTAssertEqual(SRSScheduler.nextBox(current: 4, correct: true), 5)
        XCTAssertEqual(SRSScheduler.nextBox(current: 5, correct: true), 5)
    }

    func testWrongResetsToOne() {
        XCTAssertEqual(SRSScheduler.nextBox(current: 5, correct: false), 1)
        XCTAssertEqual(SRSScheduler.nextBox(current: 2, correct: false), 1)
    }

    func testClampsInvalidCurrent() {
        XCTAssertEqual(SRSScheduler.nextBox(current: 0, correct: true), 2)   // 0→1→+1
        XCTAssertEqual(SRSScheduler.nextBox(current: 99, correct: true), 5)
    }
}

final class SRSDueTests: XCTestCase {
    func testDueDateAddsInterval() {
        // box3 = 3日後
        XCTAssertEqual(SRSScheduler.dueDate(box: 3, lastReviewedAt: t0), t0.addingTimeInterval(days(3)))
    }

    func testIsDueTrueAtOrAfterDueDate() {
        let last = t0
        // box2 = 翌日
        XCTAssertFalse(SRSScheduler.isDue(box: 2, lastReviewedAt: last, asOf: t0.addingTimeInterval(days(0))))
        XCTAssertTrue(SRSScheduler.isDue(box: 2, lastReviewedAt: last, asOf: t0.addingTimeInterval(days(1))))
        XCTAssertTrue(SRSScheduler.isDue(box: 2, lastReviewedAt: last, asOf: t0.addingTimeInterval(days(2))))
    }

    func testNeverReviewedIsNotDueReview() {
        XCTAssertFalse(SRSScheduler.isDue(box: 1, lastReviewedAt: nil, asOf: t0))
    }
}

final class SRSMasteredTests: XCTestCase {
    func testBox5AfterIntervalIsMastered() {
        let last = t0
        XCTAssertFalse(SRSScheduler.isMastered(box: 5, lastReviewedAt: last, asOf: t0.addingTimeInterval(days(15))))
        XCTAssertTrue(SRSScheduler.isMastered(box: 5, lastReviewedAt: last, asOf: t0.addingTimeInterval(days(16))))
    }

    func testLowerBoxesNeverMastered() {
        XCTAssertFalse(SRSScheduler.isMastered(box: 4, lastReviewedAt: t0, asOf: t0.addingTimeInterval(days(100))))
    }

    func testNeverReviewedNotMastered() {
        XCTAssertFalse(SRSScheduler.isMastered(box: 5, lastReviewedAt: nil, asOf: t0))
    }
}

final class SRSSelectDueTests: XCTestCase {
    func testSelectsOnlyDueReviewedNonMasteredOrderedByDueDate() {
        let newCard = SRSCard(box: 1, lastReviewedAt: nil)                                   // 新出 → 除外
        let notYet  = SRSCard(box: 3, lastReviewedAt: t0.addingTimeInterval(days(-1)))       // box3=3日後 → まだ
        let dueOld  = SRSCard(box: 2, lastReviewedAt: t0.addingTimeInterval(days(-10)))      // 期日かなり前 → due
        let dueRecent = SRSCard(box: 2, lastReviewedAt: t0.addingTimeInterval(days(-2)))     // 期日少し前 → due
        let mastered = SRSCard(box: 5, lastReviewedAt: t0.addingTimeInterval(days(-30)))     // box5超過 → mastered除外

        let result = SRSScheduler.selectDue(
            cards: [newCard, notYet, dueRecent, dueOld, mastered],
            asOf: t0
        )
        // due は dueOld と dueRecent のみ。期日の古い順（dueOld が先）。
        XCTAssertEqual(result.map(\.id), [dueOld.id, dueRecent.id])
    }

    func testEmptyWhenNothingDue() {
        let cards = [SRSCard(box: 1, lastReviewedAt: nil), SRSCard(box: 4, lastReviewedAt: t0)]
        XCTAssertTrue(SRSScheduler.selectDue(cards: cards, asOf: t0).isEmpty)
    }
}
