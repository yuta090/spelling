import XCTest
@testable import SpellingSyncCore

final class TapBurstTests: XCTestCase {

    private func magnitude(_ p: TapBurst.Particle) -> Double {
        (p.dx * p.dx + p.dy * p.dy).squareRoot()
    }

    func testCountMatches() {
        XCTAssertEqual(TapBurst.particles(seed: 1, count: 8).count, 8)
        XCTAssertEqual(TapBurst.particles(seed: 1, count: 3).count, 3)
    }

    func testZeroCountIsEmpty() {
        XCTAssertTrue(TapBurst.particles(seed: 1, count: 0).isEmpty)
        XCTAssertTrue(TapBurst.particles(seed: 1, count: -5).isEmpty)
    }

    func testDeterministicForSameSeed() {
        XCTAssertEqual(TapBurst.particles(seed: 7, count: 8), TapBurst.particles(seed: 7, count: 8))
    }

    func testDifferentSeedsDiffer() {
        // 別シードでは少なくともどこか違う（全く同じ配置にならない）。
        XCTAssertNotEqual(TapBurst.particles(seed: 1, count: 8), TapBurst.particles(seed: 2, count: 8))
    }

    func testParticlesTravelOutward() {
        // すべての粒は中心から外へ（距離 > 0）飛ぶ。
        for p in TapBurst.particles(seed: 3, count: 10) {
            XCTAssertGreaterThan(magnitude(p), 0)
        }
    }

    func testReachScalesDistance() {
        let near = TapBurst.particles(seed: 5, count: 6, reach: 1.0)
        let far = TapBurst.particles(seed: 5, count: 6, reach: 2.0)
        // 同シードで reach を2倍にすると飛距離もおよそ2倍（方向は不変）。
        for (n, f) in zip(near, far) {
            XCTAssertEqual(magnitude(f), magnitude(n) * 2, accuracy: 0.001)
        }
    }

    func testRadialSpreadHasUpAndDownAndSides() {
        // 放射状に散る＝上/下/左/右いずれの成分も少なくとも1つは出る。
        let ps = TapBurst.particles(seed: 9, count: 12)
        XCTAssertTrue(ps.contains { $0.dy < 0 }, "上へ飛ぶ粒がある")
        XCTAssertTrue(ps.contains { $0.dy > 0 }, "下へ飛ぶ粒がある")
        XCTAssertTrue(ps.contains { $0.dx < 0 }, "左へ飛ぶ粒がある")
        XCTAssertTrue(ps.contains { $0.dx > 0 }, "右へ飛ぶ粒がある")
    }

    func testSizesAndSymbolsInRange() {
        for p in TapBurst.particles(seed: 11, count: 16) {
            XCTAssertGreaterThanOrEqual(p.size, 10)
            XCTAssertLessThanOrEqual(p.size, 30)
            XCTAssertGreaterThanOrEqual(p.symbol, 0)
            XCTAssertLessThanOrEqual(p.symbol, 2)
            XCTAssertGreaterThanOrEqual(p.delay, 0)
            XCTAssertLessThanOrEqual(p.delay, 0.2)
        }
    }
}
