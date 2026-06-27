import XCTest
@testable import SpellingSyncCore

/// コンテンツゲート（レベル生成のロック判定）の純粋ロジックのテスト。
/// 無料＝Dolch pre-K / K のみ。Grade1/2/3・noun・全 NGSL バンドは有料。
final class ContentGateTests: XCTestCase {

    // MARK: - 無料判定

    func testFreeLevelsAreOnlyPreKAndK() {
        XCTAssertTrue(ContentGate.isFree(.dolch(.preK)))
        XCTAssertTrue(ContentGate.isFree(.dolch(.k)))
    }

    func testPaidLevels() {
        XCTAssertFalse(ContentGate.isFree(.dolch(.g1)))
        XCTAssertFalse(ContentGate.isFree(.dolch(.g2)))
        XCTAssertFalse(ContentGate.isFree(.dolch(.g3)))
        XCTAssertFalse(ContentGate.isFree(.dolch(.noun)))
        for band in 1...5 {
            XCTAssertFalse(ContentGate.isFree(.ngsl(band: band)), "NGSL band \(band) は有料")
        }
    }

    // MARK: - 解放判定（購読で全解放、未購読は無料のみ）

    func testSubscribedUnlocksEverything() {
        XCTAssertTrue(ContentGate.isUnlocked(.dolch(.g3), isSubscribed: true))
        XCTAssertTrue(ContentGate.isUnlocked(.ngsl(band: 5), isSubscribed: true))
        XCTAssertTrue(ContentGate.isUnlocked(.dolch(.preK), isSubscribed: true))
    }

    func testUnsubscribedUnlocksOnlyFree() {
        XCTAssertTrue(ContentGate.isUnlocked(.dolch(.preK), isSubscribed: false))
        XCTAssertTrue(ContentGate.isUnlocked(.dolch(.k), isSubscribed: false))
        XCTAssertFalse(ContentGate.isUnlocked(.dolch(.g1), isSubscribed: false))
        XCTAssertFalse(ContentGate.isUnlocked(.ngsl(band: 1), isSubscribed: false))
    }

    // MARK: - WordBank/UI の生パラメータからの型付きブリッジ

    func testBridgeFromGradeAxis() {
        XCTAssertEqual(ContentLevel(dolch: "pre-K", band: nil), .dolch(.preK))
        XCTAssertEqual(ContentLevel(dolch: "K", band: nil), .dolch(.k))
        XCTAssertEqual(ContentLevel(dolch: "1", band: nil), .dolch(.g1))
        XCTAssertEqual(ContentLevel(dolch: "2", band: nil), .dolch(.g2))
        XCTAssertEqual(ContentLevel(dolch: "3", band: nil), .dolch(.g3))
        XCTAssertEqual(ContentLevel(dolch: "noun", band: nil), .dolch(.noun))
    }

    func testBridgeFromDifficultyAxis() {
        XCTAssertEqual(ContentLevel(dolch: nil, band: 3), .ngsl(band: 3))
    }

    func testBridgeBandTakesPrecedenceWhenBothPresent() {
        // UI 上は排他だが、両方来たら band（難易度軸）を優先する。
        XCTAssertEqual(ContentLevel(dolch: "pre-K", band: 2), .ngsl(band: 2))
    }

    func testBridgeReturnsNilForInvalidInput() {
        XCTAssertNil(ContentLevel(dolch: nil, band: nil))
        XCTAssertNil(ContentLevel(dolch: "unknown", band: nil))
    }

    func testBridgeAcceptsAllValidBands() {
        for b in 1...5 {
            XCTAssertEqual(ContentLevel(dolch: nil, band: b), .ngsl(band: b))
        }
    }

    func testBridgeRejectsOutOfRangeBand() {
        // NGSL バンドは 1...5。範囲外は解釈不能として nil。
        XCTAssertNil(ContentLevel(dolch: nil, band: 0))
        XCTAssertNil(ContentLevel(dolch: nil, band: -1))
        XCTAssertNil(ContentLevel(dolch: nil, band: 6))
    }

    func testBridgeRejectsInvalidBandEvenWithValidGrade() {
        // 不正な band は、正しい grade を黙って上書きせず nil（誤入力を顕在化）。
        XCTAssertNil(ContentLevel(dolch: "pre-K", band: 0))
    }

    // MARK: - ブリッジ＋解放のエンドツーエンド（生パラメータでの利用想定）

    func testUnlockedViaRawParams() {
        // 未購読でも pre-K は解放
        let preK = ContentLevel(dolch: "pre-K", band: nil)!
        XCTAssertTrue(ContentGate.isUnlocked(preK, isSubscribed: false))
        // 未購読の NGSL band1 はロック
        let band1 = ContentLevel(dolch: nil, band: 1)!
        XCTAssertFalse(ContentGate.isUnlocked(band1, isSubscribed: false))
    }
}
