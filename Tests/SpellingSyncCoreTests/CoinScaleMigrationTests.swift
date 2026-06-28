import XCTest
@testable import SpellingSyncCore

/// コイン単位 ×10 移行の純粋ロジック（冪等・クラッシュ安全な残高解決）のテスト。
final class CoinScaleMigrationTests: XCTestCase {
    // 旧残高があり v2 未保存 → ×10 して移行、保存が必要。
    func testMigratesLegacyBalanceByFactor() {
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: nil, legacy: 20), 200)
        XCTAssertTrue(CoinScaleMigration.needsPersist(storedV2: nil))
    }

    // v2 保存済み → そのまま使う。旧残高は無視し、再倍化しない。
    func testUsesV2WhenPresentAndDoesNotRescale() {
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: 200, legacy: 20), 200)
        XCTAssertFalse(CoinScaleMigration.needsPersist(storedV2: 200))
    }

    // クラッシュ安全性: 旧キーは不変なので、移行を何度繰り返しても結果は同じ（×100にならない）。
    func testReMigrationIsIdempotent() {
        let once = CoinScaleMigration.resolveBalance(storedV2: nil, legacy: 20)
        // v2 保存前に再起動 → まだ v2 は nil、legacy も不変 → 同じ 200 を再計算。
        let twice = CoinScaleMigration.resolveBalance(storedV2: nil, legacy: 20)
        XCTAssertEqual(once, 200)
        XCTAssertEqual(twice, 200)
    }

    // 新規ユーザー（旧残高なし）→ 0。
    func testFreshInstallResolvesToZero() {
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: nil, legacy: nil), 0)
    }

    // 0 残高 → 0（×10でも0）。
    func testZeroLegacyStaysZero() {
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: nil, legacy: 0), 0)
    }

    // 破損などで負値が来ても 0 に補正する（v2 側・legacy 側とも）。
    func testNegativeValuesAreClampedToZero() {
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: nil, legacy: -5), 0)
        XCTAssertEqual(CoinScaleMigration.resolveBalance(storedV2: -5, legacy: 20), 0)
    }
}
