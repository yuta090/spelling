import Foundation

/// コイン経済の**純粋ロジック**（獲得量・連続ログイン・デイリー上限）。
///
/// I/O（永続化・UI 演出）はアプリ側。ここは「いくらもらえるか」「今日もらえるか」の判断だけを
/// 決定的に行い、テストする。設計メモ: 入手は 練習(30/問) ＋ テスト満点(50〜100/日1回) ＋
/// 連続ログイン(20,20,30,30,40,50,70 の7日カード)。消費はキャラ(40〜70)・背景(80〜280)。
/// 単位は「子のテンションが上がる桁感」を狙って一桁大きく取っている（旧 1/10 から ×10）。
public enum CoinRewards {
    /// テスト満点ボーナス。単語数に応じて **50〜100**（少なくても50、多くても100）。
    public static func perfectTestBonus(wordCount: Int) -> Int {
        min(100, max(50, wordCount * 10))
    }

    /// 連続ログインのコイン表（7日カード、8日目以降はループ）。
    public static let loginStreakTable = [20, 20, 30, 30, 40, 50, 70]

    /// ストリーク日数（1始まり）に対するコイン。7日を超えたら表をループ。
    public static func loginCoins(forStreakDay day: Int) -> Int {
        guard day >= 1 else { return 0 }
        return loginStreakTable[(day - 1) % loginStreakTable.count]
    }

    /// デイリーログインの結果（新ストリークと付与コイン）。
    public struct LoginOutcome: Equatable, Sendable {
        public let streak: Int
        public let coins: Int

        public init(streak: Int, coins: Int) {
            self.streak = streak
            self.coins = coins
        }
    }

    /// 今日まだログイン報酬を受けていなければ、新ストリークと付与コインを返す。
    /// - 前回が「昨日」なら連続（streak+1）、それ以外は途切れて 1 に戻す。
    /// - 前回が「今日」なら **nil**（本日分は付与済み）。
    public static func dailyLogin(
        lastLogin: Date?,
        today: Date,
        currentStreak: Int,
        calendar: Calendar
    ) -> LoginOutcome? {
        if let lastLogin, calendar.isDate(lastLogin, inSameDayAs: today) {
            return nil
        }
        let isConsecutive: Bool = {
            guard let lastLogin,
                  let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return false
            }
            return calendar.isDate(lastLogin, inSameDayAs: yesterday)
        }()
        let newStreak = isConsecutive ? currentStreak + 1 : 1
        return LoginOutcome(streak: newStreak, coins: loginCoins(forStreakDay: newStreak))
    }

    /// テスト満点ボーナスを今日まだ受けていないか（同じ日なら不可＝1日1回）。
    public static func canAwardPerfectBonus(lastAward: Date?, today: Date, calendar: Calendar) -> Bool {
        guard let lastAward else { return true }
        return !calendar.isDate(lastAward, inSameDayAs: today)
    }
}
