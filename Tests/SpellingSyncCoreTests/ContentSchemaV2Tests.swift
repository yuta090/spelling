import XCTest
@testable import SpellingSyncCore

/// スキーマv2 移行カナリア（実装フェーズ① 最初のスライス）。
///
/// 目的＝**入れ物を v2 へ広げても既存47件の表層UUIDが1ミリも動かない**ことを機械で固定する。
/// - `SentenceItem.sourceID` は任意追加：キーが無い既存JSONは nil で素直に decode できる（後方互換）。
/// - authoring は v1配列／v2 envelope の両方を `AuthoringSource.decode` が読み分ける（dual-decode）。
/// - sourceID は authoring の id を安定IDとして再利用（英文修正で履歴が切れない）。
final class ContentSchemaV2Tests: XCTestCase {

    // MARK: - 同梱 sentence_bank.json の場所（リポジトリルート基準）

    private var sentenceBankURL: URL {
        URL(fileURLWithPath: #filePath)            // Tests/SpellingSyncCoreTests/ContentSchemaV2Tests.swift
            .deletingLastPathComponent()           // SpellingSyncCoreTests/
            .deletingLastPathComponent()           // Tests/
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("iPadPrototype/Resources/sentence_bank.json")
    }

    // MARK: - A. SentenceItem.sourceID 後方互換

    /// 既存JSON（sourceID キー無し）が壊れず decode でき、sourceID は nil。id は保持。
    func testSentenceItemDecodesLegacyWithoutSourceID() throws {
        let json = """
        [{"id":"DFF69D5D-61F2-5BD0-98DB-617478AD1E9B","en":"I like apples",
          "ja":"わたしは りんごが すき","tokens":["I","like","apples"],
          "gradeBand":1,"contentLemmas":["like","apple"]}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([SentenceItem].self, from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id.uuidString, "DFF69D5D-61F2-5BD0-98DB-617478AD1E9B")
        XCTAssertNil(items[0].sourceID, "キーが無い既存JSONでは sourceID は nil")
    }

    /// sourceID 付与時の round-trip。encode→decode で sourceID が保たれる。
    func testSentenceItemSourceIDRoundTrips() throws {
        let item = SentenceItem(en: "I like apples", ja: "りんご", tokens: ["I", "like", "apples"],
                                gradeBand: 1, contentLemmas: ["like", "apple"], sourceID: "like-apples")
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(SentenceItem.self, from: data)
        XCTAssertEqual(back.sourceID, "like-apples")
        XCTAssertEqual(back.id, item.id)
    }

    /// カナリア：同梱の本物47件が、移行後も**全件 decode でき・件数不変・表層id/安定idともユニーク**。
    /// 移行で全件に安定 sourceID を付与済み（ビルド決定論で表層UUIDは不変）。
    func testBundledSentenceBankIsMigrated() throws {
        guard FileManager.default.fileExists(atPath: sentenceBankURL.path) else {
            throw XCTSkip("sentence_bank.json 未生成のためスキップ")
        }
        let data = try Data(contentsOf: sentenceBankURL)
        let items = try JSONDecoder().decode([SentenceItem].self, from: data)
        XCTAssertEqual(items.count, 47, "同梱文の件数が変わっている")
        // 移行済み＝全件に安定 sourceID が付き、重複が無い。
        XCTAssertTrue(items.allSatisfy { ($0.sourceID?.isEmpty == false) }, "全件に sourceID が必要")
        XCTAssertEqual(Set(items.compactMap { $0.sourceID }).count, 47, "sourceID が重複している")
        // 表層 id もユニーク。
        XCTAssertEqual(Set(items.map { $0.id }).count, 47)
    }

    // MARK: - B. AuthoringSource dual-decode（v1配列 / v2 envelope）

    /// v1：ルートが JSON 配列 → そのまま [AuthoringRecord] に取り込める（legacy importer）。
    func testAuthoringSourceDecodesV1Array() throws {
        let v1 = """
        [{"id":"like-apples","gradeBand":1,"contentLemmas":["like","apple"],
          "en":["I","like","apples"],"ja":"りんご"},
         {"id":"friend-name","gradeBand":1,"contentLemmas":["friend"],
          "slots":[{"key":"f","role":"friend","gender":"any"}],
          "en":["{f:name}","is","my","friend"],"ja":"{f}は ともだち"}]
        """.data(using: .utf8)!
        let records = try AuthoringSource.decode(v1)
        XCTAssertEqual(records.count, 2)
        // kind は推定：slots 有→personTemplate、無→plain。
        XCTAssertEqual(records[0].kind, .plain)
        XCTAssertEqual(records[1].kind, .personTemplate)
        // sourceID は authoring id を再利用。
        XCTAssertEqual(records[0].sourceID, "like-apples")
    }

    /// v2：ルートが envelope `{schema:2, records:[...]}` → kind は明示必須で読む。
    func testAuthoringSourceDecodesV2Envelope() throws {
        let v2 = """
        {"schema":2,"records":[
          {"kind":"frameTemplate","sourceID":"like-frame","gradeBand":1,
           "contentLemmas":[],"en":["I","like","___"],"ja":"___が すき",
           "frame":{"slot":"x","allowedPOS":["noun"]}},
          {"kind":"plain","sourceID":"hello-there","gradeBand":1,
           "contentLemmas":[],"en":["hello"],"ja":"こんにちは"}
        ]}
        """.data(using: .utf8)!
        let records = try AuthoringSource.decode(v2)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].kind, .frameTemplate)
        XCTAssertEqual(records[0].sourceID, "like-frame")
        XCTAssertEqual(records[1].kind, .plain)
    }

    /// v2 で kind が無いレコードは不正（明示必須）。
    func testV2RequiresExplicitKind() {
        let bad = """
        {"schema":2,"records":[
          {"sourceID":"x","gradeBand":1,"contentLemmas":[],"en":["hi"],"ja":"やあ"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AuthoringSource.decode(bad))
    }

    /// schema の値が 2 以外なら弾く（{"schema":1} を v2 と取り違えない）。
    func testV2RejectsWrongSchema() {
        let bad = """
        {"schema":1,"records":[
          {"kind":"plain","sourceID":"x","gradeBand":1,"contentLemmas":[],"en":["hi"],"ja":"やあ"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AuthoringSource.decode(bad)) { error in
            XCTAssertEqual(error as? AuthoringSourceError, .unsupportedSchema(1))
        }
    }

    /// v2 は sourceID 明示必須＝欠落/空/前後空白/不正文字は弾く（英文フォールバックに頼らない）。
    func testV2RequiresValidExplicitSourceID() {
        func env(_ sid: String) -> Data {
            """
            {"schema":2,"records":[
              {"kind":"plain","sourceID":\(sid),"gradeBand":1,"contentLemmas":[],"en":["hi"],"ja":"やあ"}
            ]}
            """.data(using: .utf8)!
        }
        XCTAssertThrowsError(try AuthoringSource.decode(env("\"\"")))         // 空
        XCTAssertThrowsError(try AuthoringSource.decode(env("\"  ok  \"")))   // 前後空白
        XCTAssertThrowsError(try AuthoringSource.decode(env("\"a b\"")))      // 内部空白
        // sourceID キー自体が無い
        let missing = """
        {"schema":2,"records":[
          {"kind":"plain","gradeBand":1,"contentLemmas":[],"en":["hi"],"ja":"やあ"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AuthoringSource.decode(missing))
    }

    /// 先頭に UTF-8 BOM が付いていても素直に読める。
    func testDecodesWithLeadingBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("""
        {"schema":2,"records":[
          {"kind":"plain","sourceID":"hello","gradeBand":1,"contentLemmas":[],"en":["hi"],"ja":"やあ"}
        ]}
        """.data(using: .utf8)!)
        let records = try AuthoringSource.decode(data)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].sourceID, "hello")
    }

    /// 同一 sourceID が重複したら弾く（安定IDの一意性を守る）。
    func testDuplicateSourceIDRejected() {
        let dup = """
        {"schema":2,"records":[
          {"kind":"plain","sourceID":"same","gradeBand":1,"contentLemmas":[],"en":["a"],"ja":"あ"},
          {"kind":"plain","sourceID":"same","gradeBand":1,"contentLemmas":[],"en":["b"],"ja":"い"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AuthoringSource.decode(dup))
    }

    // MARK: - C. 決定論 sourceID 導出

    /// authoring の id があれば再利用。
    func testSourceIDReusesAuthoringID() {
        XCTAssertEqual(ContentSourceID.derive(authoringID: "like-apples", en: ["I", "like", "apples"]),
                       "like-apples")
    }

    /// id が無い legacy 行は `legacy-<slug>-<短ハッシュ>` を決定論で付与（同入力＝同出力）。
    func testSourceIDFallbackIsDeterministic() {
        let a = ContentSourceID.derive(authoringID: nil, en: ["I", "like", "apples"])
        let b = ContentSourceID.derive(authoringID: nil, en: ["I", "like", "apples"])
        XCTAssertEqual(a, b, "同じ英文なら同じ sourceID")
        XCTAssertTrue(a.hasPrefix("legacy-"), "legacy 接頭辞を付ける: \(a)")
        let c = ContentSourceID.derive(authoringID: nil, en: ["I", "like", "oranges"])
        XCTAssertNotEqual(a, c, "違う英文は違う sourceID")
    }
}
