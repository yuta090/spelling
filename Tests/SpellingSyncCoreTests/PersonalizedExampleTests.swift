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
}
