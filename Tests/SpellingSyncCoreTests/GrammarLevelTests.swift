import XCTest
@testable import SpellingSyncCore

// 文法レベル（CEFR-J 基準・親には学年表示）。
// 設計: docs/grammar-level-cefrj-2026-06-28.md

final class GrammarStageTests: XCTestCase {
    func testStagesAreOrdered() {
        XCTAssertLessThan(GrammarStage.intro1, GrammarStage.intro2)
        XCTAssertLessThan(GrammarStage.intro2, GrammarStage.basic1)
        XCTAssertLessThan(GrammarStage.basic1, GrammarStage.basic2)
        XCTAssertLessThan(GrammarStage.basic2, GrammarStage.applied)
    }

    func testCEFRJLabels() {
        XCTAssertEqual(GrammarStage.intro1.cefrJ, "A1.1")
        XCTAssertEqual(GrammarStage.intro2.cefrJ, "A1.2")
        XCTAssertEqual(GrammarStage.basic1.cefrJ, "A1.3")
        XCTAssertEqual(GrammarStage.basic2.cefrJ, "A2.1")
        XCTAssertEqual(GrammarStage.applied.cefrJ, "A2.2")
    }

    func testEveryStageHasGradeLabelForParents() {
        for stage in GrammarStage.allCases {
            XCTAssertFalse(stage.gradeLabelJa.isEmpty, "\(stage) の学年表示が空")
        }
    }

    func testThereAreFiveStages() {
        XCTAssertEqual(GrammarStage.allCases.count, 5)
    }
}

final class GrammarPointTests: XCTestCase {
    func testEveryPointHasTitleAndExplanation() {
        for point in GrammarPoint.allCases {
            XCTAssertFalse(point.titleJa.isEmpty, "\(point) の見出しが空")
            XCTAssertFalse(point.explanationJa.isEmpty, "\(point) の解説が空（不正解時に出す固定文）")
        }
    }

    func testRepresentativeStageMapping() {
        XCTAssertEqual(GrammarPoint.beVerb.stage, .intro1)
        XCTAssertEqual(GrammarPoint.presentContinuous.stage, .intro2)
        XCTAssertEqual(GrammarPoint.pastSimple.stage, .basic1)
        XCTAssertEqual(GrammarPoint.passiveVoice.stage, .basic2)
        XCTAssertEqual(GrammarPoint.presentPerfect.stage, .applied)
    }

    /// 全 `GrammarPoint` の段階を表で固定し、docs/grammar-level-cefrj-2026-06-28.md とのズレを自動検知する。
    func testExhaustiveStageMappingMatchesTable() {
        let expected: [GrammarPoint: GrammarStage] = [
            .beVerb: .intro1, .demonstratives: .intro1, .articles: .intro1, .canModal: .intro1,
            .pronouns: .intro1, .plurals: .intro1, .presentSimple: .intro1,
            .presentContinuous: .intro2, .negation: .intro2, .yesNoQuestion: .intro2,
            .beVerbPast: .intro2, .frequencyAdverb: .intro2,
            .pastSimple: .basic1, .comparativeEr: .basic1, .imperative: .basic1, .whQuestion: .basic1,
            .willGoingTo: .basic2, .shouldModal: .basic2, .passiveVoice: .basic2,
            .infinitive: .basic2, .indirectSpeech: .basic2,
            .haveToNeedTo: .applied, .gerund: .applied, .presentPerfect: .applied
        ]
        XCTAssertEqual(Set(expected.keys), Set(GrammarPoint.allCases), "期待表が全項目を網羅していない")
        for point in GrammarPoint.allCases {
            XCTAssertEqual(point.stage, expected[point], "\(point) の段階が表と不一致")
        }
    }
}

final class GrammarGateTests: XCTestCase {
    private func item(_ grammar: GrammarPoint?) -> SentenceItem {
        SentenceItem(en: "x", ja: "x", tokens: ["x"], gradeBand: 1, grammar: grammar)
    }

    func testSentenceGrammarStageDerivesFromTag() {
        XCTAssertEqual(item(.pastSimple).grammarStage, .basic1)
        XCTAssertNil(item(nil).grammarStage)
    }

    func testAllowedWhenStageWithinCeiling() {
        XCTAssertTrue(GrammarGate.isAllowed(item(.pastSimple), ceiling: .basic1))   // 等しい
        XCTAssertTrue(GrammarGate.isAllowed(item(.beVerb), ceiling: .applied))      // 下位は当然OK
    }

    func testBlockedWhenStageExceedsCeiling() {
        // 中1上限(basic1)の子に、中2の受動態(basic2)は出さない。
        XCTAssertFalse(GrammarGate.isAllowed(item(.passiveVoice), ceiling: .basic1))
    }

    func testUntaggedSentenceIsAllowedAtAnyCeiling() {
        XCTAssertTrue(GrammarGate.isAllowed(item(nil), ceiling: .intro1))
    }

    func testEligibleFiltersAndPreservesOrder() {
        let items = [
            SentenceItem(en: "a", ja: "a", tokens: ["a"], gradeBand: 1, grammar: .beVerb),        // intro1
            SentenceItem(en: "b", ja: "b", tokens: ["b"], gradeBand: 1, grammar: .passiveVoice),  // basic2
            SentenceItem(en: "c", ja: "c", tokens: ["c"], gradeBand: 1, grammar: .pastSimple)      // basic1
        ]
        let kept = GrammarGate.eligible(items, ceiling: .basic1)
        XCTAssertEqual(kept.map(\.en), ["a", "c"])
    }
}
