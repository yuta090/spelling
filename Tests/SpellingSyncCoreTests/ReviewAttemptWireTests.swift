import XCTest
@testable import SpellingSyncCore

/// reviews/attempts の wire 変換（row⇄record）・壊れ行ドロップ・決定的ID整合の純粋ロジックテスト（本筋B土台）。
final class ReviewAttemptWireTests: XCTestCase {
    private let hh = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let prof = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    private let attempt = UUID(uuidString: "aabbccdd-eeff-0011-2233-445566778899")!
    private let parent = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
    private func t(_ s: Int) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + Double(s)) }

    // MARK: - RFC3339 ヘルパ

    func testRFC3339RoundTrip() {
        let d = t(123)
        let s = RFC3339.string(from: d)
        XCTAssertEqual(RFC3339.date(from: s), d)
    }

    func testRFC3339AcceptsNonFractional() {
        // ミリ秒なし "…Z" も受ける（受信側の保険）。
        XCTAssertNotNil(RFC3339.date(from: "2026-06-28T12:00:00Z"))
        XCTAssertNil(RFC3339.date(from: "not-a-date"))
    }

    // MARK: - ReviewWire

    private func reviewRecord(decision: ReviewDecision = .approved, deletedAt: Date? = nil, reviewedAt: Date? = nil) -> ReviewRecord {
        var r = ReviewIdentity.makeRecord(attemptID: attempt, decision: decision, householdID: hh, profileID: prof,
                                          exampleStoragePath: "households/x/p/a.pkdrawing", reviewedBy: parent,
                                          reviewedAt: reviewedAt, now: t(10))
        r.sync.deletedAt = deletedAt
        return r
    }

    func testReviewRecordToRowToRecordRoundTrip() throws {
        let original = reviewRecord(decision: .needsPractice, reviewedAt: t(20))
        let row = try XCTUnwrap(ReviewWire.wire(from: original))
        XCTAssertEqual(row.parentDecision, "needsPractice")
        XCTAssertEqual(row.attemptID, attempt)
        let back = try XCTUnwrap(ReviewWire.record(from: row))
        XCTAssertEqual(back, original)
    }

    func testReviewRowDroppedOnBrokenUpdatedAt() {
        let row = ReviewRow(id: ReviewIdentity.reviewID(forAttempt: attempt), householdID: hh, profileID: prof,
                            attemptID: attempt, parentDecision: "approved", parentExamplePath: nil, reviewedBy: nil,
                            reviewedAt: nil, updatedAt: "garbage", deletedAt: nil)
        XCTAssertNil(ReviewWire.record(from: row))
    }

    func testReviewRowDroppedOnBrokenDeletedAt() {
        // 解釈不能な deletedAt を黙って nil にすると削除済みが復活するので、行ごと落とす。
        let row = ReviewRow(id: ReviewIdentity.reviewID(forAttempt: attempt), householdID: hh, profileID: prof,
                            attemptID: attempt, parentDecision: "approved", parentExamplePath: nil, reviewedBy: nil,
                            reviewedAt: nil, updatedAt: RFC3339.string(from: t(0)), deletedAt: "nope")
        XCTAssertNil(ReviewWire.record(from: row))
    }

    func testReviewRowDroppedOnUnknownDecision() {
        let row = ReviewRow(id: ReviewIdentity.reviewID(forAttempt: attempt), householdID: hh, profileID: prof,
                            attemptID: attempt, parentDecision: "bogus", parentExamplePath: nil, reviewedBy: nil,
                            reviewedAt: nil, updatedAt: RFC3339.string(from: t(0)), deletedAt: nil)
        XCTAssertNil(ReviewWire.record(from: row))
    }

    func testReviewWireRejectsIDMismatch() {
        // id が uuidv5(attempt_id) と食い違うレコードは送らない（取り違え・unique衝突の防止）。
        var bad = reviewRecord()
        bad.sync.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        XCTAssertNil(ReviewWire.wire(from: bad))
    }

    func testReviewWireRejectsMissingHousehold() {
        var r = reviewRecord()
        r.sync.householdID = nil
        XCTAssertNil(ReviewWire.wire(from: r))
    }

    func testReviewTombstoneRoundTrips() throws {
        let deleted = reviewRecord(deletedAt: t(30))
        let row = try XCTUnwrap(ReviewWire.wire(from: deleted))
        XCTAssertNotNil(row.deletedAt)
        let back = try XCTUnwrap(ReviewWire.record(from: row))
        XCTAssertTrue(back.sync.isDeleted)
    }

    // MARK: - AttemptWire

    private func attemptRecord(deletedAt: Date? = nil, ocr: Double? = 0.87, drawing: String? = "households/x/p/d.png") -> AttemptSyncRecord {
        let payload = AttemptSyncPayload(sessionID: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!,
                                     stepID: nil, wordID: nil, expectedWord: "cat", mode: "test",
                                     recognizedText: "cot", ocrConfidence: ocr, autoDecision: "needsReview",
                                     drawingPath: drawing, submittedAt: t(5))
        let meta = SyncMetadata(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000005")!,
                                householdID: hh, profileID: prof, createdAt: t(5), updatedAt: t(8), deletedAt: deletedAt)
        return AttemptSyncRecord(sync: meta, payload: payload)
    }

    func testAttemptRecordToRowToRecordRoundTrip() throws {
        let original = attemptRecord()
        let row = try XCTUnwrap(AttemptWire.wire(from: original))
        XCTAssertEqual(row.expectedWord, "cat")
        XCTAssertEqual(row.recognizedText, "cot")
        let back = try XCTUnwrap(AttemptWire.record(from: row))
        XCTAssertEqual(back, original)
    }

    func testAttemptRoundTripWithNilOptionals() throws {
        let original = attemptRecord(ocr: nil, drawing: nil)
        let row = try XCTUnwrap(AttemptWire.wire(from: original))
        XCTAssertNil(row.ocrConfidence)
        XCTAssertNil(row.drawingPath)
        let back = try XCTUnwrap(AttemptWire.record(from: row))
        XCTAssertEqual(back, original)
    }

    func testAttemptCreatedAtUsesSubmittedAt() throws {
        let row = try XCTUnwrap(AttemptWire.wire(from: attemptRecord()))
        let back = try XCTUnwrap(AttemptWire.record(from: row))
        XCTAssertEqual(back.sync.createdAt, t(5), "createdAt は submittedAt を採用")
        XCTAssertEqual(back.sync.updatedAt, t(8))
    }

    func testAttemptRowDroppedOnBrokenSubmittedAt() {
        var row = try! XCTUnwrap(AttemptWire.wire(from: attemptRecord()))
        row.submittedAt = "garbage"
        XCTAssertNil(AttemptWire.record(from: row))
    }

    func testAttemptRowDroppedOnBrokenDeletedAt() {
        var row = try! XCTUnwrap(AttemptWire.wire(from: attemptRecord()))
        row.deletedAt = "nope"
        XCTAssertNil(AttemptWire.record(from: row))
    }

    func testAttemptWireRejectsMissingHousehold() {
        var r = attemptRecord()
        r.sync.householdID = nil
        XCTAssertNil(AttemptWire.wire(from: r))
    }

    func testAttemptReusesGenericLWWAndScope() {
        // append-only でも汎用 LWW / SyncScope にそのまま載ることを確認。
        let r = attemptRecord()
        XCTAssertEqual(LastWriteWins.reconcile(local: [r], remote: [r]).count, 1)
        XCTAssertEqual(SyncScope.scoped([r], householdID: hh).count, 1)
        XCTAssertEqual(SyncScope.scoped([r], householdID: UUID()).count, 0, "別世帯は除外")
    }
}
