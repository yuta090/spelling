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

    // MARK: - rubySegments（学年ハイブリッド＋ふりがな）
    // 改訂2026-07-02(§13.3): 習った漢字(≤maxGrade)=素／当該学年以上・教育漢字外=漢字＋グループルビ。
    // かな化（漢字消去）は廃止＝漢字は常に残し、超過分だけふりがなを振る。

    private func joinedText(_ segs: [JapaneseReading.RubySegment]) -> String {
        segs.map(\.text).joined()
    }

    func testRubySegmentsEmpty() {
        XCTAssertTrue(JapaneseReading.rubySegments("", maxGrade: 6).isEmpty)
    }

    func testRubySegmentsLearnedKanjiIsBare() {
        // 家族(家2 族3) は小6(maxGrade6)では習った漢字 → 素（ルビ無し）。
        let segs = JapaneseReading.rubySegments("家族", maxGrade: 6)
        XCTAssertEqual(joinedText(segs), "家族")
        XCTAssertTrue(segs.allSatisfy { $0.reading == nil }, "習った漢字にはルビを振らない")
    }

    func testRubySegmentsOverGradeKanjiGetsFuriganaKeepingKanji() {
        // 小1(maxGrade0)では 家族 は未習 → 漢字は残しふりがな「かぞく」。かな化しない。
        let segs = JapaneseReading.rubySegments("家族", maxGrade: 0)
        XCTAssertEqual(joinedText(segs), "家族", "漢字は消さず残す")
        XCTAssertEqual(segs.first?.reading, "かぞく")
    }

    func testRubySegmentsMixedGradeTokenGetsGroupRuby() {
        // 家族(家2=習った / 族3=未習) は1語トークン。1字でも未習を含めば語全体にグループルビ。
        let segs = JapaneseReading.rubySegments("家族", maxGrade: 2)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs.first?.text, "家族", "漢字を残す（部分かな化しない）")
        XCTAssertEqual(segs.first?.reading, "かぞく", "未習を含む語は語全体にルビ")
    }

    func testRubySegmentsKanaHasNoFurigana() {
        let segs = JapaneseReading.rubySegments("ねこ", maxGrade: 6)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs.first?.text, "ねこ")
        XCTAssertNil(segs.first?.reading)
    }

    func testRubySegmentsReconstructsTextAtAnyGrade() {
        // どの学年でも本体の連結で元の（分かち書き）文に戻る（漢字を消さない＝スペースも保持）。
        let wakachi = JapaneseReading.wakachi("私は英語を勉強します。")
        for maxGrade in [0, 2, 6] {
            let segs = JapaneseReading.rubySegments(wakachi, maxGrade: maxGrade)
            XCTAssertEqual(joinedText(segs), wakachi, "maxGrade \(maxGrade): 本体連結で元文に戻る")
        }
    }

    func testRubySegmentsLowGradeAddsFuriganaHighGradeBare() {
        let wakachi = JapaneseReading.wakachi("私は英語を勉強します。")
        // 小1: 教育漢字はまだ未習 → ふりがなが付く（漢字は残る）。
        let low = JapaneseReading.rubySegments(wakachi, maxGrade: 0)
        XCTAssertTrue(low.contains { $0.reading != nil }, "未習漢字語にふりがなが付く")
        XCTAssertTrue(joinedText(low).contains("英語"), "漢字は消さない")
        // 中学以降(maxGrade6): 教育漢字はすべて習った扱い → ルビ無し。
        let high = JapaneseReading.rubySegments(wakachi, maxGrade: 6)
        XCTAssertTrue(high.allSatisfy { $0.reading == nil }, "教育漢字は中学で素")
    }

    func testRubySegmentsOverGradeCompoundGetsGroupRuby() {
        // 小1: 蔵書 は未習複合語 → 漢字を残し語全体にふりがな「ぞうしょ」。複合語は割らない。
        let wakachi = JapaneseReading.wakachi("彼は蔵書をふやした。")
        let segs = JapaneseReading.rubySegments(wakachi, maxGrade: 1)
        XCTAssertTrue(joinedText(segs).contains("蔵書"), "未習複合語も漢字で残す: \(joinedText(segs))")
        XCTAssertTrue(segs.contains { $0.text.contains("蔵書") && $0.reading == "ぞうしょ" },
                      "蔵書 に群ルビ ぞうしょ")
    }
}
