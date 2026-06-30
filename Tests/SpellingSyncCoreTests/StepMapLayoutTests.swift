import XCTest
@testable import SpellingSyncCore

final class StepMapLayoutTests: XCTestCase {

    // MARK: - current の確定

    func testSelectedIncompleteStepIsCurrent() {
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b", "c"], completedToday: ["a"], selectedID: "b")
        XCTAssertEqual(id, "b")
    }

    func testSelectedCompletedFallsBackToFirstIncomplete() {
        // 選択中(b)が今日もう終わっている → 今日まだのうち一番下(=最初)を current に。
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b", "c"], completedToday: ["a", "b"], selectedID: "b")
        XCTAssertEqual(id, "c")
    }

    func testNoSelectionPicksFirstIncomplete() {
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b", "c"], completedToday: ["a"], selectedID: nil)
        XCTAssertEqual(id, "b")
    }

    func testAllCompletedKeepsSelectionAsCurrent() {
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b", "c"], completedToday: ["a", "b", "c"], selectedID: "b")
        XCTAssertEqual(id, "b")
    }

    func testAllCompletedNoSelectionUsesLast() {
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b", "c"], completedToday: ["a", "b", "c"], selectedID: nil)
        XCTAssertEqual(id, "c")
    }

    func testSelectionNotInListIsIgnored() {
        let id = StepMapLayout.currentStepID(
            orderedIDs: ["a", "b"], completedToday: [], selectedID: "zzz")
        XCTAssertEqual(id, "a")
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(StepMapLayout.currentStepID(orderedIDs: [], completedToday: [], selectedID: "a"))
    }

    // MARK: - 各ノードの状態

    func testNodeStatesHaveExactlyOneCurrent() {
        let states = StepMapLayout.nodeStates(
            orderedIDs: ["a", "b", "c", "d"], completedToday: ["a"], selectedID: "c")
        XCTAssertEqual(states, [.done, .upcoming, .current, .upcoming])
        XCTAssertEqual(states.filter { $0 == .current }.count, 1)
    }

    func testNodeStatesCompletedAreDoneExceptCurrent() {
        // 選択中(b)が完了済み → current は今日まだの先頭 c に移り、a/b は done。
        let states = StepMapLayout.nodeStates(
            orderedIDs: ["a", "b", "c"], completedToday: ["a", "b"], selectedID: "b")
        XCTAssertEqual(states, [.done, .done, .current])
    }

    func testNodeStatesAlwaysOneCurrentEvenAllDone() {
        let states = StepMapLayout.nodeStates(
            orderedIDs: ["a", "b"], completedToday: ["a", "b"], selectedID: nil)
        XCTAssertEqual(states.filter { $0 == .current }.count, 1)
    }

    // MARK: - 高さ

    func testContentHeightGrowsWithCount() {
        let h1 = StepMapLayout.contentHeight(count: 1, spacing: 190, groundPad: 240, skyPad: 320)
        let h3 = StepMapLayout.contentHeight(count: 3, spacing: 190, groundPad: 240, skyPad: 320)
        XCTAssertEqual(h1, 560, accuracy: 0.001)            // 240 + 320 + 0
        XCTAssertEqual(h3, 560 + 2 * 190, accuracy: 0.001)
    }

    func testContentHeightZeroCountClampsToOne() {
        let h0 = StepMapLayout.contentHeight(count: 0, spacing: 190, groundPad: 240, skyPad: 320)
        XCTAssertEqual(h0, 560, accuracy: 0.001)
    }

    // MARK: - ノード座標（下=スタート→上=空）

    func testFirstNodeSitsAtBottom() {
        let h = StepMapLayout.contentHeight(count: 3, spacing: 190, groundPad: 240, skyPad: 320)
        let p0 = StepMapLayout.nodePoint(index: 0, width: 1000, contentHeight: h, spacing: 190, groundPad: 240)
        XCTAssertEqual(p0.y, h - 240, accuracy: 0.001)   // 一番下
        XCTAssertEqual(p0.x, 340, accuracy: 0.001)       // 偶数=左 0.34
    }

    func testNodesGoUpAndZigzag() {
        let h = StepMapLayout.contentHeight(count: 3, spacing: 190, groundPad: 240, skyPad: 320)
        let p0 = StepMapLayout.nodePoint(index: 0, width: 1000, contentHeight: h, spacing: 190, groundPad: 240)
        let p1 = StepMapLayout.nodePoint(index: 1, width: 1000, contentHeight: h, spacing: 190, groundPad: 240)
        let p2 = StepMapLayout.nodePoint(index: 2, width: 1000, contentHeight: h, spacing: 190, groundPad: 240)
        XCTAssertLessThan(p1.y, p0.y)                    // 上に行くほど y は小さい
        XCTAssertLessThan(p2.y, p1.y)
        XCTAssertEqual(p1.x, 660, accuracy: 0.001)       // 奇数=右 0.66
        XCTAssertEqual(p2.x, 340, accuracy: 0.001)       // 偶数=左
    }

