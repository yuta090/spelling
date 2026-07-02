import XCTest
@testable import SpellingSyncCore

/// `ReviewQueue`（活動非依存の「間違い復習」エンジン）のテスト。
/// 設計判断: 卒業=Leitner箱（SRSScheduler 再利用）/ 再出題タイミング=ステップ基準 / キューは活動ごとに分離。
private let idA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let idB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let idC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
private let idX = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!

// MARK: - stepInterval（Leitner 間隔のステップ写像）

final class ReviewQueueStepIntervalTests: XCTestCase {
    func testIntervalsIncreaseWithBox() {
        XCTAssertEqual(ReviewQueue.stepInterval(box: 1), 1)
        XCTAssertEqual(ReviewQueue.stepInterval(box: 2), 2)
        XCTAssertEqual(ReviewQueue.stepInterval(box: 3), 3)
        XCTAssertEqual(ReviewQueue.stepInterval(box: 4), 5)
        XCTAssertEqual(ReviewQueue.stepInterval(box: 5), 8)
    }

    func testIntervalClampsOutOfRange() {
        XCTAssertEqual(ReviewQueue.stepInterval(box: 0), ReviewQueue.stepInterval(box: 1))
        XCTAssertEqual(ReviewQueue.stepInterval(box: 99), ReviewQueue.stepInterval(box: 5))
    }
}

// MARK: - apply（単一エントリポイント：解答結果の反映）

final class ReviewQueueApplyTests: XCTestCase {
    func testWrongOnFreshItemEnrollsAtBoxOne() {
        let out = ReviewQueue.apply([], itemID: idA, correct: false, step: 3)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, idA)
        XCTAssertEqual(out[0].box, SRSScheduler.minBox)
        XCTAssertEqual(out[0].lastSeenStep, 3)
        XCTAssertEqual(out[0].addedAtStep, 3)
    }

    func testCorrectOnFreshItemDoesNotEnroll() {
        // 一度も間違えていない語は復習に積まない（追加問題にしない）。
        let out = ReviewQueue.apply([], itemID: idA, correct: true, step: 3)
        XCTAssertTrue(out.isEmpty)
    }

    func testCorrectOnQueuedItemPromotesBox() {
        let start = [ReviewItemState(id: idA, box: 2, lastSeenStep: 1, addedAtStep: 0)]
        let out = ReviewQueue.apply(start, itemID: idA, correct: true, step: 4)
        XCTAssertEqual(out[0].box, 3)            // +1
        XCTAssertEqual(out[0].lastSeenStep, 4)   // 前進
        XCTAssertEqual(out[0].addedAtStep, 0)    // 不変
    }

    func testWrongOnQueuedItemResetsToBoxOne() {
        let start = [ReviewItemState(id: idA, box: 4, lastSeenStep: 1, addedAtStep: 0)]
        let out = ReviewQueue.apply(start, itemID: idA, correct: false, step: 7)
        XCTAssertEqual(out[0].box, SRSScheduler.minBox)
        XCTAssertEqual(out[0].lastSeenStep, 7)
    }

    func testIdempotentSingleEntryPerItem() {
        var states: [ReviewItemState] = []
        states = ReviewQueue.apply(states, itemID: idA, correct: false, step: 1)
        states = ReviewQueue.apply(states, itemID: idA, correct: false, step: 2)
        XCTAssertEqual(states.filter { $0.id == idA }.count, 1)
    }

    func testDoesNotTouchOtherItems() {
        let start = [ReviewItemState(id: idB, box: 3, lastSeenStep: 1, addedAtStep: 1)]
        let out = ReviewQueue.apply(start, itemID: idA, correct: false, step: 5)
        XCTAssertEqual(out.first { $0.id == idB }, start[0])
    }
}

// MARK: - isDue / isMastered（ステップ基準の再出題・卒業）

