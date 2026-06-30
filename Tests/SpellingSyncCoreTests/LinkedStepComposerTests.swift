import XCTest
@testable import SpellingSyncCore

/// 「学校テスト語などの custom 単語を、保管は personal のまま、いま見ているコースの
/// ステップ階段に“紐付け”て差し込む」純ロジックの仕様。
///
/// 設計（codex Architect 助言＋Code Reviewer 指摘反映）:
/// - 合成（synthetic）ステップは編集・同期しない。custom は personal に保管し、
///   `linkedCourseID` でどのコースに、`linkedBeforeStepID` でどのステップ手前に出すかを決める。
/// - dedup は **forward-only**: custom と同じ語は「挿入位置以降の合成ステップ」からのみ落とす。
///   挿入位置より前（＝すでに通過/完了し得る）の合成ステップは温存する。
/// - **語は正規化テキストでなく `WordToken(id, normalized)` で運ぶ**。同じ綴りでも別の実語（別id）を
///   取り違えないよう、計画後の materialize は id で実語へ対応付ける（Code Reviewer Critical 2）。
/// - バッチ化は `buildGroups` が `(storageStepID, beforeStepID)` 単位で分割（同一保管ステップ内で
///   アンカーが混在しても取りこぼさない＝Code Reviewer Rec 1）。
final class LinkedStepComposerTests: XCTestCase {

    private typealias Tok = LinkedStepComposer.WordToken

    /// id == normalized のトークン（識別を気にしないケース用）。
    private func t(_ s: String) -> Tok { Tok(id: s, normalized: s) }

    private func base(_ pairs: [(String, [String])]) -> [LinkedStepComposer.BaseStep] {
        pairs.map { LinkedStepComposer.BaseStep(stepID: $0.0, words: $0.1.map(t)) }
    }

    private func group(_ storage: String, _ before: String?, _ texts: [String]) -> LinkedStepComposer.LinkedGroup {
        LinkedStepComposer.LinkedGroup(storageStepID: storage, beforeStepID: before, words: texts.map(t))
    }

    // MARK: - plan: 基本仕様

