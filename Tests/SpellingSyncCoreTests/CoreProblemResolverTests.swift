import XCTest
@testable import SpellingSyncCore

/// 必須問題の解決ロジック（実装フェーズ① 必須土台）。
///
/// 契約（`docs/age-tiered-generation-spec-2026-06-29.md` §3）：
/// - 任意の登録語は**必ず1つの必須問題に解決**する（最後は `directSpelling`＝必ず成立／生成0でも回る）。
/// - 必須フレームは**綴りを変えない**＝はめた答えトークンが登録語の綴りと**完全一致**（活用/複数/大文字化なし）。
/// - ラダー＝フレーム→単語リスニング→直接スペル（§3.1）。単語リスニングは `allowWordListening` で無効化可（§3.3 厳格運用）。
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

    // MARK: 中央 rung＝単語リスニング（§3.1 フレーム一致→音の似たおとり→直接スペル）

    private let confusables: [ConfusableEntry] = [
        ConfusableEntry(word: "rice", soundsLike: ["lice", "race"], approved: true),
        ConfusableEntry(word: "ship", soundsLike: ["sheep"], approved: true),
    ]

    // フレームが無く、音の似たおとりがあれば単語リスニングに解決する（直接スペルの手前）。
    func testResolvesToWordListeningWhenConfusablesExist() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice")
        let problem = CoreProblemResolver.resolve(word: word, frames: [], confusables: confusables)
        XCTAssertEqual(problem, .wordListening(word: word, distractors: ["lice", "race"]))
    }

    // 単語リスニングの答えは登録語そのままの綴り（exact）。
    func testWordListeningAnswerIsExactSpelling() {
        let word = RegisteredWord(stableID: "w-ship", text: "ship")
        let problem = CoreProblemResolver.resolve(word: word, frames: [], confusables: confusables)
        guard case let .wordListening(w, distractors) = problem else {
            return XCTFail("単語リスニングに解決すべき: \(problem)")
        }
        XCTAssertEqual(w.text, "ship")        // 綴りは登録語のまま
        XCTAssertEqual(distractors, ["sheep"])
    }

    // ラダー順：フレームが合えば、おとりがあってもフレームが優先。
    func testFramePreferredOverListening() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice", partOfSpeech: "noun")
        let f = frame("f-eat", ["I", "eat", "_"], slot: 2, allowedPOS: ["noun"])
        let problem = CoreProblemResolver.resolve(word: word, frames: [f], confusables: confusables)
        guard case .spellingInvariantFrame = problem else {
            return XCTFail("フレーム優先のはず: \(problem)")
        }
    }

    // おとりが無ければ（フレームも無ければ）直接スペルへ（終端）。
    func testNoConfusablesFallsToDirectSpelling() {
        let word = RegisteredWord(stableID: "w-zzz", text: "rocket")
        let problem = CoreProblemResolver.resolve(word: word, frames: [], confusables: confusables)
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // §3.3 を厳格に守る運用：単語リスニングを無効化すると、おとりがあっても直接スペルへ。
    func testListeningCanBeDisabled() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice")
        let problem = CoreProblemResolver.resolve(word: word, frames: [], confusables: confusables,
                                                  allowWordListening: false)
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // 未承認のおとりは使わない（承認済みのみ）＝直接スペルへ。
    func testUnapprovedConfusablesIgnored() {
        let word = RegisteredWord(stableID: "w-x", text: "pour")
        let unapproved = [ConfusableEntry(word: "pour", soundsLike: ["poor"], approved: false)]
        let problem = CoreProblemResolver.resolve(word: word, frames: [], confusables: unapproved)
        XCTAssertEqual(problem, .directSpelling(word: word))
    }

    // MARK: §3.5 tier 制約はフレーム（生成物）に効く・登録語は例外

    // 文法天井を超えるフレームは必須に使わない（登録語は exempt）→ 下の rung へ。
    func testFrameOverGrammarCeilingSkipped() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice", partOfSpeech: "noun")
        // 受動態(passiveVoice=basic2) のフレームを、天井 intro1 の子に出さない。
        let hard = SpellingInvariantFrame(id: "f-hard", tokens: ["_", "is", "eaten"], answerSlotIndex: 0,
                                          ja: "和訳", allowedPOS: ["noun"], gradeBand: 1, grammar: .passiveVoice)
        let policy = ContentPolicy.standard(tier: .a, humorEnabled: false) // ceiling intro1
        let problem = CoreProblemResolver.resolve(word: word, frames: [hard],
                                                  confusables: confusables, policy: policy)
        // フレームは天井超で不可 → おとりがあるので単語リスニングへ。
        XCTAssertEqual(problem, .wordListening(word: word, distractors: ["lice", "race"]))
    }

    // 文法天井内・漢字内のフレームは使う（policy 指定でも通る）。和訳はひらがな（tier a）。
    func testFrameWithinCeilingUsedUnderPolicy() {
        let word = RegisteredWord(stableID: "w-apple", text: "apple", partOfSpeech: "noun")
        let easy = SpellingInvariantFrame(id: "f-easy", tokens: ["I", "like", "_"], answerSlotIndex: 2,
                                          ja: "りんごが すき", allowedPOS: ["noun"], gradeBand: 1, grammar: .presentSimple)
        let policy = ContentPolicy.standard(tier: .a, humorEnabled: false)
        let problem = CoreProblemResolver.resolve(word: word, frames: [easy], policy: policy)
        guard case .spellingInvariantFrame = problem else {
            return XCTFail("天井内フレームは使うべき: \(problem)")
        }
    }

    // §13.3 改訂2026-07-02：和訳の漢字ではフレームを却下しない（表示側でルビ）。tier a でも漢字入り
    // フレームを使う（超過漢字は表示時にふりがな）。難度は文法天井・語彙band で担保。
    func testFrameWithOverGradeKanjiStillUsed() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice", partOfSpeech: "noun")
        // 文法・band は tier a 内。和訳に超過漢字（米/好）を含むが、却下しない。
        let kanjiFrame = SpellingInvariantFrame(id: "f-kanji", tokens: ["I", "like", "_"], answerSlotIndex: 2,
                                                ja: "お米が 好きだよ", allowedPOS: ["noun"],
                                                gradeBand: 1, grammar: .presentSimple)
        let policy = ContentPolicy.standard(tier: .a, humorEnabled: false) // maxKanjiGrade 0
        let problem = CoreProblemResolver.resolve(word: word, frames: [kanjiFrame],
                                                  confusables: confusables, policy: policy)
        guard case let .spellingInvariantFrame(f, w) = problem else {
            return XCTFail("漢字入りでも却下せずフレームを使うべき: \(problem)")
        }
        XCTAssertEqual(f.id, "f-kanji")
        XCTAssertEqual(w.text, "rice")
    }

    // §3.5：登録語は tier 例外。むずかしい/まれな語でも、やさしい乗り物フレームには載る。
    func testRegisteredWordIsTierExempt() {
        // 登録語 "rhinoceros"（まれ）でも、フレーム側の band/grammar/漢字が tier a 内なら載る。
        let hardWord = RegisteredWord(stableID: "w-rhino", text: "rhinoceros", partOfSpeech: "noun")
        let easy = SpellingInvariantFrame(id: "f-easy", tokens: ["I", "see", "a", "_"], answerSlotIndex: 3,
                                          ja: "みえるよ", allowedPOS: ["noun"], gradeBand: 1, grammar: .presentSimple)
        let policy = ContentPolicy.standard(tier: .a, humorEnabled: false)
        let problem = CoreProblemResolver.resolve(word: hardWord, frames: [easy], policy: policy)
        guard case let .spellingInvariantFrame(_, w) = problem else {
            return XCTFail("登録語は tier 例外＝やさしいフレームに載るべき: \(problem)")
        }
        XCTAssertEqual(w.text, "rhinoceros")  // 綴りはそのまま
    }

    // policy 未指定なら tier 制約はかからない（後方互換）。
    func testNoPolicyMeansNoTierConstraint() {
        let word = RegisteredWord(stableID: "w-rice", text: "rice", partOfSpeech: "noun")
        let hard = SpellingInvariantFrame(id: "f-hard", tokens: ["_", "is", "eaten"], answerSlotIndex: 0,
                                          ja: "和訳", allowedPOS: ["noun"], gradeBand: 5, grammar: .passiveVoice)
        let problem = CoreProblemResolver.resolve(word: word, frames: [hard])
        guard case .spellingInvariantFrame = problem else {
            return XCTFail("policy 無しなら制約なしで載るべき")
        }
    }
}
