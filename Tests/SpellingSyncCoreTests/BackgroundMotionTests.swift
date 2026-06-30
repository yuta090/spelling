import XCTest
@testable import SpellingSyncCore

/// ホーム背景アニメの「動きの計算」純ロジックのテスト。
/// 時刻(秒)を入力にした決定論関数なので、ここで境界・周期性・範囲を固定する。
/// View 側は TimelineView から得た時刻をこの関数に渡すだけ（描画はテストしない）。
final class BackgroundMotionTests: XCTestCase {

    private let tol = 1e-9

    // MARK: - driftOffset（雲などの横ゆれ：滑らかな往復）

    func testDriftIsZeroAtPhaseStart() {
        // time=0, phase=0 → sin(0)=0 → オフセット 0。
        XCTAssertEqual(BackgroundMotion.driftOffset(time: 0, period: 40, amplitude: 30), 0, accuracy: tol)
    }

    func testDriftStaysWithinAmplitude() {
        // どの時刻でも ±amplitude を超えない。
        for i in 0..<400 {
            let t = Double(i) * 0.37
            let v = BackgroundMotion.driftOffset(time: t, period: 17, amplitude: 24)
            XCTAssertLessThanOrEqual(abs(v), 24 + tol, "t=\(t) で振幅超過")
        }
    }

    func testDriftIsPeriodic() {
        // f(t) == f(t + period)。
        let a = BackgroundMotion.driftOffset(time: 3.2, period: 12, amplitude: 18)
        let b = BackgroundMotion.driftOffset(time: 3.2 + 12, period: 12, amplitude: 18)
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    func testDriftReachesPositiveAndNegativeExtremes() {
        // quarter period で +amplitude、3/4 period で -amplitude（sin の山と谷）。
        let peak = BackgroundMotion.driftOffset(time: 10, period: 40, amplitude: 30) // sin(π/2)=+1
        let trough = BackgroundMotion.driftOffset(time: 30, period: 40, amplitude: 30) // sin(3π/2)=-1
        XCTAssertEqual(peak, 30, accuracy: 1e-6)
        XCTAssertEqual(trough, -30, accuracy: 1e-6)
    }

    func testDriftNonPositivePeriodIsStatic() {
        // period <= 0 はゼロ除算を避け、動かない(0)。
        XCTAssertEqual(BackgroundMotion.driftOffset(time: 5, period: 0, amplitude: 30), 0, accuracy: tol)
        XCTAssertEqual(BackgroundMotion.driftOffset(time: 5, period: -3, amplitude: 30), 0, accuracy: tol)
    }

    // MARK: - twinkle（星の瞬き：seed ごとに位相がずれる）

    func testTwinkleStaysInFloorToOne() {
        for seed in 0..<30 {
            for i in 0..<60 {
                let t = Double(i) * 0.21
                let v = BackgroundMotion.twinkle(time: t, seed: seed, period: 3.0, floor: 0.4)
                XCTAssertGreaterThanOrEqual(v, 0.4 - tol, "seed=\(seed) t=\(t)")
                XCTAssertLessThanOrEqual(v, 1.0 + tol, "seed=\(seed) t=\(t)")
            }
        }
    }

    func testTwinkleDiffersBySeedAtSameTime() {
        // 同時刻でも seed が違えば明るさが揃わない（全部同時に光らない）。
        let values = (0..<8).map { BackgroundMotion.twinkle(time: 1.0, seed: $0, period: 3.0, floor: 0.4) }
        let distinct = Set(values.map { ($0 * 1000).rounded() })
        XCTAssertGreaterThan(distinct.count, 1, "seed ごとに位相がずれていない")
    }

    func testTwinkleIsPeriodic() {
        let a = BackgroundMotion.twinkle(time: 0.7, seed: 5, period: 3.0, floor: 0.4)
        let b = BackgroundMotion.twinkle(time: 0.7 + 3.0, seed: 5, period: 3.0, floor: 0.4)
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    func testTwinkleNonPositivePeriodIsFullBright() {
        // period <= 0 は静止＝常時最大の明るさ(1)。
        XCTAssertEqual(BackgroundMotion.twinkle(time: 4, seed: 2, period: 0, floor: 0.4), 1, accuracy: tol)
    }

    // MARK: - fallProgress（雪などの落下：0→1 でループ）

    func testFallStaysInUnitInterval() {
        for seed in 0..<20 {
            for i in 0..<200 {
                let t = Double(i) * 0.13
                let v = BackgroundMotion.fallProgress(time: t, seed: seed, period: 7)
                XCTAssertGreaterThanOrEqual(v, 0 - tol, "seed=\(seed) t=\(t)")
                XCTAssertLessThan(v, 1 + tol, "seed=\(seed) t=\(t)")
            }
        }
    }

    func testFallIncreasesWithinPeriod() {
        // 折り返し前は時間とともに下がる（値が増える）。
        let a = BackgroundMotion.fallProgress(time: 0, seed: 3, period: 10)
        let b = BackgroundMotion.fallProgress(time: 0.5, seed: 3, period: 10)
        XCTAssertGreaterThan(b, a)
    }

    func testFallIsPeriodic() {
        let a = BackgroundMotion.fallProgress(time: 2.0, seed: 4, period: 6)
        let b = BackgroundMotion.fallProgress(time: 2.0 + 6, seed: 4, period: 6)
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    func testFallScattersBySeed() {
        // 同時刻でも seed ごとに高さがばらける（一斉に落ちない）。
        let values = (0..<8).map { BackgroundMotion.fallProgress(time: 0, seed: $0, period: 6) }
        let distinct = Set(values.map { ($0 * 1000).rounded() })
        XCTAssertGreaterThan(distinct.count, 1)
    }

    func testFallNegativeSeedStaysInUnitInterval() {
        // 負の seed でも契約 [0,1) を守る（位相正規化）。
        for seed in -10 ... -1 {
            let v = BackgroundMotion.fallProgress(time: 0, seed: seed, period: 6)
            XCTAssertGreaterThanOrEqual(v, 0 - tol, "seed=\(seed)")
            XCTAssertLessThan(v, 1 + tol, "seed=\(seed)")
            let v0 = BackgroundMotion.fallProgress(time: 1, seed: seed, period: 0)
            XCTAssertGreaterThanOrEqual(v0, 0 - tol, "seed=\(seed) period<=0")
            XCTAssertLessThan(v0, 1 + tol, "seed=\(seed) period<=0")
        }
    }

    func testFallNonPositivePeriodIsStaticButScattered() {
        // period <= 0 は落ちない（時間で変化しない）が、seed ごとに位置はばらける。
        let a = BackgroundMotion.fallProgress(time: 1, seed: 5, period: 0)
        let b = BackgroundMotion.fallProgress(time: 9, seed: 5, period: 0)
        XCTAssertEqual(a, b, accuracy: tol)
        XCTAssertGreaterThanOrEqual(a, 0)
        XCTAssertLessThan(a, 1)
    }
}