final class ReviewQueueDueTests: XCTestCase {
    func testDueWhenStepsSinceLastSeenReachInterval() {
        let s = ReviewItemState(id: idA, box: 2, lastSeenStep: 5, addedAtStep: 0) // 間隔=2
        XCTAssertFalse(ReviewQueue.isDue(s, currentStep: 6)) // 1ステップ後 → まだ
        XCTAssertTrue(ReviewQueue.isDue(s, currentStep: 7))  // 2ステップ後 → due
        XCTAssertTrue(ReviewQueue.isDue(s, currentStep: 9))  // それ以降も due
    }

    func testBox1DueOnVeryNextStep() {
        let s = ReviewItemState(id: idA, box: 1, lastSeenStep: 5, addedAtStep: 5) // 間隔=1
        XCTAssertFalse(ReviewQueue.isDue(s, currentStep: 5)) // 同ステップでは出さない
        XCTAssertTrue(ReviewQueue.isDue(s, currentStep: 6))  // 次のステップで出る
    }

    func testMasteredAtBox5AfterInterval() {
        let s = ReviewItemState(id: idA, box: 5, lastSeenStep: 10, addedAtStep: 0) // box5 間隔=8
        XCTAssertFalse(ReviewQueue.isMastered(s, currentStep: 17)) // 7ステップ後 → まだ
        XCTAssertTrue(ReviewQueue.isMastered(s, currentStep: 18))  // 8ステップ後 → 卒業
    }

    func testMasteredIsNotDue() {
        let s = ReviewItemState(id: idA, box: 5, lastSeenStep: 10, addedAtStep: 0)
        XCTAssertTrue(ReviewQueue.isMastered(s, currentStep: 30))
        XCTAssertFalse(ReviewQueue.isDue(s, currentStep: 30))
    }

    func testLowerBoxesNeverMastered() {
        let s = ReviewItemState(id: idA, box: 4, lastSeenStep: 0, addedAtStep: 0)
        XCTAssertFalse(ReviewQueue.isMastered(s, currentStep: 1000))
    }
}

// MARK: - selectForInjection（追加問題の選定：+1, +2）

