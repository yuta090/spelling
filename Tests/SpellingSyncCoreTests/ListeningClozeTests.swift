import XCTest
@testable import SpellingSyncCore

/// リスニング穴埋め（音の近いおとりで作る穴埋め選択）の純ロジック検証。
/// 生成は `ClozeChoiceGenerator` に委譲しつつ、おとり＝`ConfusablesSound`（音が近い語）に固定し、
/// 「空所語に承認おとりが無ければ作らない（この形式の意味が無い）」ルールを足す。
final class ListeningClozeTests: XCTestCase {

    private func item(_ en: String, _ ja: String) -> SentenceItem {
        SentenceItem(en: en, ja: ja,
                     tokens: en.split(separator: " ").map(String.init),
                     gradeBand: 1)
    }

    private let entries = ConfusablesSound.parse(csv: """
    word,sounds_like,approved,source
    sea,see|tea|she,1,ai
    rice,nice|race|lice,1,ai
    bare,bear|bar|beer,0,ai
    """)

    // MARK: 生成

    func testMakeBuildsClozeWithSoundAlikeOptions() {
        let ex = ListeningClozeGenerator.make(
            from: item("I see the sea", "うみが みえる"),
            confusables: entries, blankIndex: 3, optionCount: 4, seed: 5)
        XCTAssertNotNil(ex)
        XCTAssertEqual(ex?.answer, "sea")
        XCTAssertEqual(ex?.blankIndex, 3)
        XCTAssertEqual(ex?.options.count, 4)
        // おとりは「音が近い語」（see/tea/she）から来る。
        XCTAssertEqual(ex.map { Set($0.options) }, ["sea", "see", "tea", "she"])
        XCTAssertEqual(ex?.prompt, "うみが みえる")
    }

    /// 空所を省略したら、音の近いおとりを持つトークンを自動で選ぶ
    /// （最長＝内容語が優先だが、おとりを持たない語は飛ばす）。
    func testMakeAutoSelectsBlankThatHasConfusables() {
        // "like"(4) と "rice"(4) は同長。既定の最長ルールなら min index の "like"。
        // だが "like" にはおとりが無いので、おとりを持つ "rice" を空所にする。
        let ex = ListeningClozeGenerator.make(
            from: item("I like rice", "ごはんが すき"),
            confusables: entries, optionCount: 4, seed: 1)
        XCTAssertEqual(ex?.answer, "rice")
        XCTAssertEqual(ex?.blankIndex, 2)
        XCTAssertEqual(ex.map { Set($0.options) }, ["rice", "nice", "race", "lice"])
    }

    func testMakeReturnsNilWhenNoTokenHasConfusables() {
        let ex = ListeningClozeGenerator.make(
            from: item("I am happy", "うれしい"),
            confusables: entries, optionCount: 4, seed: 1)
        XCTAssertNil(ex)
    }

    func testMakeReturnsNilWhenExplicitBlankHasNoConfusables() {
        // 明示した空所（"like"）にはおとりが無い → 作らない。
        let ex = ListeningClozeGenerator.make(
            from: item("I like rice", "ごはんが すき"),
            confusables: entries, blankIndex: 1, optionCount: 4, seed: 1)
        XCTAssertNil(ex)
    }

    func testMakeUsesOnlyApprovedConfusables() {
        // "bare" は approved=0 → おとり0 → 作らない。
        let ex = ListeningClozeGenerator.make(
            from: item("The shelf is bare", "たなは からっぽ"),
            confusables: entries, blankIndex: 3, optionCount: 4, seed: 1)
        XCTAssertNil(ex)
    }

    func testMakeRespectsOptionCountCap() {
        let ex = ListeningClozeGenerator.make(
            from: item("I see the sea", "うみが みえる"),
            confusables: entries, blankIndex: 3, optionCount: 3, seed: 2)
        XCTAssertEqual(ex?.options.count, 3)            // 正解＋おとり2
        XCTAssertTrue(ex?.options.contains("sea") ?? false)
    }

    func testMakeIsDeterministic() {
        let a = ListeningClozeGenerator.make(
            from: item("I like rice", "ごはんが すき"), confusables: entries, seed: 42)
        let b = ListeningClozeGenerator.make(
            from: item("I like rice", "ごはんが すき"), confusables: entries, seed: 42)
        XCTAssertEqual(a?.options, b?.options)
        XCTAssertEqual(a?.blankIndex, b?.blankIndex)
    }

    /// 空所未指定で、最長候補のおとりが「自分自身だけ」で成立しない場合、
    /// 次に短いが成立する候補へフォールバックする。
    func testMakeFallsBackWhenLongestCandidateCannotForm() {
        let tricky = ConfusablesSound.parse(csv: """
        word,sounds_like,approved,source
        longword,longword,1,ai
        cat,bat|hat,1,ai
        """)
        let ex = ListeningClozeGenerator.make(
            from: item("longword cat", "—"),
            confusables: tricky, optionCount: 4, seed: 1)
        // "longword"(8) はおとりが自分自身のみ→成立せず、"cat"(3) に落ちる。
        XCTAssertEqual(ex?.answer, "cat")
        XCTAssertEqual(ex?.blankIndex, 1)
        XCTAssertEqual(ex.map { Set($0.options) }, ["cat", "bat", "hat"])
    }

    func testMakeReturnsNilForEmptyTokens() {
        let ex = ListeningClozeGenerator.make(
            from: SentenceItem(en: "", ja: "", tokens: [], gradeBand: 1),
            confusables: entries, seed: 1)
        XCTAssertNil(ex)
    }
}
