import XCTest
@testable import SpellingSyncCore

final class PersonalizedSentencesTests: XCTestCase {

    // MARK: 固定キャスト（テスト用・id 固定で決定論）

    private func person(_ idByte: UInt8, _ role: CastRole, _ gender: PersonGender,
                        _ ja: String, _ romaji: String, active: Bool = true) -> CastPerson {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = idByte
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return CastPerson(id: UUID(uuid: t), role: role, gender: gender,
                          displayNameJa: ja, romaji: romaji, isActive: active)
    }

    private var yuta: CastPerson { person(1, .child, .boy, "ゆうた", "Yuta") }
    private var yuki: CastPerson { person(2, .friend, .girl, "ゆき", "Yuki") }
    private var ken: CastPerson { person(3, .friend, .boy, "けん", "Ken") }
    private var aoi: CastPerson { person(4, .friend, .girl, "あおい", "Aoi") }

    private func fallback(_ en: String, _ ja: String, _ tokens: [String], band: Int = 1,
                          grammar: GrammarPoint? = nil) -> SentenceItem {
        SentenceItem(en: en, ja: ja, tokens: tokens, gradeBand: band, grammar: grammar)
    }

    // MARK: 1. 友達が主語（活用は作成時確定なので壊れない）

    func testFriendSubjectByName() {
        let t = PersonSentenceTemplate(
            id: "girl-likes-apples",
            category: .daily,
            fallback: fallback("She likes apples", "かのじょは りんごが すき", ["She", "likes", "apples"]),
            enTokens: [.person(slot: "f", form: .name), .literal("likes"), .literal("apples")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" りんごが すき")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1,
            contentLemmas: ["like", "apple"],
            grammar: nil
        )
        let cast = Cast(people: [yuki])
        let item = SentencePersonalizer.resolve(t, cast: cast, seed: 1)
        XCTAssertEqual(item.tokens, ["Yuki", "likes", "apples"])
        XCTAssertEqual(item.en, "Yuki likes apples")
        XCTAssertEqual(item.ja, "ゆきは りんごが すき")
        XCTAssertEqual(item.contentLemmas, ["like", "apple"])   // 名前は語彙に入らない
        XCTAssertFalse(item.contentLemmas.contains("Yuki"))
    }

    // MARK: 2. 性別：要求性別に合う人だけ。合わなければフォールバック

