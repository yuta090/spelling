import XCTest
@testable import SpellingSyncCore

final class PuzzleFormatTests: XCTestCase {
    func testPlayablePoolIsTheFinishedFourFormats() {
        XCTAssertEqual(
            PuzzleFormat.playablePool,
            [.wordOrdering, .clozeChoice, .listeningCloze, .wordListening]
        )
    }

    func testHandwritingAndCompositionAreNotPlayableYet() {
        XCTAssertFalse(PuzzleFormat.clozeHandwriting.isPlayable)
        XCTAssertFalse(PuzzleFormat.composition.isPlayable)
    }

    func testOnlyWordListeningRequiresAudio() {
        XCTAssertTrue(PuzzleFormat.wordListening.requiresAudio)
        for f in [PuzzleFormat.wordOrdering, .clozeChoice, .listeningCloze] {
            XCTAssertFalse(f.requiresAudio)
        }
    }
}

final class PuzzleFormatSchedulerTests: XCTestCase {
    private let pool = PuzzleFormat.playablePool

    func testEmptyInputsProduceEmpty() {
        XCTAssertTrue(PuzzleFormatScheduler.schedule(pool: [], length: 5, seed: 1).isEmpty)
        XCTAssertTrue(PuzzleFormatScheduler.schedule(pool: pool, length: 0, seed: 1).isEmpty)
    }

    func testLengthRespected() {
        XCTAssertEqual(PuzzleFormatScheduler.schedule(pool: pool, length: 12, seed: 1).count, 12)
    }

    func testNoConsecutiveSameFormatWhenPoolHasMultiple() {
        let plan = PuzzleFormatScheduler.schedule(pool: pool, length: 20, seed: 7)
        for (a, b) in zip(plan, plan.dropFirst()) {
            XCTAssertNotEqual(a, b, "連続して同じ形式が出てはいけない")
        }
    }

    func testUsesOnlyFormatsFromPool() {
        let plan = PuzzleFormatScheduler.schedule(pool: pool, length: 30, seed: 3)
        XCTAssertTrue(plan.allSatisfy { pool.contains($0) })
    }

    func testAllPoolFormatsAppearWhenLongEnough() {
        let plan = PuzzleFormatScheduler.schedule(pool: pool, length: 16, seed: 5)
        XCTAssertEqual(Set(plan), Set(pool), "十分な長さなら全形式が登場する")
    }

    func testDeterministicForSameSeed() {
        XCTAssertEqual(
            PuzzleFormatScheduler.schedule(pool: pool, length: 12, seed: 42),
            PuzzleFormatScheduler.schedule(pool: pool, length: 12, seed: 42)
        )
    }

    func testDifferentSeedsCanDiffer() {
        let a = PuzzleFormatScheduler.schedule(pool: pool, length: 12, seed: 1)
        let b = PuzzleFormatScheduler.schedule(pool: pool, length: 12, seed: 999)
        XCTAssertNotEqual(a, b, "シードが違えば並びは変わりうる")
    }

    func testDuplicatePoolStillNeverConsecutive() {
        let plan = PuzzleFormatScheduler.schedule(
            pool: [.wordOrdering, .wordOrdering, .clozeChoice],
            length: 10, seed: 4)
        for (a, b) in zip(plan, plan.dropFirst()) {
            XCTAssertNotEqual(a, b)
        }
    }

    func testSinglePoolYieldsAllThatFormat() {
        let plan = PuzzleFormatScheduler.schedule(pool: [.clozeChoice], length: 5, seed: 1)
        XCTAssertEqual(plan, Array(repeating: .clozeChoice, count: 5))
    }
}
