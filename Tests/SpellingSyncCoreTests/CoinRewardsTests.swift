import XCTest
@testable import SpellingSyncCore

/// コイン経済の純粋ロジック（満点ボーナス・連続ログイン・デイリー上限）のテスト。
final class CoinRewardsTests: XCTestCase {
    // 決定的にするため UTC の Gregorian カレンダーを使う。
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - 満点ボーナス（単語数で 5〜10）

    func testPerfectBonusClampsBetween5And10() {
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 1), 5)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 4), 5)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 5), 5)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 7), 7)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 10), 10)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 20), 10)
        XCTAssertEqual(CoinRewards.perfectTestBonus(wordCount: 0), 5)
    }

    // MARK: - 連続ログインのコイン表

    func testLoginCoinsTableAndLoop() {
        // 表: [2,2,3,3,4,5,7]
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 1), 2)
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 2), 2)
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 5), 4)
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 7), 7)
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 8), 2)   // 8日目=1周して2
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 14), 7)
        XCTAssertEqual(CoinRewards.loginCoins(forStreakDay: 0), 0)
    }

    // MARK: - デイリーログイン

    func testFirstLoginGivesStreak1() {
        let out = CoinRewards.dailyLogin(lastLogin: nil, today: day(2026, 6, 27), currentStreak: 0, calendar: cal)
        XCTAssertEqual(out, CoinRewards.LoginOutcome(streak: 1, coins: 2))
    }

    func testConsecutiveDayIncrementsStreak() {
        let out = CoinRewards.dailyLogin(lastLogin: day(2026, 6, 26), today: day(2026, 6, 27), currentStreak: 3, calendar: cal)
        XCTAssertEqual(out, CoinRewards.LoginOutcome(streak: 4, coins: 3))  // 4日目=3
    }

    func testGapResetsStreakToOne() {
        let out = CoinRewards.dailyLogin(lastLogin: day(2026, 6, 24), today: day(2026, 6, 27), currentStreak: 5, calendar: cal)
        XCTAssertEqual(out, CoinRewards.LoginOutcome(streak: 1, coins: 2))
    }

    func testSameDayReturnsNil() {
        let out = CoinRewards.dailyLogin(lastLogin: day(2026, 6, 27), today: day(2026, 6, 27), currentStreak: 4, calendar: cal)
        XCTAssertNil(out, "同じ日は二重に付与しない")
    }

    func testStreakLoopsCoinsAfterSeven() {
        // 7日連続のあと8日目も連続なら streak 8 → 2コイン
        let out = CoinRewards.dailyLogin(lastLogin: day(2026, 6, 26), today: day(2026, 6, 27), currentStreak: 7, calendar: cal)
        XCTAssertEqual(out, CoinRewards.LoginOutcome(streak: 8, coins: 2))
    }

    // MARK: - 満点デイリー上限

    func testCanAwardPerfectBonusOncePerDay() {
        XCTAssertTrue(CoinRewards.canAwardPerfectBonus(lastAward: nil, today: day(2026, 6, 27), calendar: cal))
        XCTAssertFalse(CoinRewards.canAwardPerfectBonus(lastAward: day(2026, 6, 27), today: day(2026, 6, 27), calendar: cal))
        XCTAssertTrue(CoinRewards.canAwardPerfectBonus(lastAward: day(2026, 6, 26), today: day(2026, 6, 27), calendar: cal))
    }
}
