import XCTest
@testable import SpellingSyncCore

/// 出題プールの絞り込み（実装フェーズ① 必須土台＝プール側）。
///
/// 子の段階 → 出題制約を1か所に集約し、生成プール（文）を絞る純関数。
/// 壁＝語彙band（ゆるい上限）／文法天井／漢字／ジャンル（humorトグル）／i+1。
/// **親登録語そのものは tier 例外**（band表で救済）。i+1 は登録語を「許される未知語1語」として数える。
final class ContentPolicyTests: XCTestCase {

    private func item(_ en: String, ja: String = "ねこ", band: Int,
                      grammar: GrammarPoint? = nil, lemmas: [String] = [],
                      genre: Genre? = nil) -> SentenceItem {
        SentenceItem(en: en, ja: ja, tokens: en.split(separator: " ").map(String.init),
                     gradeBand: band, contentLemmas: lemmas, grammar: grammar,
                     sourceID: nil, genre: genre)
    }

    private func policy(targetBand: Int = 2, ceiling: GrammarStage = .applied,
                        kanji: Int = 0, genres: Set<Genre> = [.useful],
                        iPlus1: Int = 1) -> ContentPolicy {
        ContentPolicy(targetBand: targetBand, grammarCeiling: ceiling, maxKanjiGrade: kanji,
                      enabledGenres: genres, maxNewLemmasPerSentence: iPlus1)
    }

    // 語彙band：上限超えは落とす。
    func testBandWall() {
        let items = [item("a", band: 2, lemmas: ["cat"]), item("b", band: 4, lemmas: ["rocket"])]
        let out = ContentPolicy.admissiblePool(items, policy: policy(targetBand: 2),
                                               knownLemmas: ["cat", "rocket"])
        XCTAssertEqual(out.map(\.en), ["a"])
    }

    // tier例外：上限超えの原因が登録語だけなら、band表で救済して残す。
    func testRegisteredWordIsBandExempt() {
        // "rocket"(band4) は登録語＝例外。残りの内容語 "like"(band1) は上限内。
        let it = item("I like rocket", band: 4, lemmas: ["like", "rocket"])
        let out = ContentPolicy.admissiblePool(
            [it], policy: policy(targetBand: 2),
            knownLemmas: ["like"],
            exemptRegisteredLemmas: ["rocket"],
            bandOf: ["like": 1, "rocket": 4])
        XCTAssertEqual(out.count, 1, "登録語以外が上限内なら救済して残す")
    }

    // tier例外：登録語“以外”に上限超えがあれば救済しない。
    func testNonExemptOverBandStillRejected() {
        let it = item("big rocket", band: 4, lemmas: ["big", "rocket"])
        let out = ContentPolicy.admissiblePool(
            [it], policy: policy(targetBand: 2),
            knownLemmas: ["big"],
            exemptRegisteredLemmas: ["rocket"],
            bandOf: ["big": 3, "rocket": 4])  // big(3) が上限2超え
        XCTAssertTrue(out.isEmpty)
    }

    // tier例外：非例外語の band が表に無ければ救済しない（不明を“安全”扱いしない）。
    func testRescueRejectsWhenNonExemptBandUnknown() {
        let it = item("big rocket", band: 4, lemmas: ["big", "rocket"])
        let out = ContentPolicy.admissiblePool(
            [it], policy: policy(targetBand: 2),
            knownLemmas: ["big"],
            exemptRegisteredLemmas: ["rocket"],
            bandOf: ["rocket": 4])  // big の band 不明 → 救済しない
        XCTAssertTrue(out.isEmpty, "非例外語の band 不明時は安全側で落とす")
    }

    // i+1：同じ未知語が重複しても二重計上しない（異なり数で数える）。
    func testIPlus1CountsDistinctNotOccurrences() {
        let it = item("apple apple", band: 1, lemmas: ["apple", "apple"])
        let out = ContentPolicy.admissiblePool([it],
            policy: policy(iPlus1: 1), knownLemmas: [])  // apple 1種だけ＝+1
        XCTAssertEqual(out.count, 1, "重複未知語は1語として数える")
    }

    // i+1：登録語が knownLemmas にあっても +1 を必ず消費する（登録語＝許される未知語1）。
    func testIPlus1RegisteredAlwaysConsumesBudget() {
        // apple(登録語・既知扱い) ＋ orange(未知) ＝ 実質2語 → 上限1で落とす。
        let it = item("apple orange", band: 1, lemmas: ["apple", "orange"])
        let out = ContentPolicy.admissiblePool([it],
            policy: policy(iPlus1: 1),
            knownLemmas: ["apple"],                 // apple は既知だが…
            exemptRegisteredLemmas: ["apple"])      // …登録語なので +1 を消費
        XCTAssertTrue(out.isEmpty, "登録語＋別の未知語＝2語で上限超過")
    }

    // 文法天井：超える文法は落とす（nil文法は通す）。
    func testGrammarCeiling() {
        let easy = item("x", band: 1, grammar: .presentSimple, lemmas: ["cat"])   // intro1
        let hard = item("y", band: 1, grammar: .presentPerfect, lemmas: ["cat"])  // applied
        let out = ContentPolicy.admissiblePool([easy, hard],
            policy: policy(ceiling: .intro2), knownLemmas: ["cat"])
        XCTAssertEqual(out.map(\.en), ["x"])
    }

