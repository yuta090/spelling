import XCTest
@testable import SpellingSyncCore

/// 文 → 登場キャスト（最大3体・出現順・重複なし）を決める純ロジックのテスト。
final class PuzzleCastResolverTests: XCTestCase {

    private func tokens(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    func testSingleAnimal() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("The cat is sleeping")), [.cat])
    }

    func testTwoNamedKeepsAppearanceOrder() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("Mei can help Sora")), [.mei, .sora])
    }

    func testPluralsAndTrailingPunctuation() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("Do you like dogs?")), [.dog])
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("Two rabbits jump in the park")), [.rabbit])
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("Are you sleepy, Sora?")), [.sora])
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("Can a fox jump high?")), [.fox])
    }

    func testNoCastReturnsEmpty() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("I am very happy")), [])
    }

    func testDeduplicates() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("The cat sees the cat")), [.cat])
    }

    func testCapsAtThreeInOrder() {
        let r = PuzzleCastResolver.cast(in: tokens("Sora Mei cat dog fox"))
        XCTAssertEqual(r, [.sora, .mei, .cat])
    }

    func testCustomLimit() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("cat dog fox"), limit: 2), [.cat, .dog])
    }

    func testNonPositiveLimitReturnsEmpty() {
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("cat dog"), limit: 0), [])
        XCTAssertEqual(PuzzleCastResolver.cast(in: tokens("cat dog"), limit: -1), [])
    }

    func testFromSentenceItem() {
        let item = SentenceItem(en: "The fox is running now", ja: "きつねが はしっている",
                                tokens: tokens("The fox is running now"),
                                gradeBand: 2, contentLemmas: ["fox", "run"], grammar: nil,
                                sourceID: nil, genre: nil)
        XCTAssertEqual(PuzzleCastResolver.cast(for: item), [.fox])
    }

    func testIsChildFlag() {
        XCTAssertTrue(PuzzleCast.sora.isChild)
        XCTAssertTrue(PuzzleCast.mei.isChild)
        XCTAssertFalse(PuzzleCast.turtle.isChild)
    }
}
