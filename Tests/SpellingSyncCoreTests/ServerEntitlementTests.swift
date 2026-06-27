import XCTest
@testable import SpellingSyncCore

/// サーバ権利の有効判定（Phase 2 サーバゲートの土台）のテスト。
final class ServerEntitlementTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func ent(_ status: EntitlementStatus, expires: Date? = nil, grace: Date? = nil) -> ServerEntitlement {
        ServerEntitlement(productID: "p", status: status, expiresAt: expires, graceExpiresAt: grace)
    }

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - 無効系ステータス

    func testInactiveStatusesAreNeverActive() {
        XCTAssertFalse(ent(.none, expires: at(2999, 1, 1)).isActive(now: now))
        XCTAssertFalse(ent(.expired, expires: at(2999, 1, 1)).isActive(now: now))
        XCTAssertFalse(ent(.revoked, expires: at(2999, 1, 1)).isActive(now: now))
    }

    // MARK: - active / trial

    func testActiveBeforeExpiryIsActive() {
        XCTAssertTrue(ent(.active, expires: at(2026, 7, 4)).isActive(now: at(2026, 6, 27)))
        XCTAssertTrue(ent(.trial, expires: at(2026, 7, 4)).isActive(now: at(2026, 6, 27)))
    }

    func testActiveAfterExpiryIsInactive() {
        XCTAssertFalse(ent(.active, expires: at(2026, 6, 20)).isActive(now: at(2026, 6, 27)))
    }

    func testActiveExactlyAtExpiryIsInactive() {
        let e = at(2026, 6, 27)
        XCTAssertFalse(ent(.active, expires: e).isActive(now: e), "失効時刻ちょうどは無効")
    }

    func testActiveWithoutExpiryIsActive() {
        XCTAssertTrue(ent(.active, expires: nil).isActive(now: now))
    }

    func testTrialWithoutExpiryIsInactive() {
        // トライアルは必ず期限がある前提。期限不明は安全側で無効。
        XCTAssertFalse(ent(.trial, expires: nil).isActive(now: now))
    }

    // MARK: - grace（猶予）

    func testGraceUsesGraceDeadlineEvenWhenExpiryPassed() {
        // 通常期限は過去でも、猶予期限が未来なら有効（grace の意味）。
        let e = ent(.grace, expires: at(2026, 6, 20), grace: at(2026, 7, 4))
        XCTAssertTrue(e.isActive(now: at(2026, 6, 27)))
    }

    func testGraceAfterGraceDeadlineIsInactive() {
        let e = ent(.grace, expires: at(2026, 6, 1), grace: at(2026, 6, 20))
        XCTAssertFalse(e.isActive(now: at(2026, 6, 27)))
    }

    func testGraceFallsBackToExpiryWhenNoGraceDeadline() {
        XCTAssertTrue(ent(.grace, expires: at(2026, 7, 4), grace: nil).isActive(now: at(2026, 6, 27)))
        XCTAssertFalse(ent(.grace, expires: at(2026, 6, 20), grace: nil).isActive(now: at(2026, 6, 27)))
    }

    func testGraceWithNoDeadlinesIsInactive() {
        XCTAssertFalse(ent(.grace, expires: nil, grace: nil).isActive(now: now), "猶予期限不明は安全側で無効")
    }

    // MARK: - 世帯の実効権利

    func testHouseholdEmptyIsNotEntitled() {
        XCTAssertFalse(HouseholdEntitlement.isEntitled([], now: now))
    }

    func testHouseholdAllInactiveIsNotEntitled() {
        let list = [ent(.expired, expires: at(2026, 6, 1)), ent(.revoked)]
        XCTAssertFalse(HouseholdEntitlement.isEntitled(list, now: at(2026, 6, 27)))
    }

    func testHouseholdAnyActiveIsEntitled() {
        // 片方失効、片方（別の親/プロダクト）有効 → 世帯は有効。
        let list = [ent(.expired, expires: at(2026, 6, 1)), ent(.active, expires: at(2026, 7, 4))]
        XCTAssertTrue(HouseholdEntitlement.isEntitled(list, now: at(2026, 6, 27)))
    }

    // MARK: - DB 文字列との対応

    func testStatusRawValuesMatchDBCheck() {
        XCTAssertEqual(EntitlementStatus(rawValue: "grace"), .grace)
        XCTAssertEqual(EntitlementStatus(rawValue: "active"), .active)
        XCTAssertEqual(EntitlementStatus.revoked.rawValue, "revoked")
        XCTAssertNil(EntitlementStatus(rawValue: "unknown"))
    }
}
