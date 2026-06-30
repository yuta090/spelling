import XCTest
@testable import SpellingSyncCore

final class PressFeelTests: XCTestCase {

    func testRestStateIsNeutral() {
        let s = PressFeel.state(pressed: false, depth: .primary)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.yOffset, 0)
        XCTAssertEqual(s, PressFeel.rest)
    }

    func testNotPressedReturnsRestRegardlessOfDepth() {
        XCTAssertEqual(PressFeel.state(pressed: false, depth: .primary), PressFeel.rest)
        XCTAssertEqual(PressFeel.state(pressed: false, depth: .subtle), PressFeel.rest)
    }

    func testPrimaryPressedSinksAndShrinks() {
        let s = PressFeel.state(pressed: true, depth: .primary)
        XCTAssertLessThan(s.scale, 1)         // 縮む
        XCTAssertGreaterThan(s.yOffset, 0)    // 下に沈む
    }

    func testSubtlePressedIsShallowerThanPrimary() {
        let primary = PressFeel.state(pressed: true, depth: .primary)
        let subtle = PressFeel.state(pressed: true, depth: .subtle)
        // subtle は primary より浅い（縮み・沈みが小さい）
        XCTAssertGreaterThan(subtle.scale, primary.scale)
        XCTAssertLessThan(subtle.yOffset, primary.yOffset)
        // ただし rest よりは押し込まれている
        XCTAssertLessThan(subtle.scale, 1)
        XCTAssertGreaterThan(subtle.yOffset, 0)
    }

    func testReduceMotionDisablesPressTransform() {
        // モーション低減時は押しても動かさない（rest のまま）。
        XCTAssertEqual(PressFeel.state(pressed: true, depth: .primary, reduceMotion: true), PressFeel.rest)
        XCTAssertEqual(PressFeel.state(pressed: true, depth: .subtle, reduceMotion: true), PressFeel.rest)
    }

    func testScalesStayInSaneRange() {
        for depth in [PressFeel.Depth.primary, .subtle] {
            let s = PressFeel.state(pressed: true, depth: depth)
            XCTAssertGreaterThan(s.scale, 0.8, "縮みすぎないこと")
            XCTAssertLessThanOrEqual(s.scale, 1)
            XCTAssertLessThanOrEqual(s.yOffset, 6, "沈みすぎないこと")
        }
    }
}
