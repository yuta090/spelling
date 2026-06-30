import XCTest
@testable import SpellingSyncCore

/// おぼえる練習（手書きの前・タップで選ぶ）の「まちがい選択肢」を作る純ロジックのテスト。
/// 3種: 似た綴り(similarSpelling) / かたちちがい(inflection) / 微妙なスペルミス(typo)。
/// 不変条件: 正解そのものは返さない・全件ユニーク・ASCII英字のみ・決定論。
final class SpellingDistractorsTests: XCTestCase {

    private func texts(_ ds: [SpellingDistractor]) -> [String] { ds.map { $0.text } }
    private func texts(_ ds: [SpellingDistractor], kind: SpellingDistractorKind) -> [String] {
        ds.filter { $0.kind == kind }.map { $0.text }
    }

    // MARK: - 不変条件

    func testNeverReturnsTheAnswerItself() {
        for word in ["cats", "apple", "go", "book", "dogs", "school"] {
            let ds = SpellingDistractorGenerator.make(for: word)
            XCTAssertFalse(texts(ds).contains { $0.lowercased() == word.lowercased() },
                           "\(word): 正解そのものを選択肢に出してはいけない")
        }
    }

    func testAllDistractorsAreUnique() {
        for word in ["cats", "apple", "happy", "running", "bus"] {
            let t = texts(SpellingDistractorGenerator.make(for: word))
            XCTAssertEqual(Set(t.map { $0.lowercased() }).count, t.count, "\(word): 選択肢が重複している")
        }
    }

    func testIsDeterministic() {
        let a = SpellingDistractorGenerator.make(for: "apple")
        let b = SpellingDistractorGenerator.make(for: "apple")
        XCTAssertEqual(a, b, "同じ入力なら同じ出力（決定論）")
    }

