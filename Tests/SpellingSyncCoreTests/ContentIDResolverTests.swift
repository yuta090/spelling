import XCTest
@testable import SpellingSyncCore

/// 表層ID 別名解決（実装フェーズ① 入れ物移行）。
///
/// 英文を直すと表層 `id`(UUIDv5) が変わり、復習履歴/ReviewQueue が切れる。
/// `content_id_aliases.json`（旧→新）を**1ホップだけ**引いて履歴をつなぐ。
/// 鎖（aliasの値がさらにaliasのキー）を禁止する不変条件で、多段リネームの取りこぼしを防ぐ。
final class ContentIDResolverTests: XCTestCase {

    func testResolvesOneHop() throws {
        let r = try ContentIDResolver(aliases: ["old1": "new1", "old2": "new2"])
        XCTAssertEqual(r.resolve("old1"), "new1")
        XCTAssertEqual(r.resolve("old2"), "new2")
    }

    func testUnknownIDPassesThrough() throws {
        let r = try ContentIDResolver(aliases: ["old1": "new1"])
        XCTAssertEqual(r.resolve("current"), "current", "別名に無いIDはそのまま返す")
    }

    func testRejectsChains() {
        // old -> mid -> new の鎖（mid が値かつキー）は不正＝初期化で弾く。
        XCTAssertThrowsError(try ContentIDResolver(aliases: ["old": "mid", "mid": "new"])) { error in
            XCTAssertEqual(error as? ContentIDResolverError, .chainedAlias("mid"))
        }
    }

    func testRejectsSelfAlias() {
        XCTAssertThrowsError(try ContentIDResolver(aliases: ["x": "x"]))
    }

    // 3連鎖 a->b->c も弾く（b が値かつキー）。畳んで「a->c, b->c」で渡す運用を強制。
    func testRejectsThreeLinkChain() {
        XCTAssertThrowsError(try ContentIDResolver(aliases: ["a": "b", "b": "c"])) { error in
            XCTAssertEqual(error as? ContentIDResolverError, .chainedAlias("b"))
        }
    }
}
