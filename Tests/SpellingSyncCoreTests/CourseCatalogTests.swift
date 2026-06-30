import XCTest
@testable import SpellingSyncCore

/// コース（学年×英検の2軸）のカタログ生成（仮想・読み取り専用）と練習抑制の純ロジック。
///
/// 設計（`docs/step-map-and-courses-spec-2026-06-29.md` §5 / `docs/eiken-level-mapping.md` §2 / 本実装プラン）：
/// - 同梱 wordbank の頻度順語彙を **英検バンド範囲**でスライスしてステップ階段を作る。
/// - 学年帯は英検バンドを学年数で等分割して入れ子化（小1+小2 ⊂ 英検5級）。
/// - 入力順非依存の決定論（再起動/ビルド間で同じ stepID・語並び）。
/// - 機能語(the/and/you 等)・短すぎ・非英字・訳無しは出題に不向きなので除外。
/// - マスター済み（ノーミス合格かつ最新クリア）の語は**練習**から外す（テストには出す）。
final class CourseCatalogTests: XCTestCase {

    /// テスト用に「rank=n の出題可能なダミー語」を作る（3文字以上・**英字のみ**・訳あり）。
    /// rank の各桁を a〜j に写像して英字だけのユニーク語にする（数字混入を避ける）。
    private func row(rank: Int) -> LeveledRow {
        let suffix = String(format: "%04d", rank).map { Character(UnicodeScalar(97 + Int(String($0))!)!) }
        return LeveledRow(word: "wordzz" + String(suffix), gloss: "やく\(rank)", ngslRank: rank)
    }
    private func rows(ranks: [Int]) -> [LeveledRow] { ranks.map(row(rank:)) }
    private func rows(_ range: ClosedRange<Int>) -> [LeveledRow] { range.map(row(rank:)) }

    // MARK: - 英検バンド範囲（eiken-level-mapping.md §2）

    func testEikenRankRanges() {
        XCTAssertEqual(EikenLevel.g5.rankRange, 1...500)
        XCTAssertEqual(EikenLevel.g4.rankRange, 501...1500)
        XCTAssertEqual(EikenLevel.g3.rankRange, 1501...2200)
        XCTAssertEqual(EikenLevel.p2.rankRange, 2201...2816)
    }

    func testEikenCourseID() {
        XCTAssertEqual(EikenLevel.g5.courseID, "eiken-g5")
        XCTAssertEqual(EikenLevel.p2.courseID, "eiken-p2")
    }

    // MARK: - 学年帯（英検バンドの学年等分割・入れ子）

    func testGradeCourseID() {
        XCTAssertEqual(GradeBand.courseID(schoolGrade: 1), "grade-1")
        XCTAssertEqual(GradeBand.courseID(schoolGrade: 9), "grade-9")
    }

