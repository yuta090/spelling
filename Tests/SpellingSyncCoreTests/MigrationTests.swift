import XCTest
@testable import SpellingSyncCore

/// 旧アプリが書いていた JSON を再現するためのエンコード用ミラー。
/// 実際のアプリと同じデフォルト JSONEncoder/Decoder（Date は deferredToDate）で往復させる。
private struct LegacyAttemptFixture: Encodable {
    var id: UUID
    var word: String
    var recognizedText: String?
    var decision: String?
    var date: Date?
    var sessionID: UUID?
    var parentReviewDecision: String?
    var parentReviewedAt: Date?
}

private struct LegacySchoolTestFixture: Encodable {
    var id: UUID
    var date: Date?
    var stepID: String?
    var stepTitle: String?
    var score: Int?
    var total: Int?
    var missedWords: String?
    var note: String?
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func decodeAttempt(_ fixture: LegacyAttemptFixture) throws -> AttemptRecord {
    let data = try JSONEncoder().encode(fixture)
    let dto = try JSONDecoder().decode(LegacyAttemptDTO.self, from: data)
    return Migration.migrate(dto)
}

final class AttemptMigrationTests: XCTestCase {
    func testPreservesLegacyIdAndCoreFields() throws {
        let id = UUID()
        let session = UUID()
        let record = try decodeAttempt(LegacyAttemptFixture(
            id: id,
            word: "cat",
            recognizedText: "cat",
            decision: "autoCorrect",
            date: t0,
            sessionID: session,
            parentReviewDecision: "unreviewed",
            parentReviewedAt: nil
        ))
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.sync.id, id)
        XCTAssertEqual(record.word, "cat")
        XCTAssertEqual(record.recognizedText, "cat")
        XCTAssertEqual(record.decision, .autoCorrect)
        XCTAssertEqual(record.sessionID, session)
        XCTAssertEqual(record.sync.createdAt, t0)
        XCTAssertFalse(record.sync.isDeleted)
    }

    func testUpdatedAtIsCreatedAtWhenNotReviewed() throws {
        let record = try decodeAttempt(LegacyAttemptFixture(
            id: UUID(), word: "dog", recognizedText: "dog", decision: "needsReview",
            date: t0, sessionID: UUID(), parentReviewDecision: "unreviewed", parentReviewedAt: nil
        ))
        XCTAssertEqual(record.sync.updatedAt, t0)
    }

    func testUpdatedAtUsesParentReviewTimeWhenReviewed() throws {
        let reviewedAt = t0.addingTimeInterval(3600)
        let record = try decodeAttempt(LegacyAttemptFixture(
            id: UUID(), word: "dog", recognizedText: "dog", decision: "needsReview",
            date: t0, sessionID: UUID(), parentReviewDecision: "approved", parentReviewedAt: reviewedAt
        ))
        XCTAssertEqual(record.parentReviewState, .approved)
        XCTAssertEqual(record.sync.updatedAt, reviewedAt)
    }

    func testRequiresParentReviewMatchesDecision() throws {
        let needs = try decodeAttempt(LegacyAttemptFixture(
            id: UUID(), word: "x", recognizedText: nil, decision: "needsReview",
            date: t0, sessionID: nil, parentReviewDecision: nil, parentReviewedAt: nil
        ))
        let auto = try decodeAttempt(LegacyAttemptFixture(
            id: UUID(), word: "y", recognizedText: nil, decision: "autoCorrect",
            date: t0, sessionID: nil, parentReviewDecision: nil, parentReviewedAt: nil
        ))
        XCTAssertTrue(needs.requiresParentReview)
        XCTAssertFalse(auto.requiresParentReview)
    }

    func testMissingOptionalFieldsGetSafeDefaults() throws {
        // recognizedText / decision / parentReviewDecision 欠落 → 既定値。
        let record = try decodeAttempt(LegacyAttemptFixture(
            id: UUID(), word: "z", recognizedText: nil, decision: nil,
            date: t0, sessionID: nil, parentReviewDecision: nil, parentReviewedAt: nil
        ))
        XCTAssertEqual(record.recognizedText, "")
        XCTAssertEqual(record.decision, .needsReview)            // アプリの既定と一致
        XCTAssertEqual(record.parentReviewState, .unreviewed)
    }

    func testMissingIdGeneratesConsistentIdAndSessionFallback() throws {
        // id / sessionID / date 欠落の最古フォーマット。id は採番され、sessionID は同じ値に揃う。
        let data = Data(#"{"word":"q"}"#.utf8)
        let dto = try JSONDecoder().decode(LegacyAttemptDTO.self, from: data)
        let record = Migration.migrate(dto)
        XCTAssertEqual(record.sessionID, record.sync.id)            // 同一 id（二重採番しない）
        XCTAssertEqual(record.sync.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(record.sync.updatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(record.word, "q")
    }

    func testCanonicalRecordCodableRoundTrip() throws {
        let original = AttemptRecord(
            sync: SyncMetadata(id: UUID(), householdID: UUID(), profileID: UUID(), createdAt: t0, updatedAt: t0),
            word: "cat", recognizedText: "cat", decision: .autoCorrect,
            sessionID: UUID(), parentReviewState: .approved
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AttemptRecord.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

final class SchoolTestMigrationTests: XCTestCase {
    func testMapsLegacyFields() throws {
        let id = UUID()
        let data = try JSONEncoder().encode(LegacySchoolTestFixture(
            id: id, date: t0, stepID: "step-1", stepTitle: "ステップ 1",
            score: 3, total: 4, missedWords: "dog", note: "がんばった"
        ))
        let dto = try JSONDecoder().decode(LegacySchoolTestDTO.self, from: data)
        let record = Migration.migrate(dto)
        XCTAssertEqual(record.sync.id, id)
        XCTAssertEqual(record.sync.createdAt, t0)
        XCTAssertEqual(record.stepID, "step-1")
        XCTAssertEqual(record.stepTitle, "ステップ 1")
        XCTAssertEqual(record.score, 3)
        XCTAssertEqual(record.total, 4)
        XCTAssertEqual(record.missedWords, "dog")
        XCTAssertEqual(record.note, "がんばった")
    }

    func testDefaultsForMissingFields() throws {
        let data = try JSONEncoder().encode(LegacySchoolTestFixture(
            id: UUID(), date: t0, stepID: nil, stepTitle: nil,
            score: nil, total: nil, missedWords: nil, note: nil
        ))
        let dto = try JSONDecoder().decode(LegacySchoolTestDTO.self, from: data)
        let record = Migration.migrate(dto)
        XCTAssertNil(record.stepID)
        XCTAssertEqual(record.stepTitle, "")
        XCTAssertEqual(record.score, 0)
        XCTAssertEqual(record.total, 1)        // アプリは total を最低 1 に丸める
        XCTAssertEqual(record.missedWords, "")
        XCTAssertEqual(record.note, "")
    }

    func testMissingDateFallsBackToEpoch() throws {
        let data = Data(#"{}"#.utf8)
        let dto = try JSONDecoder().decode(LegacySchoolTestDTO.self, from: data)
        let record = Migration.migrate(dto)
        XCTAssertEqual(record.sync.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(record.sync.updatedAt, Date(timeIntervalSince1970: 0))
    }
}