    func testGenderConstraintFallsBackWhenNoMatch() {
        let t = PersonSentenceTemplate(
            id: "boy-can-run",
            category: .play,
            fallback: fallback("He can run fast", "かれは はやく はしれる", ["He", "can", "run", "fast"]),
            enTokens: [.person(slot: "b", form: .name), .literal("can"), .literal("run"), .literal("fast")],
            jaParts: [.person(slot: "b", suffix: "は"), .literal(" はやく はしれる")],
            slots: [PersonSlotSpec(key: "b", role: .friend, requiredGender: .boy)],
            gradeBand: 2
        )
        // 女の子しかいない → boy スロット埋まらず fallback
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki, aoi]), seed: 1)
        XCTAssertEqual(item.tokens, ["He", "can", "run", "fast"])

        // 男の子がいれば本人名
        let item2 = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki, ken]), seed: 1)
        XCTAssertEqual(item2.tokens, ["Ken", "can", "run", "fast"])
    }

    func testPossessivePronounByGender() {
        let t = PersonSentenceTemplate(
            id: "this-is-bag",
            category: .school,
            fallback: fallback("This is her bag", "これは かのじょの かばん", ["This", "is", "her", "bag"]),
            enTokens: [.literal("This"), .literal("is"),
                       .person(slot: "f", form: .possessiveDeterminer), .literal("bag")],
            jaParts: [.literal("これは "), .person(slot: "f", suffix: "の"), .literal(" かばん")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        // 女の子 → her
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 3).tokens,
                       ["This", "is", "her", "bag"])
        // 男の子 → his
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [ken]), seed: 3).tokens,
                       ["This", "is", "his", "bag"])
    }

    // MARK: 3. 本人＝呼びかけ専用（主語に入れない＝一致崩れ回避）

    func testChildVocative() {
        let t = PersonSentenceTemplate(
            id: "this-is-for-you",
            category: .greeting,
            fallback: fallback("This is for you", "これ きみに あげる", ["This", "is", "for", "you"]),
            enTokens: [.person(slot: "me", form: .vocativeName, suffix: ","),
                       .literal("this"), .literal("is"), .literal("for"), .literal("you")],
            jaParts: [.person(slot: "me", suffix: "、"), .literal("これ あげる")],
            slots: [PersonSlotSpec(key: "me", role: .child)],
            gradeBand: 1
        )
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuta, yuki]), seed: 1)
        XCTAssertEqual(item.tokens, ["Yuta,", "this", "is", "for", "you"])
        XCTAssertEqual(item.ja, "ゆうた、これ あげる")
        // 本人未登録ならフォールバック
        let noChild = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1)
        XCTAssertEqual(noChild.tokens, ["This", "is", "for", "you"])
    }

    // MARK: 4. 複数スロットは別人（3人会話の土台）

    func testDistinctPeopleAcrossSlots() {
        let t = PersonSentenceTemplate(
            id: "a-and-b-play",
            category: .play,
            fallback: fallback("They play together", "ふたりで あそぶ", ["They", "play", "together"]),
            enTokens: [.person(slot: "a", form: .name), .literal("and"),
                       .person(slot: "b", form: .name), .literal("play")],
            jaParts: [.person(slot: "a"), .literal("と"), .person(slot: "b"), .literal(" あそぶ")],
            slots: [PersonSlotSpec(key: "a", role: .friend), PersonSlotSpec(key: "b", role: .friend)],
            gradeBand: 1
        )
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki, ken, aoi]), seed: 7)
        // a と b は必ず別人
        let names = [item.tokens[0], item.tokens[2]]
        XCTAssertEqual(Set(names).count, 2, "two slots must be distinct people: \(names)")

        // 友達が1人しかいなければ別人にできず fallback
        let one = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 7)
        XCTAssertEqual(one.tokens, ["They", "play", "together"])
    }

    // MARK: 4b. 制約付きスロットでも貪欲で誤フォールバックしない（DFS バックトラック）

    func testConstrainedMultiSlotDoesNotFalselyFallBack() {
        // slots: [だれでも友達, 女の子の友達]。cast: [Yuki(girl), Ken(boy)]。
        // 貪欲だと "だれでも" が Yuki を取り、"女の子" が空→fallback してしまう。
        // 正しくは だれでも=Ken・女の子=Yuki が成立する。
        let t = PersonSentenceTemplate(
            id: "any-and-girl",
            category: .play,
            fallback: fallback("They play", "あそぶ", ["They", "play"]),
            enTokens: [.person(slot: "any", form: .name), .literal("and"),
                       .person(slot: "girl", form: .name), .literal("play")],
            jaParts: [.person(slot: "any"), .literal("と"), .person(slot: "girl"), .literal(" あそぶ")],
            slots: [PersonSlotSpec(key: "any", role: .friend),
                    PersonSlotSpec(key: "girl", role: .friend, requiredGender: .girl)],
            gradeBand: 1
        )
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki, ken]), seed: 5)
        XCTAssertNotEqual(item.tokens, ["They", "play"], "解が在るのに fallback してはいけない")
        XCTAssertEqual(item.tokens[0], "Ken")   // any は男の子に回る
        XCTAssertEqual(item.tokens[2], "Yuki")  // girl は女の子で確定
    }

    // MARK: 4c. 代名詞・所有格・目的格の表層形

    func testSubjectAndObjectAndPossessiveForms() {
        let t = PersonSentenceTemplate(
            id: "pronoun-forms",
            category: .daily,
            fallback: fallback("x", "x", ["x"]),
            enTokens: [.person(slot: "f", form: .subjectPronoun),
                       .literal("gave"),
                       .person(slot: "f", form: .objectPronoun, suffix: ""),
                       .person(slot: "f", form: .namePossessive)],
            jaParts: [.literal("x")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        // 男の子：He / him / Ken's（文頭の主語は大文字化される）
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [ken]), seed: 1).tokens,
                       ["He", "gave", "him", "Ken's"])
        // 女の子：She / her / Yuki's
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1).tokens,
                       ["She", "gave", "her", "Yuki's"])
    }

    func testUnspecifiedGenderHasNoConstraintAndTheyForms() {
        let nobody = person(20, .friend, .unspecified, "だれか", "Sora")
        let t = PersonSentenceTemplate(
            id: "unspecified",
            category: .daily,
            fallback: fallback("x", "x", ["x"]),
            enTokens: [.person(slot: "f", form: .subjectPronoun)],
            jaParts: [.literal("x")],
            // requiredGender 無し → unspecified も候補
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        // 文頭なので they→They に大文字化される（unspecified は they 系）。
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [nobody]), seed: 1).tokens, ["They"])
    }

    // MARK: 4d. Codable 往復（suffix 省略を許容）

    func testCodableRoundTripAndSuffixDefault() throws {
        let t = PersonSentenceTemplate(
            id: "rt",
            category: .school,
            fallback: fallback("She is my friend", "ともだち", ["She", "is", "my", "friend"]),
            enTokens: [.person(slot: "f", form: .vocativeName, suffix: ","), .literal("hi")],
            jaParts: [.person(slot: "f", suffix: "、"), .literal("やあ")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(PersonSentenceTemplate.self, from: data)
        XCTAssertEqual(t, back)

        // suffix を省いた JSON も復号でき、既定 "" になる。
        let json = #"{"kind":"person","slot":"f","form":"name"}"#.data(using: .utf8)!
        let token = try JSONDecoder().decode(EnglishTokenTemplate.self, from: json)
        XCTAssertEqual(token, .person(slot: "f", form: .name, suffix: ""))
    }

    // MARK: 5. 決定論：同 seed→同結果、別 seed で分布が動く

    func testDeterministicSameSeed() {
        let t = PersonSentenceTemplate(
            id: "friend-runs",
            category: .play,
            fallback: fallback("She runs", "かのじょは はしる", ["She", "runs"]),
            enTokens: [.person(slot: "f", form: .name), .literal("runs")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" はしる")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        let cast = Cast(people: [yuki, ken, aoi])
        let a = SentencePersonalizer.resolve(t, cast: cast, seed: 42)
        let b = SentencePersonalizer.resolve(t, cast: cast, seed: 42)
        XCTAssertEqual(a, b)              // 同 seed→完全一致（id 含む）
        XCTAssertEqual(a.id, b.id)        // 決定論 UUID

        // 複数 seed をなめると全員が登場しうる（分布が固定でない）。
        var seen = Set<String>()
        for s: UInt64 in 0..<40 {
            seen.insert(SentencePersonalizer.resolve(t, cast: cast, seed: s).tokens[0])
        }
        XCTAssertTrue(seen.count >= 2, "seed を変えると別の友達も出るはず: \(seen)")
    }

    // MARK: 5.5 文頭の代名詞は大文字になる（her→Her 等）

    func testSentenceInitialPossessivePronounIsCapitalized() {
        // {f:posdet}（her/his）が文頭に来るテンプレ。素の代名詞は小文字なので
        // 描画後に文頭を大文字化していないと "her bag is bigger" になってしまう。
        let t = PersonSentenceTemplate(
            id: "posdet-bag-bigger",
            category: .daily,
            fallback: fallback("Her bag is bigger", "かのじょの かばんは もっと 大きい",
                               ["Her", "bag", "is", "bigger"]),
            enTokens: [.person(slot: "f", form: .possessiveDeterminer),
                       .literal("bag"), .literal("is"), .literal("bigger")],
            jaParts: [.person(slot: "f", suffix: "の"), .literal(" かばんは もっと 大きい")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 2
        )
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1)
        XCTAssertEqual(item.tokens.first, "Her")        // 文頭タイルも大文字
        XCTAssertEqual(item.en, "Her bag is bigger")
    }

    func testNameInitialUnaffectedByCapitalization() {
        // 既に大文字の名前が文頭のときは変化しない（二重大文字化しない）。
        let t = PersonSentenceTemplate(
            id: "girl-likes-apples-cap",
            category: .daily,
            fallback: fallback("She likes apples", "かのじょは りんごが すき", ["She", "likes", "apples"]),
            enTokens: [.person(slot: "f", form: .name), .literal("likes"), .literal("apples")],
            jaParts: [.person(slot: "f", suffix: "は"), .literal(" りんごが すき")],
            slots: [PersonSlotSpec(key: "f", role: .friend, requiredGender: .girl)],
            gradeBand: 1
        )
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1)
        XCTAssertEqual(item.tokens.first, "Yuki")
        XCTAssertEqual(item.en, "Yuki likes apples")
    }

    // MARK: 6. スロット無し／非アクティブ／ローマ字無し

    func testNoSlotsReturnsFallback() {
        let fb = fallback("Hello", "やあ", ["Hello"])
        let t = PersonSentenceTemplate(
            id: "static", category: .greeting, fallback: fb,
            enTokens: [.literal("Hello")], jaParts: [.literal("やあ")],
            slots: [], gradeBand: 1
        )
        XCTAssertEqual(SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1), fb)
    }

    func testInactiveAndNoRomajiExcluded() {
        let t = PersonSentenceTemplate(
            id: "friend-name",
            category: .daily,
            fallback: fallback("She is here", "かのじょが いる", ["She", "is", "here"]),
            enTokens: [.person(slot: "f", form: .name), .literal("is"), .literal("here")],
            jaParts: [.person(slot: "f", suffix: "が"), .literal(" いる")],
            slots: [PersonSlotSpec(key: "f", role: .friend)],
            gradeBand: 1
        )
        let inactive = person(9, .friend, .girl, "ひな", "Hina", active: false)
        let noRomaji = person(10, .friend, .girl, "さくら", "")
        // 候補が全員 除外 → fallback
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [inactive, noRomaji]), seed: 1)
        XCTAssertEqual(item.tokens, ["She", "is", "here"])
    }
}