    func testGradeRangesNestInsideEikenBands() {
        // tier a（小1,小2）＝英検5級 band[1,500] を2等分。
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 1), 1...250)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 2), 251...500)
        // 連続＋英検5級を完全網羅。
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 1).upperBound + 1,
                       GradeBand.rankRange(schoolGrade: 2).lowerBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 1).lowerBound, EikenLevel.g5.rankRange.lowerBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 2).upperBound, EikenLevel.g5.rankRange.upperBound)

        // tier b（小3,小4）＝4級 band[501,1500] を2等分。
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 3), 501...1000)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 4), 1001...1500)

        // tier c（小5,小6,中1）＝3級 band[1501,2200] を3等分（端は英検帯に一致）。
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 5).lowerBound, EikenLevel.g3.rankRange.lowerBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 7).upperBound, EikenLevel.g3.rankRange.upperBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 5).upperBound + 1, GradeBand.rankRange(schoolGrade: 6).lowerBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 6).upperBound + 1, GradeBand.rankRange(schoolGrade: 7).lowerBound)

        // tier d（中2,中3）＝準2級 band[2201,2816] を2等分。
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 8).lowerBound, EikenLevel.p2.rankRange.lowerBound)
        XCTAssertEqual(GradeBand.rankRange(schoolGrade: 9).upperBound, EikenLevel.p2.rankRange.upperBound)
    }

    // MARK: - buildSteps（英検）

    func testBuildStepsEikenFiltersToRangeAndNamespacesIDs() {
        // rank 1..600 を供給 → 英検5級(1..500)だけ採用。
        let steps = CourseCatalog.buildSteps(rows: rows(1...600), eiken: .g5, stepSize: 10)
        let words = steps.flatMap { $0.words }
        XCTAssertEqual(words.first?.ngslRank, 1)
        XCTAssertEqual(words.last?.ngslRank, 500)            // 501..600 は範囲外
        XCTAssertEqual(words.count, 500)
        XCTAssertEqual(steps.first?.stepID, "eiken-g5.s01")
        XCTAssertEqual(steps.first?.index, 0)
        XCTAssertEqual(steps.count, 50)                      // 500 / 10
    }

    // MARK: - buildSteps（学年）

    func testBuildStepsGradeUsesNestedRange() {
        let steps = CourseCatalog.buildSteps(rows: rows(1...600), schoolGrade: 1, stepSize: 10)
        let words = steps.flatMap { $0.words }
        XCTAssertEqual(words.first?.ngslRank, 1)
        XCTAssertEqual(words.last?.ngslRank, 250)            // 小1 = 1..250
        XCTAssertEqual(steps.first?.stepID, "grade-1.s01")
    }

    func testStepIDsSequential() {
        let steps = CourseCatalog.buildSteps(rows: rows(1...500), eiken: .g5, stepSize: 10)
        for (i, s) in steps.enumerated() {
            XCTAssertEqual(s.stepID, "eiken-g5.s" + String(format: "%02d", i + 1))
            XCTAssertEqual(s.index, i)
        }
    }

    func testStepSizingAndRemainderKept() {
        // 範囲内に25語 → 10/10/5。
        let steps = CourseCatalog.buildSteps(rows: rows(1...25),
                                             courseID: "x", rankRange: 1...25, stepSize: 10)
        XCTAssertEqual(steps.map { $0.words.count }, [10, 10, 5])
    }

    // MARK: - 決定論

    func testSortIndependence() {
        let base = rows(1...100)
        let sorted = CourseCatalog.buildSteps(rows: base, courseID: "x", rankRange: 1...100, stepSize: 10)
        let shuffledA = CourseCatalog.buildSteps(rows: base.reversed(), courseID: "x", rankRange: 1...100, stepSize: 10)
        let shuffledB = CourseCatalog.buildSteps(rows: [base[50], base[3], base[99]] + base,
                                                 courseID: "x", rankRange: 1...100, stepSize: 10)
        XCTAssertEqual(shuffledA, sorted)
        // 重複入力でも range 内ユニークになる訳ではない（重複は許容）—ここは順序安定だけ確認。
        XCTAssertEqual(shuffledB.flatMap { $0.words.map(\.ngslRank) }.sorted(), shuffledB.flatMap { $0.words.map(\.ngslRank) })
    }

    func testTieBreakByWordWhenSameRank() {
        let a = LeveledRow(word: "banana", gloss: "バナナ", ngslRank: 5)
        let b = LeveledRow(word: "apple", gloss: "りんご", ngslRank: 5)
        let steps = CourseCatalog.buildSteps(rows: [a, b], courseID: "x", rankRange: 1...10, stepSize: 10)
        XCTAssertEqual(steps.first?.words.map(\.text), ["apple", "banana"])
    }

    // MARK: - フィルタ

    func testFunctionWordsExcluded() {
        let input = [
            LeveledRow(word: "the", gloss: "その", ngslRank: 1),
            LeveledRow(word: "and", gloss: "と", ngslRank: 2),
            LeveledRow(word: "you", gloss: "あなた", ngslRank: 3),
            LeveledRow(word: "apple", gloss: "りんご", ngslRank: 4),
        ]
        let words = CourseCatalog.buildSteps(rows: input, courseID: "x", rankRange: 1...10, stepSize: 10)
            .flatMap { $0.words.map(\.text) }
        XCTAssertEqual(words, ["apple"])
    }

    func testShortNonAlphaAndEmptyGlossExcluded() {
        let input = [
            LeveledRow(word: "ab", gloss: "短い", ngslRank: 1),         // 2文字
            LeveledRow(word: "ca1t", gloss: "数字混じり", ngslRank: 2),  // 非英字
            LeveledRow(word: "cake", gloss: "  ", ngslRank: 3),         // 訳空白
            LeveledRow(word: "tiger", gloss: "とら", ngslRank: 4),      // 通す
        ]
        let words = CourseCatalog.buildSteps(rows: input, courseID: "x", rankRange: 1...10, stepSize: 10)
            .flatMap { $0.words.map(\.text) }
        XCTAssertEqual(words, ["tiger"])
    }

    func testFilterAppliedBeforeRange() {
        var input = rows(1...9)                                          // 通る9語(rank1..9)
        input.insert(LeveledRow(word: "the", gloss: "その", ngslRank: 5), at: 0) // 範囲内だが機能語
        let steps = CourseCatalog.buildSteps(rows: input, courseID: "x", rankRange: 1...9, stepSize: 100)
        XCTAssertEqual(steps.first?.words.count, 9)
        XCTAssertFalse(steps.flatMap { $0.words.map(\.text) }.contains("the"))
    }

    // MARK: - 合成語の安定ID＆署名

    func testWordStableIDIsDeterministicAndCourseScoped() {
        let a = CourseCatalog.wordStableID(courseID: "eiken-g5", text: "apple")
        let b = CourseCatalog.wordStableID(courseID: "eiken-g5", text: "apple")
        let c = CourseCatalog.wordStableID(courseID: "grade-1", text: "apple")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testCatalogStepSignatureStableAcrossBuilds() {
        func sig() -> StepSignature {
            let steps = CourseCatalog.buildSteps(rows: rows(1...100), eiken: .g5, stepSize: 10)
            let s = steps[0]
            let ids = s.words.map { CourseCatalog.wordStableID(courseID: "eiken-g5", text: $0.text).uuidString }
            return RequiredCompletionSignature.make(stepID: s.stepID, wordStableIDs: ids)
        }
        XCTAssertEqual(sig(), sig())
    }

    // MARK: - 端

    func testEmptyRowsYieldNoSteps() {
        XCTAssertTrue(CourseCatalog.buildSteps(rows: [], eiken: .g5).isEmpty)
    }

    func testStepSizeFallsBackWhenNonPositive() {
        let steps = CourseCatalog.buildSteps(rows: rows(1...9), courseID: "x", rankRange: 1...9, stepSize: 0)
        XCTAssertEqual(steps.flatMap { $0.words.count }, [9])  // 既定(10)で1ステップ
    }

    // MARK: - 練習抑制（マスター済みは練習で出さない・テストは別）

    func testPracticeWordsExcludesSuppressed() {
        let words = ["cat", "dog", "sun"]
        let out = PracticeSelection.practiceWords(words, suppressed: ["cat"], keyOf: { $0 })
        XCTAssertEqual(out, ["dog", "sun"])
    }

    func testPracticeWordsEmptySuppressedIsIdentity() {
        let words = ["cat", "dog"]
        XCTAssertEqual(PracticeSelection.practiceWords(words, suppressed: [], keyOf: { $0 }), words)
    }

    func testPracticeWordsKeyMapping() {
        struct W: Equatable { let text: String }
        let ws = [W(text: "Cat"), W(text: "Dog")]
        // 正規化（小文字）キーで判定する想定を keyOf で表現。
        let out = PracticeSelection.practiceWords(ws, suppressed: ["cat"], keyOf: { $0.text.lowercased() })
        XCTAssertEqual(out, [W(text: "Dog")])
    }

    // 再ドリル許可：一部抑制なら抑制を除いた残りを返す（通常の飽き防止と同じ）。
    func testPracticeWordsAllowingRedrillPartialSuppressionExcludes() {
        let words = ["cat", "dog", "sun"]
        let out = PracticeSelection.practiceWordsAllowingRedrill(words, suppressed: ["cat"], keyOf: { $0 })
        XCTAssertEqual(out, ["dog", "sun"])
    }

    // 再ドリル許可：全部抑制（全語マスター済み）で空になるなら、練習を“できなく”しないよう全語に戻す。
    func testPracticeWordsAllowingRedrillAllSuppressedFallsBackToFull() {
        let words = ["cat", "dog", "sun"]
        let out = PracticeSelection.practiceWordsAllowingRedrill(words,
                                                                 suppressed: ["cat", "dog", "sun"],
                                                                 keyOf: { $0 })
        XCTAssertEqual(out, words)
    }

    // 再ドリル許可：元が空（ステップに語が無い）なら空のまま（「たんごがない」は維持）。
    func testPracticeWordsAllowingRedrillEmptyInputStaysEmpty() {
        let words: [String] = []
        let out = PracticeSelection.practiceWordsAllowingRedrill(words, suppressed: ["cat"], keyOf: { $0 })
        XCTAssertTrue(out.isEmpty)
    }

    // 抑制キー：既存シグナル(最新クリア/未解決/復習アクティブ)から算出（codex Architect の真理値表）。
    func testSuppressedPracticeKeysTruthTable() {
        // 各ケースの語を1つずつ。
        let latestCleared: Set<String> = ["clearedNeverMissed", "reCleared", "graduated"]
        let unresolved: Set<String> = ["missedDue"]                       // 最新ミス
        let activeReview: Set<String> = ["missedDue", "reCleared"]        // 復習中(未マスター)
        let suppressed = PracticeSelection.suppressedPracticeKeys(
            latestClearedTexts: latestCleared,
            unresolvedTexts: unresolved,
            activeReviewTexts: activeReview
        )
        // 抑制される＝練習に出さない。
        XCTAssertTrue(suppressed.contains("clearedNeverMissed"))  // 最新クリア・未解決でない・復習でない
        XCTAssertTrue(suppressed.contains("graduated"))           // 卒業済み＋最新クリア
        // 抑制されない＝練習に出す。
        XCTAssertFalse(suppressed.contains("brandNew"))           // 未クリア（そもそも latestCleared に無い）
        XCTAssertFalse(suppressed.contains("missedDue"))          // 最新ミス→練習に戻す
        XCTAssertFalse(suppressed.contains("reCleared"))          // 再クリアだが復習中→卒業まで練習
    }
}
