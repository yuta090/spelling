import XCTest
@testable import SpellingSyncCore

private func item(
    _ en: String,
    _ ja: String,
    tokens: [String],
    band: Int
) -> SentenceItem {
    SentenceItem(en: en, ja: ja, tokens: tokens, gradeBand: band)
}

// MARK: - 出題範囲（学年の壁＝絶対）

final class SentenceSelectionTests: XCTestCase {
    func testEligibleWhenBandWithinTarget() {
        let i = item("I go home.", "私は家に帰る。", tokens: ["I", "go", "home"], band: 2)
        XCTAssertTrue(SentenceSelection.isEligible(i, targetBand: 2))
        XCTAssertTrue(SentenceSelection.isEligible(i, targetBand: 3))
    }

    func testIneligibleWhenBandExceedsTarget() {
        let i = item("I go home.", "私は家に帰る。", tokens: ["I", "go", "home"], band: 4)
        XCTAssertFalse(SentenceSelection.isEligible(i, targetBand: 3))
    }

    func testEligibleFiltersAndPreservesOrder() {
        let items = [
            item("a", "a", tokens: ["a"], band: 1),
            item("b", "b", tokens: ["b"], band: 5),
            item("c", "c", tokens: ["c"], band: 2)
        ]
        let kept = SentenceSelection.eligible(items, targetBand: 2)
        XCTAssertEqual(kept.map(\.en), ["a", "c"])
    }
}

// MARK: - 決定的シャッフル

final class SeededShuffleTests: XCTestCase {
    func testIsPermutationOfInput() {
        let input = Array(0..<10)
        let out = SeededShuffle.shuffle(input, seed: 42)
        XCTAssertEqual(out.sorted(), input)
    }

    func testDeterministicForSameSeed() {
        let input = Array(0..<10)
        XCTAssertEqual(SeededShuffle.shuffle(input, seed: 7), SeededShuffle.shuffle(input, seed: 7))
    }

    func testDifferentSeedsCanDiffer() {
        let input = Array(0..<20)
        XCTAssertNotEqual(SeededShuffle.shuffle(input, seed: 1), SeededShuffle.shuffle(input, seed: 999))
    }

    func testHandlesEmptyAndSingle() {
        XCTAssertEqual(SeededShuffle.shuffle([Int](), seed: 1), [])
        XCTAssertEqual(SeededShuffle.shuffle([5], seed: 1), [5])
    }
}

// MARK: - 並べ替え生成

final class WordOrderingGeneratorTests: XCTestCase {
    func testTilesAreAPermutationOfTokens() throws {
        let i = item("I go home", "私は家に帰る", tokens: ["I", "go", "home"], band: 1)
        let ex = try XCTUnwrap(WordOrderingGenerator.make(from: i, seed: 3))
        XCTAssertEqual(ex.scrambledTiles.map(\.text).sorted(), i.tokens.sorted())
        XCTAssertEqual(ex.answer, i.tokens)
        XCTAssertEqual(ex.prompt, i.ja)
        XCTAssertEqual(ex.itemID, i.id)
    }

    func testTileIDsAreStableAndDistinctEvenWithDuplicateWords() throws {
        // 重複語（the が2回）でもタイルは id で区別できる。
        let i = item("the cat and the dog", "ねこといぬ",
                     tokens: ["the", "cat", "and", "the", "dog"], band: 1)
        let ex = try XCTUnwrap(WordOrderingGenerator.make(from: i, seed: 11))
        XCTAssertEqual(Set(ex.scrambledTiles.map(\.id)).count, 5)
    }

    func testDoesNotReturnAlreadySolvedOrderForMultiToken() throws {
        // 並べ替えなのに最初から正解順だと問題にならない。多語では別の順を返す。
        let i = item("I go home", "私は家に帰る", tokens: ["I", "go", "home"], band: 1)
        let ex = try XCTUnwrap(WordOrderingGenerator.make(from: i, seed: 0))
        XCTAssertNotEqual(ex.scrambledTiles.map(\.text), i.tokens)
    }

    func testDeterministicForSameSeed() {
        let i = item("one two three four", "一二三四",
                     tokens: ["one", "two", "three", "four"], band: 1)
        XCTAssertEqual(
            WordOrderingGenerator.make(from: i, seed: 5),
            WordOrderingGenerator.make(from: i, seed: 5)
        )
    }

    func testReturnsNilForNonScramblableTokens() {
        // 全同一・単語1個・空は並べ替え問題として成立しない → nil。
        XCTAssertNil(WordOrderingGenerator.make(
            from: item("the the", "ザ・ザ", tokens: ["the", "the"], band: 1), seed: 1))
        XCTAssertNil(WordOrderingGenerator.make(
            from: item("go", "行け", tokens: ["go"], band: 1), seed: 1))
        XCTAssertNil(WordOrderingGenerator.make(
            from: item("", "", tokens: [], band: 1), seed: 1))
    }

    func testIsScramblableReflectsDistinctTokenCount() {
        XCTAssertTrue(item("a b", "", tokens: ["a", "b"], band: 1).isScramblable)
        XCTAssertFalse(item("a a", "", tokens: ["a", "a"], band: 1).isScramblable)
    }
}

// MARK: - 並べ替え採点

final class WordOrderingGraderTests: XCTestCase {
    func testExactMatchIsCorrect() {
        let g = WordOrderingGrader.grade(submitted: ["I", "go", "home"], answer: ["I", "go", "home"])
        XCTAssertTrue(g.isCorrect)
        XCTAssertEqual(g.correctPositions, 3)
        XCTAssertEqual(g.total, 3)
    }

    func testWrongOrderGivesPartialCredit() {
        // 先頭は合っているが残り2語が入れ替わり。
        let g = WordOrderingGrader.grade(submitted: ["I", "home", "go"], answer: ["I", "go", "home"])
        XCTAssertFalse(g.isCorrect)
        XCTAssertEqual(g.correctPositions, 1)
        XCTAssertEqual(g.total, 3)
    }

    func testCompletelyWrongIsZero() {
        // 全位置で不一致な並び（逆順だと中央が残るので、ずらして全外しにする）。
        let g = WordOrderingGrader.grade(submitted: ["go", "home", "I"], answer: ["I", "go", "home"])
        XCTAssertFalse(g.isCorrect)
        XCTAssertEqual(g.correctPositions, 0)
    }

    func testShorterSubmissionIsNotCorrect() {
        let g = WordOrderingGrader.grade(submitted: ["I", "go"], answer: ["I", "go", "home"])
        XCTAssertFalse(g.isCorrect)
        XCTAssertEqual(g.correctPositions, 2)
        XCTAssertEqual(g.total, 3)
    }

    func testLongerSubmissionIsNotFullCredit() {
        // 余剰トークンを足しても満点にならない（total は長い方を採用）。
        let g = WordOrderingGrader.grade(submitted: ["I", "go", "home", "x"], answer: ["I", "go", "home"])
        XCTAssertFalse(g.isCorrect)
        XCTAssertEqual(g.correctPositions, 3)
        XCTAssertEqual(g.total, 4)
    }
}
