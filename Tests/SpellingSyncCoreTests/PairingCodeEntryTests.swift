import XCTest
@testable import SpellingSyncCore

final class PairingCodeEntryTests: XCTestCase {
    func testKeepsSixDigitsAsIs() {
        XCTAssertEqual(PairingCodeEntry.normalize("123456"), "123456")
        XCTAssertTrue(PairingCodeEntry.isComplete("123456"))
    }

    func testStripsSeparatorsAndSpaces() {
        XCTAssertEqual(PairingCodeEntry.normalize("12 34-56"), "123456")
        XCTAssertEqual(PairingCodeEntry.normalize(" 1 2 3 4 5 6 "), "123456")
        XCTAssertTrue(PairingCodeEntry.isComplete("12-34-56"))
    }

    func testStripsLetters() {
        XCTAssertEqual(PairingCodeEntry.normalize("1a2b3c"), "123")
        XCTAssertFalse(PairingCodeEntry.isComplete("1a2b3c"))
    }

    func testCapsToSixDigits() {
        XCTAssertEqual(PairingCodeEntry.normalize("1234567890"), "123456")
        XCTAssertTrue(PairingCodeEntry.isComplete("1234567890"))
    }

    func testIncompleteAndEmpty() {
        XCTAssertEqual(PairingCodeEntry.normalize(""), "")
        XCTAssertFalse(PairingCodeEntry.isComplete(""))
        XCTAssertEqual(PairingCodeEntry.normalize("12345"), "12345")
        XCTAssertFalse(PairingCodeEntry.isComplete("12345"))
    }

    func testIgnoresFullWidthNonASCIIDigits() {
        // 全角数字は ASCII でないため無視される（numberPad は ASCII を返すため実害なし・仕様を固定）。
        XCTAssertEqual(PairingCodeEntry.normalize("１２３456"), "456")
    }
}
