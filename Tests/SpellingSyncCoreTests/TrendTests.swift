import XCTest
@testable import SpellingSyncCore

/// 「前の期間と比べてどうか」トレンド計算の純粋ロジックのテスト。
final class TrendTests: XCTestCase {

    // MARK: - direction

    func testDirectionUpWhenAboveTolerance() {
        XCTAssertEqual(Trend.direction(current: 10, previous: 5, flatTolerance: 2), .up)
    }

    func testDirectionDownWhenBelowTolerance() {
        XCTAssertEqual(Trend.direction(current: 5, previous: 10, flatTolerance: 2), .down)
    }

    func testDirectionFlatWhenWithinTolerance() {
        XCTAssertEqual(Trend.direction(current: 6, previous: 5, flatTolerance: 2), .flat)
        XCTAssertEqual(Trend.direction(current: 4, previous: 5, flatTolerance: 2), .flat)
        XCTAssertEqual(Trend.direction(current: 5, previous: 5, flatTolerance: 2), .flat)
    }

    func testDirectionFlatAtExactToleranceBoundary() {
        // 差の絶対値がちょうど flatTolerance なら flat（境界は flat 側に含める）。
        XCTAssertEqual(Trend.direction(current: 7, previous: 5, flatTolerance: 2), .flat)
        XCTAssertEqual(Trend.direction(current: 3, previous: 5, flatTolerance: 2), .flat)
    }

    func testDirectionUpJustPastToleranceBoundary() {
        XCTAssertEqual(Trend.direction(current: 7.01, previous: 5, flatTolerance: 2), .up)
    }

    func testDirectionDownJustPastToleranceBoundary() {
        XCTAssertEqual(Trend.direction(current: 2.99, previous: 5, flatTolerance: 2), .down)
    }

    func testDirectionZeroToleranceRequiresExactMatchForFlat() {
        XCTAssertEqual(Trend.direction(current: 5, previous: 5, flatTolerance: 0), .flat)
        XCTAssertEqual(Trend.direction(current: 5.0001, previous: 5, flatTolerance: 0), .up)
        XCTAssertEqual(Trend.direction(current: 4.9999, previous: 5, flatTolerance: 0), .down)
    }

    // MARK: - accuracyDeltaPoints

    func testAccuracyDeltaPointsPositive() {
        // 0.82 -> 82%, 0.75 -> 75% -> +7pt
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 0.82, previous: 0.75), 7)
    }

    func testAccuracyDeltaPointsNegative() {
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 0.70, previous: 0.85), -15)
    }

    func testAccuracyDeltaPointsZeroWhenEqual() {
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 0.5, previous: 0.5), 0)
    }

    func testAccuracyDeltaPointsRoundsEachSideBeforeSubtracting() {
        // current 0.845 -> round(84.5) = 85（Foundation の .rounded() は四捨五入で .5 を切り上げ）
        // previous 0.835 -> round(83.5) = 84
        // 表示は 85% / 84% になるので、差は生の差(0.01*100=1)ではなく表示どおりの 85-84=1 になる。
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 0.845, previous: 0.835), 1)
    }

    func testAccuracyDeltaPointsHandlesZeroAndFullAccuracy() {
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 1.0, previous: 0.0), 100)
        XCTAssertEqual(Trend.accuracyDeltaPoints(current: 0.0, previous: 1.0), -100)
    }
}
