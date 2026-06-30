import XCTest
@testable import SpellingSyncCore

/// ステップの焦点（必須をやる段階 / 満点クリア後の自由＝パズル解放）と、
/// 満点になった“瞬間”の「あたらしいクイズがでた！」アンロック演出を1回だけ出すための記録。
///
/// 設計（docs/age-tiered-generation-spec-2026-06-29.md §2 自動フロー）：
/// - 「必須（手書き満点）を先にクリア → 満点後にパズル（自由）がアンロック」。
///   理由＝①必ず覚えてほしい構文/単語を先に確実に通す ②一つをしっかり定着、の両立。
/// - **パズルはクリア条件にしない**。満点＝唯一のクリア条件（呼び出し側の満点ゲートに委譲・§3.6で二重管理しない）。
/// - 演出は「満点になった瞬間に1回だけ」。毎回起動で再演出しない（[[control-repeating-animated-ui]] と同じ方針）。
///   キーは StepSignature なので、単語を入れ替えて新しいセットを満点にすれば新しい演出になる。
final class StepFocusResolverTests: XCTestCase {

    // 満点でない → 必須をやる段階。
    func testFocusIsRequiredWhenNotMastered() {
        XCTAssertEqual(StepFocusResolver.focus(isMastered: false), .required)
    }

    // 満点 → パズルが解放された自由段階。
    func testFocusIsFreePlayWhenMastered() {
        XCTAssertEqual(StepFocusResolver.focus(isMastered: true), .freePlayUnlocked)
    }

    // 満点になっていて、その署名でまだ演出していない → アンロック演出を出す。
    func testCelebratesWhenMasteredAndNotYetCelebrated() {
        let sig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2"])
        let celebration = StepUnlockCelebration()
        XCTAssertTrue(StepFocusResolver.shouldCelebrateUnlock(
            signature: sig, isMastered: true, celebration: celebration))
    }

    // まだ満点でない → 演出は出さない（クリアしていないのに祝わない）。
    func testNoCelebrationWhenNotMastered() {
        let sig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1"])
        let celebration = StepUnlockCelebration()
        XCTAssertFalse(StepFocusResolver.shouldCelebrateUnlock(
            signature: sig, isMastered: false, celebration: celebration))
    }

    // 既に演出した署名 → もう出さない（毎回起動で再演出しない）。
    func testNoCelebrationWhenAlreadyCelebrated() {
        let sig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1"])
        var celebration = StepUnlockCelebration()
        celebration.markCelebrated(sig)
        XCTAssertFalse(StepFocusResolver.shouldCelebrateUnlock(
            signature: sig, isMastered: true, celebration: celebration))
    }

    // 演出を記録すると、その署名では shouldCelebrate が false に落ちる。
    func testMarkCelebratedThenStopsCelebrating() {
        let sig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1"])
        var celebration = StepUnlockCelebration()
        XCTAssertTrue(StepFocusResolver.shouldCelebrateUnlock(
            signature: sig, isMastered: true, celebration: celebration))
        celebration.markCelebrated(sig)
        XCTAssertFalse(StepFocusResolver.shouldCelebrateUnlock(
            signature: sig, isMastered: true, celebration: celebration))
    }

    // 単語を入れ替えた新しいセット（＝別署名）を満点にしたら、また祝う。
    func testNewWordSetCelebratesAgain() {
        let oldSig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2"])
        var celebration = StepUnlockCelebration()
        celebration.markCelebrated(oldSig)

        let newSig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2", "w3"])
        XCTAssertFalse(celebration.wasCelebrated(newSig))
        XCTAssertTrue(StepFocusResolver.shouldCelebrateUnlock(
            signature: newSig, isMastered: true, celebration: celebration))
    }

    // 永続化できる（Codable round-trip）。
    func testCelebrationRoundTrips() throws {
        var celebration = StepUnlockCelebration()
        celebration.markCelebrated(RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1"]))
        let data = try JSONEncoder().encode(celebration)
        let back = try JSONDecoder().decode(StepUnlockCelebration.self, from: data)
        XCTAssertEqual(back, celebration)
    }
}
