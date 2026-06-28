import Foundation

/// 保護者「ようす」タブの**純粋集計**ロジック。
/// 利用時間（日別秒バケット）・正答率の調子分類・曜日別取り組み数を、Date/乱数に依存せず決定的に扱う。
/// 暦境界の必要なものは `Calendar` を注入してテスト可能にする。アプリ側は日付→キー変換と I/O のみ担う。

// MARK: - UsageLog（アプリ前面滞在時間の日別バケット）

/// 日キー（"yyyy-MM-dd" などアプリが決める安定文字列）→ 滞在秒。の純粋操作。
public enum UsageLog {
    /// その日に滞在秒を加算する（非正は無視）。
    public static func add(_ log: [String: Int], dayKey: String, seconds: Int) -> [String: Int] {
        guard seconds > 0 else { return log }
        var next = log
        next[dayKey, default: 0] += seconds
        return next
    }

    /// その日の滞在秒（無ければ 0）。
    public static func seconds(_ log: [String: Int], on dayKey: String) -> Int {
        log[dayKey] ?? 0
    }

    /// 指定した日キー群の合計滞在秒。
    public static func total(_ log: [String: Int], days dayKeys: [String]) -> Int {
        dayKeys.reduce(0) { $0 + (log[$1] ?? 0) }
    }

    /// 指定した日キー群の滞在秒を順番どおりに並べた系列（欠けは 0）。スパークライン用。
    public static func series(_ log: [String: Int], days dayKeys: [String]) -> [Int] {
        dayKeys.map { log[$0] ?? 0 }
    }

    /// 指定キーだけを残す（古い日を捨てて保存量を抑える）。
    public static func pruned(_ log: [String: Int], keeping dayKeys: Set<String>) -> [String: Int] {
        log.filter { dayKeys.contains($0.key) }
    }
}

// MARK: - UsageInterval（前面滞在区間の暦日分割）

/// 滞在区間を暦日ごとに割り当てた 1 区切り（その日の暦頭と、その日に属する秒数）。
public struct UsageSegment: Equatable, Sendable {
    public let dayStart: Date
    public let seconds: Int

    public init(dayStart: Date, seconds: Int) {
        self.dayStart = dayStart
        self.seconds = seconds
    }
}

/// 前面滞在区間 `[start, end]` を暦日ごとの秒に分割する純粋ロジック。
/// 日付またぎ（23:50→00:10 など）を当日・翌日へ正しく振り分けるために使う。
public enum UsageInterval {
    /// 区間を暦日境界で分割し、各日の秒数を返す（`end <= start` は空）。
    public static func split(start: Date, end: Date, calendar: Calendar) -> [UsageSegment] {
        guard end > start else { return [] }
        var segments: [UsageSegment] = []
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            // 翌日の暦頭。求められない異常時は end で打ち切る（無限ループ回避）。
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let segmentEnd = min(end, nextDay)
            let seconds = Int(segmentEnd.timeIntervalSince(cursor).rounded())
            if seconds > 0 { segments.append(UsageSegment(dayStart: dayStart, seconds: seconds)) }
            guard segmentEnd > cursor else { break }
            cursor = segmentEnd
        }
        return segments
    }
}

// MARK: - AccuracyBand（直近正答率の「調子」分類）

/// 直近の正答率の調子。UI の色分け（好調=緑／要フォロー=橙／ふつう=中立）と「データ無し」を表す。
public enum AccuracyBand: String, Sendable, Equatable {
    /// まだ十分なデータが無い。
    case none
    /// 要フォロー（しきい値未満）。
    case watch
    /// ふつう。
    case ok
    /// 好調（しきい値以上）。
    case good

    /// 正答率(0...1)と総イベント数から調子を分類する。
    /// サンプルが少ないと調子がブレるため、`minEvents` 未満は `.none`（データ待ち）とする。
    /// - Parameters:
    ///   - minEvents: これ未満は `.none`（既定 5）。
    ///   - watchBelow: この値未満は `.watch`（既定 0.6）。
    ///   - goodAtLeast: この値以上は `.good`（既定 0.8）。
    public static func classify(
        accuracy: Double,
        totalEvents: Int,
        minEvents: Int = 5,
        watchBelow: Double = 0.6,
        goodAtLeast: Double = 0.8
    ) -> AccuracyBand {
        guard totalEvents >= max(minEvents, 1) else { return .none }
        if accuracy >= goodAtLeast { return .good }
        if accuracy < watchBelow { return .watch }
        return .ok
    }
}

// MARK: - DailyActivity（曜日バー用の日別取り組み数）

/// 学習イベントを「指定した各日の暦内に入る件数」へ日別集計する純粋ロジック。
public enum DailyActivity {
    /// `dayStarts`（各日の暦頭）に対応する日別イベント件数を、順番どおりに返す。
    /// イベントは `calendar` の暦日でどの `dayStart` と同じ日かを判定する。
    public static func counts(events: [LearningEvent], dayStarts: [Date], calendar: Calendar) -> [Int] {
        let normalizedStarts = dayStarts.map { calendar.startOfDay(for: $0) }
        var buckets = [Date: Int]()
        for start in normalizedStarts { buckets[start] = 0 }
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            if buckets[day] != nil { buckets[day]! += 1 }
        }
        return normalizedStarts.map { buckets[$0] ?? 0 }
    }
}
