import XCTest
@testable import SpellingSyncCore

final class AnswerExplanationTests: XCTestCase {
    func testCorrectAnswer() {
        let item = SentenceItem(
            en: "This is a pen.",
            ja: "これはペンです。",
            tokens: ["This", "is", "a", "pen."],
            gradeBand: 1,
            grammar: .beVerb
        )
        let grade = OrderingGrade(isCorrect: true, correctPositions: 4, total: 4)
        let result = SentenceFeedback.make(item: item, submitted: ["This", "is", "a", "pen."], grade: grade)

        XCTAssertEqual(result.wasCorrect, true)
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.correctText, "This is a pen.")
        XCTAssertEqual(result.meaningJa, "これはペンです。")
        XCTAssertEqual(result.headline, GrammarPoint.beVerb.titleJa)
        XCTAssertTrue(result.chips.isEmpty)
    }

    func testIncorrectAnswerWithGrammar() {
        let item = SentenceItem(
            en: "This is a pen.",
            ja: "これはペンです。",
            tokens: ["This", "is", "a", "pen."],
            gradeBand: 1,
            grammar: .beVerb
        )
        let grade = OrderingGrade(isCorrect: false, correctPositions: 2, total: 4)
        let result = SentenceFeedback.make(item: item, submitted: ["is", "This", "a", "pen."], grade: grade)

        XCTAssertEqual(result.wasCorrect, false)
        XCTAssertEqual(result.detail, GrammarPoint.beVerb.explanationJa)
        XCTAssertEqual(result.headline, GrammarPoint.beVerb.titleJa)
        XCTAssertEqual(result.correctText, "This is a pen.")
        XCTAssertEqual(result.meaningJa, "これはペンです。")
    }

    func testIncorrectAnswerWithoutGrammar() {
        let item = SentenceItem(
            en: "Hello world.",
            ja: "こんにちは世界。",
            tokens: ["Hello", "world."],
            gradeBand: 1,
            grammar: nil
        )
        let grade = OrderingGrade(isCorrect: false, correctPositions: 0, total: 2)
        let result = SentenceFeedback.make(item: item, submitted: ["world.", "Hello"], grade: grade)

        XCTAssertEqual(result.wasCorrect, false)
        XCTAssertNil(result.headline)
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.correctText, "Hello world.")
        XCTAssertEqual(result.meaningJa, "こんにちは世界。")
    }

    func testSingleTokenSentence() {
        let item = SentenceItem(
            en: "Run.",
            ja: "走れ。",
            tokens: ["Run."],
            gradeBand: 1,
            grammar: .imperative
        )
        let grade = OrderingGrade(isCorrect: true, correctPositions: 1, total: 1)
        let result = SentenceFeedback.make(item: item, submitted: ["Run."], grade: grade)

        XCTAssertEqual(result.wasCorrect, true)
        XCTAssertEqual(result.correctText, "Run.")
        XCTAssertNil(result.detail)
    }

    func testEmptyTokensGivesNilCorrectText() {
        let item = SentenceItem(
            en: "",
            ja: "",
            tokens: [],
            gradeBand: 1,
            grammar: nil
        )
        let grade = OrderingGrade(isCorrect: false, correctPositions: 0, total: 0)
        let result = SentenceFeedback.make(item: item, submitted: [], grade: grade)

        XCTAssertNil(result.correctText)
    }
}