    func testEmptyOrTooShortReturnsEmpty() {
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "").isEmpty)
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "  ").isEmpty)
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "a").isEmpty)
    }

    func testOnlyAsciiLetters() {
        for d in SpellingDistractorGenerator.make(for: "apple") {
            XCTAssertTrue(d.text.allSatisfy { $0.isASCII && $0.isLetter }, "ASCII英字以外を含む: \(d.text)")
            XCTAssertGreaterThanOrEqual(d.text.count, 2)
        }
    }

    /// アポストロフィ・ハイフン・アクセント・非ラテン文字を含む語は対象外（空）。
    func testNonAsciiOrPunctuatedWordsReturnEmpty() {
        for word in ["don't", "a-b", "café", "rosé", "naïve", "Tokyo's"] {
            XCTAssertTrue(SpellingDistractorGenerator.make(for: word).isEmpty,
                          "\(word): ASCII英字以外を含む語は空を返す")
        }
    }

    func testNegativeOrZeroLimitReturnsEmptyAndDoesNotCrash() {
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "apple", limit: 0).isEmpty)
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "apple", limit: -1).isEmpty)
        XCTAssertTrue(SpellingDistractorGenerator.make(for: "apple", limit: -100).isEmpty)
    }

    // MARK: - 微妙なスペルミス（typo）

    func testTypoProducesDoubledLetter() {
        // apple → applle（字をダブらせる）
        let t = texts(SpellingDistractorGenerator.make(for: "apple"), kind: .typo)
        XCTAssertTrue(t.contains("applle"), "ダブり字の typo を作る。actual=\(t)")
    }

    func testTypoProducesDeletion() {
        // apple → aple（字を抜かす）
        let t = texts(SpellingDistractorGenerator.make(for: "apple"), kind: .typo)
        XCTAssertTrue(t.contains("aple"), "脱字の typo を作る。actual=\(t)")
    }

    func testTypoProducesTransposition() {
        // apple → appel（となりを入れ替える）
        let t = texts(SpellingDistractorGenerator.make(for: "apple"), kind: .typo)
        XCTAssertTrue(t.contains("appel"), "入れ替えの typo を作る。actual=\(t)")
    }

    // MARK: - 似た綴り（similarSpelling）

    func testSimilarSpellingSubstitutesLetters() {
        // cats → kats (c→k), cots (a→o)
        let t = texts(SpellingDistractorGenerator.make(for: "cats"), kind: .similarSpelling)
        XCTAssertTrue(t.contains("kats"), "c→k の似た綴りを作る。actual=\(t)")
        XCTAssertTrue(t.contains("cots"), "a→o の似た綴りを作る。actual=\(t)")
    }

    // MARK: - かたちちがい（inflection）

    func testInflectionDropsTrailingS() {
        // cats → cat（複数形ちがい）
        let t = texts(SpellingDistractorGenerator.make(for: "cats"), kind: .inflection)
        XCTAssertTrue(t.contains("cat"), "語尾 s を落とした形を作る。actual=\(t)")
    }

    func testInflectionAddsS() {
        // cat → cats（複数形ちがい）
        let t = texts(SpellingDistractorGenerator.make(for: "cat"), kind: .inflection)
        XCTAssertTrue(t.contains("cats"), "語尾に s を足した形を作る。actual=\(t)")
    }

    /// 劣化形（appl / bu / py）を作らない。語尾ルールは確実に言えるものだけ。
    func testInflectionAvoidsDegenerateStems() {
        let apples = texts(SpellingDistractorGenerator.make(for: "apples"), kind: .inflection)
        XCTAssertTrue(apples.contains("apple"), "apples → apple。actual=\(apples)")
        XCTAssertFalse(apples.contains("appl"), "apples → appl は作らない。actual=\(apples)")

        let bus = texts(SpellingDistractorGenerator.make(for: "bus"), kind: .inflection)
        XCTAssertFalse(bus.contains("bu"), "bus → bu は作らない（短語の s 落としはしない）。actual=\(bus)")

        let pies = texts(SpellingDistractorGenerator.make(for: "pies"), kind: .inflection)
        XCTAssertTrue(pies.contains("pie"), "pies → pie。actual=\(pies)")
        XCTAssertFalse(pies.contains("py"), "pies → py は作らない。actual=\(pies)")
    }

    /// ses/xes/zes の語幹推測はしない＝houses→hous のような劣化を出さない（末尾 s を1つ落とすだけ）。
    func testReversePluralDoesNotMangleEStems() {
        for (plural, singular, bad) in [("houses", "house", "hous"),
                                        ("cases", "case", "cas"),
                                        ("roses", "rose", "ros")] {
            let t = texts(SpellingDistractorGenerator.make(for: plural), kind: .inflection)
            XCTAssertTrue(t.contains(singular), "\(plural) → \(singular)。actual=\(t)")
            XCTAssertFalse(t.contains(bad), "\(plural) → \(bad) は作らない。actual=\(t)")
        }
    }

    /// 単数 → 複数の sibilant は +es（box→boxs ではなく boxes）。
    func testSibilantSingularPluralizesWithEs() {
        XCTAssertTrue(texts(SpellingDistractorGenerator.make(for: "box"), kind: .inflection).contains("boxes"),
                      "box → boxes")
        XCTAssertTrue(texts(SpellingDistractorGenerator.make(for: "dish"), kind: .inflection).contains("dishes"),
                      "dish → dishes")
        XCTAssertTrue(texts(SpellingDistractorGenerator.make(for: "fox"), kind: .inflection).contains("foxes"),
                      "fox → foxes")
        // 普通の語は +s。
        XCTAssertTrue(texts(SpellingDistractorGenerator.make(for: "dog"), kind: .inflection).contains("dogs"),
                      "dog → dogs")
        XCTAssertFalse(texts(SpellingDistractorGenerator.make(for: "box"), kind: .inflection).contains("boxs"),
                       "box → boxs は作らない")
    }

    func testVerbInflectionProducesBothIngAndEd() {
        // 動詞は -ing と -ed の両方を作る
        let t = texts(SpellingDistractorGenerator.make(for: "play", partOfSpeech: "verb"), kind: .inflection)
        XCTAssertTrue(t.contains("playing"), "動詞は ing 形を作る。actual=\(t)")
        XCTAssertTrue(t.contains("played"), "動詞は ed 形を作る。actual=\(t)")
    }

    /// 全大文字の語は接尾辞もケースを合わせる（CATSs / PLAYing を作らない）。
    func testAllCapsKeepsConsistentCase() {
        let play = texts(SpellingDistractorGenerator.make(for: "PLAY", partOfSpeech: "verb"), kind: .inflection)
        XCTAssertTrue(play.contains("PLAYING"), "PLAY → PLAYING。actual=\(play)")
        XCTAssertFalse(play.contains("PLAYing"), "ケースが混ざらない。actual=\(play)")
        let cat = texts(SpellingDistractorGenerator.make(for: "CAT"), kind: .inflection)
        XCTAssertTrue(cat.contains("CATS"), "CAT → CATS。actual=\(cat)")
    }

    // MARK: - フィルタ / 件数

    func testKindsFilterReturnsOnlyRequestedKinds() {
        let ds = SpellingDistractorGenerator.make(for: "apple", kinds: [.typo])
        XCTAssertFalse(ds.isEmpty)
        XCTAssertTrue(ds.allSatisfy { $0.kind == .typo }, "typo だけを要求したら typo だけ返す")
    }

    func testLimitCapsCount() {
        let ds = SpellingDistractorGenerator.make(for: "school", limit: 3)
        XCTAssertLessThanOrEqual(ds.count, 3)
    }

    func testLimitMixesKindsForVariety() {
        // 3つに絞っても種類が偏りすぎない（最低2種類は混ざる）
        let ds = SpellingDistractorGenerator.make(for: "cats", limit: 3)
        XCTAssertGreaterThanOrEqual(Set(ds.map { $0.kind }).count, 2,
                                    "限定時も複数種類を混ぜる。actual=\(ds)")
    }
}
