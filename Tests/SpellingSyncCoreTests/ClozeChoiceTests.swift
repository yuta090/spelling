import XCTest
@testable import SpellingSyncCore

private func item(_ en: String, _ ja: String, tokens: [String]) -> SentenceItem {
    SentenceItem(en: en, ja: ja, tokens: tokens, gradeBand: 1)
}

final class ClozeChoiceGeneratorTests: XCTestCase {
    func testBlanksGivenIndexAndIncludesAnswer() throws {
        let i = item("I like apples", "りんごが すき", tokens: ["I", "like", "apples"])
        let ex = try XCTUnwrap(ClozeChoiceGenerator.make(
            from: i, distractors: ["likes", "liked", "want"], blankIndex: 1, optionCount: 4, seed: 1))
        XCTAssertEqual(ex.answer, "like")
        XCTAssertEqual(ex.blankIndex, 1)
        XCTAssertEqual(ex.displayTokens, i.tokens)
        XCTAssertEqual(ex.prompt, i.ja)
        XCTAssertTrue(ex.options.contains("like"))
        XCTAssertEqual(ex.options.count, 4)
        XCTAssertTrue(Set(ex.options).isSubset(of: Set(["like", "likes", "liked", "want"])))
    }

    func testDeterministicForSameSeed() {
        let i = item("I like apples", "x", tokens: ["I", "like", "apples"])
        XCTAssertEqual(
            ClozeChoiceGenerator.make(from: i, distractors: ["likes", "liked", "want"], blankIndex: 1, seed: 9),
            ClozeChoiceGenerator.make(from: i, distractors: ["likes", "liked", "want"], blankIndex: 1, seed: 9)
        )
    }

    func testExcludesAnswerAndDuplicateDistractors() throws {
        let i = item("I like apples", "x", tokens: ["I", "like", "apples"])
        let ex = try XCTUnwrap(ClozeChoiceGenerator.make(
            from: i, distractors: ["like", "likes", "likes", "liked"], blankIndex: 1, optionCount: 4, seed: 2))
        XCTAssertEqual(ex.options.filter { $0 == "like" }.count, 1)   // 正解は1つだけ
        XCTAssertEqual(ex.options.count, Set(ex.options).count)        // 重複なし
    }

    func testCapsToOptionCount() throws {
        let i = item("a b c", "x", tokens: ["a", "b", "c"])
        let ex = try XCTUnwrap(ClozeChoiceGenerator.make(
            from: i, distractors: ["d", "e", "f", "g", "h"], blankIndex: 0, optionCount: 3, seed: 5))
        XCTAssertEqual(ex.options.count, 3)
        XCTAssertTrue(ex.options.contains("a"))
    }

    func testNilWhenNoUsableDistractors() {
        // 正解だけでは選択肢にならない。
        let i = item("a b", "x", tokens: ["a", "b"])
        XCTAssertNil(ClozeChoiceGenerator.make(from: i, distractors: [], blankIndex: 0, seed: 1))
        XCTAssertNil(ClozeChoiceGenerator.make(from: i, distractors: ["a"], blankIndex: 0, seed: 1)) // 正解と同じだけ
    }

    func testNilForEmptyTokensOrBadIndex() {
        XCTAssertNil(ClozeChoiceGenerator.make(
            from: item("", "", tokens: []), distractors: ["x"], blankIndex: 0, seed: 1))
        XCTAssertNil(ClozeChoiceGenerator.make(
            from: item("a", "x", tokens: ["a"]), distractors: ["b"], blankIndex: 5, seed: 1))
    }

    func testDefaultBlankIndexIsDeterministic() {
        let i = item("I like apples", "x", tokens: ["I", "like", "apples"])
        let a = ClozeChoiceGenerator.make(from: i, distractors: ["x", "y", "z"], seed: 3)
        let b = ClozeChoiceGenerator.make(from: i, distractors: ["x", "y", "z"], seed: 3)
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.blankIndex, b?.blankIndex)
    }

    func testNilForNegativeBlankIndex() {
        let i = item("a b", "x", tokens: ["a", "b"])
        XCTAssertNil(ClozeChoiceGenerator.make(from: i, distractors: ["c"], blankIndex: -1, seed: 1))
    }

    func testOptionCountBelowTwoStillYieldsTwo() throws {
        // optionCount<2 でも最低2（正解＋おとり1）を保証。
        let i = item("a b", "x", tokens: ["a", "b"])
        let ex = try XCTUnwrap(ClozeChoiceGenerator.make(
            from: i, distractors: ["c", "d"], blankIndex: 0, optionCount: 1, seed: 1))
        XCTAssertEqual(ex.options.count, 2)
    }

    func testDefaultBlankIndexTieTakesFirstLongest() {
        // 同長の最長が複数なら最小 index。
        XCTAssertEqual(ClozeChoiceGenerator.defaultBlankIndex(["cat", "dog", "ok"]), 0)
    }
}

final class ClozeChoiceGraderTests: XCTestCase {
    func testCorrect() {
        XCTAssertTrue(ClozeChoiceGrader.grade(selected: "like", answer: "like").isCorrect)
    }
    func testIncorrect() {
        XCTAssertFalse(ClozeChoiceGrader.grade(selected: "liked", answer: "like").isCorrect)
    }
}
