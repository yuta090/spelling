import XCTest
@testable import SpellingSyncCore

/// 練習中の例文ヒントを「Castで名前入りに差し替える」純粋ロジックの仕様。
/// 対象語を教えるテンプレ（contentLemmas に語を含む・スロットあり）を決定論的に1件選び、
/// Cast で解決して返す。名前を埋められない（＝fallback になる）ときは nil（既存の静的例文に任せる）。
final class PersonalizedExampleTests: XCTestCase {

    // MARK: 固定キャスト（id 固定で決定論）

    private func person(_ idByte: UInt8, _ role: CastRole, _ gender: PersonGender,
                        _ ja: String, _ romaji: String, active: Bool = true) -> CastPerson {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = idByte
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return CastPerson(id: UUID(uuid: t), role: role, gender: gender,
                          displayNameJa: ja, romaji: romaji, isActive: active)
    }

    private var yuki: CastPerson { person(2, .friend, .girl, "ゆき", "Yuki") }
    private var ken: CastPerson { person(3, .friend, .boy, "けん", "Ken") }

    private func fallback(_ en: String, _ ja: String, _ tokens: [String]) -> SentenceItem {
        SentenceItem(en: en, ja: ja, tokens: tokens, gradeBand: 1)
    }

    /// 友達(女の子)1人を主語にした「りんご(apple)」テンプレ。
    private func likeApples(id: String = "like-apples") -> PersonSentenceTemplate {
        PersonSentenceTemplate(
            id: id,
            category: .school,
            fallback: fallback("She likes apples", "かのじょは りんごが すき", ["She", "likes", "apples"]),
            enTokens: [.person(slot: "f", form: .name), .literal("likes"), .literal("apples")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" りんごが すき")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1,
            contentLemmas: ["like", "apple"]
        )
    }

    /// 友達(男の子)1人を主語にした「はしる(run)」テンプレ。
    private func canRun(id: String = "can-run") -> PersonSentenceTemplate {
        PersonSentenceTemplate(
            id: id,
            category: .play,
            fallback: fallback("He can run fast", "かれは はやく はしれる", ["He", "can", "run", "fast"]),
            enTokens: [.person(slot: "b", form: .name), .literal("can"), .literal("run"), .literal("fast")],
            jaParts: [.person(slot: "b", suffix: "は"), .literal(" はやく はしれる")],
            slots: [PersonSlotSpec(key: "b", role: .friend, requiredGender: .boy)],
            gradeBand: 1,
            contentLemmas: ["run", "fast"]
        )
    }

    // MARK: 1. 対象語に一致＋Castありで名前入り例文が返る

