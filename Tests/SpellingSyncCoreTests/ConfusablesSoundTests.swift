import XCTest
@testable import SpellingSyncCore

final class ConfusablesSoundTests: XCTestCase {

    private let csv = """
    word,sounds_like,approved,source
    right,light|night|write,1,ai
    rice,lice|nice|race,1,ai
    boat,vote|coat|goat,0,ai

    think,sink|pink|thank,1,hand
    """

    // MARK: パース

    func testParseSkipsHeaderAndBlankLines() {
        let entries = ConfusablesSound.parse(csv: csv)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].word, "right")
        XCTAssertEqual(entries[0].soundsLike, ["light", "night", "write"])
        XCTAssertTrue(entries[0].approved)
        XCTAssertFalse(entries[2].approved)          // boat=0
    }

    func testParseIgnoresMalformedLines() {
        let bad = "word,sounds_like,approved,source\njustoneword\nok,a|b,1,ai\n"
        let entries = ConfusablesSound.parse(csv: bad)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].word, "ok")
    }

    // MARK: 検索（既定は承認済みのみ）

    func testDistractorsApprovedOnlyByDefault() {
        let entries = ConfusablesSound.parse(csv: csv)
        XCTAssertEqual(ConfusablesSound.distractors(for: "right", in: entries), ["light", "night", "write"])
        XCTAssertEqual(ConfusablesSound.distractors(for: "boat", in: entries), [])   // 未承認は出さない
    }

    func testDistractorsCaseInsensitive() {
        let entries = ConfusablesSound.parse(csv: csv)
        XCTAssertEqual(ConfusablesSound.distractors(for: "RIGHT", in: entries), ["light", "night", "write"])
    }

    func testDistractorsUnknownWordEmpty() {
        let entries = ConfusablesSound.parse(csv: csv)
        XCTAssertEqual(ConfusablesSound.distractors(for: "banana", in: entries), [])
    }

    // MARK: 堅牢性（トリム・CRLF・先頭空行・重複）

    func testParseTrimsFieldsAndHandlesCRLF() {
        let messy = "word,sounds_like,approved,source\r\n  right , light | night ,1 ,ai\r\n"
        let entries = ConfusablesSound.parse(csv: messy)
        XCTAssertEqual(entries.count, 1)
        guard entries.count == 1 else { return }
        XCTAssertEqual(entries[0].word, "right")                       // 前後空白除去
        XCTAssertEqual(entries[0].soundsLike, ["light", "night"])      // 各おとりも除去
        XCTAssertTrue(entries[0].approved)                             // "1 "→true（CRLF/空白に強い）
        XCTAssertEqual(ConfusablesSound.distractors(for: "right", in: entries), ["light", "night"])
    }

    func testParseSkipsHeaderAfterLeadingBlankLines() {
        let withBlanks = "\n\nword,sounds_like,approved,source\nok,a|b,1,ai\n"
        let entries = ConfusablesSound.parse(csv: withBlanks)
        XCTAssertEqual(entries.count, 1)                              // ヘッダを語として取り込まない
        XCTAssertEqual(entries[0].word, "ok")
    }

    func testDistractorsPrefersApprovedDuplicate() {
        // 同じ見出し語が未承認→承認の順で重複しても、承認済みを返す。
        let dup = """
        word,sounds_like,approved,source
        cat,xxx|yyy,0,ai
        cat,cap|hat,1,ai
        """
        let entries = ConfusablesSound.parse(csv: dup)
        XCTAssertEqual(ConfusablesSound.distractors(for: "cat", in: entries), ["cap", "hat"])
    }
}