final class ReviewQueueSelectionTests: XCTestCase {
    func testSelectsOnlyDueUpToCap() {
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0), // 間隔1 → due
            ReviewItemState(id: idB, box: 2, lastSeenStep: 4, addedAtStep: 1), // 間隔2、1ステップ後 → まだ
            ReviewItemState(id: idC, box: 1, lastSeenStep: 1, addedAtStep: 1)  // 間隔1 → due
        ]
        let picked = ReviewQueue.selectForInjection(states, currentStep: 5, cap: 2)
        XCTAssertEqual(Set(picked.map(\.id)), [idA, idC]) // due は A,C。cap=2 なので両方。
    }

    func testCapLimitsCount() {
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0),
            ReviewItemState(id: idB, box: 1, lastSeenStep: 0, addedAtStep: 1),
            ReviewItemState(id: idC, box: 1, lastSeenStep: 0, addedAtStep: 2)
        ]
        XCTAssertEqual(ReviewQueue.selectForInjection(states, currentStep: 5, cap: 1).count, 1)
        XCTAssertEqual(ReviewQueue.selectForInjection(states, currentStep: 5, cap: 2).count, 2)
    }

    func testCapZeroOrNegativeReturnsEmpty() {
        let states = [ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0)]
        XCTAssertTrue(ReviewQueue.selectForInjection(states, currentStep: 5, cap: 0).isEmpty)
        XCTAssertTrue(ReviewQueue.selectForInjection(states, currentStep: 5, cap: -3).isEmpty)
    }

    func testOrdersByMostOverdueThenAddedAt() {
        // 同 box1（間隔1）。lastSeenStep が古いほど超過大 → 先に出す。
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 4, addedAtStep: 4), // 超過=1
            ReviewItemState(id: idB, box: 1, lastSeenStep: 1, addedAtStep: 0), // 超過=4（最も昔）
            ReviewItemState(id: idC, box: 1, lastSeenStep: 2, addedAtStep: 1)  // 超過=3
        ]
        let picked = ReviewQueue.selectForInjection(states, currentStep: 5, cap: 3)
        XCTAssertEqual(picked.map(\.id), [idB, idC, idA])
    }

    func testOrdersByOverdueNormalizedByBoxNotRawAge() {
        // 素の経過では Y(box4, 6ステップ前)が X(box1, 3ステップ前)より昔だが、
        // 自分の予定からの超過では X(超過 10-7-1=2) > Y(超過 10-4-5=1)。未定着の低boxを優先。
        let states = [
            ReviewItemState(id: idX, box: 4, lastSeenStep: 4, addedAtStep: 0), // 間隔5、超過=1
            ReviewItemState(id: idA, box: 1, lastSeenStep: 7, addedAtStep: 1)  // 間隔1、超過=2
        ]
        let picked = ReviewQueue.selectForInjection(states, currentStep: 10, cap: 2)
        XCTAssertEqual(picked.map(\.id), [idA, idX])
    }

    func testStableTieBreakByAddedAtThenID() {
        // 超過が同じ（同 lastSeenStep・同 box）なら addedAtStep の古い順。
        let states = [
            ReviewItemState(id: idB, box: 1, lastSeenStep: 1, addedAtStep: 2),
            ReviewItemState(id: idA, box: 1, lastSeenStep: 1, addedAtStep: 1)
        ]
        let picked = ReviewQueue.selectForInjection(states, currentStep: 5, cap: 2)
        XCTAssertEqual(picked.map(\.id), [idA, idB])
    }

    func testEmptyWhenNothingDue() {
        let states = [
            ReviewItemState(id: idA, box: 3, lastSeenStep: 5, addedAtStep: 0) // 間隔3、0ステップ後
        ]
        XCTAssertTrue(ReviewQueue.selectForInjection(states, currentStep: 5, cap: 2).isEmpty)
    }
}

// MARK: - composeRound（base + 復習注入の合成）

final class ReviewQueueComposeRoundTests: XCTestCase {
    func testAppendsDueReviewsAfterBaseUpToCap() {
        let base = [idX, idC] // 通常出題（順序維持）
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0), // due
            ReviewItemState(id: idB, box: 1, lastSeenStep: 0, addedAtStep: 1)  // due
        ]
        let round = ReviewQueue.composeRound(base: base, states: states, currentStep: 5, cap: 2)
        XCTAssertEqual(round.prefix(2).map { $0 }, base) // base が先・順序維持
        XCTAssertEqual(Set(round.dropFirst(2)), [idA, idB]) // 復習が後ろに追加
    }

    func testDoesNotDuplicateItemsAlreadyInBase() {
        // 復習対象 idA が base にも居るなら二重に足さない。cap は新規追加に効く。
        let base = [idA, idX]
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0), // due だが base に在
            ReviewItemState(id: idB, box: 1, lastSeenStep: 0, addedAtStep: 1)  // due・新規
        ]
        let round = ReviewQueue.composeRound(base: base, states: states, currentStep: 5, cap: 1)
        XCTAssertEqual(round, [idA, idX, idB]) // idA は重複せず、新規 idB のみ追加
    }

    func testCapZeroReturnsBaseOnly() {
        let base = [idX]
        let states = [ReviewItemState(id: idA, box: 1, lastSeenStep: 0, addedAtStep: 0)]
        XCTAssertEqual(ReviewQueue.composeRound(base: base, states: states, currentStep: 5, cap: 0), base)
    }

    func testNoDueReturnsBaseOnly() {
        let base = [idX, idC]
        let states = [ReviewItemState(id: idA, box: 3, lastSeenStep: 5, addedAtStep: 0)] // not due
        XCTAssertEqual(ReviewQueue.composeRound(base: base, states: states, currentStep: 5, cap: 2), base)
    }
}

