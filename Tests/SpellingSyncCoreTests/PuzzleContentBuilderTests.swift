import XCTest
@testable import SpellingSyncCore

/// ことばパズルの出題プールを文バンクから組み立てる PuzzleContentBuilder のテスト。
/// 方針: 空所＝内容語（最長トークン）/ おとり＝同じか下の学年の内容語 / 決定論。
final class PuzzleContentBuilderTests: XCTestCase {

    private func item(_ en: String, band: Int, _ grammar: GrammarPoint? = nil) -> SentenceItem {
        SentenceItem(en: en, ja: "（やく）",
                     tokens: en.split(separator: " ").map(String.init),
                     gradeBand: band, grammar: grammar)
    }

    private var bank: [SentenceItem] {
        [
            item("She likes apples", band: 1, .presentSimple),   // 最長=apples
            item("He can swim", band: 1, .canModal),             // 最長=swim
            item("We play soccer", band: 1, .presentSimple),     // 最長=soccer
            item("This bag is bigger", band: 2, .comparativeEr), // 最長=bigger
            item("Go", band: 1)                                  // 1トークン＝並べ替え不可
        ]
    }

    // MARK: ぶんづくり

    func testOrderingItemsKeepsOnlyScramblable() {
        let out = PuzzleContentBuilder.orderingItems(bank)
        XCTAssertEqual(out.count, 4)                       // 1トークンの "Go" は除外
        XCTAssertFalse(out.contains { $0.tokens == ["Go"] })
    }

    // MARK: あなうめ（選択）

    func testClozeBlankIsLongestToken() {
        let samples = PuzzleContentBuilder.clozeSamples(bank, seed: 1)
        let apples = samples.first { $0.item.en == "She likes apples" }
        XCTAssertNotNil(apples)
        XCTAssertEqual(apples?.item.tokens[apples!.blankIndex], "apples")
    }

    func testClozeDistractorsExcludeAnswerAndAreLevelAppropriate() {
        let samples = PuzzleContentBuilder.clozeSamples(bank, seed: 7)
        // band1 の "soccer" 問題：おとりは band<=1 の内容語のみ（"bigger"(band2) は出ない）
        let soccer = samples.first { $0.item.en == "We play soccer" }!
        XCTAssertFalse(soccer.distractors.contains("soccer"))         // 正解は除外
        XCTAssertFalse(soccer.distractors.contains("bigger"))         // 上位学年語は出さない
        XCTAssertTrue(soccer.distractors.allSatisfy { ["apples", "swim"].contains($0) })
    }

    func testClozeBand2CanUseLowerBandDistractors() {
        let samples = PuzzleContentBuilder.clozeSamples(bank, seed: 3)
        let bigger = samples.first { $0.item.en == "This bag is bigger" }!
        // band2 は band<=2 の内容語が使える（band1 語も可）
        XCTAssertFalse(bigger.distractors.isEmpty)
        XCTAssertFalse(bigger.distractors.contains("bigger"))
    }

    func testClozeIsDeterministic() {
        // id はインスタンスごとに異なるので、判断結果（空所位置・おとり並び）で比較する。
        func shape(_ s: [PuzzleContentBuilder.ClozeSample]) -> [String] {
            s.map { "\($0.item.en)|\($0.blankIndex)|\($0.distractors.joined(separator: ","))" }
        }
        XCTAssertEqual(shape(PuzzleContentBuilder.clozeSamples(bank, seed: 42)),
                       shape(PuzzleContentBuilder.clozeSamples(bank, seed: 42)))
    }

    func testClozeSkipsSingleTokenSentences() {
        let samples = PuzzleContentBuilder.clozeSamples(bank, seed: 1)
        XCTAssertFalse(samples.contains { $0.item.en == "Go" })   // 1語は穴埋めにならない
    }

    // MARK: きいて あなうめ

    private var confusables: [ConfusableEntry] {
        [
            ConfusableEntry(word: "sea", soundsLike: ["see", "she"], approved: true),
            ConfusableEntry(word: "rice", soundsLike: ["lice", "race"], approved: true),
        ]
    }

    func testListeningSamplesOnlyIncludeSentencesWithConfusableToken() {
        let items = [
            item("I eat rice", band: 1),       // "rice" に音類似おとり有り
            item("He can swim", band: 1),      // 音類似おとり無し
        ]
        let samples = PuzzleContentBuilder.listeningSamples(items, confusables: confusables, seed: 1)
        XCTAssertEqual(samples.count, 1)
        let s = samples[0]
        XCTAssertEqual(s.item.en, "I eat rice")
        XCTAssertEqual(s.item.tokens[s.blankIndex], "rice")   // 空所は音類似おとりのある語
    }

    // MARK: おとを きいて えらぶ

    func testListeningWordsReturnsHeadwordsWithDistractors() {
        let words = PuzzleContentBuilder.listeningWords(confusables)
        XCTAssertEqual(Set(words), ["sea", "rice"])
    }
}
