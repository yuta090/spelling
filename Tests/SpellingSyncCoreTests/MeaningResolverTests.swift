import XCTest
@testable import SpellingSyncCore

/// 練習ヒントに出す「意味（訳）」の決め方。登録/取り込み時にユーザーが持っている訳(promptText)を
/// 最優先し、無いときだけ同梱辞書(EJDict)の第1語義に落とす（EJDictの変な第1語義が手入力訳を上書きしない）。
final class MeaningResolverTests: XCTestCase {
    /// 単語リストの訳(promptText)があれば、それをそのまま最優先で使う。
    func testPrefersStoredPromptText() {
        XCTAssertEqual(
            MeaningResolver.resolve(promptText: "たくさん", dictionaryGloss: "くじ"),
            "たくさん"
        )
    }

    /// promptText は「第1語義切り出し」に通さない（手入力の訳は丸ごと保つ）。
    func testKeepsStoredPromptWholeWithoutSenseSplitting() {
        XCTAssertEqual(
            MeaningResolver.resolve(promptText: "あそぶ、ゲームをする", dictionaryGloss: nil),
            "あそぶ、ゲームをする"
        )
    }

    /// promptText が空/空白なら、同梱辞書(EJDict)の第1語義にフォールバックする。
    func testFallsBackToDictionaryFirstSenseWhenPromptEmpty() {
        XCTAssertEqual(
            MeaningResolver.resolve(promptText: "   ", dictionaryGloss: "受け取る,得る,理解する"),
            "受け取る"
        )
        XCTAssertEqual(
            MeaningResolver.resolve(promptText: nil, dictionaryGloss: "りんご"),
            "りんご"
        )
    }

    /// どちらも無ければ nil（呼び出し側は意味を出さない）。
    func testReturnsNilWhenBothMissing() {
        XCTAssertNil(MeaningResolver.resolve(promptText: nil, dictionaryGloss: nil))
        XCTAssertNil(MeaningResolver.resolve(promptText: "", dictionaryGloss: "   "))
    }
}
