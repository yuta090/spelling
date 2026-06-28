import XCTest
@testable import SpellingSyncCore

/// SentenceBankBuilder：学年タグ付け・壁・適切性・重複・決定論idを固定する。
/// 重要：壁は「文中の見える内容語すべて」に効く（著者 lemma に頼らない）。
final class SentenceBankBuilderTests: XCTestCase {

    private let band: [String: Int] = [
        "like": 1, "apple": 1, "friend": 1, "run": 1, "fast": 1, "read": 1, "book": 1,
        "play": 1, "soccer": 2, "bag": 1, "big": 2, "dog": 1, "cat": 1, "rocket": 4,
        "red": 2, "see": 1, "finish": 1,
    ]

    private func cand(_ en: String, _ ja: String = "和訳",
                      grammar: GrammarPoint? = nil, declaredBand: Int? = nil,
                      source: String = "curated") -> SentenceBankBuilder.Candidate {
        .init(en: en, ja: ja, grammar: grammar, declaredBand: declaredBand, source: source)
    }

    // 採用：内容語は見えるトークンから導く。gradeBand=内容語の最大band。tokens・grammar保持。
    func testAcceptDerivesContentFromTokens() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("She likes apples", "かのじょは りんごが すき", grammar: .presentSimple)],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.rejected.count, 0)
        let item = r.accepted.first
        XCTAssertEqual(item?.tokens, ["She", "likes", "apples"])
        XCTAssertEqual(item?.gradeBand, 1)
        XCTAssertEqual(item?.contentLemmas, ["like", "apple"])  // likes→like, apples→apple
        XCTAssertEqual(item?.grammar, .presentSimple)
        XCTAssertEqual(item?.en, "She likes apples")
    }

    // gradeBand は内容語の最大（bigger→big=2）。
    func testGradeBandIsMaxOfContentWords() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("Her bag is bigger", grammar: .comparativeEr)],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.accepted.first?.gradeBand, 2)
    }

    // 機能語を除き、語形変化を lemma 化して band 解決。
    func testAutoContentExtractionAndLemmatize() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("The dog runs")],  // the=機能語, dog=1, runs→run=1
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.rejected.count, 0)
        XCTAssertEqual(r.accepted.first?.gradeBand, 1)
        XCTAssertEqual(r.accepted.first?.contentLemmas, ["dog", "run"])
    }

    // 壁は見える全語に効く：lemma に含まれない可視語 red(band2) を見落とさない（回帰）。
    func testWallChecksAllVisibleWords() {
        // declaredBand=1 でも red(band2) は level で解決されるので gradeBand=2 になる。
        let accepted = SentenceBankBuilder.build(
            candidates: [cand("He has a red pencil", declaredBand: 1)],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(accepted.accepted.first?.gradeBand, 2)   // 1 ではなく 2
        // 対象band=1 の子には出さない（red が壁を超える）。
        let blocked = SentenceBankBuilder.build(
            candidates: [cand("He has a red pencil", declaredBand: 1)],
            band: band, targetBand: 1, grammarCeiling: .applied)
        XCTAssertEqual(blocked.accepted.count, 0)
        XCTAssertEqual(blocked.rejected.first?.reason, .overTargetBand("red", 2))
    }

    // curated（宣言バンドあり）：level 未収録語は採用し警告に留める（②と同じ＝壊さない）。
    func testCuratedTrustsDeclaredBandForUnleveledWord() {
        let noApple = band.filter { $0.key != "apple" }
        let r = SentenceBankBuilder.build(
            candidates: [cand("She likes apples", grammar: .presentSimple, declaredBand: 1)],
            band: noApple, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.rejected.count, 0)
        XCTAssertEqual(r.accepted.first?.gradeBand, 1)
        XCTAssertEqual(r.accepted.first?.contentLemmas, ["like", "apples"])  // 解決不能語は表層のまま
        XCTAssertEqual(r.warnings.count, 1)
        XCTAssertEqual(r.warnings.first?.kind, .contentWordNotLeveled("apples"))
    }

    // declaredBand 信頼でも対象band超なら不採用（壁は守る）。
    func testDeclaredBandOverTargetRejected() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("I like xyzzy", declaredBand: 5)],  // xyzzy は未収録
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.accepted.count, 0)
        XCTAssertEqual(r.rejected.first?.reason, .overTargetBand("xyzzy", 5))
    }

    // tanaka（宣言バンド無し）：未収録の内容語があれば不採用。
    func testRejectUnleveledContentWord() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("I like zorblax", source: "tanaka")],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.accepted.count, 0)
        XCTAssertEqual(r.rejected.first?.reason, .unleveledContentWord("zorblax"))
    }

    // 解決済み語が対象band超なら不採用（rocket=4 > target3）。
    func testRejectOverTargetBand() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("I see a rocket")],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.accepted.count, 0)
        XCTAssertEqual(r.rejected.first?.reason, .overTargetBand("rocket", 4))
    }

    // 文法の壁：上限超で不採用（語彙チェックより先）。
    func testRejectGrammarOverCeiling() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("I have finished", grammar: .presentPerfect)],
            band: band, targetBand: 3, grammarCeiling: .intro1)
        XCTAssertEqual(r.accepted.count, 0)
        XCTAssertEqual(r.rejected.first?.reason, .grammarOverCeiling(.applied))
    }

    // 語数の壁。
    func testTooFewAndTooManyTokens() {
        let few = SentenceBankBuilder.build(
            candidates: [cand("Hello")],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(few.rejected.first?.reason, .tooFewTokens)

        let many = SentenceBankBuilder.build(
            candidates: [cand("a a a a a a")],
            band: band, targetBand: 3, grammarCeiling: .applied, maxTokens: 5)
        XCTAssertEqual(many.rejected.first?.reason, .tooManyTokens(6))
    }

    // 不適切語ブロックリスト（語彙チェックより先・原形でも照合）。
    func testBlocklist() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("I like beer", source: "tanaka")],
            band: band, targetBand: 3, grammarCeiling: .applied, blocklist: ["beer"])
        XCTAssertEqual(r.accepted.count, 0)
        XCTAssertEqual(r.rejected.first?.reason, .blockedWord("beer"))
    }

    // 重複（正規化トークン列が同じ）は後勝ちを弾く。
    func testDuplicate() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("The dog runs"), cand("the dog runs.")],
            band: band, targetBand: 3, grammarCeiling: .applied)
        XCTAssertEqual(r.accepted.count, 1)
        XCTAssertEqual(r.rejected.first?.reason, .duplicate)
    }

    // 決定論id：同じ文は再実行でも同一id。
    func testDeterministicID() {
        let make = {
            SentenceBankBuilder.build(
                candidates: [self.cand("The dog runs")],
                band: self.band, targetBand: 3, grammarCeiling: .applied).accepted.first?.id
        }
        XCTAssertNotNil(make())
        XCTAssertEqual(make(), make())
    }

    // serialize → decode 往復で一致。
    func testSerializeRoundTrip() {
        let r = SentenceBankBuilder.build(
            candidates: [cand("She likes apples", grammar: .presentSimple), cand("The dog runs")],
            band: band, targetBand: 3, grammarCeiling: .applied)
        let json = SentenceBankBuilder.serialize(r.accepted)
        let back = SentenceBankBuilder.decode(json: json)
        XCTAssertEqual(back, r.accepted)
    }

    // 句読点除去：前後の記号は落とし内部は残す。
    func testTokenizeStripsEdgePunctuation() {
        XCTAssertEqual(SentenceBankBuilder.tokenize("Hello, world!"), ["Hello", "world"])
        XCTAssertEqual(SentenceBankBuilder.tokenize("don't run."), ["don't", "run"])
        XCTAssertEqual(SentenceBankBuilder.tokenize("  spaced   out  "), ["spaced", "out"])
    }
}
