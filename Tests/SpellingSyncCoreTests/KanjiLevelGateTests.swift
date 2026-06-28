import XCTest
@testable import SpellingSyncCore

/// 学年別漢字配当表（教育漢字1,026字）と、和訳 `ja` の漢字を「習った学年以内」に
/// 制限する検査 `KanjiLevelGate` の検証。
final class KanjiLevelGateTests: XCTestCase {

    // MARK: - 配当表データ

    func testTotalCountIs1026() {
        XCTAssertEqual(KyoikuKanji.count, 1026)
    }

    func testPerGradeCounts() {
        let expected = [1: 80, 2: 160, 3: 200, 4: 202, 5: 193, 6: 191]
        for (g, n) in expected {
            XCTAssertEqual(KyoikuKanji.byGrade[g]?.count, n, "G\(g) の字数が違う")
        }
    }

    func testGradeOfKnownKanji() {
        XCTAssertEqual(KyoikuKanji.gradeOf["一"], 1)
        XCTAssertEqual(KyoikuKanji.gradeOf["学"], 1)
        XCTAssertEqual(KyoikuKanji.gradeOf["校"], 1)
        XCTAssertEqual(KyoikuKanji.gradeOf["親"], 2)
        XCTAssertEqual(KyoikuKanji.gradeOf["京"], 2)
        XCTAssertEqual(KyoikuKanji.gradeOf["医"], 3)
        XCTAssertEqual(KyoikuKanji.gradeOf["都"], 3)
        XCTAssertEqual(KyoikuKanji.gradeOf["県"], 3)   // 県は旧表から G3 のまま
        // 2020施行で新たに G4 へ追加された都道府県漢字（旧表では教育漢字外だった）。
        XCTAssertEqual(KyoikuKanji.gradeOf["茨"], 4)
        XCTAssertEqual(KyoikuKanji.gradeOf["阪"], 4)
    }

    func testNonKyoikuKanjiIsNil() {
        XCTAssertNil(KyoikuKanji.gradeOf["彼"])   // 中学常用・教育漢字外
        XCTAssertNil(KyoikuKanji.gradeOf["僕"])
    }

    // MARK: - 学年→許可学年（1学年前まで）

    func testMaxGradeIsOneGradeBehind() {
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 1), 0)  // 小1=漢字なし(ひらがな)
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 2), 1)  // 小2→小1まで
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 3), 2)
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 6), 5)
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 7), 6)  // 中1以降は教育漢字すべて
        XCTAssertEqual(KanjiLevelGate.maxGrade(forSchoolGrade: 9), 6)
    }

    // MARK: - 検査本体

    func testOffendingKanjiByGrade() {
        // 学(1)校(1)：小1まで許可なら通る、漢字ゼロ(小1児童)なら両方アウト。
        XCTAssertEqual(KanjiLevelGate.offendingKanji(in: "学校であそぶ", maxGrade: 1), [])
        XCTAssertEqual(KanjiLevelGate.offendingKanji(in: "学校であそぶ", maxGrade: 0), ["学", "校"])
        // 親(2)京(2)都(3)：小2までだと 都(G3) だけが超過。
        XCTAssertEqual(KanjiLevelGate.offendingKanji(in: "親と京都へ", maxGrade: 2), ["都"])
        XCTAssertEqual(KanjiLevelGate.offendingKanji(in: "親と京都へ", maxGrade: 3), [])
    }

    func testNonKyoikuKanjiAlwaysOffends() {
        XCTAssertEqual(KanjiLevelGate.offendingKanji(in: "彼は走る", maxGrade: 6), ["彼"])  // 走(G2)はOK・彼はNG
    }

    func testHiraganaKatakanaAsciiNeverOffend() {
        XCTAssertTrue(KanjiLevelGate.isWithin("いぬが はしる", maxGrade: 0))
        XCTAssertTrue(KanjiLevelGate.isWithin("リンゴを たべる", maxGrade: 0))
        XCTAssertTrue(KanjiLevelGate.isWithin("Go home! 123", maxGrade: 0))
    }

    func testIsWithinMatchesOffending() {
        XCTAssertTrue(KanjiLevelGate.isWithin("学校", maxGrade: 1))
        XCTAssertFalse(KanjiLevelGate.isWithin("学校", maxGrade: 0))
    }
}
