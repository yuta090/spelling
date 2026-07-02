import Foundation

/// 「よくまちがえる単語」1件ぶん（親が子の苦手を単語粒度で見るためのカード用）。
public struct StrugglingWord: Equatable, Sendable {
    /// 正規化済みの単語テキスト。
    public let word: String
    /// 期間内のまちがい回数（採点確定テストで不正解だった回数）。
    public let missCount: Int
    /// 期間内で最後にまちがえた日時。
    public let lastMissDate: Date
    /// 最後にまちがえた日時より後に、同じ単語で採点確定テストのクリアがあるか（「その後できた」バッジ用）。
    public let clearedAfterLastMiss: Bool

    public init(word: String, missCount: Int, lastMissDate: Date, clearedAfterLastMiss: Bool) {
        self.word = word
        self.missCount = missCount
        self.lastMissDate = lastMissDate
        self.clearedAfterLastMiss = clearedAfterLastMiss
    }
}

/// 「よくまちがえる単語」の**純粋な集計**ロジック。
/// 「まちがい」＝採点が確定したテスト（`kind == .test(graded: true)`）で `cleared == false` のイベント。
/// 練習（`.practice`）と未採点テスト（`.test(graded: false)`）はまちがいとして数えない
/// （`LearningReportBuilder.accuracy` と同じ「採点確定のみを事実として扱う」方針に揃える）。
public enum StrugglingWordsBuilder {
    /// 期間 `[from, to]`（両端含む）のイベントから、単語ごとのまちがい集計を上位 `limit` 件つくる。
    /// 並び順: `missCount` 降順 → 同数なら `lastMissDate` が新しい順 → それも同じなら `word` 昇順（起動ごとに順序が揺れないための完全順序）。
    /// `missCount == 0` の語は含めない。
    /// - `clearedAfterLastMiss` は期間内のイベントのみで判定する（期間外の後日クリアは見ない）。
    public static func build(events: [LearningEvent], from: Date, to: Date, limit: Int = 5, calendar: Calendar) -> [StrugglingWord] {
        let inRange = events.filter { $0.date >= from && $0.date <= to }
        guard !inRange.isEmpty else { return [] }

        func isGradedTest(_ event: LearningEvent) -> Bool {
            if case .test(let graded) = event.kind { return graded }
            return false
        }

        var missesByWord: [String: [Date]] = [:]
        var gradedClearsByWord: [String: [Date]] = [:]

        for event in inRange where isGradedTest(event) {
            if event.cleared {
                gradedClearsByWord[event.word, default: []].append(event.date)
            } else {
                missesByWord[event.word, default: []].append(event.date)
            }
        }

        let results: [StrugglingWord] = missesByWord.compactMap { word, missDates in
            guard let lastMiss = missDates.max() else { return nil }
            let clearedAfter = (gradedClearsByWord[word] ?? []).contains { $0 > lastMiss }
            return StrugglingWord(word: word, missCount: missDates.count, lastMissDate: lastMiss, clearedAfterLastMiss: clearedAfter)
        }

        let sorted = results.sorted { lhs, rhs in
            if lhs.missCount != rhs.missCount { return lhs.missCount > rhs.missCount }
            if lhs.lastMissDate != rhs.lastMissDate { return lhs.lastMissDate > rhs.lastMissDate }
            return lhs.word < rhs.word
        }

        return Array(sorted.prefix(limit))
    }
}
