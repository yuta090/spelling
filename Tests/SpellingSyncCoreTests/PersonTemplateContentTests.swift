import XCTest
@testable import SpellingSyncCore

/// 同梱予定の承認済みテンプレ（scripts/person_templates.authoring.json）の整合テスト。
/// ローダで全件通ること＋代表 Cast で resolve が壊れないことを担保する。
/// ファイルが無い環境ではスキップ（生成前/CI 差異に強くする）。
final class PersonTemplateContentTests: XCTestCase {

    /// このテストファイルから見たリポジトリの scripts/ パス。
    private var contentURL: URL {
        URL(fileURLWithPath: #filePath)            // Tests/SpellingSyncCoreTests/PersonTemplateContentTests.swift
            .deletingLastPathComponent()           // SpellingSyncCoreTests/
            .deletingLastPathComponent()           // Tests/
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("scripts/person_templates.authoring.json")
    }

    func testAuthoredContentLoadsAndResolves() throws {
        guard FileManager.default.fileExists(atPath: contentURL.path) else {
            throw XCTSkip("person_templates.authoring.json 未生成のためスキップ")
        }
        let data = try Data(contentsOf: contentURL)
        let templates = try PersonTemplateAuthoring.load(jsonArray: data)  // 全件 throw なしで通ること
        XCTAssertGreaterThanOrEqual(templates.count, 20, "テンプレ件数が少なすぎる")

        // 代表 Cast（本人＋男女の友達）で全件 resolve が壊れない（空トークンを出さない）。
        let cast = Cast(people: [
            CastPerson(role: .child, gender: .unspecified, displayNameJa: "ゆうた", romaji: "Yuta"),
            CastPerson(role: .friend, gender: .girl, displayNameJa: "ゆき", romaji: "Yuki"),
            CastPerson(role: .friend, gender: .boy, displayNameJa: "けん", romaji: "Ken")
        ])
        for t in templates {
            let item = SentencePersonalizer.resolve(t, cast: cast, seed: 7)
            XCTAssertFalse(item.tokens.isEmpty, "\(t.id): tokens 空")
            XCTAssertFalse(item.en.isEmpty, "\(t.id): en 空")
            XCTAssertFalse(item.ja.isEmpty, "\(t.id): ja 空")
            // 名前は語彙に混ざらない。
            for name in ["Yuta", "Yuki", "Ken"] {
                XCTAssertFalse(item.contentLemmas.contains(name), "\(t.id): contentLemmas に名前")
            }
        }
    }
}
