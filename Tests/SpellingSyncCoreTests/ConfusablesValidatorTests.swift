import XCTest
@testable import SpellingSyncCore

/// confusables_sound ビルド検証の純ロジック検証。
/// 方針（ユーザー決定 2026-06-28）：
///  - ハード規則（守れなければ却下）はデータだけで判定：承認済み・見出し語と別・重複なし・個数2〜4・正規化。
///  - wordbank 実在/band は「警告」（レポートに出すだけ・自動削除しない）。
///    wordbank の gloss には gray/math のような実在語の欠落があるため、機械削除は良いデータを壊す。
final class ConfusablesValidatorTests: XCTestCase {

    private func entry(_ word: String, _ sounds: [String], approved: Bool = true) -> ConfusableEntry {
        ConfusableEntry(word: word, soundsLike: sounds, approved: approved)
    }

    // MARK: ハード規則（却下/採用）

    func testAcceptsCleanApprovedRow() {
        let r = ConfusablesValidator.validate(
            entries: [entry("right", ["light", "night", "white"])],
            known: ["right", "light", "night", "white"], band: [:], targetBand: nil)
        XCTAssertEqual(r.accepted.map(\.word), ["right"])
        XCTAssertEqual(r.accepted.first?.soundsLike, ["light", "night", "white"])
        XCTAssertTrue(r.rejected.isEmpty)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testUnapprovedRowsAreExcludedNotRejected() {
        let r = ConfusablesValidator.validate(
            entries: [entry("rice", ["nice", "lice"], approved: false)],
            known: ["rice", "nice", "lice"], band: [:], targetBand: nil)
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertTrue(r.rejected.isEmpty)        // 未承認は「問題」ではなく単に同梱しないだけ
        XCTAssertEqual(r.excludedUnapprovedCount, 1)
    }

    func testNormalizesLowercaseAndTrim() {
        let r = ConfusablesValidator.validate(
            entries: [entry(" Right ", ["Light", " NIGHT "])],
            known: [], band: [:], targetBand: nil)
        XCTAssertEqual(r.accepted.first?.word, "right")
        XCTAssertEqual(r.accepted.first?.soundsLike, ["light", "night"])
    }

    func testRemovesSelfReferenceAndDuplicates() {
        let r = ConfusablesValidator.validate(
            entries: [entry("rice", ["rice", "nice", "nice", "lice"])],
            known: [], band: [:], targetBand: nil)
        // self("rice")と重複("nice")を除去 → nice, lice
        XCTAssertEqual(r.accepted.first?.soundsLike, ["nice", "lice"])
    }

    func testRejectsWhenFewerThanTwoDistractorsAfterCleaning() {
        // self除去で1語に → 却下
        let r = ConfusablesValidator.validate(
            entries: [entry("rice", ["rice", "nice"])],
            known: [], band: [:], targetBand: nil)
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertEqual(r.rejected.map(\.word), ["rice"])
        XCTAssertEqual(r.rejected.first?.reason, .tooFewDistractors)
    }

    func testRejectsWhenMoreThanFourDistractors() {
        let r = ConfusablesValidator.validate(
            entries: [entry("bat", ["cat", "hat", "mat", "rat", "sat"])],
            known: [], band: [:], targetBand: nil)
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .tooManyDistractors)
    }

    func testAcceptsExactlyTwoAndFourDistractors() {
        let two = ConfusablesValidator.validate(
            entries: [entry("rice", ["nice", "lice"])], known: [], band: [:], targetBand: nil)
        XCTAssertEqual(two.accepted.first?.soundsLike.count, 2)
        let four = ConfusablesValidator.validate(
            entries: [entry("bat", ["cat", "hat", "mat", "rat"])], known: [], band: [:], targetBand: nil)
        XCTAssertEqual(four.accepted.first?.soundsLike.count, 4)
        XCTAssertTrue(two.rejected.isEmpty && four.rejected.isEmpty)
    }

