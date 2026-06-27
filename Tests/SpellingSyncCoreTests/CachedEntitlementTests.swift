import XCTest
@testable import SpellingSyncCore

/// 課金権利オフラインキャッシュの有効判定のテスト。
final class CachedEntitlementTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testNotSubscribedIsNeverActive() {
        let e = CachedEntitlement(isSubscribed: false, expiresAt: at(2999, 1, 1))
        XCTAssertFalse(e.isActive(now: at(2026, 6, 27)))
    }

    func testSubscribedWithoutExpiryIsActive() {
        let e = CachedEntitlement(isSubscribed: true, expiresAt: nil)
        XCTAssertTrue(e.isActive(now: at(2026, 6, 27)))
    }

    func testSubscribedBeforeExpiryIsActive() {
        let e = CachedEntitlement(isSubscribed: true, expiresAt: at(2026, 7, 4))
        XCTAssertTrue(e.isActive(now: at(2026, 6, 27)))
    }

    func testSubscribedAfterExpiryIsInactive() {
        let e = CachedEntitlement(isSubscribed: true, expiresAt: at(2026, 6, 20))
        XCTAssertFalse(e.isActive(now: at(2026, 6, 27)))
    }

    func testExactlyAtExpiryIsInactive() {
        let expiry = at(2026, 6, 27)
        let e = CachedEntitlement(isSubscribed: true, expiresAt: expiry)
        XCTAssertFalse(e.isActive(now: expiry), "失効時刻ちょうどは無効（now < expiresAt のみ有効）")
    }

    func testNoneIsInactive() {
        XCTAssertFalse(CachedEntitlement.none.isActive(now: at(2026, 6, 27)))
    }

    func testCodableRoundTrip() throws {
        let e = CachedEntitlement(isSubscribed: true, expiresAt: at(2026, 7, 4))
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(CachedEntitlement.self, from: data)
        XCTAssertEqual(decoded, e)
    }
}
