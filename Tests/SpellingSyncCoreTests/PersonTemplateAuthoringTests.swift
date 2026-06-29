import XCTest
@testable import SpellingSyncCore

final class PersonTemplateAuthoringTests: XCTestCase {

    private func girl(_ idByte: UInt8, _ ja: String, _ romaji: String) -> CastPerson {
        var b = [UInt8](repeating: 0, count: 16); b[15] = idByte
        let t = (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15])
        return CastPerson(id: UUID(uuid: t), role: .friend, gender: .girl, displayNameJa: ja, romaji: romaji)
    }
    private func child(_ idByte: UInt8, _ ja: String, _ romaji: String) -> CastPerson {
        var b = [UInt8](repeating: 0, count: 16); b[15] = idByte
        let t = (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15])
        return CastPerson(id: UUID(uuid: t), role: .child, gender: .unspecified, displayNameJa: ja, romaji: romaji)
    }

    // MARK: 1. 正常ロード → resolve まで通る

    func testLoadAndResolveFriendSubject() throws {
        let json = """
        [{
          "id": "friend-likes-apples",
          "category": "daily",
          "grammar": "presentSimple",
          "gradeBand": 1,
          "contentLemmas": ["like","apple"],
          "slots": [{"key":"f","role":"friend","gender":"girl"}],
          "en": ["{f:name}","likes","apples"],
          "ja": "{f}は りんごが すき",
          "fallbackEn": ["She","likes","apples"],
          "fallbackJa": "かのじょは りんごが すき"
        }]
        """.data(using: .utf8)!
        let templates = try PersonTemplateAuthoring.load(jsonArray: json)
        XCTAssertEqual(templates.count, 1)
        let t = templates[0]
        XCTAssertEqual(t.grammar, .presentSimple)
        XCTAssertEqual(t.fallback.en, "She likes apples")
        XCTAssertEqual(t.fallback.tokens, ["She","likes","apples"])

        let yuki = girl(2, "ゆき", "Yuki")
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [yuki]), seed: 1)
        XCTAssertEqual(item.tokens, ["Yuki","likes","apples"])
        XCTAssertEqual(item.ja, "ゆきは りんごが すき")
        XCTAssertEqual(item.contentLemmas, ["like","apple"])  // 名前は語彙に入らない
    }

    // MARK: genre 配線（humor トグルの素）

    // genre 省略時は nil（既定＝useful 相当）。テンプレ・fallback・解決後すべて nil。
    func testGenreDefaultsNilWhenOmitted() throws {
        let json = """
        [{
          "id": "friend-likes-apples",
          "category": "daily",
          "grammar": "presentSimple",
          "gradeBand": 1,
          "contentLemmas": ["like","apple"],
          "slots": [{"key":"f","role":"friend","gender":"girl"}],
          "en": ["{f:name}","likes","apples"],
          "ja": "{f}は りんごが すき",
          "fallbackEn": ["She","likes","apples"],
          "fallbackJa": "かのじょは りんごが すき"
        }]
        """.data(using: .utf8)!
        let t = try PersonTemplateAuthoring.load(jsonArray: json)[0]
        XCTAssertNil(t.genre)
        XCTAssertNil(t.fallback.genre)
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [girl(2, "ゆき", "Yuki")]), seed: 1)
        XCTAssertNil(item.genre)
    }

    // genre:"humor" は authoring→テンプレ→fallback→解決後 SentenceItem まで通る。
    func testGenreHumorFlowsThroughResolve() throws {
        let json = """
        [{
          "id": "friend-likes-apples-humor",
          "category": "daily",
          "grammar": "presentSimple",
          "genre": "humor",
          "gradeBand": 1,
          "contentLemmas": ["like","apple"],
          "slots": [{"key":"f","role":"friend","gender":"girl"}],
          "en": ["{f:name}","likes","apples"],
          "ja": "{f}は りんごが すき",
          "fallbackEn": ["She","likes","apples"],
          "fallbackJa": "かのじょは りんごが すき"
        }]
        """.data(using: .utf8)!
        let t = try PersonTemplateAuthoring.load(jsonArray: json)[0]
        XCTAssertEqual(t.genre, .humor)
        XCTAssertEqual(t.fallback.genre, .humor)   // Cast未登録で fallback が出ても humor のまま
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [girl(2, "ゆき", "Yuki")]), seed: 1)
        XCTAssertEqual(item.genre, .humor)         // 名前差し込み後も humor を維持
    }

    func testVocativeSuffixAndChildResolve() throws {
        let json = """
        [{
          "id": "this-is-for-you",
          "category": "greeting",
          "gradeBand": 1,
          "contentLemmas": [],
          "slots": [{"key":"me","role":"child"}],
          "en": ["{me:vocative},","this","is","for","you"],
          "ja": "{me}、これ あげる",
          "fallbackEn": ["This","is","for","you"],
          "fallbackJa": "これ あげる"
        }]
        """.data(using: .utf8)!
        let t = try PersonTemplateAuthoring.load(jsonArray: json)[0]
        let item = SentencePersonalizer.resolve(t, cast: Cast(people: [child(1, "ゆうた", "Yuta")]), seed: 1)
        XCTAssertEqual(item.tokens, ["Yuta,","this","is","for","you"])  // "," が名前トークンに付く
        XCTAssertEqual(item.ja, "ゆうた、これ あげる")
    }

    // MARK: 2. fallback id は template.id から決定論

    func testFallbackIDDeterministic() throws {
        func make() throws -> SentenceItem {
            let json = """
            [{"id":"x","category":"daily","gradeBand":1,"contentLemmas":[],
              "slots":[{"key":"f","role":"friend"}],
              "en":["{f:name}","runs"],"ja":"{f}は はしる",
              "fallbackEn":["She","runs"],"fallbackJa":"かのじょは はしる"}]
            """.data(using: .utf8)!
            return try PersonTemplateAuthoring.load(jsonArray: json)[0].fallback
        }
        XCTAssertEqual(try make().id, try make().id)   // 再ロードでも同一 UUID
    }

    // MARK: 3. 検証エラー

    func testUndefinedSlotThrows() {
        let json = """
        [{"id":"bad","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"f","role":"friend"}],
          "en":["{g:name}","runs"],"ja":"はしる",
          "fallbackEn":["She","runs"],"fallbackJa":"はしる"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PersonTemplateAuthoring.load(jsonArray: json)) {
            XCTAssertEqual($0 as? AuthoringError, .undefinedSlot(id: "bad", key: "g"))
        }
    }

    func testUnusedSlotThrows() {
        let json = """
        [{"id":"bad","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"f","role":"friend"},{"key":"g","role":"friend"}],
          "en":["{f:name}","runs"],"ja":"{f}は はしる",
          "fallbackEn":["She","runs"],"fallbackJa":"はしる"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PersonTemplateAuthoring.load(jsonArray: json)) {
            XCTAssertEqual($0 as? AuthoringError, .unusedSlot(id: "bad", key: "g"))
        }
    }

    func testChildNonVocativeThrows() {
        let json = """
        [{"id":"bad","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"me","role":"child"}],
          "en":["{me:name}","runs"],"ja":"{me}は はしる",
          "fallbackEn":["I","run"],"fallbackJa":"ぼくは はしる"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PersonTemplateAuthoring.load(jsonArray: json)) {
            XCTAssertEqual($0 as? AuthoringError, .childMustBeVocative(id: "bad", key: "me"))
        }
    }

    func testUnknownFormThrows() {
        let json = """
        [{"id":"bad","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"f","role":"friend"}],
          "en":["{f:zzz}","runs"],"ja":"{f}は はしる",
          "fallbackEn":["She","runs"],"fallbackJa":"はしる"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PersonTemplateAuthoring.load(jsonArray: json)) {
            XCTAssertEqual($0 as? AuthoringError, .unknownForm(id: "bad", form: "zzz"))
        }
    }

    func testDuplicateIDThrows() {
        let json = """
        [{"id":"dup","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"f","role":"friend"}],
          "en":["{f:name}"],"ja":"{f}",
          "fallbackEn":["She"],"fallbackJa":"かのじょ"},
         {"id":"dup","category":"daily","gradeBand":1,"contentLemmas":[],
          "slots":[{"key":"f","role":"friend"}],
          "en":["{f:name}"],"ja":"{f}",
          "fallbackEn":["He"],"fallbackJa":"かれ"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PersonTemplateAuthoring.load(jsonArray: json)) {
            XCTAssertEqual($0 as? AuthoringError, .duplicateID(id: "dup"))
        }
    }
}
