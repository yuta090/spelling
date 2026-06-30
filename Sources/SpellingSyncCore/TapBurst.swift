import Foundation

/// タップした瞬間に「星がパッと飛び出す」演出のパーティクル配置を計算する純ロジック。
///
/// 方針: 中心から放射状に散る星/キラキラの飛び先（dx, dy）・大きさ・遅延・回転・記号種別を、
/// seed の決定論関数として返す。乱数を描画時に使わず seed ベースにすることで、テスト可能かつ
/// 再現可能に保つ（[[background-motion]] と同じ思想）。アニメ進行や reduceMotion 判定は View 側。
public enum TapBurst {

    private static let twoPi = 2.0 * Double.pi

    /// 飛び出す一粒。`dx`/`dy` は中心からの最終移動量（pt、dy は負で上）。
    public struct Particle: Equatable, Sendable {
        public let dx: Double
        public let dy: Double
        /// 記号の大きさ（pt）。
        public let size: Double
        /// 出現の遅延（秒）。少しずらして弾けるように見せる。
        public let delay: Double
        /// 終端での回転角（度）。
        public let rotation: Double
        /// 記号の種別インデックス（0..2）。View 側で star.fill / sparkle / sparkles 等に対応づける。
        public let symbol: Int

        public init(dx: Double, dy: Double, size: Double, delay: Double, rotation: Double, symbol: Int) {
            self.dx = dx
            self.dy = dy
            self.size = size
            self.delay = delay
            self.rotation = rotation
            self.symbol = symbol
        }
    }

    /// seed → `[0, 1)` の決定論的な位相。黄金比でばらつかせ、隣同士が揃わないようにする。
    private static func unitPhase(seed: Int) -> Double {
        let p = (Double(seed) * 0.6180339887498949).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    /// タップ演出の星/キラキラを返す。
    /// - Parameters:
    ///   - seed: タップごとに変える識別子（配置をばらけさせる）。
    ///   - count: 飛ばす粒の数。0 以下なら空配列。
    ///   - reach: 飛距離の倍率（主要CTAは大きく、選択肢など軽い所は小さく）。
    /// - Returns: 放射状に散る粒の配列。
    public static func particles(seed: Int, count: Int = 8, reach: Double = 1.0) -> [Particle] {
        guard count > 0 else { return [] }
        var result: [Particle] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            // 方向: 円周上に均等配置＋粒ごとの小さなジッタで自然に散らす。
            let jitter = (unitPhase(seed: seed &* 131 &+ i) - 0.5) * 0.5
            let angle = (Double(i) + 0.5) / Double(count) * twoPi + jitter
            // 飛距離・大きさ・回転は別位相で決定。
            let pd = unitPhase(seed: seed &* 17 &+ i &* 7)
            let ps = unitPhase(seed: seed &* 53 &+ i &* 3)
            let distance = (70 + pd * 40) * reach          // 70..110 を reach 倍
            let size = 14 + ps * 10                          // 14..24
            let rotation = (ps - 0.5) * 60                   // ±30
            let delay = Double(i % 4) * 0.02                 // 0..0.06
            result.append(Particle(
                dx: cos(angle) * distance,
                dy: sin(angle) * distance,
                size: size,
                delay: delay,
                rotation: rotation,
                symbol: i % 3
            ))
        }
        return result
    }
}
