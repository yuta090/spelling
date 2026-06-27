import XCTest
@testable import SpellingSyncCore

/// reviews/attempts の Sidecar/Reducer 純粋ロジックテスト（本筋B土台3）。
final class ReviewAttemptReducerTests: XCTestCase {
    private let hh = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let other = UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000FF")!
    private let prof = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    private let attempt = UUID(uuidString: "aabbccdd-eeff-0011-2233-445566778899")!
    private func t(_ s: Int) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + Double(s)) }
    private var reviewID: UUID { ReviewIdentity.reviewID(forAttempt: attempt) }

    private func localReview(_ decision: ReviewDecision, created: Int = 0) -> LocalReview {
        LocalReview(payload: ReviewPayload(attemptID: attempt, decision: decision), createdAt: t(created))
    }

    // MARK: - ReviewSidecarStore.project

    func testProjectNewReviewStamps() {
        let store = ReviewSidecarStore()
        let recs = store.project(localReviews: [localReview(.approved, created: 1)], now: t(10), householdID: hh, profileID: prof)
        XCTAssertEqual(recs.count, 1)
        let r = recs[0]
        XCTAssertEqual(r.sync.id, reviewID)
        XCTAssertEqual(r.sync.householdID, hh)
        XCTAssertEqual(r.sync.profileID, prof)
        XCTAssertEqual(r.sync.createdAt, t(1))
        XCTAssertEqual(r.sync.updatedAt, t(10))
        XCTAssertFalse(r.sync.isDeleted)
    }

    func testProjectUnchangedKeepsMetadata() {
        var store = ReviewSidecarStore()
        let first = store.project(localReviews: [localReview(.approved)], now: t(10), householdID: hh, profileID: prof)
        store.ingest(first)
        let again = store.project(localReviews: [localReview(.approved)], now: t(99), householdID: hh, profileID: prof)
        XCTAssertEqual(again[0].sync.updatedAt, t(10), "内容不変なら updatedAt 据え置き")
    }

    func testProjectChangedBumpsAndClearsTombstone() {
        var store = ReviewSidecarStore()
        store.ingest(store.project(localReviews: [localReview(.approved)], now: t(10), householdID: hh, profileID: prof))
        let changed = store.project(localReviews: [localReview(.needsPractice)], now: t(20), householdID: hh, profileID: prof)
        XCTAssertEqual(changed[0].payload.decision, .needsPractice)
        XCTAssertEqual(changed[0].sync.updatedAt, t(20))
        XCTAssertFalse(changed[0].sync.isDeleted)
    }

    func testProjectMissingLocalTombstones() {
        var store = ReviewSidecarStore()
        store.ingest(store.project(localReviews: [localReview(.approved)], now: t(10), householdID: hh, profileID: prof))
        let recs = store.project(localReviews: [], now: t(20), householdID: hh, profileID: prof)
        XCTAssertEqual(recs.count, 1)
        XCTAssertTrue(recs[0].sync.isDeleted)
        XCTAssertEqual(recs[0].sync.deletedAt, t(20))
    }

    func testProjectClockRegressionBumps() {
        var store = ReviewSidecarStore()
        store.ingest(store.project(localReviews: [localReview(.approved)], now: t(100), householdID: hh, profileID: prof))
        let changed = store.project(localReviews: [localReview(.needsPractice)], now: t(50), householdID: hh, profileID: prof)
        XCTAssertEqual(changed[0].sync.updatedAt, t(100).addingTimeInterval(0.001), "クロック逆行でも前版より厳密に後")
    }

    func testProjectNoHouseholdIsEmpty() {
        let store = ReviewSidecarStore()
        XCTAssertEqual(store.project(localReviews: [localReview(.approved)], now: t(10), householdID: nil, profileID: prof).count, 0)
    }

    func testIngestResolvesByLWW() {
        var store = ReviewSidecarStore()
        var older = ReviewIdentity.makeRecord(attemptID: attempt, decision: .approved, householdID: hh, profileID: prof, now: t(10))
        var newer = older
        newer.payload.decision = .needsPractice
        newer.sync.updatedAt = t(20)
        store.ingest([newer, older])   // 逆順でも勝者は newer
        XCTAssertEqual(store.metadata(for: reviewID)?.updatedAt, t(20))
        _ = older
    }

    // MARK: - ReviewSyncReducer.plan

    func testReducerPushesNewLocalReview() {
        let plan = ReviewSyncReducer.plan(localReviews: [localReview(.approved)], remote: [], store: ReviewSidecarStore(),
                                          now: t(10), householdID: hh, profileID: prof, pushedThrough: nil)
        XCTAssertEqual(plan.toPush.count, 1)
        XCTAssertEqual(plan.merged.count, 1)
        XCTAssertEqual(plan.toPush[0].sync.updatedAt, t(10))
    }

    func testReducerSuppressesEchoOfPulledRemote() {
        var store = ReviewSidecarStore()
        // 1回目: push 済みとして ingest。
        let first = ReviewSyncReducer.plan(localReviews: [localReview(.approved)], remote: [], store: store,
                                           now: t(10), householdID: hh, profileID: prof, pushedThrough: nil)
        store.ingest(first.merged)
        // 2回目: 同じものを pull で受け取る → 送り返さない。
        let pulled = first.merged
        let second = ReviewSyncReducer.plan(localReviews: [localReview(.approved)], remote: pulled, store: store,
                                            now: t(20), householdID: hh, profileID: prof, pushedThrough: t(10))
        XCTAssertEqual(second.toPush.count, 0, "取込済みリモートの echo は送らない")
        XCTAssertEqual(second.merged.count, 1)
    }

    func testReducerHighWaterFiltersAlreadyPushed() {
        var store = ReviewSidecarStore()
        store.ingest(store.project(localReviews: [localReview(.approved)], now: t(10), householdID: hh, profileID: prof))
        // 採点し直し → updatedAt=t20。
        let blocked = ReviewSyncReducer.plan(localReviews: [localReview(.needsPractice)], remote: [], store: store,
                                             now: t(20), householdID: hh, profileID: prof, pushedThrough: t(20))
        XCTAssertEqual(blocked.toPush.count, 0, "high-water 以下は送らない（strict >）")
        let allowed = ReviewSyncReducer.plan(localReviews: [localReview(.needsPractice)], remote: [], store: store,
                                             now: t(20), householdID: hh, profileID: prof, pushedThrough: t(10))
        XCTAssertEqual(allowed.toPush.count, 1)
    }

    func testReducerRemoteNewerWinsAndNotPushedBack() {
        var store = ReviewSidecarStore()
        store.ingest(store.project(localReviews: [localReview(.approved)], now: t(10), householdID: hh, profileID: prof))
        var remote = ReviewIdentity.makeRecord(attemptID: attempt, decision: .needsPractice, householdID: hh, profileID: prof, now: t(30))
        remote.sync.updatedAt = t(30)
        let plan = ReviewSyncReducer.plan(localReviews: [localReview(.approved)], remote: [remote], store: store,
                                          now: t(20), householdID: hh, profileID: prof, pushedThrough: t(10))
        XCTAssertEqual(plan.merged.count, 1)
        XCTAssertEqual(plan.merged[0].payload.decision, .needsPractice, "新しいリモートが勝つ")
        XCTAssertEqual(plan.toPush.count, 0, "リモート版を送り返さない")
    }

    // MARK: - AttemptSyncReducer.plan

    private func attemptRec(_ id: String, updated: Int, household: UUID? = nil) -> AttemptSyncRecord {
        let payload = AttemptSyncPayload(sessionID: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!,
                                         expectedWord: "cat", mode: "test", recognizedText: "cot",
                                         autoDecision: "needsReview", submittedAt: t(updated))
        let meta = SyncMetadata(id: UUID(uuidString: id)!, householdID: household ?? hh, profileID: prof,
                                createdAt: t(updated), updatedAt: t(updated))
        return AttemptSyncRecord(sync: meta, payload: payload)
    }

    func testAttemptPushesServerMissingOnly() {
        let a = attemptRec("11111111-0000-0000-0000-000000000001", updated: 5)
        let b = attemptRec("22222222-0000-0000-0000-000000000002", updated: 6)
        // b はサーバに既存 → a だけ送る。
        let plan = AttemptSyncReducer.plan(localAttempts: [a, b], remote: [b], householdID: hh, pushedThrough: nil)
        XCTAssertEqual(plan.toPush.map { $0.id }, [a.id])
        XCTAssertEqual(plan.merged.count, 2)
    }

    func testAttemptHighWaterFilters() {
        let a = attemptRec("11111111-0000-0000-0000-000000000001", updated: 5)
        XCTAssertEqual(AttemptSyncReducer.plan(localAttempts: [a], remote: [], householdID: hh, pushedThrough: t(5)).toPush.count, 0)
        XCTAssertEqual(AttemptSyncReducer.plan(localAttempts: [a], remote: [], householdID: hh, pushedThrough: t(4)).toPush.count, 1)
    }

    func testAttemptScopeExcludesOtherHousehold() {
        let mine = attemptRec("11111111-0000-0000-0000-000000000001", updated: 5)
        let theirs = attemptRec("33333333-0000-0000-0000-000000000003", updated: 5, household: other)
        let plan = AttemptSyncReducer.plan(localAttempts: [mine, theirs], remote: [], householdID: hh, pushedThrough: nil)
        XCTAssertEqual(plan.toPush.map { $0.id }, [mine.id], "別世帯は除外")
    }

    func testAttemptRemoteOnlyNotPushed() {
        let remoteOnly = attemptRec("44444444-0000-0000-0000-000000000004", updated: 7)
        let plan = AttemptSyncReducer.plan(localAttempts: [], remote: [remoteOnly], householdID: hh, pushedThrough: nil)
        XCTAssertEqual(plan.toPush.count, 0)
        XCTAssertEqual(plan.merged.count, 1, "リモートのみでも merged には載る")
    }
}