    func testReturnsPersonalizedSentenceForMatchingWord() {
        let cast = Cast(people: [yuki])
        let item = PersonalizedExample.sentence(for: "apple", templates: [likeApples()], cast: cast, seed: 7)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.en, "Yuki likes apples")
        XCTAssertEqual(item?.ja, "ゆきは りんごが すき")
    }

    // MARK: 2. どのテンプレの contentLemmas にも無い語 → nil

    func testReturnsNilWhenNoTemplateTeachesWord() {
        let cast = Cast(people: [yuki, ken])
        let item = PersonalizedExample.sentence(for: "zebra", templates: [likeApples(), canRun()], cast: cast, seed: 7)
        XCTAssertNil(item)
    }

    // MARK: 3. Castが空（スロットを埋められない）→ fallback は出さず nil

    func testReturnsNilWhenCastCannotFillSlots() {
        let item = PersonalizedExample.sentence(for: "apple", templates: [likeApples()], cast: Cast(people: []), seed: 7)
        XCTAssertNil(item, "名前が入らないなら静的例文に任せる（fallbackは出さない）")
    }

    // MARK: 4. 大文字小文字を無視して一致

    func testWordMatchingIsCaseInsensitive() {
        let cast = Cast(people: [yuki])
        let item = PersonalizedExample.sentence(for: "Apple", templates: [likeApples()], cast: cast, seed: 7)
        XCTAssertEqual(item?.en, "Yuki likes apples")
    }

    // MARK: 5. 同じ入力 → 同じ出力（決定論）

    func testDeterministicForSameInputs() {
        let cast = Cast(people: [yuki])
        let a = PersonalizedExample.sentence(for: "apple", templates: [likeApples(id: "t1"), likeApples(id: "t2")], cast: cast, seed: 99)
        let b = PersonalizedExample.sentence(for: "apple", templates: [likeApples(id: "t1"), likeApples(id: "t2")], cast: cast, seed: 99)
        XCTAssertEqual(a, b)
        XCTAssertNotNil(a)
    }

    // MARK: 6. スロットの無い（名前が入りようがない）テンプレだけなら nil

    func testIgnoresTemplatesWithoutSlots() {
        let generic = PersonSentenceTemplate(
            id: "generic-apple",
            category: .school,
            fallback: fallback("I like apples", "わたしは りんごが すき", ["I", "like", "apples"]),
            enTokens: [.literal("I"), .literal("like"), .literal("apples")],
            jaParts: [.literal("わたしは りんごが すき")],
            slots: [],
            gradeBand: 1,
            contentLemmas: ["like", "apple"]
        )
        let item = PersonalizedExample.sentence(for: "apple", templates: [generic], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertNil(item)
    }

    // MARK: 7. 文中に実際に現れる表層形（屈折形）にも一致する

    // likeApples の例文は「{f} likes apples」＝表層形 "likes" "apples" を含み、
    // contentLemmas は ["like","apple"]。基本形も屈折形も当たる。

    func testMatchesSurfacePlural() {            // "apples" は文中に出る
        let item = PersonalizedExample.sentence(for: "apples", templates: [likeApples()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertEqual(item?.en, "Yuki likes apples")
    }

    func testMatchesSurfaceThirdPersonS() {      // "likes" も文中に出る
        let item = PersonalizedExample.sentence(for: "likes", templates: [likeApples()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertEqual(item?.en, "Yuki likes apples")
    }

    func testMatchesBaseLemmaEvenWhenSentenceInflected() {  // 文は複数形でも基本形 "apple" で当たる
        let item = PersonalizedExample.sentence(for: "apple", templates: [likeApples()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertEqual(item?.en, "Yuki likes apples")
    }

    // MARK: 8. 実在語どうしの誤マッチが起きない（reviewer 指摘の回帰）

    /// 「see」を教える文（"can see well"）。表層形は see/can/well。
    private func canSee() -> PersonSentenceTemplate {
        PersonSentenceTemplate(
            id: "can-see",
            category: .school,
            fallback: fallback("She can see well", "かのじょは よく みえる", ["She", "can", "see", "well"]),
            enTokens: [.person(slot: "f", form: .name), .literal("can"), .literal("see"), .literal("well")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" よく みえる")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1,
            contentLemmas: ["see", "well"]
        )
    }

    func testDoesNotFalseMatchSeedAgainstSee() { // "seed" は "see" の文に存在しない → nil
        let item = PersonalizedExample.sentence(for: "seed", templates: [canSee()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertNil(item, "see+d=seed の機械生成で誤って当ててはいけない")
    }

    func testStillMatchesActualSurfaceAndLemma() { // see / well は当たる
        XCTAssertNotNil(PersonalizedExample.sentence(for: "see", templates: [canSee()], cast: Cast(people: [yuki]), seed: 7))
        XCTAssertNotNil(PersonalizedExample.sentence(for: "well", templates: [canSee()], cast: Cast(people: [yuki]), seed: 7))
    }

    func testDoesNotFalseMatchGoodsAgainstGood() { // "goods" は good を教える文に出ない → nil
        let item = PersonalizedExample.sentence(for: "goods", templates: [canSee()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertNil(item)
    }

    // MARK: 9. 表層形の前後句読点は無視して一致

    func testSurfaceWordIgnoresTrailingPunctuation() {
        let withComma = PersonSentenceTemplate(
            id: "run-fast-comma",
            category: .play,
            fallback: fallback("She runs fast", "かのじょは はやい", ["She", "runs", "fast"]),
            enTokens: [.person(slot: "f", form: .name), .literal("runs"), .literal("fast!")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" はやい")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1,
            contentLemmas: ["run"]   // ※ "fast" は lemma に無く、表層 "fast!" からのみ当てる
        )
        let item = PersonalizedExample.sentence(for: "fast", templates: [withComma], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertNotNil(item, "末尾の感嘆符を落として fast に一致すべき")
    }

    // MARK: 10. 登録名と同じ綴りの語は人物トークン経由で誤マッチしない（プライバシー）

    func testPractisedWordEqualToCastNameDoesNotMatch() {
        // likeApples の人物トークンは解決後に "Yuki" になるが、照合は .literal のみ見る。
        // 子が綴り練習語として "yuki" をやっても、この文の対象語にはならない（nil）。
        let item = PersonalizedExample.sentence(for: "yuki", templates: [likeApples()], cast: Cast(people: [yuki]), seed: 7)
        XCTAssertNil(item, "名前(人物スロット)を対象語として拾ってはいけない")
    }

    // MARK: 11. 明示的な good テンプレでも goods は誤マッチしない

    func testGoodTemplateDoesNotMatchGoods() {
        let goodTemplate = PersonSentenceTemplate(
            id: "is-good-at-math",
            category: .school,
            fallback: fallback("She is good at math", "かのじょは さんすうが とくい", ["She", "is", "good", "at", "math"]),
            enTokens: [.person(slot: "f", form: .name), .literal("is"), .literal("good"), .literal("at"), .literal("math")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" さんすうが とくい")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1,
            contentLemmas: ["good", "math"]
        )
        XCTAssertNil(PersonalizedExample.sentence(for: "goods", templates: [goodTemplate], cast: Cast(people: [yuki]), seed: 7))
        XCTAssertNotNil(PersonalizedExample.sentence(for: "good", templates: [goodTemplate], cast: Cast(people: [yuki]), seed: 7))
    }
}
