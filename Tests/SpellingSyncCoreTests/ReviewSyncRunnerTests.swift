import XCTest
@testable import SpellingSyncCore

/// `ReviewSyncRunner` の同期手順（pull→merge→push）を、フェイクのトランスポート/シンクで
/// `swift test` だけで自動検証する（`WordSyncRunnerTests` の review 版）。
private final class FakeReviewTransport: ReviewSyncTransport, @unchecked Sendable {
    var page: ReviewPullPage
    var pushError: Error?
    /// pull が呼ばれた時点で実行するフック（pull 後にローカルが変わる状況の再現に使う）。
    var onPull: (@Sendable () -> Void)?

    private(set) var pulledSince: Int?
    private(set) var pushCallCount = 0
    private(set) var pushedRows: [ReviewRow] = []

    init(page: ReviewPullPage) { self.page = page }

    func pullAll(table: String, since cursor: Int) async throws -> ReviewPullPage {
        pulledSince = cursor
        onPull?()
        return page
    }

    func push(table: String, rows: [ReviewRow]) async throws {
        pushCallCount += 1
        if let pushError { throw pushError }
        pushedRows = rows
    }
}

private final class FakeReviewSink: ReviewLocalSink, @unchecked Sendable {
    var localReviews: [LocalReview]
    private(set) var planCallCount = 0
    private(set) var appliedLive: [ReviewRecord]?

    init(localReviews: [LocalReview]) { self.localReviews = localReviews }

    func planAndApply(_ makePlan: @Sendable ([LocalReview]) -> ReviewSyncReducer.Plan) async -> ReviewSyncReducer.Plan {
        planCallCount += 1
        let plan = makePlan(localReviews)
        appliedLive = LastWriteWins.live(plan.merged)
        return plan
    }
}

private struct ReviewPushFailed: Error {}

final class ReviewSyncRunnerTests: XCTestCase {
    private let table = "reviews"
    private let household = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let otherHousehold = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private let attempt1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let attempt2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func reviewRow(_ attemptID: UUID, _ decision: String, updatedAt: Date) -> ReviewRow {
        ReviewRow(
            id: ReviewIdentity.reviewID(forAttempt: attemptID),
            householdID: household, profileID: nil, attemptID: attemptID,
            parentDecision: decision, parentExamplePath: nil, reviewedBy: nil, reviewedAt: nil,
            updatedAt: RFC3339.string(from: updatedAt), deletedAt: nil
        )
    }

    private func localReview(_ attemptID: UUID, _ decision: ReviewDecision) -> LocalReview {
        LocalReview(payload: ReviewPayload(attemptID: attemptID, decision: decision), createdAt: t0)
    }

    func testCursorKeyIsPerHousehold() {
        XCTAssertNotEqual(
            ReviewSyncRunner.cursorKey(table: table, householdID: household),
            ReviewSyncRunner.cursorKey(table: table, householdID: otherHousehold)
        )
    }

    func testPullAndMergeAppliesRemoteAndAdvancesCursor() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [reviewRow(attempt1, "approved", updatedAt: at(5))], nextCursor: 42))
        let sink = FakeReviewSink(localReviews: [])
        let outcome = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: ReviewSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(transport.pulledSince, 0)
        XCTAssertEqual(sink.planCallCount, 1, "読取〜反映は 1 回の原子的呼び出し")
        XCTAssertEqual(sink.appliedLive?.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)], "リモート採点が UI に反映される")
        let key = ReviewSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(outcome.state.cursors.pullCursor(for: key), 42)
        XCTAssertTrue(outcome.toPush.isEmpty, "リモートのみは送り返さない")
    }

    func testPullAndMergeReadsLocalAfterPull() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [], nextCursor: 0))
        let sink = FakeReviewSink(localReviews: [])
        let fresh = localReview(attempt1, .needsPractice)
        transport.onPull = { sink.localReviews = [fresh] }
        let outcome = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: ReviewSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(sink.planCallCount, 1)
        XCTAssertEqual(outcome.toPush.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)], "pull 後に読んだローカル採点が送信対象になる")
    }

    func testPushEncodesRowsAndAdvancesHighWater() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [], nextCursor: 0))
        let sink = FakeReviewSink(localReviews: [localReview(attempt1, .approved)])
        let merged = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: ReviewSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(merged.toPush.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)])

        let newState = try await ReviewSyncRunner.push(
            table: table, householdID: household, state: merged.state,
            toPush: merged.toPush, transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 1)
        XCTAssertEqual(transport.pushedRows.map(\.attemptID), [attempt1])
        let key = ReviewSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(newState.cursors.pushedThrough(for: key), at(10))
    }

    func testPushEmptyIsNoOp() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [], nextCursor: 0))
        let state = ReviewSyncState()
        let newState = try await ReviewSyncRunner.push(
            table: table, householdID: household, state: state, toPush: [], transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 0)
        XCTAssertEqual(newState, state)
    }

    func testPushFailureKeepsRecordPushableNextCycle() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [], nextCursor: 0))
        transport.pushError = ReviewPushFailed()
        let sink = FakeReviewSink(localReviews: [localReview(attempt1, .approved)])

        let first = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: ReviewSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(first.toPush.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)], "初回は送信対象に乗る")
        do {
            _ = try await ReviewSyncRunner.push(
                table: table, householdID: household, state: first.state,
                toPush: first.toPush, transport: transport
            )
            XCTFail("push は失敗を伝播すべき")
        } catch is ReviewPushFailed {}

        let second = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: first.state,
            transport: transport, sink: sink, now: at(20)
        )
        XCTAssertEqual(second.toPush.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)], "push 失敗後の次サイクルで再送対象に残る")
    }

    func testSuccessfulPushDoesNotRePushNextCycle() async throws {
        let transport = FakeReviewTransport(page: ReviewPullPage(rows: [], nextCursor: 0))
        let sink = FakeReviewSink(localReviews: [localReview(attempt1, .approved)])

        let first = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: ReviewSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(first.toPush.map(\.id), [ReviewIdentity.reviewID(forAttempt: attempt1)])
        let afterPush = try await ReviewSyncRunner.push(
            table: table, householdID: household, state: first.state,
            toPush: first.toPush, transport: transport
        )

        let second = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: household, state: afterPush,
            transport: transport, sink: sink, now: at(20)
        )
        XCTAssertTrue(second.toPush.isEmpty, "送信成功済みの採点は再送しない")
    }
}