    // 漢字は「捨てる」でなくルビ（§13.3 改訂2026-07-02）：超過漢字を含む和訳でも却下しない。
    // 難度は語彙band で担保し、表示側 rubySegments が当該学年以上の漢字にふりがなを振る。
    func testKanjiDoesNotRejectAdmission() {
        let hira = item("a", ja: "ねこ", band: 1, lemmas: ["cat"])
        let kanji = item("b", ja: "図書館", band: 1, lemmas: ["cat"])  // 超過漢字入りでも通す
        let out = ContentPolicy.admissiblePool([hira, kanji],
            policy: policy(kanji: 0), knownLemmas: ["cat"])  // maxGrade 0 でも却下しない
        XCTAssertEqual(out.map(\.en), ["a", "b"], "漢字では却下しない（表示側でルビ）")
    }

    // ジャンル：humor が無効なら humor 文を除外（nil は useful 扱い）。
    func testGenreToggleExcludesHumor() {
        let useful = item("u", band: 1, lemmas: ["cat"], genre: .useful)
        let humor = item("h", band: 1, lemmas: ["cat"], genre: .humor)
        let plain = item("p", band: 1, lemmas: ["cat"], genre: nil)
        let out = ContentPolicy.admissiblePool([useful, humor, plain],
            policy: policy(genres: [.useful]), knownLemmas: ["cat"])
        XCTAssertEqual(out.map(\.en), ["u", "p"], "humor は除外・nilはuseful扱いで残る")
    }

    func testGenreToggleIncludesHumorWhenEnabled() {
        let humor = item("h", band: 1, lemmas: ["cat"], genre: .humor)
        let out = ContentPolicy.admissiblePool([humor],
            policy: policy(genres: [.useful, .humor]), knownLemmas: ["cat"])
        XCTAssertEqual(out.count, 1)
    }

    // i+1：未知語が登録語1つだけなら通る。
    func testIPlus1AllowsSingleNewWord() {
        let it = item("I like apple", band: 1, lemmas: ["like", "apple"])
        let out = ContentPolicy.admissiblePool([it],
            policy: policy(iPlus1: 1), knownLemmas: ["like"])  // apple のみ未知＝+1
        XCTAssertEqual(out.count, 1)
    }

    // i+1：未知語が2つ以上なら落とす。
    func testIPlus1RejectsTwoNewWords() {
        let it = item("apple orange", band: 1, lemmas: ["apple", "orange"])
        let out = ContentPolicy.admissiblePool([it],
            policy: policy(iPlus1: 1), knownLemmas: [])  // どちらも未知＝+2
        XCTAssertTrue(out.isEmpty)
    }

    // SentenceItem.genre は optional：nil はJSON出力から省かれる（既存同梱物 byte 不変）。
    func testGenreOmittedWhenNil() throws {
        let it = item("a", band: 1, lemmas: ["cat"], genre: nil)
        let json = String(data: try JSONEncoder().encode(it), encoding: .utf8)!
        XCTAssertFalse(json.contains("genre"), "nil の genre は出力に出さない")
    }

    // MARK: - 段階(tier) → 標準ポリシー（spec §5 4段階表）

    // 段階ごとの文法天井・漢字学年が spec の表どおりか。
    func testStandardPolicyPerTier() {
        let a = ContentPolicy.standard(tier: .a, humorEnabled: false)
        XCTAssertEqual(a.grammarCeiling, .intro1)
        XCTAssertEqual(a.maxKanjiGrade, 0)

        let b = ContentPolicy.standard(tier: .b, humorEnabled: false)
        XCTAssertEqual(b.grammarCeiling, .intro2)
        XCTAssertEqual(b.maxKanjiGrade, 2)

        let c = ContentPolicy.standard(tier: .c, humorEnabled: false)
        XCTAssertEqual(c.grammarCeiling, .basic1)
        XCTAssertEqual(c.maxKanjiGrade, 4)

        let d = ContentPolicy.standard(tier: .d, humorEnabled: false)
        XCTAssertEqual(d.grammarCeiling, .applied)
        XCTAssertEqual(d.maxKanjiGrade, 6)
    }

    // band は“ゆるい上限”（学年差を付けない）＝全段階で同じ緩い値。
    func testStandardPolicyBandIsLooseAndConstant() {
        let bands = ContentTier.allCases.map { ContentPolicy.standard(tier: $0, humorEnabled: false).targetBand }
        XCTAssertEqual(Set(bands).count, 1, "band は段階で変えない（ゆるい上限）")
        XCTAssertGreaterThanOrEqual(bands[0], 5, "rare語落とし用のゆるい上限（最高band以上）")
    }

    // i+1 は段階別既知語リスト導入前なので“無効（実質無制限）”。
    func testStandardPolicyIPlus1DisabledForNow() {
        let p = ContentPolicy.standard(tier: .a, humorEnabled: false)
        // 既知語ゼロでも、内容語が複数ある文を i+1 で落とさない。
        let it = item("apple orange grape", band: 1, lemmas: ["apple", "orange", "grape"])
        let out = ContentPolicy.admissiblePool([it], policy: p, knownLemmas: [])
        XCTAssertEqual(out.count, 1, "i+1 は今は効かせない（既知語リスト未導入）")
    }

    // ジャンル：humor トグル ON のときだけ humor を許可。useful/story は常に許可。
    func testStandardPolicyHumorToggle() {
        let off = ContentPolicy.standard(tier: .a, humorEnabled: false)
        XCTAssertTrue(off.enabledGenres.contains(.useful))
        XCTAssertTrue(off.enabledGenres.contains(.story))
        XCTAssertFalse(off.enabledGenres.contains(.humor), "humor OFF なら除外")

        let on = ContentPolicy.standard(tier: .a, humorEnabled: true)
        XCTAssertTrue(on.enabledGenres.contains(.humor), "humor ON なら許可")
    }
}
