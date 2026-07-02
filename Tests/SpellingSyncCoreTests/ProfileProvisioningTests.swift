import XCTest
@testable import SpellingSyncCore

/// `ProvisionedProfile.make` が `ChildProfile` ＋世帯から provisioning 値を安定に組むこと。
/// `updatedAt` は生成時刻（安定値）＝毎サイクル now() で送って `profiles` を churn させない保証。
final class ProfileProvisioningTests: XCTestCase {
    private let household = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testMakeUsesLocalIDAndStableCreatedAt() {
        let child = ChildProfile(displayName: "ゆうた", createdAt: t0)
        let p = ProvisionedProfile.make(from: child, householdID: household)

        XCTAssertEqual(p.id, child.id, "ローカル id をそのままサーバ profiles.id に使う（クライアント権威 ID）")
        XCTAssertEqual(p.householdID, household)
        XCTAssertEqual(p.displayName, "ゆうた")
        XCTAssertEqual(p.appLanguage, "japanese")
        XCTAssertEqual(p.updatedAt, t0, "LWW 時刻は生成時刻＝安定（churn 回避）")
    }

    func testMakeIsDeterministicAcrossCalls() {
        // 同じ入力なら毎回同じ値。冪等 upsert（同じ updatedAt）で LWW ガードが再送を無視できる。
        let child = ChildProfile(displayName: "みか", createdAt: t0)
        XCTAssertEqual(
            ProvisionedProfile.make(from: child, householdID: household),
            ProvisionedProfile.make(from: child, householdID: household)
        )
    }
}
