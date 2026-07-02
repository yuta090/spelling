import XCTest
@testable import SpellingSyncCore

final class PracticeRoundPlannerTests: XCTestCase {
    func test_threeRounds_stagesAndStars() {
        let base = 0.30
        let r0 = PracticeRoundPlanner.progress(round: 0, totalRounds: 3, baseOpacity: base)
        let r1 = PracticeRoundPlanner.progress(round: 1, totalRounds: 3, baseOpacity: base)
        let r2 = PracticeRoundPlanner.progress(round: 2, totalRounds: 3, baseOpacity: base)

        XCTAssertEqual(r0.stage, .look)
        XCTAssertEqual(r1.stage, .trace)
        XCTAssertEqual(r2.stage, .memory)

        XCTAssertFalse(r0.isFinal)
        XCTAssertFalse(r1.isFinal)
        XCTAssertTrue(r2.isFinal)

        XCTAssertEqual(r0.starsFilled, 1)
        XCTAssertEqual(r1.starsFilled, 2)
        XCTAssertEqual(r2.starsFilled, 3)
        XCTAssertEqual(r0.totalStars, 3)
    }

    func test_opacity_decreasesEachRound_andStaysPositive() {
        let base = 0.30
        let o0 = PracticeRoundPlanner.progress(round: 0, totalRounds: 3, baseOpacity: base).guideStartOpacity
        let o1 = PracticeRoundPlanner.progress(round: 1, totalRounds: 3, baseOpacity: base).guideStartOpacity
        let o2 = PracticeRoundPlanner.progress(round: 2, totalRounds: 3, baseOpacity: base).guideStartOpacity

        XCTAssertEqual(o0, 0.30, accuracy: 1e-9)          // 最初はくっきり
        XCTAssertGreaterThan(o0, o1)
        XCTAssertGreaterThan(o1, o2)
        XCTAssertGreaterThan(o2, 0)                       // 最後の回も 0 で始めない（そこから UI が消す）
    }

    func test_singleRound_isFinalLookGuideFull() {
        let p = PracticeRoundPlanner.progress(round: 0, totalRounds: 1, baseOpacity: 0.30)
        XCTAssertTrue(p.isFinal)
        XCTAssertEqual(p.stage, .look)                    // 1回だけならお手本は出したまま
        XCTAssertEqual(p.guideStartOpacity, 0.30, accuracy: 1e-9)
        XCTAssertEqual(p.starsFilled, 1)
        XCTAssertEqual(p.totalStars, 1)
    }

    func test_outOfRangeRound_isClamped() {
        let p = PracticeRoundPlanner.progress(round: 99, totalRounds: 3, baseOpacity: 0.30)
        XCTAssertTrue(p.isFinal)
        XCTAssertEqual(p.stage, .memory)
        XCTAssertEqual(p.starsFilled, 3)
    }

    func test_zeroTotal_isSafe() {
        let p = PracticeRoundPlanner.progress(round: 0, totalRounds: 0, baseOpacity: 0.30)
        XCTAssertEqual(p.totalStars, 1)
        XCTAssertTrue(p.isFinal)
    }
}

final class PracticePraiseTests: XCTestCase {
    func test_phrase_cyclesByIndex() {
        XCTAssertEqual(PracticePraise.phrase(index: 0, japanese: true), PracticePraise.japanese[0])
        XCTAssertEqual(PracticePraise.phrase(index: 1, japanese: true), PracticePraise.japanese[1])
        // 剰余で巡回
        let n = PracticePraise.japanese.count
        XCTAssertEqual(PracticePraise.phrase(index: n, japanese: true), PracticePraise.japanese[0])
    }

    func test_phrase_negativeIndex_isSafe() {
        let n = PracticePraise.japanese.count
        XCTAssertEqual(PracticePraise.phrase(index: -1, japanese: true), PracticePraise.japanese[n - 1])
    }

    func test_phrase_englishPool() {
        XCTAssertEqual(PracticePraise.phrase(index: 0, japanese: false), PracticePraise.english[0])
    }

    // 採点完了などの「大きなごほうび表示」で飽きないよう、十分な数の言い回しを用意しておく。
    func test_pools_haveAtLeastTenPhrases() {
        XCTAssertGreaterThanOrEqual(PracticePraise.japanese.count, 10)
        XCTAssertGreaterThanOrEqual(PracticePraise.english.count, 10)
    }

    // 重複した言い回しがあると「ランダム感」が薄れるので、各プールはユニークにしておく。
    func test_pools_haveNoDuplicates() {
        XCTAssertEqual(Set(PracticePraise.japanese).count, PracticePraise.japanese.count)
        XCTAssertEqual(Set(PracticePraise.english).count, PracticePraise.english.count)
    }
}
