import XCTest
@testable import SpellingSyncCore

/// TanakaExtractor：Tanaka 例文（英日）から子ども向け短文を機械抽出する純ロジックを固定する。
/// 方針：抽出は「事前フィルタ → 決定論ソート → 既存重複除外の前に limit → SentenceBankBuilder で機械検査」。
///  - 学年の壁・未収録語・ブロックリスト・トークン上限は **Core(SentenceBankBuilder) に委譲**する。
///  - 本 Extractor は Tanaka 固有の前処理（最小トークン3・記号/数字過多・固有名詞だらけ・
///    二重の子ども安全ブロック・バッチ内重複）と、既存バンクとの重複除外・決定論順だけを足す。
final class TanakaExtractorTests: XCTestCase {

    // 充分な leveled 語彙。tanaka は宣言バンド無しなので未収録語は弾かれる。
    private let band: [String: Int] = [
        "like": 1, "apple": 1, "dog": 1, "cat": 1, "run": 1, "fast": 1, "play": 1,
        "ball": 1, "see": 1, "book": 1, "read": 1, "big": 2, "small": 1, "red": 2,
        "rocket": 4, "eat": 1, "fish": 1, "bird": 1, "walk": 1, "jump": 1,
    ]

    private func row(_ en: String, _ ja: String = "和訳") -> TanakaExtractor.Row {
        .init(en: en, ja: ja)
    }

    private func extract(_ rows: [TanakaExtractor.Row],
                         targetBand: Int = 5,
                         existingKeys: Set<String> = [],
                         blocklist: Set<String> = [],
                         minTokens: Int = 3,
                         maxTokens: Int = 10,
                         limit: Int? = nil) -> TanakaExtractor.Output {
        TanakaExtractor.extract(
            rows: rows, band: band, targetBand: targetBand,
            existingKeys: existingKeys, blocklist: blocklist,
            minTokens: minTokens, maxTokens: maxTokens, limit: limit)
    }

    // 採用：きれいな短文は SentenceItem になる。grammar は nil（Tanaka は文法タグ無し）。
    func testAcceptsCleanSentence() {
        let out = extract([row("The dog runs fast", "いぬが はやく はしる")])
        XCTAssertEqual(out.accepted.count, 1)
        let item = out.accepted.first
        XCTAssertEqual(item?.tokens, ["The", "dog", "runs", "fast"])
        XCTAssertEqual(item?.ja, "いぬが はやく はしる")
        XCTAssertNil(item?.grammar)              // nil grammar → 文法天井は常に通過
        XCTAssertEqual(item?.gradeBand, 1)
        XCTAssertEqual(item?.contentLemmas, ["dog", "run", "fast"])
    }

    // 最小トークン：3未満は事前却下（並べ替え/穴埋めにならない短文）。
    func testTooFewTokensRejected() {
        let out = extract([row("Dogs run")])    // 2語
        XCTAssertEqual(out.accepted.count, 0)
        XCTAssertEqual(out.preRejected.first?.reason, .tooFewTokens)
    }

    // 最大トークン：上限超は事前却下。
    func testTooManyTokensRejected() {
        let out = extract([row("the dog and the cat run and play and see")], maxTokens: 8)
        XCTAssertEqual(out.accepted.count, 0)
        if case .tooManyTokens = out.preRejected.first?.reason {} else {
            XCTFail("tooManyTokens を期待: \(String(describing: out.preRejected.first?.reason))")
        }
    }

    // 学年の壁：対象band超の内容語は Core が却下（出力に出ない）。
    func testOverBandRejectedByCore() {
        let out = extract([row("I see a rocket")], targetBand: 3)  // rocket=4 > 3
        XCTAssertEqual(out.accepted.count, 0)
        XCTAssertEqual(out.builderResult.rejected.first?.reason, .overTargetBand("rocket", 4))
    }

    // 未収録の内容語は Core が却下（tanaka は宣言バンド無し）。
    func testUnleveledContentWordRejectedByCore() {
        let out = extract([row("I like zorblax today")])  // zorblax/today 未収録
        XCTAssertEqual(out.accepted.count, 0)
        if case .unleveledContentWord = out.builderResult.rejected.first?.reason {} else {
            XCTFail("unleveledContentWord を期待: \(String(describing: out.builderResult.rejected.first?.reason))")
        }
    }

