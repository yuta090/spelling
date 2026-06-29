import XCTest
@testable import SpellingSyncCore

final class GlossFormatterTests: XCTestCase {
    func testTakesFirstSenseBeforeIdeographicComma() {
        XCTAssertEqual(GlossFormatter.primarySense("猫、ねこ"), "猫")
    }

    func testTakesFirstOfManySenses() {
        XCTAssertEqual(GlossFormatter.primarySense("走る、駆ける、運営する"), "走る")
    }

    func testHandlesAsciiAndOtherSeparators() {
        XCTAssertEqual(GlossFormatter.primarySense("apple, りんご"), "apple")
        XCTAssertEqual(GlossFormatter.primarySense("犬／いぬ"), "犬")
        XCTAssertEqual(GlossFormatter.primarySense("赤；あか"), "赤")
        XCTAssertEqual(GlossFormatter.primarySense("上・うえ"), "上")
    }

    func testSplitsOnNewline() {
        XCTAssertEqual(GlossFormatter.primarySense("犬\nいぬ"), "犬")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(GlossFormatter.primarySense("  りんご  "), "りんご")
        XCTAssertEqual(GlossFormatter.primarySense("ねこ 、 いえねこ"), "ねこ")
    }

    func testSkipsLeadingSeparators() {
        XCTAssertEqual(GlossFormatter.primarySense("、、ねこ"), "ねこ")
    }

    func testSingleSensePassesThrough() {
        XCTAssertEqual(GlossFormatter.primarySense("ねこ"), "ねこ")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(GlossFormatter.primarySense(""), "")
        XCTAssertEqual(GlossFormatter.primarySense("   "), "")
    }

    func testAllSeparatorsFallsBackToTrimmedOriginal() {
        // 区切りだけ → 取り出せる語義が無いので元（trim）を返す。
        XCTAssertEqual(GlossFormatter.primarySense("、，；"), "、，；")
    }
}
