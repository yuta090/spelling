#if DEBUG
import XCTest
@testable import SpellingSyncCore

final class AIOCRJudgmentTests: XCTestCase {

    // MARK: - パース: 素直な JSON

    func test_parse_plainJSON() {
        let v = AIOCRResponseParser.parse(#"{"reading":"because","correct":true,"legible":true,"comment":"neat"}"#)
        XCTAssertEqual(v?.reading, "because")
        XCTAssertEqual(v?.correct, true)
        XCTAssertEqual(v?.legible, true)
        XCTAssertEqual(v?.comment, "neat")
    }

    // MARK: - パース: コードフェンス＋前後テキストを許容

    func test_parse_fencedWithExtraText() {
        let content = """
        Sure! Here is my judgment:
        ```json
        {"reading": "becuase", "correct": false, "legible": true, "comment": "letters swapped"}
        ```
        Hope that helps.
        """
        let v = AIOCRResponseParser.parse(content)
        XCTAssertEqual(v?.reading, "becuase")
        XCTAssertEqual(v?.correct, false)
        XCTAssertEqual(v?.legible, true)
    }

    // MARK: - パース: 文字列中の波括弧に惑わされない / ネスト

    func test_parse_ignoresBracesInsideStrings() {
        let v = AIOCRResponseParser.parse(#"{"reading":"a}b{c","correct":false,"legible":true,"comment":"x"}"#)
        XCTAssertEqual(v?.reading, "a}b{c")
        XCTAssertEqual(v?.correct, false)
    }

    // MARK: - パース: bool が文字列や数値で来ても解釈

    func test_parse_boolAsStringOrNumber() {
        let v = AIOCRResponseParser.parse(#"{"reading":"cat","correct":"yes","legible":1,"comment":""}"#)
        XCTAssertEqual(v?.correct, true)
        XCTAssertEqual(v?.legible, true)
    }

    // MARK: - パース: 欠落キーは nil、reading 無しは失敗

    func test_parse_missingOptionalKeys() {
        let v = AIOCRResponseParser.parse(#"{"reading":"dog"}"#)
        XCTAssertEqual(v?.reading, "dog")
        XCTAssertNil(v?.correct)
        XCTAssertNil(v?.legible)
        XCTAssertEqual(v?.comment, "")
    }

    func test_parse_failsWithoutReading() {
        XCTAssertNil(AIOCRResponseParser.parse(#"{"correct":true}"#))
    }

    func test_parse_failsOnGarbage() {
        XCTAssertNil(AIOCRResponseParser.parse("I couldn't read the image, sorry."))
    }

    // MARK: - パース: JSON前に未対応クォートを含む散文があっても拾える

    func test_parse_preambleWithUnmatchedQuote() {
        let content = #"Here's what I "think" the child wrote: {"reading":"cat","correct":true,"legible":true}"#
        let v = AIOCRResponseParser.parse(content)
        XCTAssertEqual(v?.reading, "cat")
        XCTAssertEqual(v?.correct, true)
    }

    // MARK: - パース: reading を持たない先行オブジェクトは飛ばして次を採用

    func test_parse_skipsLeadingNonVerdictObject() {
        let content = #"{"note":"thinking"} then {"reading":"dog","correct":false}"#
        let v = AIOCRResponseParser.parse(content)
        XCTAssertEqual(v?.reading, "dog")
        XCTAssertEqual(v?.correct, false)
    }

    // MARK: - 正規化と一致判定（モデルの自己申告に依存しない客観比較）

    func test_readingMatchesTarget_ignoresCaseAndPunctuation() {
        let v = AIOCRVerdict(reading: " Because. ", correct: false)
        XCTAssertTrue(v.readingMatchesTarget("because"))
    }

    func test_readingMatchesTarget_detectsMismatch() {
        let v = AIOCRVerdict(reading: "becuase")
        XCTAssertFalse(v.readingMatchesTarget("because"))
    }

    func test_normalize_stripsNonLetters() {
        XCTAssertEqual(AIOCRText.normalize("C-A-T 123!"), "cat")
    }

    // MARK: - プロンプトに出題語が含まれ、捏造抑止の指示がある

    func test_instruction_containsTargetAndAntiHallucination() {
        let p = AIOCRPrompt.instruction(target: "apple")
        XCTAssertTrue(p.contains("apple"))
        XCTAssertTrue(p.lowercased().contains("legible"))
        XCTAssertTrue(p.lowercased().contains("json"))
    }
}
#endif