    func testRejectsDuplicateHeadwordKeepingFirst() {
        let r = ConfusablesValidator.validate(
            entries: [entry("rice", ["nice", "lice"]), entry("RICE", ["race", "vice"])],
            known: [], band: [:], targetBand: nil)
        XCTAssertEqual(r.accepted.map(\.word), ["rice"])               // 先頭の rice だけ採用
        XCTAssertEqual(r.accepted.first?.soundsLike, ["nice", "lice"]) // 後勝ちしない
        XCTAssertEqual(r.rejected.first?.reason, .duplicateHeadword)
    }

    func testRejectsTokenWithCSVBreakingChar() {
        // おとりに `|` を含む → serialize→parse の往復が壊れるので却下。
        let r = ConfusablesValidator.validate(
            entries: [entry("rice", ["ni|ce", "lice"])], known: [], band: [:], targetBand: nil)
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .invalidToken("ni|ce"))
    }

    // MARK: 警告（採用は維持・レポートのみ）

    func testWarnsButKeepsWhenDistractorMissingFromWordbank() {
        // gray は実在語だが gloss 欠落。削除せず警告のみ。
        let r = ConfusablesValidator.validate(
            entries: [entry("play", ["pray", "gray", "pay"])],
            known: ["play", "pray", "pay"], band: [:], targetBand: nil)
        XCTAssertEqual(r.accepted.first?.soundsLike, ["pray", "gray", "pay"])   // gray は残る
        XCTAssertTrue(r.warnings.contains { $0.word == "play" && $0.kind == .notInWordbank("gray") })
    }

    func testWarnsWhenHeadwordMissingFromWordbank() {
        let r = ConfusablesValidator.validate(
            entries: [entry("berry", ["very", "cherry"])],
            known: ["very", "cherry"], band: [:], targetBand: nil)
        XCTAssertEqual(r.accepted.map(\.word), ["berry"])      // 採用は維持
        XCTAssertTrue(r.warnings.contains { $0.kind == .notInWordbank("berry") })
    }

    func testWarnsBandUnknownAndBandOverTargetOnlyWhenTargetGiven() {
        let band = ["right": 1, "light": 1, "white": 9]   // white は band9
        let r = ConfusablesValidator.validate(
            entries: [entry("right", ["light", "white", "kite"])],
            known: ["right", "light", "white", "kite"], band: band, targetBand: 3)
        XCTAssertEqual(r.accepted.first?.soundsLike, ["light", "white", "kite"])   // 全部残す
        // white=band9>3 → over、kite は band不明 → unknown
        XCTAssertTrue(r.warnings.contains { $0.kind == .bandOverTarget("white", 9) })
        XCTAssertTrue(r.warnings.contains { $0.kind == .bandUnknown("kite") })
    }

    func testNoBandWarningsWhenTargetNil() {
        let r = ConfusablesValidator.validate(
            entries: [entry("right", ["light", "white"])],
            known: ["right", "light", "white"], band: [:], targetBand: nil)
        XCTAssertFalse(r.warnings.contains { if case .bandUnknown = $0.kind { return true }; return false })
    }

    // MARK: シリアライズ（再パース可能な CSV）

    func testSerializeRoundTripsThroughParse() {
        let r = ConfusablesValidator.validate(
            entries: [entry("right", ["light", "night"]), entry("rice", ["nice", "lice"])],
            known: [], band: [:], targetBand: nil)
        let csv = ConfusablesValidator.serialize(r.accepted)
        let reparsed = ConfusablesSound.parse(csv: csv)
        XCTAssertEqual(reparsed.count, 2)
        XCTAssertEqual(reparsed.first?.word, "right")
        XCTAssertEqual(reparsed.first?.soundsLike, ["light", "night"])
        XCTAssertTrue(reparsed.allSatisfy(\.approved))      // 同梱は approved=1 のみ
    }
}
