import XCTest
@testable import SpellingSyncCore

/// `JapaneseReading.kanaizingOverGrade` の構造的な不変条件をテストする。
/// 読みそのもの（例: 猫→ねこ）は OS 内蔵辞書由来だが、Apple プラットフォームで安定しているため
/// 代表的な常用語のみ最小限に確認する。細かな読みの揺れ（私→わたくし等）には依存しない。
final class JapaneseReadingTests: XCTestCase {

    private func isAllHiraganaOrSpace(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) || $0 == " " || $0 == "　" }
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(JapaneseReading.kanaizingOverGrade("", maxGrade: 0), "")
    }

    func testAlreadyKanaIsUnchanged() {
        XCTAssertEqual(JapaneseReading.kanaizingOverGrade("ねこ", maxGrade: 0), "ねこ")
        XCTAssertEqual(JapaneseReading.kanaizingOverGrade("ねこを かっている", maxGrade: 0), "ねこを かっている")
    }

    func testWithinGradeKanjiIsKept() {
        // 山 は配当1年。許可学年1以上ならそのまま残す（速い道＝isWithin で即 return）。
        XCTAssertEqual(JapaneseReading.kanaizingOverGrade("山", maxGrade: 1), "山")
        XCTAssertEqual(JapaneseReading.kanaizingOverGrade("山", maxGrade: 6), "山")
    }

    func testOverGradeKanjiBecomesKana() {
        // 猫 は教育漢字外（=未習扱い）。許可0ではかなに落ちる。
        let out = JapaneseReading.kanaizingOverGrade("猫", maxGrade: 0)
        XCTAssertFalse(out.contains("猫"))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(isAllHiraganaOrSpace(out), "全てひらがなのはず: \(out)")
        // 代表的な常用語の読みは安定。
        XCTAssertEqual(out, "ねこ")
    }

    func testKeepsWithinKanjiWhileKanaizingOverGradeInSameSentence() {
        // 「山」(配当1)は残し、「猫」(未習)はかな。助詞「と」も保つ。許可学年1。
        let out = JapaneseReading.kanaizingOverGrade("山と猫", maxGrade: 1)
        XCTAssertTrue(out.contains("山"), "習った漢字は残す: \(out)")
        XCTAssertTrue(out.contains("と"), "かなはそのまま: \(out)")
        XCTAssertFalse(out.contains("猫"), "未習漢字はかなに: \(out)")
    }

    func testPreservesSpacesBetweenTokens() {
        // 分かち書きのスペースは保つ（過剰漢字を含む文でも）。
        let out = JapaneseReading.kanaizingOverGrade("ねこ 猫", maxGrade: 0)
        XCTAssertTrue(out.contains(" "), "スペースを保つ: \(out)")
        XCTAssertFalse(out.contains("猫"))
    }

    func testPreservesTrailingPunctuation() {
        let out = JapaneseReading.kanaizingOverGrade("猫。", maxGrade: 0)
        XCTAssertTrue(out.hasSuffix("。"), "末尾の句点を保つ: \(out)")
        XCTAssertFalse(out.contains("猫"))
    }

    // MARK: - wakachi（分かち書き）

    func testWakachiEmptyStaysEmpty() {
        XCTAssertEqual(JapaneseReading.wakachi(""), "")
    }

    func testWakachiSeparatesBunsetsuWithSpaces() {
        // 助詞は前の語にくっつき、自立語の前で区切る。
        XCTAssertEqual(JapaneseReading.wakachi("私は英語を勉強します。"), "私は 英語を 勉強します。")
    }

    func testWakachiHandlesAllKanaSentence() {
        // かなだらけの文（学年でかな化した結果）でも文節で区切れる。
        XCTAssertEqual(
            JapaneseReading.wakachi("わたくしはえいごをべんきょうします。"),
            "わたくしは えいごを べんきょうします。"
        )
    }

    func testWakachiNoSpaceBeforePunctuation() {
        let out = JapaneseReading.wakachi("私は英語を勉強します。")
        XCTAssertFalse(out.contains(" 。"), "句点の前にスペースを入れない: \(out)")
        XCTAssertTrue(out.hasSuffix("。"), "末尾は句点: \(out)")
        XCTAssertFalse(out.contains("  "), "二重スペースを作らない: \(out)")
    }

    func testWakachiDoesNotDoubleSpaceAlreadySpaced() {
        // すでに分かち書きされた入力でも二重スペースにしない。
        let out = JapaneseReading.wakachi("ねこ を かう")
        XCTAssertFalse(out.contains("  "), "二重スペースを作らない: \(out)")
        XCTAssertFalse(out.hasPrefix(" "), "先頭にスペースを残さない: \(out)")
        XCTAssertFalse(out.hasSuffix(" "), "末尾にスペースを残さない: \(out)")
    }

    func testWakachiKeepsMidSentencePunctuationAttached() {
        XCTAssertEqual(JapaneseReading.wakachi("はしる。 とぶ。"), "はしる。 とぶ。")
    }

    func testWakachiNoSpaceAfterOpeningBracket() {
        // 開き括弧の直後の語はくっつける（「 ねこ ではなく 「ねこ）。
        let out = JapaneseReading.wakachi("ねこが「にゃあ」となく。")
        XCTAssertFalse(out.contains("「 "), "開き括弧の直後にスペースを入れない: \(out)")
        XCTAssertTrue(out.contains("「にゃあ"), "開き括弧と語をくっつける: \(out)")
    }

    // MARK: - readableExample（分かち書き → かな化、順序保証）

    func testReadableExampleKeepsCompoundIntactWhenKanaized() {
        // 蔵書(未習) は小1ではかな化されるが、複合語として「ぞうしょ」のまま（"ぞう しょ"に割らない）。
        let out = JapaneseReading.readableExample("彼は蔵書をふやした。", maxGrade: 1)
        XCTAssertTrue(out.contains("ぞうしょ"), "複合語を割らない: \(out)")
        XCTAssertFalse(out.contains("ぞう しょ"), "複合語を割らない: \(out)")
        XCTAssertFalse(out.contains("蔵書"), "未習漢字はかなに: \(out)")
        XCTAssertFalse(out.contains("  "), "二重スペースなし: \(out)")
    }

    func testReadableExampleKeepsWithinGradeKanjiAndWakachi() {
        // 小6では 蔵書 は漢字のまま、かつ分かち書きされる。
        let out = JapaneseReading.readableExample("彼は蔵書をふやした。", maxGrade: 6)
        XCTAssertTrue(out.contains("蔵書"), "習った漢字は残す: \(out)")
        XCTAssertTrue(out.contains(" "), "分かち書きする: \(out)")
        XCTAssertTrue(out.hasSuffix("。"), "末尾は句点: \(out)")
    }

    func testReadableExampleEmptyStaysEmpty() {
        XCTAssertEqual(JapaneseReading.readableExample("", maxGrade: 1), "")
    }
}
