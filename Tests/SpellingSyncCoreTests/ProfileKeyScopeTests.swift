import XCTest
@testable import SpellingSyncCore

/// 永続化キーの名前空間化。子ども別キーは `profiles/<id>/` を付け、グローバルキーは素通し。
/// 分類の二重管理ズレを検出する（childScoped ∩ global = ∅、既知キー全件がどちらかに属する）。
/// 設計: docs/multi-child-profiles-design-2026-07-01.md §3
final class ProfileKeyScopeTests: XCTestCase {

    private let pid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testChildScopedKeyGetsPrefixed() {
        let scoped = ProfileKeyScope.scopedKey("spellingTrainer.words", profileID: pid)
        XCTAssertEqual(scoped, "profiles/11111111-1111-1111-1111-111111111111/spellingTrainer.words")
    }

    func testGlobalKeyPassesThrough() {
        // entitlement は家族＝世帯単位（全プロファイル共有）。prefix しない。
        let scoped = ProfileKeyScope.scopedKey("spellingTrainer.cachedEntitlement", profileID: pid)
        XCTAssertEqual(scoped, "spellingTrainer.cachedEntitlement")
    }

    func testUnknownKeyDefaultsToScoped() {
        // 未分類キーは安全側で prefix（プロファイル間の漏れを防ぐ）。
        let scoped = ProfileKeyScope.scopedKey("spellingTrainer.somethingNew", profileID: pid)
        XCTAssertTrue(scoped.hasPrefix("profiles/\(pid.uuidString)/"))
    }

    func testChildScopedAndGlobalAreDisjoint() {
        let overlap = ProfileKeyScope.childScopedKeys.intersection(ProfileKeyScope.globalKeys)
        XCTAssertTrue(overlap.isEmpty, "重複キー: \(overlap)")
    }

    func testChildScopedKeysAreNotGlobal() {
        for key in ProfileKeyScope.childScopedKeys {
            XCTAssertFalse(ProfileKeyScope.globalKeys.contains(key), "\(key) が global にも含まれる")
            XCTAssertTrue(
                ProfileKeyScope.scopedKey(key, profileID: pid).hasPrefix("profiles/"),
                "\(key) は prefix されるべき"
            )
        }
    }

    func testGlobalKeysNeverPrefixed() {
        for key in ProfileKeyScope.globalKeys {
            XCTAssertEqual(ProfileKeyScope.scopedKey(key, profileID: pid), key, "\(key) は素通しのはず")
        }
    }

    func testEntitlementIsGlobal() {
        // 家族込み課金の要（§7）。回帰防止で明示的に固定。
        XCTAssertTrue(ProfileKeyScope.globalKeys.contains("spellingTrainer.cachedEntitlement"))
    }

    func testKeyCountsAreStable() {
        // キー追加/削除時に「どちらに分類するか」を意識的に決めさせる回帰トリップワイヤ。
        // 変更したらこの数を更新し、分類（子/グローバル）を必ずレビューする。
        XCTAssertEqual(ProfileKeyScope.childScopedKeys.count, 35)
        XCTAssertEqual(ProfileKeyScope.globalKeys.count, 10)
    }

    func testCoreChildDataKeysAreScoped() {
        // 代表的な子データが子スコープであることを固定。
        for key in ["spellingTrainer.words", "spellingTrainer.attempts",
                    "spellingTrainer.rewardCoins.v2", "spellingTrainer.childName",
                    "spellingTrainer.spellingReviewStates"] {
            XCTAssertTrue(ProfileKeyScope.childScopedKeys.contains(key), "\(key) は子スコープのはず")
        }
    }
}
