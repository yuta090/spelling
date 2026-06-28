import XCTest
@testable import SpellingSyncCore

/// 必須問題の解決ロジック（実装フェーズ① 必須土台）。
///
/// 契約（`docs/age-tiered-generation-spec-2026-06-29.md` §3）：
/// - 任意の登録語は**必ず1つの必須問題に解決**する（最後は `directSpelling`＝必ず成立／生成0でも回る）。
/// - 必須フレームは**綴りを変えない**＝はめた答えトークンが登録語の綴りと**完全一致**（活用/複数/大文字化なし）。
/// - 必須は「綴りを自分で打つ形」に限る（選んで答える形は必須に使わない）。
/// - Core はアプリの `SpellingWord` を持ち込まず、`RegisteredWord`(Core DTO)で受ける。
final class CoreProblemResolverTests: XCTestCase {

    private func frame(_ id: String, _ tokens: [String], slot: Int,
                       ja: String = "和訳", allowedPOS: [String] = []) -> SpellingInvariantFrame {
        SpellingInvariantFrame(id: id, tokens: tokens, answerSlotIndex: slot, ja: ja, allowedPOS: allowedPOS)
    }

    // フレームが合えば綴り不変フレームを選ぶ。
    func testResolvesToFrameWhenAvailable() {
        let word = RegisteredWord(stableID: "w-apple", text: "apple", partOfSpeech: "noun")
        let f = frame("f-like", ["I", "like", "APPLE_SLOT"], slot: 2, allowedPOS: ["noun"])
        let problem = CoreProblemResolver.resolve(word: word, frames: [f])
        guard case let .spellingInvariantFrame(chosen, w) = problem else {
            return XCTFail("綴り不変フレームに解決すべき: \(problem)")
        }
        XCTAssertEqual(chosen.id, "f-like")
        XCTAssertEqual(w, word)
    }

    // フレームに登録語を入れても綴りが一切変わらない（完全一致）。
    func testFrameKeepsSpellingExact() {
        let word = RegisteredWord(stableID: "w-apple", text: "apple")
        let f = frame("f-like", ["I", "like", "_"], slot: 2)
        let filled = f.filled(with: word)
        XCTAssertEqual(filled.tokens[filled.answerIndex], "apple", "答えトークンは綴り不変であること")
        XCTAssertEqual(filled.tokens, ["I", "like", "apple"])
    }

    // フレームが無ければ必ず直接スペルに落ちる（終端・常に成立）。
    func testFallsBackToDirectSpelling() {
        let word = RegisteredWord(stableID: "w-zzz", text: "rocket")
        let problem = CoreProblemResolver.resolve(word: word, frames: [])
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // 品詞が合わないフレームは使わず直接スペルへ（無理にはめない）。
    func testSkipsFrameOnPOSMismatch() {
        let word = RegisteredWord(stableID: "w-run", text: "run", partOfSpeech: "verb")
        let nounFrame = frame("f-like", ["I", "like", "_"], slot: 2, allowedPOS: ["noun"])
        let problem = CoreProblemResolver.resolve(word: word, frames: [nounFrame])
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // スロット位置が壊れたフレームは使わない（安全側＝直接スペル）。
    func testIgnoresMalformedFrame() {
        let word = RegisteredWord(stableID: "w-apple", text: "apple")
        let broken = frame("f-bad", ["I", "like"], slot: 9)  // 範囲外
        let problem = CoreProblemResolver.resolve(word: word, frames: [broken])
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // 品詞情報が無い語は、POS制約の無いフレームになら載る。
    func testWordWithoutPOSUsesUnconstrainedFrame() {
        let word = RegisteredWord(stableID: "w-x", text: "book")
        let f = frame("f-open", ["read", "a", "_"], slot: 2, allowedPOS: [])
        let problem = CoreProblemResolver.resolve(word: word, frames: [f])
        guard case .spellingInvariantFrame = problem else {
            return XCTFail("POS制約無しフレームには載るべき")
        }
    }
}
