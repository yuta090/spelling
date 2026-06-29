import XCTest
@testable import SpellingSyncCore

/// ことばパズルの文に出てくる「キャスト以外の名詞」を絵ヒント（SFシンボル）に対応づける
/// 純ロジックのテスト。描画は App 側、ここは「どの名詞が・どのアイコンで・どの順か」だけ。
final class PuzzleObjectIconResolverTests: XCTestCase {

    func testMatchesKnownNoun() {
        let icons = PuzzleObjectIconResolver.icons(in: ["The", "sun", "is", "hot."])
        XCTAssertEqual(icons.map(\.key), ["sun"])
        XCTAssertEqual(icons.first?.systemImage, "sun.max.fill")
    }

    func testIgnoresPunctuationAndCase() {
        // "Book," → book / 大文字や記号付きでも拾う
        let icons = PuzzleObjectIconResolver.icons(in: ["I", "read", "a", "Book,", "today."])
        XCTAssertEqual(icons.map(\.key), ["book"])
    }

    func testHandlesSimplePlural() {
        let icons = PuzzleObjectIconResolver.icons(in: ["Two", "books", "here."])
        XCTAssertEqual(icons.map(\.key), ["book"])
    }

    func testKeepsAppearanceOrderAndDeduplicatesBySymbol() {
        let icons = PuzzleObjectIconResolver.icons(in: ["sun", "book", "sun", "star"])
        XCTAssertEqual(icons.map(\.key), ["sun", "book", "star"])
    }

    func testRespectsLimit() {
        let icons = PuzzleObjectIconResolver.icons(in: ["sun", "book", "star", "car"], limit: 2)
        XCTAssertEqual(icons.count, 2)
        XCTAssertEqual(icons.map(\.key), ["sun", "book"])
    }

    func testNonPositiveLimitReturnsEmpty() {
        XCTAssertTrue(PuzzleObjectIconResolver.icons(in: ["sun"], limit: 0).isEmpty)
    }

    func testCastAnimalsAreNotObjects() {
        // cat/dog/bird/rabbit/turtle/fox はキャスト側（PuzzleCast）が担当。
        // 絵ヒント（オブジェクト）側では拾わない＝二重表示しない。
        let icons = PuzzleObjectIconResolver.icons(in: ["cat", "dog", "bird", "fox", "Sora", "Mei"])
        XCTAssertTrue(icons.isEmpty)
    }

    func testUnknownNounReturnsNothing() {
        XCTAssertTrue(PuzzleObjectIconResolver.icons(in: ["the", "happy", "zzz"]).isEmpty)
    }

    func testExcludingKeysSkipsThem() {
        // すでにキャスト等で出している語を除外できる。
        let icons = PuzzleObjectIconResolver.icons(in: ["sun", "book"], excluding: ["sun"])
        XCTAssertEqual(icons.map(\.key), ["book"])
    }
}
