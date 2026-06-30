import XCTest
@testable import SpellingSyncCore

/// おぼえる練習（手書きの前・タップで選ぶ）1問を組む純ロジックのテスト。
///
/// - 品詞が分かり英文フレームに載る語 → `frame != nil`（文＋空所＋4択）。
/// - 載らない語（品詞不明 等） → `frame == nil`（意味＋綴り4択）。
/// - どちらも options は「正解＋おとり・決定論シャッフル」。正解の綴りは不変。
final class MemorizeChoiceBuilderTests: XCTestCase {

    private func noun(_ t: String) -> RegisteredWord {
        RegisteredWord(stableID: t, text: t, partOfSpeech: "noun")
    }
    private func verb(_ t: String) -> RegisteredWord {
        RegisteredWord(stableID: t, text: t, partOfSpeech: "verb")
    }
    private func adj(_ t: String) -> RegisteredWord {
        RegisteredWord(stableID: t, text: t, partOfSpeech: "adjective")
    }
    private func unknown(_ t: String) -> RegisteredWord {
        RegisteredWord(stableID: t, text: t, partOfSpeech: nil)
    }

    // MARK: - 不変条件（どちらの形でも）

    func testAnswerIsAlwaysAmongOptions() {
        for w in [noun("apple"), verb("run"), adj("happy"), unknown("queue")] {
            let p = MemorizeChoiceBuilder.make(word: w, seed: 1)
            XCTAssertTrue(p.options.contains(w.text), "\(w.text) の正解が選択肢に無い")
            XCTAssertEqual(p.answer, w.text)
        }
    }

    func testOptionsAreUnique() {
        let p = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 7)
        XCTAssertEqual(Set(p.options).count, p.options.count, "選択肢に重複: \(p.options)")
    }

    func testOptionCountIsRespected() {
        let p = MemorizeChoiceBuilder.make(word: noun("apple"), optionCount: 4, seed: 3)
        XCTAssertLessThanOrEqual(p.options.count, 4)
        XCTAssertGreaterThanOrEqual(p.options.count, 2, "りんごなら正解＋おとりで4択になるはず")
    }

    func testAnswerSpellingIsExact() {
        let p = MemorizeChoiceBuilder.make(word: noun("foxes"), seed: 9)
        XCTAssertEqual(p.answer, "foxes")
        XCTAssertTrue(p.options.contains("foxes"))
        if let f = p.frame {
            XCTAssertEqual(f.displayTokens[f.blankIndex], StarterSpellingFrames.slotToken,
                           "空所は埋めずプレースホルダのまま出す")
        }
    }

    func testIsDeterministic() {
        let a = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 42)
        let b = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 42)
        XCTAssertEqual(a, b)
    }

    func testIsCorrectGrades() {
        let p = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 1)
        XCTAssertTrue(p.isCorrect("apple"))
        XCTAssertFalse(p.isCorrect("aple"))
    }

    // MARK: - フレーム選択（品詞）

    func testNounGetsNounFrame() {
        let p = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 1)
        let f = try? XCTUnwrap(p.frame)
        XCTAssertNotNil(f, "名詞は英文フレームに載るはず")
        if let f {
            XCTAssertEqual(f.displayTokens[f.blankIndex], StarterSpellingFrames.slotToken)
            // 名詞フレームは "like" 文（I like ___ / Do you like ___）
            XCTAssertTrue(f.displayTokens.contains("like"), "名詞フレームのトークン: \(f.displayTokens)")
        }
    }

    func testVerbGetsVerbFrame() {
        let p = MemorizeChoiceBuilder.make(word: verb("run"), seed: 1)
        XCTAssertNotNil(p.frame, "動詞は英文フレームに載るはず")
    }

    func testAdjectiveGetsAdjectiveFrame() {
        let p = MemorizeChoiceBuilder.make(word: adj("happy"), seed: 1)
        let f = p.frame
        XCTAssertNotNil(f, "形容詞は英文フレームに載るはず")
        // be 動詞フレーム（It is / I am / You are）のどれか
        if let f { XCTAssertTrue(f.displayTokens.contains("is") || f.displayTokens.contains("am") || f.displayTokens.contains("are")) }
    }

    func testUnknownPOSFallsBackToStandalone() {
        let p = MemorizeChoiceBuilder.make(word: unknown("apple"), seed: 1)
        XCTAssertNil(p.frame, "品詞不明はフレームに載せず意味＋4択にフォールバック")
        XCTAssertTrue(p.options.contains("apple"))
    }

    // MARK: - 退化ケース（クラッシュさせない）

    func testNonAsciiWordDoesNotCrashAndIsStandalone() {
        let p = MemorizeChoiceBuilder.make(word: unknown("café"), seed: 1)
        XCTAssertEqual(p.answer, "café")
        XCTAssertTrue(p.options.contains("café"))
        XCTAssertNil(p.frame)
    }

    func testVeryShortWordStillReturnsAnswer() {
        let p = MemorizeChoiceBuilder.make(word: unknown("a"), seed: 1)
        XCTAssertEqual(p.answer, "a")
        XCTAssertTrue(p.options.contains("a"))
    }

    func testDistractorsActuallyDifferFromAnswerWhenPossible() {
        let p = MemorizeChoiceBuilder.make(word: noun("apple"), seed: 5)
        let wrong = p.options.filter { $0 != "apple" }
        XCTAssertFalse(wrong.isEmpty, "りんごなら必ずおとりが作れる")
    }
}
