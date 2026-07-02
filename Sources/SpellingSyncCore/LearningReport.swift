import Foundation

/// 学習イベント 1 件（練習・テストの 1 回ぶん）。レポート集計の入力。
/// アプリ側が `SpellingAttempt` 等から正規化テキスト・日付・クリア可否に変換して渡す。
public struct LearningEvent: Equatable, Sendable {
    /// イベント種別。採点対象（テスト）か、採点対象外（練習）かを表す。
    /// テストは `graded`（正解/不正解が確定済みか）を併せ持つ。練習は常に採点しない。
    public enum Kind: Equatable, Sendable {
        case practice
        /// テスト答案。`graded` は自動判定/親採点で正解・不正解が確定しているか
        /// （未確定＝OCRが読めず親レビュー待ちなら false）。
        case test(graded: Bool)
    }

    /// 正規化済みの単語テキスト。
    public let word: String
    public let date: Date
    /// 正解/クリア扱いか（OCR自動正解 or 親承認など、アプリ側の意味論に従う）。
    public let cleared: Bool
    public let kind: Kind

    public init(word: String, date: Date, cleared: Bool, kind: Kind) {
        self.word = word
        self.date = date
        self.cleared = cleared
        self.kind = kind
    }
}

/// 期間内の学習サマリ（親が子の頑張りを見るためのレポート）。
public struct LearningReport: Equatable, Sendable {
    /// 期間内の総イベント数。
    public let totalEvents: Int
    /// 期間内に取り組んだ単語の異なり数。
    public let distinctWords: Int
    /// 期間内に一度でもクリアした単語の異なり数。
    public let learnedWords: Int
    /// 何らかの学習があった日数（カレンダー日単位）。
    public let activeDays: Int
    /// 期間末日から連続して学習している日数（末日に学習が無ければ 0）。
    public let currentStreakDays: Int
    /// 正答率（採点が確定したテストのうちクリアした割合、0...1）。採点確定テストが0件なら0。
    /// 練習（`kind == .practice`）と未採点テスト（`kind == .test(graded: false)`）は分母にも分子にも入らない
    /// （「練習をやるほど正答率が下がる／未採点が不正解扱いされる」誤計測を避けるため）。
    public let accuracy: Double
    /// 採点が確定したテスト件数（`accuracy` の分母）。`AccuracyBand.classify` のサンプル数にも使う。
    public let gradedTestCount: Int

    public init(totalEvents: Int, distinctWords: Int, learnedWords: Int, activeDays: Int, currentStreakDays: Int, accuracy: Double, gradedTestCount: Int) {
        self.totalEvents = totalEvents
        self.distinctWords = distinctWords
        self.learnedWords = learnedWords
        self.activeDays = activeDays
        self.currentStreakDays = currentStreakDays
        self.accuracy = accuracy
        self.gradedTestCount = gradedTestCount
    }

    public static let empty = LearningReport(totalEvents: 0, distinctWords: 0, learnedWords: 0, activeDays: 0, currentStreakDays: 0, accuracy: 0, gradedTestCount: 0)
}

/// 学習レポートの**純粋な集計**ロジック（Phase 2「学習レポート」の中核）。
/// I/O（同期データの取得）はアプリ/サーバ側。ここは決定的に集計するだけでテストできる。
public enum LearningReportBuilder {
    /// 期間 `[from, to]`（両端含む）のイベントから学習サマリを作る。
    /// - currentStreak は `to` の暦日から遡って、学習のあった日が連続している数。
    /// - 日付の境界・連続判定は `calendar` に従う（タイムゾーン注入でテスト可能）。
    public static func build(events: [LearningEvent], from: Date, to: Date, calendar: Calendar) -> LearningReport {
        let inRange = events.filter { $0.date >= from && $0.date <= to }
        guard !inRange.isEmpty else { return .empty }

        let total = inRange.count
        let distinct = Set(inRange.map { $0.word })
        let learned = Set(inRange.filter { $0.cleared }.map { $0.word })
        let activeDaySet = Set(inRange.map { calendar.startOfDay(for: $0.date) })

        // 正答率は「採点が確定したテスト」だけを分母にする。練習と未採点テストは除外。
        let gradedTests = inRange.filter { event in
            if case .test(let graded) = event.kind { return graded }
            return false
        }
        let gradedClearedCount = gradedTests.reduce(into: 0) { $0 += $1.cleared ? 1 : 0 }

        // 末日から遡って連続学習日数を数える。
        // 1日戻すたびに startOfDay で正規化する（DST で深夜が無い日でも前日の暦頭と一致させる）。
        var streak = 0
        var day = calendar.startOfDay(for: to)
        while activeDaySet.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = calendar.startOfDay(for: prev)
        }

        return LearningReport(
            totalEvents: total,
            distinctWords: distinct.count,
            learnedWords: learned.count,
            activeDays: activeDaySet.count,
            currentStreakDays: streak,
            accuracy: gradedTests.isEmpty ? 0 : Double(gradedClearedCount) / Double(gradedTests.count),
            gradedTestCount: gradedTests.count
        )
    }
}
