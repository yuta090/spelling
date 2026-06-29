import XCTest
@testable import SpellingSyncCore

/// 必須クリア状態（実装フェーズ① 必須土台）。
///
/// 契約（§3-7）：完了キーは文字列でなく **(stepID, 単語構成signature)**。
/// 単語の追加/置換で signature が変わり、自動で「未完了」に戻る（再ロック）。
/// これは「この単語セットの必須を一通り済ませた」印だけ＝既存の満点ゲートとは二重管理しない。
final class RequiredCompletionTests: XCTestCase {

    // signature は単語ID集合の順序・重複に依存しない（同じ集合＝同じ署名）。
    func testSignatureIsOrderAndDuplicateInsensitive() {
        let a = RequiredCompletionSignature.make(stepID: "step1", wordStableIDs: ["w1", "w2", "w3"])
        let b = RequiredCompletionSignature.make(stepID: "step1", wordStableIDs: ["w3", "w1", "w2", "w1"])
        XCTAssertEqual(a, b)
    }

    // stepID が違えば署名も違う。
    func testSignatureDependsOnStep() {
        let a = RequiredCompletionSignature.make(stepID: "step1", wordStableIDs: ["w1"])
        let b = RequiredCompletionSignature.make(stepID: "step2", wordStableIDs: ["w1"])
        XCTAssertNotEqual(a, b)
    }

    // クリアを記録すると、その単語セットでは完了扱い。
    func testMarkAndQueryCleared() {
        let sig = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2"])
        var rc = RequiredCompletion()
        XCTAssertFalse(rc.isCleared(sig))
        rc.markCleared(sig)
        XCTAssertTrue(rc.isCleared(sig))
    }

    // 単語が増える/変わると signature が変わり、自動で未完了に戻る（再ロック）。
    func testReLocksWhenWordSetChanges() {
        var rc = RequiredCompletion()
        let before = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2"])
        rc.markCleared(before)

        let afterAdd = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w2", "w3"])
        XCTAssertFalse(rc.isCleared(afterAdd), "単語追加で未完了に戻る")

        let afterReplace = RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1", "w9"])
        XCTAssertFalse(rc.isCleared(afterReplace), "単語置換で未完了に戻る")

        // 元の集合に戻れば再び完了扱い（履歴は保持）。
        XCTAssertTrue(rc.isCleared(before))
    }

    // 永続化できる（Codable round-trip）。
    func testCompletionRoundTrips() throws {
        var rc = RequiredCompletion()
        rc.markCleared(RequiredCompletionSignature.make(stepID: "s", wordStableIDs: ["w1"]))
        let data = try JSONEncoder().encode(rc)
        let back = try JSONDecoder().decode(RequiredCompletion.self, from: data)
        XCTAssertEqual(back, rc)
    }
}
