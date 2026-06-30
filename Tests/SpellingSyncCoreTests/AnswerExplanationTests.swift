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
        XCTAssertNil(result.headline)   // ぶんづくりは文法見出しを出さない
        XCTAssertTrue(result.chips.isEmpty)
    }

    // ぶんづくりの不正解は「文法タグ」ではなく「正しい並び（構文）」で教える。
    // 文法タグの解説（detail）と見出し（headline）は語順とズレるため出さず、
    // 正解文＋意味＋ならびかたヒント（orderHint）を出す。
    func testIncorrectAnswerShowsOrderHintNotGrammar() {
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
        XCTAssertNil(result.detail)    // 文法タグ解説は出さない
        XCTAssertNil(result.headline)  // 文法見出しも出さない
        XCTAssertEqual(result.correctText, "This is a pen.")
        XCTAssertEqual(result.meaningJa, "これはペンです。")
        XCTAssertEqual(result.orderHint, "This → is → a → pen のじゅんばん")
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
        XCTAssertEqual(result.orderHint, "Hello → world のじゅんばん")
    }

    // 正解時はならびかたヒントを出さない（できたね！＋意味だけ）。
    func testCorrectAnswerHasNoOrderHint() {
        let item = SentenceItem(
            en: "This is a pen.",
            ja: "これはペンです。",
            tokens: ["This", "is", "a", "pen."],
            gradeBand: 1,
            grammar: .beVerb
        )
        let grade = OrderingGrade(isCorrect: true, correctPositions: 4, total: 4)
        let result = SentenceFeedback.make(item: item, submitted: ["This", "is", "a", "pen."], grade: grade)
        XCTAssertNil(result.orderHint)
    }

    // MARK: - orderHint 純関数

    func testOrderHintJoinsWordsWithArrows() {
        XCTAssertEqual(SentenceFeedback.orderHint(["Yes", "I", "can."]), "Yes → I → can のじゅんばん")
    }

    func testOrderHintStripsEdgePunctuationButKeepsApostrophe() {
        XCTAssertEqual(SentenceFeedback.orderHint(["I'm", "happy!"]), "I'm → happy のじゅんばん")
    }

    func testOrderHintDropsPunctuationOnlyTokens() {
        XCTAssertEqual(SentenceFeedback.orderHint(["Look", "!", "Run."]), "Look → Run のじゅんばん")
    }

    func testOrderHintNilForSingleWord() {
        XCTAssertNil(SentenceFeedback.orderHint(["Run."]))
        XCTAssertNil(SentenceFeedback.orderHint([]))
        XCTAssertNil(SentenceFeedback.orderHint([".", "!"]))
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
