import XCTest
@testable import SpellingSyncCore

/// スペル練習（書き問題）のヒント例文を「その練習語を含み・子の段階で読める生成文」から選ぶ純ロジックのテスト。
/// 田中コーパス（大人題材）直読みをやめ、生成バンク（学年タグ付き）から選ぶための土台。
final class PracticeExampleSelectorTests: XCTestCase {
    private let tierA = ContentPolicy.standard(tier: .a, humorEnabled: false)

    private func item(_ en: String, ja: String, band: Int,
                      lemmas: [String], tokens: [String]? = nil,
                      grammar: GrammarPoint? = nil) -> SentenceItem {
        SentenceItem(en: en, ja: ja, tokens: tokens ?? en.split(separator: " ").map(String.init),
                     gradeBand: band, contentLemmas: lemmas, grammar: grammar)
    }

    /// 練習語がその文の内容語に（活用形込みで）含まれれば候補になる。
    func testFindsExampleContainingPracticeWord() {
        let bank = [item("She likes apples", ja: "かのじょは りんごが すき", band: 1, lemmas: ["like", "apples"])]
        let hit = PracticeExampleSelector.example(for: "apple", in: bank, policy: tierA)
        XCTAssertEqual(hit?.en, "She likes apples")
    }

    /// 照合は見出し語化する：練習語 "study" は文中の "studies"/"studied" に一致する。
    func testMatchesViaLemmaForInflectedForms() {
        let bank = [item("She studies English", ja: "かのじょは えいごを べんきょうする", band: 1, lemmas: ["studies", "english"])]
        XCTAssertNotNil(PracticeExampleSelector.example(for: "study", in: bank, policy: tierA))
    }

    /// 練習語を含む文が無ければ nil（→ 呼び出し側は例文を隠すフォールバック）。
    func testReturnsNilWhenNoSentenceContainsWord() {
        let bank = [item("She likes apples", ja: "かのじょは りんごが すき", band: 1, lemmas: ["like", "apples"])]
        XCTAssertNil(PracticeExampleSelector.example(for: "elephant", in: bank, policy: tierA))
    }

    /// 段階a（漢字maxGrade=0＝ひらがな主体）では、和訳に配当外漢字を含む文は除外する。
    func testExcludesSentenceWithKanjiBeyondTierAGate() {
        let bank = [item("I study hard", ja: "しっかり 勉強する", band: 1, lemmas: ["study", "hard"])]
        XCTAssertNil(PracticeExampleSelector.example(for: "study", in: bank, policy: tierA),
                     "「勉強」は段階aの漢字ゲート(maxGrade=0)を超えるので除外される")
    }

    /// 候補が複数あるとき、決定論的に並ぶ（学年band低い→短い→英文アルファベット順）。
    func testDeterministicOrderingPrefersLowerBandThenShorter() {
        let long = item("I really like red apples a lot", ja: "りんごが すき", band: 1, lemmas: ["apple"])
        let short = item("I like apples", ja: "りんごが すき", band: 1, lemmas: ["apple"])
        let cands = PracticeExampleSelector.candidates(for: "apple", in: [long, short], policy: tierA)
        XCTAssertEqual(cands.map(\.en), ["I like apples", "I really like red apples a lot"])
    }

    /// seed で決定論的に候補を回転（同じ入力＝同じ結果・繰り返し表示で多様性）。
    func testSeedRotatesDeterministicallyAmongCandidates() {
        let a = item("I like apples", ja: "りんごが すき", band: 1, lemmas: ["apple"])
        let b = item("We eat apples", ja: "りんごを たべる", band: 1, lemmas: ["apple"])
        let cands = PracticeExampleSelector.candidates(for: "apple", in: [a, b], policy: tierA)
        let pick0 = PracticeExampleSelector.example(for: "apple", in: [a, b], policy: tierA, seed: 0)
        let pick1 = PracticeExampleSelector.example(for: "apple", in: [a, b], policy: tierA, seed: 1)
        XCTAssertEqual(pick0?.en, cands[0].en)
        XCTAssertEqual(pick1?.en, cands[1].en)
        // 同じ seed は毎回同じ（決定論）。
        XCTAssertEqual(PracticeExampleSelector.example(for: "apple", in: [a, b], policy: tierA, seed: 5)?.en,
                       PracticeExampleSelector.example(for: "apple", in: [a, b], policy: tierA, seed: 5)?.en)
    }
}
