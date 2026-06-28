import XCTest
@testable import SpellingSyncCore

/// `PersonalizedSessionBuilder.build` の純粋ロジック検証。
/// 役割：テンプレ集＋Cast から、カテゴリ絞り込み・件数上限・決定論で
/// 解決済み `SentenceItem` 列を組む（クイズへ渡す1セッション分）。
final class PersonalizedSessionBuilderTests: XCTestCase {

    // MARK: 固定キャスト（id 固定で決定論）

    private func person(_ idByte: UInt8, _ role: CastRole, _ gender: PersonGender,
                        _ ja: String, _ romaji: String) -> CastPerson {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = idByte
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return CastPerson(id: UUID(uuid: t), role: role, gender: gender,
                          displayNameJa: ja, romaji: romaji)
    }

    private var yuta: CastPerson { person(1, .child, .boy, "ゆうた", "Yuta") }
    private var yuki: CastPerson { person(2, .friend, .girl, "ゆき", "Yuki") }
    private var ken: CastPerson { person(3, .friend, .boy, "けん", "Ken") }

    // MARK: テスト用テンプレ（カテゴリ違い・スロット有無を混ぜる）

    /// フォールバック文（本番ローダと同じく id を決定論生成して、テンプレ再構築でも安定させる）。
    private func det(_ key: String, en: String, ja: String, tokens: [String]) -> SentenceItem {
        SentenceItem(id: DeterministicHash.uuid("fallback\u{1f}" + key),
                     en: en, ja: ja, tokens: tokens, gradeBand: 1)
    }

    private func friendTemplate(_ id: String, _ category: SentenceCategory) -> PersonSentenceTemplate {
        PersonSentenceTemplate(
            id: id,
            category: category,
            fallback: det(id, en: "She likes apples", ja: "かのじょは りんごが すき",
                          tokens: ["She", "likes", "apples"]),
            enTokens: [.person(slot: "f", form: .name), .literal("likes"), .literal("apples")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" りんごが すき")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1,
            contentLemmas: ["like", "apple"]
        )
    }

    /// スロット無し（＝常にフォールバックの素の文を返す）テンプレ。
    private func plainTemplate(_ id: String, _ category: SentenceCategory, en: String) -> PersonSentenceTemplate {
        PersonSentenceTemplate(
            id: id,
            category: category,
            fallback: det(id, en: en, ja: "やくぶん", tokens: en.split(separator: " ").map(String.init)),
            enTokens: en.split(separator: " ").map { .literal(String($0)) },
            jaParts: [.literal("やくぶん")],
            slots: [],
            gradeBand: 1
        )
    }

    private var pool: [PersonSentenceTemplate] {
        [
            friendTemplate("a-school", .school),
            friendTemplate("b-school", .school),
            friendTemplate("c-play", .play),
            plainTemplate("d-greeting", .greeting, en: "See you tomorrow"),
            plainTemplate("e-greeting", .greeting, en: "Good morning"),
        ]
    }

    // MARK: 1. 件数上限：count を超えない／プールが小さければプール数

    func testRespectsCount() {
        let cast = Cast(people: [yuta, yuki, ken])
        XCTAssertEqual(PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: 3, seed: 1).count, 3)
        XCTAssertEqual(PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: 99, seed: 1).count, pool.count)
        XCTAssertTrue(PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: 0, seed: 1).isEmpty)
    }

    // MARK: 2. カテゴリ絞り込み（nil=全部）

    func testCategoryFilter() {
        let cast = Cast(people: [yuki])
        let school = PersonalizedSessionBuilder.build(templates: pool, cast: cast, category: .school, count: 10, seed: 1)
        XCTAssertEqual(school.count, 2)   // a-school / b-school のみ
        let greeting = PersonalizedSessionBuilder.build(templates: pool, cast: cast, category: .greeting, count: 10, seed: 1)
        XCTAssertEqual(greeting.count, 2) // d/e
        // 該当なしカテゴリ → 空
        XCTAssertTrue(PersonalizedSessionBuilder.build(templates: pool, cast: cast, category: .home, count: 10, seed: 1).isEmpty)
    }

    // MARK: 3. 決定論：同 seed→完全一致、別 seed→並び/選択が変わりうる

    func testDeterministicForSameSeed() {
        let cast = Cast(people: [yuta, yuki, ken])
        let a = PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: 3, seed: 42)
        let b = PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: 3, seed: 42)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedChangesSelection() {
        let cast = Cast(people: [yuta, yuki, ken])
        // 全件取り出し（count=pool数）でも、別 seed なら並びが変わるはず。
        let a = PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: pool.count, seed: 1)
        let b = PersonalizedSessionBuilder.build(templates: pool, cast: cast, count: pool.count, seed: 2)
        XCTAssertEqual(Set(a.map(\.en)), Set(b.map(\.en)))   // 同じ集合
        XCTAssertNotEqual(a.map(\.en), b.map(\.en))           // でも並びは変わる
    }

    // MARK: 4. フォールバック：Cast 空でも素の文（fallback）で件数分そろう

    func testEmptyCastUsesFallbacks() {
        let items = PersonalizedSessionBuilder.build(templates: pool, cast: Cast(people: []), count: 5, seed: 1)
        XCTAssertEqual(items.count, 5)
        // friend テンプレはフォールバック "She likes apples" になる（名前が出ない）
        XCTAssertTrue(items.contains { $0.en == "She likes apples" })
        XCTAssertFalse(items.contains { $0.en.contains("Yuki") })
    }

    // MARK: 5. テンプレ空 → 空

    func testEmptyTemplatesYieldsEmpty() {
        XCTAssertTrue(PersonalizedSessionBuilder.build(templates: [], cast: Cast(people: [yuki]), count: 5, seed: 1).isEmpty)
    }

    // MARK: 6. 名前は contentLemmas に漏れない（語彙汚染しない）

    func testNamesNeverLeakIntoContentLemmas() {
        let cast = Cast(people: [yuki, ken])
        let items = PersonalizedSessionBuilder.build(templates: pool, cast: cast, category: .school, count: 10, seed: 7)
        for item in items {
            XCTAssertFalse(item.contentLemmas.contains("Yuki"))
            XCTAssertFalse(item.contentLemmas.contains("Ken"))
        }
    }

    // MARK: 7. カテゴリ別件数（親UIの選択肢：空カテゴリを隠す／件数表示用）

    func testCategoryCounts() {
        let counts = PersonalizedSessionBuilder.categoryCounts(templates: pool)
        XCTAssertEqual(counts[.school], 2)
        XCTAssertEqual(counts[.play], 1)
        XCTAssertEqual(counts[.greeting], 2)
        // テンプレが無いカテゴリはキーに現れない（nil）。
        XCTAssertNil(counts[.home])
        XCTAssertNil(counts[.daily])
        XCTAssertNil(counts[.other])
        // 合計はプール数に一致。
        XCTAssertEqual(counts.values.reduce(0, +), pool.count)
    }

    func testCategoryCountsEmpty() {
        XCTAssertTrue(PersonalizedSessionBuilder.categoryCounts(templates: []).isEmpty)
    }

    // MARK: 8. SentenceCategory は CaseIterable（親UIの選択肢列挙に使う）

    func testCategoryIsCaseIterable() {
        let all = Set(SentenceCategory.allCases)
        XCTAssertTrue(all.isSuperset(of: [.school, .play, .greeting, .home, .daily, .other]))
    }
}
