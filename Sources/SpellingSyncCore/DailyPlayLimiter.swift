import Foundation

/// 「1日に N 回まで」の遊び回数を数えるための純ロジック（無料プランのことばパズル等に使う）。
///
/// 状態は呼び出し側が持つ2値（`lastPlayedDay` = 最後に遊んだ日 / `storedCount` = その日の回数）で表す。
/// 日付が変わっていれば回数は 0 に戻る（カレンダー日でリセット）。`Date` は呼び出し側から渡す
/// （Core は時計を持たない＝テスト容易）。プレミアム/デバッグ解放の判定はアプリ層の責務で、
/// ここには持ち込まない（「無料なら N 回」の数えだけを担う）。
public struct DailyPlayLimiter: Equatable, Sendable {
    /// 1日に許可する回数（無料プラン）。
    public let dailyLimit: Int

    public init(dailyLimit: Int) {
        self.dailyLimit = dailyLimit
    }

    /// 今日すでに遊んだ回数。最後に遊んだ日が今日でなければ 0（日替わりリセット）。
    public func playsToday(lastPlayedDay: Date?, storedCount: Int, today: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastPlayedDay, calendar.isDate(last, inSameDayAs: today) else { return 0 }
        return max(0, storedCount)
    }

    /// 今日あと何回遊べるか（0…dailyLimit）。
    public func remaining(lastPlayedDay: Date?, storedCount: Int, today: Date, calendar: Calendar = .current) -> Int {
        max(0, dailyLimit - playsToday(lastPlayedDay: lastPlayedDay, storedCount: storedCount, today: today, calendar: calendar))
    }

    /// まだ遊べるか。
    public func canPlay(lastPlayedDay: Date?, storedCount: Int, today: Date, calendar: Calendar = .current) -> Bool {
        remaining(lastPlayedDay: lastPlayedDay, storedCount: storedCount, today: today, calendar: calendar) > 0
    }

    /// 1回完了を記録した後の新しい保存値 `(day, count)`。
    /// 日付が変わっていれば 1 から数え直す。呼び出し側はこれを永続化する。
    public func recordingCompletion(lastPlayedDay: Date?, storedCount: Int, today: Date, calendar: Calendar = .current) -> (day: Date, count: Int) {
        let next = playsToday(lastPlayedDay: lastPlayedDay, storedCount: storedCount, today: today, calendar: calendar) + 1
        return (today, next)
    }
}
