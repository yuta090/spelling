import Foundation

/// 「前の期間と比べてどうか」を表す向き。UI の矢印・色分けに使う。
public enum TrendDirection: Equatable, Sendable {
    case up
    case down
    case flat
}

/// 期間比較（トレンド）の**純粋な**計算。Date/乱数に依存せず決定的。
/// アプリ側は「今期間」「前期間」の集計値（正答率・利用時間・回数など）を渡すだけで、
/// 向きの判定・表示用の丸めをここに任せる。
public enum Trend {
    /// 現在値と前期間値を比較して向きを判定する。
    /// 差（`current - previous`）の絶対値が `flatTolerance` 以下なら誤差・横ばいとみなし `.flat`。
    /// - Parameters:
    ///   - flatTolerance: 非負を想定。`abs(current - previous) <= flatTolerance` で `.flat`。
    public static func direction(current: Double, previous: Double, flatTolerance: Double) -> TrendDirection {
        let delta = current - previous
        if abs(delta) <= flatTolerance { return .flat }
        return delta > 0 ? .up : .down
    }

    /// 正答率（0...1 の割合）どうしの差を、表示用のパーセントポイント整数に丸めて返す。
    /// 画面には `Int((accuracy * 100).rounded())` で丸めた%を表示する規約（`OverviewAccuracyCard` 等）に
    /// 合わせて、**先にそれぞれを%に丸めてから引き算する**（生の割合差を丸めるのではない）。
    /// こうしないと「今期間85% − 前期間82%」の表示なのに差が+2ではなく+3と出る、といったズレが起きうる。
    public static func accuracyDeltaPoints(current: Double, previous: Double) -> Int {
        let currentPoints = Int((current * 100).rounded())
        let previousPoints = Int((previous * 100).rounded())
        return currentPoints - previousPoints
    }
}
