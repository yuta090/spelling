import XCTest
@testable import SpellingSyncCore

/// 練習の「やめた語から続ける」再開ロジックの純粋テスト。
///
/// 背景バグ：再開判定が「保存した語ID列 == いま計算し直した練習選択」の完全一致に
/// 依存していたため、練習で `firstIntroducedAt` がスタンプされる／抑制が変わると
/// 選択集合が揺れて再開が破棄され、1問目からやり直しになっていた。
///
/// 方針A：セッション開始時の語ID列を保存し、再開時は**アクティブに残っている語だけ**で
/// 再構築する（抑制・1日上限による揺れの影響を受けない）。
final class PracticeResumeTests: XCTestCase {
    // Foundation の UUID に依存させず Int で検証する（純ロジックは ID 型に非依存）。

    func testResumesWhenAllWordsStillAvailable() {
        // 抑制/上限で選択が縮んでも、アクティブに全語が残っていれば「やめた語」から続く。
        let resolved = PracticeResume.resolve(
            savedWordIDs: [1, 2, 3, 4, 5],
            savedIndex: 2,
            availableIDs: [1, 2, 3, 4, 5]
        )
        XCTAssertEqual(resolved?.wordIDs, [1, 2, 3, 4, 5])
        XCTAssertEqual(resolved?.index, 2)
    }

    func testShiftsIndexWhenEarlierWordsRemoved() {
        // やめた地点より前の語が消えたら、生き残りに合わせてインデックスを詰める。
        let resolved = PracticeResume.resolve(
            savedWordIDs: [1, 2, 3, 4, 5],
            savedIndex: 3, // 語 4 の上でやめた
            availableIDs: [1, 3, 4, 5] // 語 2 が消えた
        )
        XCTAssertEqual(resolved?.wordIDs, [1, 3, 4, 5])
        XCTAssertEqual(resolved?.index, 2, "語4の位置。前で消えた語2ぶん前詰め")
    }

    func testResumesAmongSurvivorsWhenStoppedWordRemoved() {
        // やめた語そのものが消えても、続きの語から再開できる（nil にしない）。
        let resolved = PracticeResume.resolve(
            savedWordIDs: [1, 2, 3, 4, 5],
            savedIndex: 2, // 語 3 の上でやめた
            availableIDs: [1, 2, 4, 5] // 語 3 が消えた
        )
        XCTAssertEqual(resolved?.wordIDs, [1, 2, 4, 5])
        // 語3の前に生きている語は 1,2 の2つ → index 2（＝語4）から続く。
        XCTAssertEqual(resolved?.index, 2)
    }

    func testClampsIndexToLastSurvivor() {
        // 生き残りが少なくインデックスが範囲外になる場合は末尾に丸める。
        let resolved = PracticeResume.resolve(
            savedWordIDs: [1, 2, 3, 4, 5],
            savedIndex: 4, // 語 5 の上でやめた
            availableIDs: [1, 2] // 3,4,5 が消えた
        )
        XCTAssertEqual(resolved?.wordIDs, [1, 2])
        XCTAssertEqual(resolved?.index, 1, "生き残り末尾に丸める")
    }

    func testReturnsNilWhenNoWordsSurvive() {
        XCTAssertNil(PracticeResume.resolve(
            savedWordIDs: [1, 2, 3],
            savedIndex: 1,
            availableIDs: [9, 10]
        ))
    }

    func testReturnsNilForEmptySavedWords() {
        XCTAssertNil(PracticeResume.resolve(savedWordIDs: [], savedIndex: 0, availableIDs: [1]))
    }

    func testReturnsNilForOutOfRangeIndex() {
        XCTAssertNil(PracticeResume.resolve(savedWordIDs: [1, 2], savedIndex: -1, availableIDs: [1, 2]))
        XCTAssertNil(PracticeResume.resolve(savedWordIDs: [1, 2], savedIndex: 2, availableIDs: [1, 2]))
    }

    func testResumesFromStartWhenStoppedAtFirstWord() {
        let resolved = PracticeResume.resolve(
            savedWordIDs: [1, 2, 3],
            savedIndex: 0,
            availableIDs: [1, 2, 3]
        )
        XCTAssertEqual(resolved?.wordIDs, [1, 2, 3])
        XCTAssertEqual(resolved?.index, 0)
    }
}