    // 1) 紐付けが無ければ合成ステップをそのまま 1..n で通す。
    func testNoLinked_passesThroughAndNumbers() {
        let plan = LinkedStepComposer.plan(
            base: base([("c.s01", ["cat", "dog"]), ("c.s02", ["sun"])]),
            linked: []
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1, words: [t("cat"), t("dog")]),
            .init(origin: .synthetic(stepID: "c.s02"), number: 2, words: [t("sun")]),
        ])
    }

    // 2) アンカー（beforeStepID）の手前に custom ステップを挿し、通し番号を振り直す。
    func testLinkedBeforeAnchor_insertedAndRenumbered() {
        let plan = LinkedStepComposer.plan(
            base: base([("c.s01", ["cat"]), ("c.s02", ["sun"])]),
            linked: [group("p1", "c.s02", ["quiz", "test"])]
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1, words: [t("cat")]),
            .init(origin: .custom(storageStepID: "p1"), number: 2, words: [t("quiz"), t("test")]),
            .init(origin: .synthetic(stepID: "c.s02"), number: 3, words: [t("sun")]),
        ])
    }

    // 3) アンカーが nil なら末尾に積む。
    func testNilAnchor_appendedAtEnd() {
        let plan = LinkedStepComposer.plan(
            base: base([("c.s01", ["cat"])]),
            linked: [group("p1", nil, ["quiz"])]
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1, words: [t("cat")]),
            .init(origin: .custom(storageStepID: "p1"), number: 2, words: [t("quiz")]),
        ])
    }

    // 4) アンカーが base に存在しなければ末尾フォールバック（ID凍結漏れ等の保険）。
    func testUnknownAnchor_appendedAtEnd() {
        let plan = LinkedStepComposer.plan(
            base: base([("c.s01", ["cat"])]),
            linked: [group("p1", "c.sXX", ["quiz"])]
        )
        XCTAssertEqual(plan.map(\.origin), [
            .synthetic(stepID: "c.s01"),
            .custom(storageStepID: "p1"),
        ])
    }

    // 5) バッチ内の重複は先勝ちで畳む（順序維持）。
    func testWithinBatchDedup() {
        let plan = LinkedStepComposer.plan(
            base: [],
            linked: [group("p1", nil, ["quiz", "test", "quiz"])]
        )
        XCTAssertEqual(plan, [
            .init(origin: .custom(storageStepID: "p1"), number: 1, words: [t("quiz"), t("test")]),
        ])
    }

    // 6) forward dedup: custom と同じ語は「挿入位置以降」の合成からのみ落とし、前は温存。
    func testForwardDedup_stripsAnchorAndLater_keepsEarlier() {
        let plan = LinkedStepComposer.plan(
            base: base([
                ("c.s01", ["sun", "cat"]),   // 挿入位置より前 → 温存（"sun" 残す）
                ("c.s02", ["sun", "dog"]),   // アンカー（挿入位置）→ "sun" を落とす
                ("c.s03", ["sun", "fox"]),   // 以降 → "sun" を落とす
            ]),
            linked: [group("p1", "c.s02", ["sun"])]
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1, words: [t("sun"), t("cat")]),
            .init(origin: .custom(storageStepID: "p1"), number: 2, words: [t("sun")]),
            .init(origin: .synthetic(stepID: "c.s02"), number: 3, words: [t("dog")]),
            .init(origin: .synthetic(stepID: "c.s03"), number: 4, words: [t("fox")]),
        ])
    }

    // 7) 同一アンカーに複数バッチ → storageStepID 昇順で決定論的に並べる。
    func testSameAnchor_orderedByStorageID() {
        let plan = LinkedStepComposer.plan(
            base: base([("c.s01", ["cat"])]),
            linked: [
                group("p2", "c.s01", ["b"]),
                group("p1", "c.s01", ["a"]),
            ]
        )
        XCTAssertEqual(plan.map(\.origin), [
            .custom(storageStepID: "p1"),
            .custom(storageStepID: "p2"),
            .synthetic(stepID: "c.s01"),
        ])
    }

    // 8) forward dedup で合成ステップが空になったら、そのノードは落とす（空の階段を見せない）。
    func testEmptiedSyntheticStep_dropped() {
        let plan = LinkedStepComposer.plan(
            base: base([
                ("c.s01", ["cat"]),
                ("c.s02", ["quiz"]),         // custom と同じ語だけ → 空になり消える
            ]),
            linked: [group("p1", "c.s02", ["quiz"])]
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1, words: [t("cat")]),
            .init(origin: .custom(storageStepID: "p1"), number: 2, words: [t("quiz")]),
        ])
    }

    // MARK: - identity（Code Reviewer Critical 2）

    // 9) 同じ綴りでも別の実語（別id）は取り違えない。
    //    forward dedup で前の合成 "sun"(syn-sun) は温存、custom "sun"(per-sun) は別id で出る。
    func testDistinctWordsSameText_keepDistinctIdentity() {
        let plan = LinkedStepComposer.plan(
            base: [
                .init(stepID: "c.s01", words: [Tok(id: "syn-sun", normalized: "sun"),
                                               Tok(id: "syn-cat", normalized: "cat")]),
                .init(stepID: "c.s02", words: [Tok(id: "syn-sun2", normalized: "sun"),
                                               Tok(id: "syn-dog", normalized: "dog")]),
            ],
            linked: [
                .init(storageStepID: "p1", beforeStepID: "c.s02",
                      words: [Tok(id: "per-sun", normalized: "sun")]),
            ]
        )
        XCTAssertEqual(plan, [
            .init(origin: .synthetic(stepID: "c.s01"), number: 1,
                  words: [Tok(id: "syn-sun", normalized: "sun"), Tok(id: "syn-cat", normalized: "cat")]),
            .init(origin: .custom(storageStepID: "p1"), number: 2,
                  words: [Tok(id: "per-sun", normalized: "sun")]),
            .init(origin: .synthetic(stepID: "c.s02"), number: 3,
                  words: [Tok(id: "syn-dog", normalized: "dog")]),
        ])
    }

    // MARK: - buildGroups（Code Reviewer Rec 1）

    private func input(_ id: String, _ normalized: String, _ storage: String?, _ before: String?)
        -> LinkedStepComposer.LinkedWordInput {
        LinkedStepComposer.LinkedWordInput(id: id, normalized: normalized,
                                           storageStepID: storage, beforeStepID: before)
    }

    // 10) 同一 (storageStepID, beforeStepID) はまとめ、語順を保つ。
    func testBuildGroups_groupsSameStorageAndAnchor() {
        let groups = LinkedStepComposer.buildGroups(from: [
            input("a", "quiz", "p1", "c.s02"),
            input("b", "test", "p1", "c.s02"),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].beforeStepID, "c.s02")
        XCTAssertEqual(groups[0].words, [Tok(id: "a", normalized: "quiz"), Tok(id: "b", normalized: "test")])
    }

    // 11) 同じ保管ステップでもアンカーが違えば別グループに割る（取りこぼさない）。
    //     決定論のため storageStepID は (storage, anchor) を含む合成キーにする。
    func testBuildGroups_splitsByAnchorWithinSameStorage() {
        let groups = LinkedStepComposer.buildGroups(from: [
            input("a", "alpha", "p1", "c.s01"),
            input("b", "beta",  "p1", "c.s03"),
        ])
        XCTAssertEqual(groups.count, 2)
        // 2件とも別の storageStepID（合成キー）になり、custom ステップが衝突しない。
        XCTAssertNotEqual(groups[0].storageStepID, groups[1].storageStepID)
        XCTAssertEqual(Set(groups.map(\.beforeStepID)), ["c.s01", "c.s03"])
    }

    // 12) storage が nil（保管ステップ未設定）でもフォールバックバケットでグループ化できる。
    func testBuildGroups_nilStorage_bucketed() {
        let groups = LinkedStepComposer.buildGroups(from: [
            input("a", "alpha", nil, nil),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].words, [Tok(id: "a", normalized: "alpha")])
        XCTAssertNil(groups[0].beforeStepID)
    }

    // 13) buildGroups → plan の往復が成立（同一アンカーの2バッチが安定順で挿入）。
    func testBuildGroups_thenPlan_roundTrips() {
        let groups = LinkedStepComposer.buildGroups(from: [
            input("a", "alpha", "p1", "c.s01"),
            input("b", "beta",  "p2", "c.s01"),
        ])
        let plan = LinkedStepComposer.plan(base: base([("c.s01", ["cat"])]), linked: groups)
        // p1@... と p2@... が storageStepID 昇順で c.s01 の手前に並ぶ。
        XCTAssertEqual(plan.map(\.number), [1, 2, 3])
        XCTAssertEqual(plan.last?.origin, .synthetic(stepID: "c.s01"))
        XCTAssertEqual(plan.prefix(2).flatMap { $0.words.map(\.normalized) }, ["alpha", "beta"])
    }
}
