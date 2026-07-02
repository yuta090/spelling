import XCTest
@testable import SpellingSyncCore

/// `CastNameHighlighter.segments` — 例文中のなかま名の出現箇所を分割する純ロジック。
/// 親側プレビューで「名前が問題に入る」ことを色付きで見せるための土台。
final class CastNameHighlighterTests: XCTestCase {

    private func joined(_ segments: [CastNameHighlighter.Segment]) -> String {
        segments.map(\.text).joined()
    }

    func testEnglishNameIsSegmented() {
        let segments = CastNameHighlighter.segments(in: "Yuki likes apples.", names: ["Yuki"])
        XCTAssertEqual(segments, [
            .init(text: "Yuki", isName: true),
            .init(text: " likes apples.", isName: false),
        ])
    }

    func testPossessiveKeepsNamePartOnly() {
        let segments = CastNameHighlighter.segments(in: "This is Yuki's bag.", names: ["Yuki"])
        XCTAssertEqual(segments, [
            .init(text: "This is ", isName: false),
            .init(text: "Yuki", isName: true),
            .init(text: "'s bag.", isName: false),
        ])
    }

    func testEnglishWordBoundaryPreventsPartialMatch() {
        // "Ken" は "Kendama" の中でマッチしない（前後が英字なら名前ではない）。
        let segments = CastNameHighlighter.segments(in: "Kendama is fun.", names: ["Ken"])
        XCTAssertEqual(segments, [.init(text: "Kendama is fun.", isName: false)])
    }

    func testJapaneseNameIsSegmented() {
        // 日本語はスペースが無いので単純な出現箇所で分割する（助詞が続いてよい）。
        let segments = CastNameHighlighter.segments(in: "ゆきはりんごがすき。", names: ["ゆき"])
        XCTAssertEqual(segments, [
            .init(text: "ゆき", isName: true),
            .init(text: "はりんごがすき。", isName: false),
        ])
    }

    func testMultipleNamesAndOccurrences() {
        let segments = CastNameHighlighter.segments(in: "Yuki and Ren! Run, Ren!", names: ["Yuki", "Ren"])
        XCTAssertEqual(segments, [
            .init(text: "Yuki", isName: true),
            .init(text: " and ", isName: false),
            .init(text: "Ren", isName: true),
            .init(text: "! Run, ", isName: false),
            .init(text: "Ren", isName: true),
            .init(text: "!", isName: false),
        ])
    }

    func testLongerNameWinsOverlap() {
        // "ゆう" と "ゆうた" の両方が登録されていたら、長い一致を優先する。
        let segments = CastNameHighlighter.segments(in: "ゆうたはやい！", names: ["ゆう", "ゆうた"])
        XCTAssertEqual(segments.first, .init(text: "ゆうた", isName: true))
    }

    func testNoMatchReturnsSingleLiteral() {
        let segments = CastNameHighlighter.segments(in: "Good morning!", names: ["Yuki"])
        XCTAssertEqual(segments, [.init(text: "Good morning!", isName: false)])
        XCTAssertEqual(CastNameHighlighter.segments(in: "Good morning!", names: []),
                       [.init(text: "Good morning!", isName: false)])
    }

    func testEmptyNamesAreIgnoredAndTextIsPreserved() {
        let text = "Yuki likes apples."
        let segments = CastNameHighlighter.segments(in: text, names: ["", "Yuki"])
        XCTAssertEqual(joined(segments), text)   // 分割しても原文は必ず復元できる
        XCTAssertTrue(segments.contains(.init(text: "Yuki", isName: true)))
    }
}
