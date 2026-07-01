import XCTest
@testable import SpellingSyncCore

/// 子ども向けのやさしい判定。芯は「機械が字を読めたか（＝綺麗さ）」を「綴りの正誤」と混同しないこと。
/// 字が汚くて読めなかっただけ（needsReview/rewrite/timeExpired）は **間違い扱いにしない**（pending）。
final class ChildGradingTests: XCTestCase {

    // MARK: - outcome: 自動採点 → 子ども向け判定

    func test_autoCorrect_isCorrect() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .autoCorrect, parentReview: .unreviewed),
            .correct)
    }

    func test_autoIncorrect_isTryAgain() {
        // はっきり綴りが違う → やさしく「もう いちど」
        XCTAssertEqual(
            ChildGrading.outcome(decision: .autoIncorrect, parentReview: .unreviewed),
            .tryAgain)
    }

    func test_needsReview_isPending_notWrong() {
        // 機械が読めなかっただけ → 間違いにしない（中立・達成を邪魔しない）
        XCTAssertEqual(
            ChildGrading.outcome(decision: .needsReview, parentReview: .unreviewed),
            .pending)
    }

    func test_rewrite_isPending_notWrong() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .rewrite, parentReview: .unreviewed),
            .pending)
    }

    func test_timeExpired_isPending_notWrong() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .timeExpired, parentReview: .unreviewed),
            .pending)
    }

    // MARK: - 親採点は自動採点を上書きする

    func test_parentApproved_overridesToCorrect_evenIfAutoIncorrect() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .autoIncorrect, parentReview: .approved),
            .correct)
    }

    func test_parentNeedsPractice_overridesToTryAgain_evenIfAutoCorrect() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .autoCorrect, parentReview: .needsPractice),
            .tryAgain)
    }

    func test_parentApproved_overridesNeedsReviewToCorrect() {
        XCTAssertEqual(
            ChildGrading.outcome(decision: .needsReview, parentReview: .approved),
            .correct)
    }

    // MARK: - achievementSatisfied: 表示とは別の「達成を満たすか」判定

    func test_correct_satisfies_onlyWhenGenuineAttempt() {
        // 通常の自動正解は必ずインクあり → 満たす
        XCTAssertTrue(ChildGrading.achievementSatisfied(outcome: .correct, genuineAttempt: true))
        // 親のデフォルト一括承認で空答案が autoCorrect 化しても、インク無しなら満たさない
        XCTAssertFalse(ChildGrading.achievementSatisfied(outcome: .correct, genuineAttempt: false))
    }

    func test_notSatisfied_tryAgain_regardlessOfAttempt() {
        XCTAssertFalse(ChildGrading.achievementSatisfied(outcome: .tryAgain, genuineAttempt: true))
        XCTAssertFalse(ChildGrading.achievementSatisfied(outcome: .tryAgain, genuineAttempt: false))
    }

    func test_pending_satisfies_onlyWhenGenuineAttempt() {
        // 字が汚くて読めなかっただけ（実際に書いた）→ 満たす
        XCTAssertTrue(ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: true))
        // パス/時間切れ/未記入（実際に書いていない）→ 満たさない（ズル防止）
        XCTAssertFalse(ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: false))
    }

    // MARK: - isAchieved: クラウン/ごほうび/パズル解放の達成ゲート

    func test_isAchieved_allSatisfied() {
        XCTAssertTrue(ChildGrading.isAchieved(satisfied: [true, true, true]))
    }

    func test_notAchieved_whenAnyUnsatisfied() {
        XCTAssertFalse(ChildGrading.isAchieved(satisfied: [true, false, true]))
    }

    func test_notAchieved_whenEmpty() {
        XCTAssertFalse(ChildGrading.isAchieved(satisfied: []))
    }

    // MARK: - 合成: 汚い手書きは達成できるが、パス連打はできない

    func test_messyButAttempted_achieves() {
        // 全語 needsReview（OCR読めず）だが実際に書いた → 達成
        let satisfied = [
            ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: true),
            ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: true)
        ]
        XCTAssertTrue(ChildGrading.isAchieved(satisfied: satisfied))
    }

    func test_passedEverything_doesNotAchieve() {
        // 全語パス/時間切れ（書いていない） → 未達成
        let satisfied = [
            ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: false),
            ChildGrading.achievementSatisfied(outcome: .pending, genuineAttempt: false)
        ]
        XCTAssertFalse(ChildGrading.isAchieved(satisfied: satisfied))
    }
}
