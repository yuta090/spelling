import Foundation

/// ホーム背景アニメ（手描き procedural シーン）の「動きの計算」純ロジック。
///
/// 方針: View 側は `TimelineView(.animation)` から得た時刻(秒)をここへ渡すだけにし、
/// 動きの値（雲の横ゆれ・星の瞬き）はすべて時刻の決定論関数として計算する。
/// 乱数を描画時に使わず seed ベースにすることで、テスト可能かつ再現可能に保つ。
public enum BackgroundMotion {

    private static let twoPi = 2.0 * Double.pi

    /// seed → `[0, 1)` の決定論的な位相。黄金比でばらつかせ、隣の要素と揃わないようにする。
    /// 負の seed でも必ず `[0, 1)` に正規化する。
    private static func unitPhase(seed: Int) -> Double {
        let p = (Double(seed) * 0.6180339887498949).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    /// 雲などレイヤーの横ゆれオフセット（pt）。`amplitude` を超えない滑らかな往復（sin）。
    /// - Parameters:
    ///   - time: 経過時刻（秒）。`TimelineView` の `date.timeIntervalSinceReferenceDate` を想定。
    ///   - period: 一往復にかける秒数。0 以下なら静止（0 を返す）。
    ///   - amplitude: 片側の最大移動量（pt）。
    ///   - phase: 位相オフセット（0–1、レイヤーごとにずらす）。
    /// - Returns: `[-amplitude, +amplitude]` のオフセット。
    public static func driftOffset(time: Double, period: Double, amplitude: Double, phase: Double = 0) -> Double {
        guard period > 0 else { return 0 }
        return amplitude * sin(twoPi * (time / period + phase))
    }

    /// 星の瞬き明るさ。`seed` ごとに位相をずらし、全部が同時に光らないようにする。
    /// - Parameters:
    ///   - time: 経過時刻（秒）。
    ///   - seed: 要素の識別子（星のインデックスなど）。位相のばらつきに使う。
    ///   - period: 明滅一周の秒数。0 以下なら静止＝常時最大(1)。
    ///   - floor: 最小の明るさ（0–1）。これと 1 の間で明滅する。
    /// - Returns: `[floor, 1]` の明るさ。
    public static func twinkle(time: Double, seed: Int, period: Double = 3.4, floor: Double = 0.45) -> Double {
        guard period > 0 else { return 1 }
        let f = min(max(floor, 0), 1)
        let phase = unitPhase(seed: seed)
        let wave = 0.5 + 0.5 * sin(twoPi * (time / period + phase))
        return f + (1 - f) * wave
    }

    /// 落下する粒子（雪など）の縦位置。0（上）→1（下）を `period` 秒でループする。
    /// `seed` ごとに開始位相をずらし、一斉に落ちないようにする。横揺れは別途 `driftOffset` を使う。
    /// - Parameters:
    ///   - time: 経過時刻（秒）。
    ///   - seed: 粒子の識別子。開始高さのばらつきに使う。
    ///   - period: 上から下まで落ちきる秒数。0 以下なら落下せず、seed 由来の固定位置に留まる。
    /// - Returns: `[0, 1)` の縦位置（フラクション）。
    public static func fallProgress(time: Double, seed: Int, period: Double) -> Double {
        let phase = unitPhase(seed: seed)
        guard period > 0 else { return phase }
        let x = time / period + phase
        return x - floor(x)
    }
}
