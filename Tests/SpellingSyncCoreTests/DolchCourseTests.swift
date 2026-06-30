import XCTest
@testable import SpellingSyncCore

/// Dolch サイトワード（基礎語）コースのカタログ生成（仮想・読み取り専用）の純ロジック。
///
/// 設計の核心:
/// - 出題順は Dolch 難易度の自然順 pre-K → K → 1 → 2 → 3 → noun（名詞は最後）。同帯内はアルファベット順。
/// - **機能語(the/and/you/this 等)を除外しない**: Dolch はそれら自体が教材の中心。長さは ≥2、訳無しは除外。
/// - 入力順非依存の決定論（再起動/ビルド間で同じ stepID・語並び）。
final class DolchCourseTests: XCTestCase {

    private func r(_ word: String, _ dolch: String, gloss: String = "やく") -> DolchRow {
        DolchRow(word: word, gloss: gloss, dolch: dolch)
    }

    /// 連番から英字のみのユニーク語を作る（数字混入を避けてフィルタを通す）。
    private func alphaWord(_ i: Int) -> String {
        "ww" + String(format: "%03d", i).map { Character(UnicodeScalar(97 + Int(String($0))!)!) }
    }

    // MARK: - DolchBand 順序

    func testDolchBandOrderIsNaturalDifficulty() {
        XCTAssertEqual(DolchBand.preK.order, 0)
        XCTAssertEqual(DolchBand.k.order, 1)
        XCTAssertEqual(DolchBand.g1.order, 2)
        XCTAssertEqual(DolchBand.g2.order, 3)
        XCTAssertEqual(DolchBand.g3.order, 4)
        XCTAssertEqual(DolchBand.noun.order, 5)
    }

    func testDolchBandRawValuesMatchDB() {
        XCTAssertEqual(DolchBand(rawValue: "pre-K"), .preK)
        XCTAssertEqual(DolchBand(rawValue: "K"), .k)
        XCTAssertEqual(DolchBand(rawValue: "1"), .g1)
        XCTAssertEqual(DolchBand(rawValue: "2"), .g2)
        XCTAssertEqual(DolchBand(rawValue: "3"), .g3)
        XCTAssertEqual(DolchBand(rawValue: "noun"), .noun)
        XCTAssertNil(DolchBand(rawValue: "K2"))
    }

    // MARK: - 出題順（帯順 → 同帯アルファベット順）

    func testStepsOrderedByBandThenAlphabetical() {
        let input = [
            r("watch", "noun"),
            r("sit", "2"),
            r("she", "K"),
            r("up", "pre-K"),
            r("red", "pre-K"),
            r("our", "K"),
        ]
        let words = CourseCatalog.buildDolchSteps(rows: input, stepSize: 100)
            .flatMap { $0.words.map(\.text) }
        // pre-K(red,up) → K(our,she) → 2(sit) → noun(watch)。同帯内はアルファベット昇順。
        XCTAssertEqual(words, ["red", "up", "our", "she", "sit", "watch"])
    }

    // MARK: - 機能語を**残す**（核心）

    func testFunctionWordsAreKept() {
        let input = [r("the", "pre-K"), r("and", "pre-K"), r("you", "pre-K"), r("this", "pre-K")]
        let words = CourseCatalog.buildDolchSteps(rows: input, stepSize: 100)
            .flatMap { $0.words.map(\.text) }
        XCTAssertEqual(words.sorted(), ["and", "the", "this", "you"])
    }

    // MARK: - フィルタ（訳無し / 1文字 / 非英字 / 未知の dolch を除外）

    func testRejectsEmptyGlossShortNonAlphaAndUnknownBand() {
        let input = [
            r("go", "pre-K", gloss: "いく"),     // 通す（2文字・機能語でも残す）
            r("a", "pre-K", gloss: "ひとつの"),  // 1文字 → 除外
            r("ye1s", "K", gloss: "はい"),       // 非英字 → 除外
            r("dog", "noun", gloss: "  "),       // 訳空白 → 除外
            r("cat", "K9", gloss: "ねこ"),       // 未知の dolch 帯 → 除外
            r("run", "1", gloss: "はしる"),      // 通す
        ]
        let words = CourseCatalog.buildDolchSteps(rows: input, stepSize: 100)
            .flatMap { $0.words.map(\.text) }
        XCTAssertEqual(words.sorted(), ["go", "run"])
    }

    // MARK: - stepID 命名 & 分割

    func testStepIDNamingAndSizing() {
        // 同帯25語 → 10/10/5。stepID は dolch.s01..s03。
        let input = (0..<25).map { r(alphaWord($0), "pre-K") }
        let steps = CourseCatalog.buildDolchSteps(rows: input, stepSize: 10)
        XCTAssertEqual(steps.map { $0.words.count }, [10, 10, 5])
        XCTAssertEqual(steps.map(\.stepID), ["dolch.s01", "dolch.s02", "dolch.s03"])
        XCTAssertEqual(steps.map(\.index), [0, 1, 2])
    }

    func testStepSizeFallsBackWhenNonPositive() {
        let input = (0..<9).map { r(alphaWord($0), "pre-K") }
        let steps = CourseCatalog.buildDolchSteps(rows: input, stepSize: 0)
        XCTAssertEqual(steps.flatMap { $0.words.count }, [9])  // 既定(10)で1ステップ
    }

    // MARK: - 決定論（入力順非依存）

    func testDeterministicAcrossInputOrder() {
        let input = [
            r("up", "pre-K"), r("she", "K"), r("watch", "noun"),
            r("sit", "2"), r("red", "pre-K"), r("our", "K"),
        ]
        let a = CourseCatalog.buildDolchSteps(rows: input, stepSize: 4)
        let b = CourseCatalog.buildDolchSteps(rows: input.reversed(), stepSize: 4)
        XCTAssertEqual(a, b)              // 入力順を反転しても同一＝決定論
        XCTAssertFalse(a.isEmpty)

        // 重複入りでも入力順非依存で決定論（重複は除かれず安定順で並ぶ）。
        let cInput = [input[3], input[0]] + input          // sit,up を先頭に重複追加
        let c1 = CourseCatalog.buildDolchSteps(rows: cInput, stepSize: 4)
        let c2 = CourseCatalog.buildDolchSteps(rows: cInput.reversed(), stepSize: 4)
        XCTAssertEqual(c1, c2)                              // 重複があっても入力順非依存で同一
        let c1Texts = c1.flatMap { $0.words.map(\.text) }
        XCTAssertEqual(c1Texts.count, cInput.count)         // 重複は除かれない（全語が残る）
        // 同一帯内はアルファベット順（pre-K 帯の red < up < up を確認）。
        XCTAssertEqual(c1Texts.prefix(3).map { $0 }, ["red", "up", "up"])
    }

    // MARK: - 端

    func testEmptyRowsYieldNoSteps() {
        XCTAssertTrue(CourseCatalog.buildDolchSteps(rows: []).isEmpty)
    }

    // MARK: - 安定ID は courseID="dolch" でスコープされる

    func testWordStableIDScopedToDolchCourse() {
        let d = CourseCatalog.wordStableID(courseID: "dolch", text: "the")
        let g = CourseCatalog.wordStableID(courseID: "grade-1", text: "the")
        XCTAssertEqual(d, CourseCatalog.wordStableID(courseID: "dolch", text: "the"))
        XCTAssertNotEqual(d, g)
    }
}