// MARK: - activeCount（復習中＝未卒業の件数。親レポート用）

final class ReviewQueueActiveCountTests: XCTestCase {
    func testCountsOnlyNonMastered() {
        let states = [
            ReviewItemState(id: idA, box: 1, lastSeenStep: 9, addedAtStep: 9),   // 現役
            ReviewItemState(id: idB, box: 3, lastSeenStep: 8, addedAtStep: 0),   // 現役
            ReviewItemState(id: idC, box: 5, lastSeenStep: 0, addedAtStep: 0)    // 卒業（box5・間隔超過）
        ]
        XCTAssertEqual(ReviewQueue.activeCount(states, currentStep: 10), 2)
    }

    func testEmptyIsZero() {
        XCTAssertEqual(ReviewQueue.activeCount([], currentStep: 5), 0)
    }
}

// MARK: - pruneMastered（任意の掃除）

final class ReviewQueuePruneTests: XCTestCase {
    func testRemovesOnlyMastered() {
        let states = [
            ReviewItemState(id: idA, box: 5, lastSeenStep: 0, addedAtStep: 0),  // 卒業（間隔8超過）
            ReviewItemState(id: idB, box: 1, lastSeenStep: 9, addedAtStep: 9)   // 現役
        ]
        let out = ReviewQueue.pruneMastered(states, currentStep: 10)
        XCTAssertEqual(out.map(\.id), [idB])
    }
}

// MARK: - Codable（永続化）

final class ReviewQueueCodableTests: XCTestCase {
    func testRoundTrips() throws {
        let states = [
            ReviewItemState(id: idA, box: 3, lastSeenStep: 4, addedAtStep: 1),
            ReviewItemState(id: idB, box: 1, lastSeenStep: 7, addedAtStep: 7)
        ]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([ReviewItemState].self, from: data)
        XCTAssertEqual(decoded, states)
    }
}

// MARK: - 結合シナリオ（間違い→数ステップかけて卒業）

final class ReviewQueueScenarioTests: XCTestCase {
    /// 「1度正解で即消える」のではなく、数回の正解を経て段階的に卒業することを通しで確認。
    func testWrongItemGraduatesOverMultipleCorrectAnswers() {
        var states: [ReviewItemState] = []
        var step = 0

        // step0: 通常出題で idA を間違える → キュー入り（box1）
        states = ReviewQueue.apply(states, itemID: idA, correct: false, step: step)
        XCTAssertEqual(states.first?.box, 1)

        // 以後、due になるたび追加問題として出し、正解で box を上げていく。
        // box1→2→3→4→5 と上がり、5到達後の間隔超過で卒業。1回正解では消えない。
        var graduated = false
        for _ in 0..<40 {
            step += 1
            let due = ReviewQueue.selectForInjection(states, currentStep: step, cap: 2)
            for item in due {
                states = ReviewQueue.apply(states, itemID: item.id, correct: true, step: step)
            }
            states = ReviewQueue.pruneMastered(states, currentStep: step)
            if states.isEmpty { graduated = true; break }
        }
        XCTAssertTrue(graduated, "数ステップかけて卒業するはず")
        // 1回目の正解（step1付近）では卒業していないこと＝即消えしないことの担保。
    }

    func testOneCorrectDoesNotImmediatelyGraduate() {
        var states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0) // box1
        // 次のステップで1回だけ正解 → box2 になるだけ。まだキューに残る（即消えしない）。
        states = ReviewQueue.apply(states, itemID: idA, correct: true, step: 1)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].box, 2)
        XCTAssertFalse(ReviewQueue.isMastered(states[0], currentStep: 1))
    }
}

// MARK: - remove（項目をキューから外す＝卒業扱い）

final class ReviewQueueRemoveTests: XCTestCase {
    func testRemovesExistingItem() {
        var states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        states = ReviewQueue.apply(states, itemID: idB, correct: false, step: 0)
        let out = ReviewQueue.remove(states, itemID: idA)
        XCTAssertEqual(out.map(\.id), [idB])
    }