    func testNodePointsCount() {
        let pts = StepMapLayout.nodePoints(count: 4, width: 800, contentHeight: 1000, spacing: 190, groundPad: 240)
        XCTAssertEqual(pts.count, 4)
    }

    // MARK: - 小道のアンカー

    func testPathPointsBracketNodesWithGroundAndGoal() {
        let nodes = StepMapLayout.nodePoints(count: 3, width: 1000, contentHeight: 1000, spacing: 190, groundPad: 240)
        let path = StepMapLayout.pathPoints(nodePoints: nodes, width: 1000, contentHeight: 1000, skyPad: 320)
        XCTAssertEqual(path.count, nodes.count + 2)       // [地上] + ノード + [ゴール]
        XCTAssertEqual(path.first?.y ?? 0, 1000 - 110, accuracy: 0.001)   // 地上アンカー
        XCTAssertEqual(path.last?.x ?? 0, 500, accuracy: 0.001)          // ゴールは中央
        XCTAssertEqual(path.last?.y ?? 0, 320 - 110, accuracy: 0.001)
    }

    // MARK: - コース完了サマリ（できた Xこ / Yこ）

    func testProgressCountsClearedStepsWithinCourse() {
        let p = StepMapLayout.progress(orderedIDs: ["a", "b", "c", "d"], completed: ["a", "c"])
        XCTAssertEqual(p.cleared, 2)
        XCTAssertEqual(p.total, 4)
        XCTAssertFalse(p.allCleared)
        XCTAssertEqual(p.fraction, 0.5, accuracy: 0.001)
    }

    func testProgressIgnoresClearedIDsOutsideCourse() {
        // 別コースで満点になった stepID（このコースに無い）はこのコースの「できた」に数えない。
        let p = StepMapLayout.progress(orderedIDs: ["a", "b"], completed: ["a", "x", "y"])
        XCTAssertEqual(p.cleared, 1)
        XCTAssertEqual(p.total, 2)
    }

    func testProgressAllClearedWhenEveryStepDone() {
        let p = StepMapLayout.progress(orderedIDs: ["a", "b"], completed: ["a", "b"])
        XCTAssertEqual(p.cleared, 2)
        XCTAssertEqual(p.total, 2)
        XCTAssertTrue(p.allCleared)
        XCTAssertEqual(p.fraction, 1.0, accuracy: 0.001)
    }

    func testProgressEmptyCourseIsNotAllCleared() {
        let p = StepMapLayout.progress(orderedIDs: [], completed: ["a"])
        XCTAssertEqual(p.cleared, 0)
        XCTAssertEqual(p.total, 0)
        XCTAssertFalse(p.allCleared)      // 0/0 を「全部できた」にしない
        XCTAssertEqual(p.fraction, 0, accuracy: 0.001)
    }

    // MARK: - 縦／横向きのレイアウト調整値

    func testMetricsSelectsByOrientation() {
        XCTAssertEqual(StepMapLayout.metrics(isLandscape: false), StepMapLayout.portraitMetrics)
        XCTAssertEqual(StepMapLayout.metrics(isLandscape: true), StepMapLayout.landscapeMetrics)
    }

    func testLandscapeMetricsAreTighterThanPortrait() {
        let p = StepMapLayout.portraitMetrics
        let l = StepMapLayout.landscapeMetrics
        // 横向きは縦の高さが乏しいので間隔・余白を詰める。
        XCTAssertLessThan(l.spacing, p.spacing)
        XCTAssertLessThan(l.groundPad, p.groundPad)
        XCTAssertLessThan(l.skyPad, p.skyPad)
        // ジグザグは内側へ寄せる（端で切れないように）。
        XCTAssertGreaterThan(l.leftFrac, p.leftFrac)
        XCTAssertLessThan(l.rightFrac, p.rightFrac)
        // 左右は中央(0.5)を挟んで対称気味・leftFrac < rightFrac は維持。
        XCTAssertLessThan(l.leftFrac, l.rightFrac)
    }

    func testLandscapeMetricsReduceContentHeight() {
        // 同じステップ数なら横向きの方が地図全体が低い（横画面に収まりやすい）。
        let n = 6
        let p = StepMapLayout.portraitMetrics
        let l = StepMapLayout.landscapeMetrics
        let hP = StepMapLayout.contentHeight(count: n, spacing: p.spacing, groundPad: p.groundPad, skyPad: p.skyPad)
        let hL = StepMapLayout.contentHeight(count: n, spacing: l.spacing, groundPad: l.groundPad, skyPad: l.skyPad)
        XCTAssertLessThan(hL, hP)
    }
}
