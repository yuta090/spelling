import XCTest
@testable import SpellingSyncCore

/// テスト直後の「その場採点 → そのまま復習」で使う純ロジック。
/// 芯は「親が『直そう』にした単語だけを、出題順のまま・重複なしで子の復習に渡す」こと。
final class SessionGradingTests: XCTestCase {

    private func item(_ word: String, _ decision: ParentReviewState) -> SessionGrading.GradedItem {
        SessionGrading.GradedItem(word: word, decision: decision)
    }

    func test_empty_returnsEmpty() {
        XCTAssertEqual(SessionGrading.wordsNeedingPractice([]), [])
    }

    func test_allApproved_returnsEmpty() {
        let items = [item("cat", .approved), item("dog", .approved)]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), [])
    }

    func test_onlyNeedsPractice_areReturned() {
        let items = [item("cat", .approved), item("dog", .needsPractice), item("sun", .approved)]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), ["dog"])
    }

    func test_unreviewed_isNotReturned() {
        // 未採点（デフォルトOK扱い）は復習に回さない。復習は親が明示的に「直そう」にした語だけ。
        let items = [item("cat", .unreviewed), item("dog", .needsPractice)]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), ["dog"])
    }

    func test_preservesQuestionOrder() {
        let items = [
            item("sun", .needsPractice),
            item("cat", .approved),
            item("dog", .needsPractice)
        ]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), ["sun", "dog"])
    }

    func test_dedupesSameWord_keepingFirstSpelling() {
        // 同じ単語が複数回出て、どれか1つでも「直そう」なら1回だけ復習に出す（最初の綴りを保つ）。
        let items = [
            item("Cat", .approved),
            item("cat", .needsPractice),
            item("cat", .needsPractice)
        ]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), ["Cat"])
    }

    func test_caseInsensitiveDedupe_acrossDifferentDecisions() {
        // 大文字小文字違いは同じ単語。1つでも needsPractice なら復習対象。
        let items = [item("Sun", .approved), item("sun", .needsPractice)]
        XCTAssertEqual(SessionGrading.wordsNeedingPractice(items), ["Sun"])
    }

    // MARK: - summarize（採点後の「何問中何問せいかい」＋復習単語）

    func test_summarize_empty() {
        let s = SessionGrading.summarize([])
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.correctCount, 0)
        XCTAssertEqual(s.needsPractice, [])
    }

    func test_summarize_allApproved_allCorrect() {
        let s = SessionGrading.summarize([item("cat", .approved), item("dog", .approved)])
        XCTAssertEqual(s.total, 2)
        XCTAssertEqual(s.correctCount, 2)
        XCTAssertEqual(s.needsPractice, [])
    }

    func test_summarize_mixed_countsAndOrder() {
        // 3語中 cat=OK / dog=直そう / sun=直そう → 正解1、復習は出題順（dog, sun）。
        let items = [item("cat", .approved), item("dog", .needsPractice), item("sun", .needsPractice)]
        let s = SessionGrading.summarize(items)
        XCTAssertEqual(s.total, 3)
        XCTAssertEqual(s.correctCount, 1)
        XCTAssertEqual(s.needsPractice, ["dog", "sun"])
    }

    func test_summarize_dedupesSameWord() {
        // 同じ単語が複数回でも1問として数える。1つでも直そうなら不正解（復習対象）。
        let items = [item("Cat", .approved), item("cat", .needsPractice)]
        let s = SessionGrading.summarize(items)
        XCTAssertEqual(s.total, 1)
        XCTAssertEqual(s.correctCount, 0)
        XCTAssertEqual(s.needsPractice, ["Cat"])
    }

    func test_summarize_unreviewedCountsAsCorrect() {
        // 未採点（デフォルトOK扱い）は正解に数える＝復習には回さない。
        let s = SessionGrading.summarize([item("cat", .unreviewed), item("dog", .approved)])
        XCTAssertEqual(s.total, 2)
        XCTAssertEqual(s.correctCount, 2)
        XCTAssertEqual(s.needsPractice, [])
    }

    func test_summarize_correctPlusNeedsPractice_equalsTotal() {
        // 不変条件: correctCount + needsPractice.count == total（重複排除後）。
        let items = [
            item("a", .approved), item("A", .needsPractice),
            item("b", .approved),
            item("c", .needsPractice),
            item("d", .unreviewed)
        ]
        let s = SessionGrading.summarize(items)
        XCTAssertEqual(s.correctCount + s.needsPractice.count, s.total)
    }
}
