import XCTest
@testable import SpellingSyncCore

/// 親採点(review)の同期レコード契約・決定的ID・汎用LWW再利用のテスト（本筋B土台）。
final class ReviewSyncTests: XCTestCase {
    private let a1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let a2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let hh = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private func t(_ s: Int) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + Double(s)) }

    // MARK: - 決定的ID

    func testReviewIDIsDeterministicPerAttempt() {
        XCTAssertEqual(ReviewIdentity.reviewID(forAttempt: a1), ReviewIdentity.reviewID(forAttempt: a1))
        XCTAssertNotEqual(ReviewIdentity.reviewID(forAttempt: a1), ReviewIdentity.reviewID(forAttempt: a2))
    }

    func testReviewIDMatchesGoldenLowercaseUUIDv5() {
        // 独立計算した golden 値（Python `uuid.uuid5(namespace, 小文字attempt_id)`）と一致すること。
        // これで「小文字正規形に揃えている」「RFC4122 uuidv5 と互換」の両方を一発で担保する。
        // 文字を含む UUID（a-f）でないと大文字/小文字バグを検出できない。
        let letterAttempt = UUID(uuidString: "aabbccdd-eeff-0011-2233-445566778899")!
        let golden = UUID(uuidString: "0D47FC43-6DBF-5CA8-894A-292E10FEE6DF")!
        XCTAssertEqual(ReviewIdentity.reviewID(forAttempt: letterAttempt), golden,
                       "namespace/小文字化/uuidv5アルゴリズムが Postgres と一致する契約値")
        // バージョン5 nibble。
        let s = golden.uuidString
        XCTAssertEqual(s[s.index(s.startIndex, offsetBy: 14)], "5", "uuidv5 のバージョン nibble は 5")
    }

    func testReviewIDIgnoresInputCasing() {
        // 入力UUIDの大小に関わらず同一ID（小文字正規化しているため）。
        let upper = UUID(uuidString: "AABBCCDD-EEFF-0011-2233-445566778899")!
        let lower = UUID(uuidString: "aabbccdd-eeff-0011-2233-445566778899")!
        XCTAssertEqual(ReviewIdentity.reviewID(forAttempt: upper), ReviewIdentity.reviewID(forAttempt: lower))
    }

    func testMakeRecordUsesDeterministicID() {
        let r = ReviewIdentity.makeRecord(attemptID: a1, decision: .approved, householdID: hh, profileID: nil, now: t(0))
        XCTAssertEqual(r.sync.id, ReviewIdentity.reviewID(forAttempt: a1))
        XCTAssertEqual(r.id, r.sync.id, "Identifiable の id は sync.id に一致")
        XCTAssertEqual(r.payload.attemptID, a1)
        XCTAssertEqual(r.payload.decision, .approved)
        XCTAssertEqual(r.sync.householdID, hh)
    }

    // MARK: - 汎用 LWW でレビューが解決する

    func testNewerReviewWins() {
        let older = ReviewIdentity.makeRecord(attemptID: a1, decision: .needsPractice, householdID: hh, profileID: nil, now: t(0))
        var newer = older
        newer.payload.decision = .approved
        newer.sync.updatedAt = t(10)
        XCTAssertEqual(LastWriteWins.resolve(older, newer).payload.decision, .approved)
        XCTAssertEqual(LastWriteWins.resolve(newer, older).payload.decision, .approved, "対称（順序非依存）")
    }

    func testReconcileDedupesSameAttemptToNewest() {
        // 同一 attempt を2端末が採点 → 同一ID。reconcile で1件（新しい方）に収束。
        let local = ReviewIdentity.makeRecord(attemptID: a1, decision: .needsPractice, householdID: hh, profileID: nil, now: t(0))
        var remote = local
        remote.payload.decision = .approved
        remote.sync.updatedAt = t(5)
        let merged = LastWriteWins.reconcile(local: [local], remote: [remote])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].payload.decision, .approved)
    }

    func testTombstonePriorityOnTie() {
        let live = ReviewIdentity.makeRecord(attemptID: a1, decision: .approved, householdID: hh, profileID: nil, now: t(0))
        var deleted = live
        deleted.sync.deletedAt = t(0)   // updatedAt 同時刻 → 削除優先
        XCTAssertTrue(LastWriteWins.resolve(live, deleted).sync.isDeleted)
        XCTAssertEqual(LastWriteWins.live([deleted]).count, 0)
        XCTAssertEqual(LastWriteWins.live([live]).count, 1)
    }

    func testTwoAttemptsAreSeparateRecords() {
        let r1 = ReviewIdentity.makeRecord(attemptID: a1, decision: .approved, householdID: hh, profileID: nil, now: t(0))
        let r2 = ReviewIdentity.makeRecord(attemptID: a2, decision: .needsPractice, householdID: hh, profileID: nil, now: t(0))
        let merged = LastWriteWins.reconcile(local: [r1, r2], remote: [])
        XCTAssertEqual(merged.count, 2)
    }

    // MARK: - DB 文字列との対応 / Codable

    func testDecisionRawValuesMatchDBCheck() {
        XCTAssertEqual(ReviewDecision.needsPractice.rawValue, "needsPractice")
        XCTAssertEqual(ReviewDecision(rawValue: "approved"), .approved)
        XCTAssertEqual(ReviewDecision(rawValue: "unreviewed"), .unreviewed)
        XCTAssertNil(ReviewDecision(rawValue: "bogus"))
    }

    func testCodableRoundTrip() throws {
        let r = ReviewIdentity.makeRecord(attemptID: a1, decision: .needsPractice, householdID: hh,
                                          profileID: nil, exampleStoragePath: "households/x/p/a.pkdrawing",
                                          reviewedBy: hh, now: t(3))
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(ReviewRecord.self, from: data)
        XCTAssertEqual(back, r)
    }
}
