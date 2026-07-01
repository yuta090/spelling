import XCTest
@testable import SpellingSyncCore

final class StepEditabilityTests: XCTestCase {
    func test_personalStep_isEditable() {
        // personal トラックに実在するステップID → 編集可
        XCTAssertTrue(StepEditability.isEditable(
            stepID: "2026-06-30",
            personalStepIDs: ["2026-06-30", "2026-06-29"]))
    }

    func test_syntheticCourseStep_isReadOnly() {
        // 合成コースのステップIDは personal 集合に無い → 読み取り
        XCTAssertFalse(StepEditability.isEditable(
            stepID: "grade.1.step.03",
            personalStepIDs: ["2026-06-30"]))
    }

    func test_linkedDisplayStep_isReadOnly() {
        // `linked.` 差し込みは表示用の見せかけIDなので保管と1:1でない → 読み取り
        XCTAssertFalse(StepEditability.isEditable(
            stepID: "linked.grade.1.abc",
            personalStepIDs: ["2026-06-30"]))
    }

    func test_emptyPersonalSet_isReadOnly() {
        XCTAssertFalse(StepEditability.isEditable(
            stepID: "anything",
            personalStepIDs: []))
    }
}