    func testRemoveAbsentItemIsNoOp() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let out = ReviewQueue.remove(states, itemID: idX)
        XCTAssertEqual(out, states)
    }

    func testRemoveIsIdempotent() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let once = ReviewQueue.remove(states, itemID: idA)
        let twice = ReviewQueue.remove(once, itemID: idA)
        XCTAssertTrue(once.isEmpty)
        XCTAssertEqual(once, twice)
    }
}

// MARK: - applyParentReview（親採点の反映：set-like・冪等）

final class ReviewQueueParentReviewTests: XCTestCase {
    // 直そう → box1 で登録（未登録時）
    func testNeedsPracticeEnrollsAtBoxOne() {
        let out = ReviewQueue.applyParentReview([], itemID: idA, decision: .needsPractice, step: 4)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, idA)
        XCTAssertEqual(out[0].box, SRSScheduler.minBox)
        XCTAssertEqual(out[0].lastSeenStep, 4)
    }

    // 直そう → 登録済みでも box1 にリセット（set-like：何回・どのステップで呼んでも box1 に収束）
    func testNeedsPracticeResetsToBoxOneRegardlessOfHistory() {
        // box を上げておく
        var states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        states = ReviewQueue.apply(states, itemID: idA, correct: true, step: 1) // box2
        states = ReviewQueue.apply(states, itemID: idA, correct: true, step: 2) // box3
        let out = ReviewQueue.applyParentReview(states, itemID: idA, decision: .needsPractice, step: 5)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].box, SRSScheduler.minBox)
        XCTAssertEqual(out[0].lastSeenStep, 5)
    }

    // OK → キューから削除（卒業扱い）
    func testApprovedRemovesFromQueue() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let out = ReviewQueue.applyParentReview(states, itemID: idA, decision: .approved, step: 3)
        XCTAssertTrue(out.isEmpty)
    }

    // OK → 未登録なら何もしない
    func testApprovedOnAbsentItemIsNoOp() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let out = ReviewQueue.applyParentReview(states, itemID: idX, decision: .approved, step: 3)
        XCTAssertEqual(out, states)
    }

    // 未採点 → 何もしない
    func testUnreviewedIsNoOp() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let out = ReviewQueue.applyParentReview(states, itemID: idA, decision: .unreviewed, step: 3)
        XCTAssertEqual(out, states)
    }

    // 冪等：同じ判定を同一ステップで2回反映しても結果は変わらない（OK＝削除）
    func testApprovedIsIdempotent() {
        let states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        let once = ReviewQueue.applyParentReview(states, itemID: idA, decision: .approved, step: 3)
        let twice = ReviewQueue.applyParentReview(once, itemID: idA, decision: .approved, step: 3)
        XCTAssertEqual(once, twice)
    }

    // 冪等：直そうを同一ステップで2回反映しても box は多重に上がらない（box1 のまま）
    func testNeedsPracticeSameStepDoesNotMultiClimb() {
        let once = ReviewQueue.applyParentReview([], itemID: idA, decision: .needsPractice, step: 3)
        let twice = ReviewQueue.applyParentReview(once, itemID: idA, decision: .needsPractice, step: 3)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice[0].box, SRSScheduler.minBox)
    }

    // トグル収束：OK→直そう→OK は最終 OK の状態（削除）に収束する
    func testToggleConvergesToLastDecision() {
        var states = ReviewQueue.apply([], itemID: idA, correct: false, step: 0)
        states = ReviewQueue.applyParentReview(states, itemID: idA, decision: .approved, step: 1)     // 削除
        states = ReviewQueue.applyParentReview(states, itemID: idA, decision: .needsPractice, step: 2) // box1 で復活
        states = ReviewQueue.applyParentReview(states, itemID: idA, decision: .approved, step: 3)     // 再度削除
        XCTAssertTrue(states.isEmpty)
    }
}