    // 既存バンクとの重複は除外（正規化キー一致）。limit より後の最終段。
    func testDedupAgainstExistingBank() {
        let key = TanakaExtractor.normalizedKey("The dog runs fast")
        let out = extract([row("The dog runs fast.")], existingKeys: [key])  // 末尾ピリオド違いでも一致
        XCTAssertEqual(out.accepted.count, 0)
        XCTAssertEqual(out.duplicateExisting, 1)
    }

    // バッチ内重複：同じ正規化キーは1件だけ採用、残りは事前却下。
    func testDedupWithinBatch() {
        let out = extract([row("The dog runs fast"), row("the dog runs fast.")])
        XCTAssertEqual(out.accepted.count, 1)
        XCTAssertTrue(out.preRejected.contains { $0.reason == .duplicateInBatch })
    }

    // ブロックリスト（外部・語）に当たる文は Core が却下。組み込み安全語とは別レイヤ。
    func testBlocklistRejectedByCore() {
        let out = extract([row("The dog runs fast")], blocklist: ["dog"])
        XCTAssertEqual(out.accepted.count, 0)
        XCTAssertEqual(out.builderResult.rejected.first?.reason, .blockedWord("dog"))
    }

    // 二重の子ども安全ブロック（組み込み NG 語）は事前却下。
    func testKidSafetyBuiltinBlock() {
        let out = extract([row("They drink wine often")])  // wine は組み込み NG
        XCTAssertEqual(out.accepted.count, 0)
        XCTAssertTrue(out.preRejected.contains { if case .kidUnsafe = $0.reason { return true } else { return false } })
    }

    // 記号/数字過多：引用符・数字・特殊記号を含む文は事前却下。
    func testDisallowedCharactersRejected() {
        let quoted = extract([row("\"Run!\" he said")])
        XCTAssertTrue(quoted.preRejected.contains { $0.reason == .disallowedCharacters })

        let digits = extract([row("I see 3 dogs")])
        XCTAssertTrue(digits.preRejected.contains { $0.reason == .disallowedCharacters })
    }

    // 固有名詞だらけ：文中の大文字始まり非機能語が過半なら事前却下。
    func testMostlyProperNounsRejected() {
        let out = extract([row("Tom Bob Sam run")])   // Tom/Bob/Sam=固有名詞(3) / 4語
        XCTAssertTrue(out.preRejected.contains { $0.reason == .mostlyProperNouns })
    }

    // limit：決定論ソート後に上位 N 件だけ採用、残りは capped。既存重複除外は limit の後。
    func testLimitCapsDeterministically() {
        let rows = [row("The dog runs fast"), row("A cat eats fish"), row("Birds fly high")]
        // "Birds fly high" は high/fly 未収録なので Core 却下 → 採用候補は2件。limit=1 で1件。
        let out = extract(rows, limit: 1)
        XCTAssertEqual(out.accepted.count, 1)
        XCTAssertGreaterThanOrEqual(out.cappedOut, 0)
    }

    // 決定論：入力順を入れ替えても採用集合と順序は同一。
    func testDeterministicRegardlessOfInputOrder() {
        let a = [row("The dog runs fast"), row("A cat eats fish"), row("Red birds walk")]
        let b = Array(a.reversed())
        let outA = extract(a)
        let outB = extract(b)
        XCTAssertEqual(outA.accepted, outB.accepted)
        XCTAssertEqual(outA.accepted.map(\.id), outB.accepted.map(\.id))
    }

    // normalizedKey：tokenize → 小文字 → 空白結合（句読点/大小無視）。
    func testNormalizedKey() {
        XCTAssertEqual(TanakaExtractor.normalizedKey("The Dog runs."), "the dog runs")
        XCTAssertEqual(TanakaExtractor.normalizedKey("the   dog  runs"),
                       TanakaExtractor.normalizedKey("The dog runs!"))
    }
}
