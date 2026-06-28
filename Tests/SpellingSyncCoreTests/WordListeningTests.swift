import XCTest
@testable import SpellingSyncCore

final class WordListeningTests: XCTestCase {

    // MARK: 生成

    func testMakeBuildsOptionsWithAnswer() {
        let ex = WordListeningGenerator.make(
            word: "right", distractors: ["light", "night", "write"], optionCount: 4, seed: 7)
        XCTAssertNotNil(ex)
        XCTAssertEqual(ex?.answer, "right")
        XCTAssertEqual(ex?.word, "right")
        XCTAssertEqual(ex?.options.count, 4)
        XCTAssertEqual(ex.map { Set($0.options) }, ["right", "light", "night", "write"])
    }

    func testMakeExcludesAnswerAndDuplicatesFromDistractors() {
        let ex = WordListeningGenerator.make(
            word: "right", distractors: ["right", "light", "light", "night"], optionCount: 4, seed: 1)
        XCTAssertEqual(ex.map { Set($0.options) }, ["right", "light", "night"])
        XCTAssertEqual(ex?.options.count, 3)
    }

    func testMakeRespectsOptionCountCap() {
        let ex = WordListeningGenerator.make(
            word: "right", distractors: ["light", "night", "write", "bright", "kite"],
            optionCount: 3, seed: 1)
        XCTAssertEqual(ex?.options.count, 3)        // 正解＋おとり2
        XCTAssertTrue(ex?.options.contains("right") ?? false)
    }

    func testMakeReturnsNilWhenNoUsableDistractors() {
        XCTAssertNil(WordListeningGenerator.make(word: "right", distractors: [], optionCount: 4, seed: 1))
        XCTAssertNil(WordListeningGenerator.make(word: "right", distractors: ["right"], optionCount: 4, seed: 1))
    }

    func testMakeIsDeterministic() {
        let a = WordListeningGenerator.make(word: "ship", distractors: ["sheep", "shop", "chip"], optionCount: 4, seed: 99)
        let b = WordListeningGenerator.make(word: "ship", distractors: ["sheep", "shop", "chip"], optionCount: 4, seed: 99)
        XCTAssertEqual(a?.options, b?.options)
    }

    // MARK: 採点

    func testGrade() {
        XCTAssertTrue(WordListeningGrader.grade(selected: "right", answer: "right").isCorrect)
        XCTAssertFalse(WordListeningGrader.grade(selected: "light", answer: "right").isCorrect)
    }
}
