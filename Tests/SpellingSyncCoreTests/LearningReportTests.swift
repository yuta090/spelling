import XCTest
@testable import SpellingSyncCore

/// 学習レポート集計（親が子の頑張りを見る）のテスト。
final class LearningReportTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 既定は「採点確定テスト」として扱う（既存テスト群はもともと "テストのクリア可否" を検証する意図のため）。
    private func ev(_ word: String, _ date: Date, _ cleared: Bool, kind: LearningEvent.Kind = .test(graded: true)) -> LearningEvent {
        LearningEvent(word: word, date: date, cleared: cleared, kind: kind)
    }

    func testEmptyIsEmptyReport() {
        let r = LearningReportBuilder.build(events: [], from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r, .empty)
    }

    func testCountsDistinctAndLearned() {
        let events = [
            ev("cat", at(2026, 6, 10), true),
            ev("cat", at(2026, 6, 11), false),   // 同じ語の再挑戦
            ev("dog", at(2026, 6, 11), false),   // 取り組んだが未クリア
            ev("sun", at(2026, 6, 12), true),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.totalEvents, 4)
        XCTAssertEqual(r.distinctWords, 3, "cat/dog/sun")
        XCTAssertEqual(r.learnedWords, 2, "cat（1回でもクリア）/ sun")
        XCTAssertEqual(r.activeDays, 3, "6/10,11,12")
        XCTAssertEqual(r.accuracy, 0.5, accuracy: 0.0001, "クリア2 / 総4")
    }

    func testRangeFiltersOutEvents() {
        let events = [
            ev("a", at(2026, 5, 31), true),  // 範囲外（前）
            ev("b", at(2026, 6, 15), true),  // 範囲内
            ev("c", at(2026, 7, 1), true),   // 範囲外（後）
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1, 0), to: at(2026, 6, 30, 23), calendar: cal)
        XCTAssertEqual(r.totalEvents, 1)
        XCTAssertEqual(r.distinctWords, 1)
    }

    func testStreakCountsConsecutiveDaysEndingAtTo() {
        // 6/25,26,27 連続。to=6/27 → streak=3。
        let events = [
            ev("a", at(2026, 6, 25), true),
            ev("a", at(2026, 6, 26), true),
            ev("a", at(2026, 6, 27, 9), true),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 27, 23), calendar: cal)
        XCTAssertEqual(r.currentStreakDays, 3)
    }

    func testStreakBreaksOnGap() {
        // 6/24 と 6/26,27（6/25 が空白）。to=6/27 → 末尾の連続は 6/26,27 の 2。
        let events = [
            ev("a", at(2026, 6, 24), true),
            ev("a", at(2026, 6, 26), true),
            ev("a", at(2026, 6, 27), true),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 27, 23), calendar: cal)
        XCTAssertEqual(r.currentStreakDays, 2)
    }

    func testStreakZeroWhenLastDayInactive() {
        // 学習は 6/25 まで、to=6/27 → 末日 6/27 に学習無し → streak=0。
        let events = [ev("a", at(2026, 6, 25), true)]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 27, 23), calendar: cal)
        XCTAssertEqual(r.currentStreakDays, 0)
        XCTAssertEqual(r.activeDays, 1)
    }

    func testAccuracyZeroWhenNoCleared() {
        let events = [ev("a", at(2026, 6, 10), false), ev("b", at(2026, 6, 10), false)]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.accuracy, 0)
        XCTAssertEqual(r.learnedWords, 0)
    }

    func testStreakAcrossDSTMidnightTransition() {
        // ブラジルは 2018-11-04 の深夜 00:00→01:00 に夏時間入り（11/4 の startOfDay は 01:00）。
        // 11/3(通常)・11/4(DST)・11/5(通常) と連続学習 → 境界をまたいでも streak=3 でなければならない。
        var spa = Calendar(identifier: .gregorian)
        spa.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        func d(_ mo: Int, _ da: Int, _ h: Int) -> Date {
            spa.date(from: DateComponents(year: 2018, month: mo, day: da, hour: h))!
        }
        let events = [ev("a", d(11, 3, 12), true), ev("a", d(11, 4, 12), true), ev("a", d(11, 5, 12), true)]
        let r = LearningReportBuilder.build(events: events, from: d(11, 1, 0), to: d(11, 5, 23), calendar: spa)
        XCTAssertEqual(r.currentStreakDays, 3, "DST境界をまたいでも連続3日")
        XCTAssertEqual(r.activeDays, 3)
    }

    func testRangeEndpointsAreInclusive() {
        let from = at(2026, 6, 1, 0)
        let to = at(2026, 6, 30, 23)
        let r = LearningReportBuilder.build(events: [ev("a", from, true), ev("b", to, false)],
                                            from: from, to: to, calendar: cal)
        XCTAssertEqual(r.totalEvents, 2, "from と to ちょうどのイベントも含む")
    }

    func testTimezoneAwareDayGrouping() {
        // JST 6/27 00:30 と 6/27 23:30 は JST では同じ日（activeDays=1, streak=1）。
        var jst = Calendar(identifier: .gregorian)
        jst.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let d1 = jst.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 0, minute: 30))!
        let d2 = jst.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 23, minute: 30))!
        let to = jst.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 23, minute: 59))!
        let r = LearningReportBuilder.build(events: [ev("a", d1, true), ev("a", d2, true)],
                                            from: jst.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
                                            to: to, calendar: jst)
        XCTAssertEqual(r.activeDays, 1)
        XCTAssertEqual(r.currentStreakDays, 1)
        XCTAssertEqual(r.totalEvents, 2)
    }

    // MARK: - accuracy の分母（採点確定テストのみ。練習・未採点テストを除外）

    func testPracticeEventsDoNotAffectAccuracy() {
        // テスト2件（クリア1・未クリア1）＝正答率50%。練習を何件混ぜても変わらない。
        let events = [
            ev("cat", at(2026, 6, 10), true, kind: .test(graded: true)),
            ev("dog", at(2026, 6, 10), false, kind: .test(graded: true)),
            ev("cat", at(2026, 6, 11), false, kind: .practice),
            ev("dog", at(2026, 6, 11), false, kind: .practice),
            ev("sun", at(2026, 6, 12), false, kind: .practice),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.totalEvents, 5, "練習も『がんばり』の量として全イベント数には入る")
        XCTAssertEqual(r.gradedTestCount, 2, "分母は採点確定テストの2件のみ")
        XCTAssertEqual(r.accuracy, 0.5, accuracy: 0.0001, "練習を混ぜても正答率は変わらない")
    }

    func testUnreviewedTestsAreExcludedFromAccuracyDenominator() {
        // 未採点（needsReview 相当）のテストは cleared=false で渡ってきても、分母・分子どちらにも入らない。
        let events = [
            ev("cat", at(2026, 6, 10), true, kind: .test(graded: true)),
            ev("dog", at(2026, 6, 10), false, kind: .test(graded: false)),
            ev("sun", at(2026, 6, 11), false, kind: .test(graded: false)),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.totalEvents, 3)
        XCTAssertEqual(r.gradedTestCount, 1, "未採点2件は分母から除外")
        XCTAssertEqual(r.accuracy, 1.0, accuracy: 0.0001, "採点確定した1件がクリアなので100%")
    }

    func testAllUnreviewedYieldsAccuracyBandNone() {
        // 採点確定テストが1件も無ければ、AccuracyBand は「データ待ち」= .none にすべき。
        let events = [
            ev("cat", at(2026, 6, 10), false, kind: .test(graded: false)),
            ev("dog", at(2026, 6, 11), false, kind: .test(graded: false)),
            ev("sun", at(2026, 6, 12), false, kind: .practice),
        ]
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.gradedTestCount, 0)
        XCTAssertEqual(AccuracyBand.classify(accuracy: r.accuracy, totalEvents: r.gradedTestCount), .none)
    }

    func testFiveGradedTestsYieldClassifiedBand() {
        // 採点確定テストが5件そろえば AccuracyBand の最低サンプル数を満たし、.none を脱する。
        let events = (0..<5).map { i in
            ev("w\(i)", at(2026, 6, 10), true, kind: .test(graded: true))
        }
        let r = LearningReportBuilder.build(events: events, from: at(2026, 6, 1), to: at(2026, 6, 30), calendar: cal)
        XCTAssertEqual(r.gradedTestCount, 5)
        XCTAssertEqual(AccuracyBand.classify(accuracy: r.accuracy, totalEvents: r.gradedTestCount), .good, "全クリアなので好調")
    }
}
