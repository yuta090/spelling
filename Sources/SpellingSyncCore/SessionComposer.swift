import Foundation

/// セッションの組み立て（複数フォーマットを混ぜて飽きさせない）。
/// 設計: docs/exercise-formats-and-distractors-2026-06-28.md
///
/// **source 非依存**：入力は解決済みの `SentenceItem` 列。静的バンクでも
/// パーソナライズ（キャスト差し込み）由来でも同じく扱える。決定論（seed）。

/// セッションの1ステップ：どの文を・どの形式で出すか。
public struct SessionStep: Equatable, Sendable {
    public var item: SentenceItem
    public var format: ExerciseFormat
    public init(item: SentenceItem, format: ExerciseFormat) {
        self.item = item
        self.format = format
    }
}

public enum SessionComposer {
    /// items × formats を混ぜた決定論セッション列を返す。
    /// ルール：
    /// - **連続して同じ形式を出さない**（formats が2つ以上のとき）。
    /// - item は決定論シャッフル順で巡回（`length` が多ければ繰り返す＝同じ文を別形式で再出題）。
    /// - 形式の妥当性（並べ替え可能か・おとりがあるか等）は**呼び出し側が保証**する前提（v1）。
    public static func compose(items: [SentenceItem],
                               formats: [ExerciseFormat],
                               length: Int,
                               seed: UInt64) -> [SessionStep] {
        guard !items.isEmpty, !formats.isEmpty, length > 0 else { return [] }

        // 重複形式を渡されても「連続同形式なし」を保証するため、出現順で一意化する。
        var seenFormats = Set<ExerciseFormat>()
        let distinctFormats = formats.filter { seenFormats.insert($0).inserted }

        let shuffledItems = SeededShuffle.shuffle(items, seed: seed)
        let shuffledFormats = SeededShuffle.shuffle(distinctFormats, seed: seed &+ 1)

        var steps: [SessionStep] = []
        steps.reserveCapacity(length)
        for i in 0..<length {
            // formats が distinct なので、i%n と (i+1)%n は n>=2 で必ず別 index
            // ＝連続して同じ形式にならない。
            let item = shuffledItems[i % shuffledItems.count]
            let format = shuffledFormats[i % shuffledFormats.count]
            steps.append(SessionStep(item: item, format: format))
        }
        return steps
    }
}
