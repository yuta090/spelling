import XCTest
@testable import SpellingSyncCore

/// `AttemptSyncRunner` の同期手順（pull→merge→push）を、フェイクのトランスポート/シンクで
/// `swift test` だけで自動検証する（`WordSyncRunnerTests` の attempt 版）。
/// attempt は append-only なのでサイドカーが無く、再送防止は「pull に含まれる id 除外＋high-water」で担保する。
private final class FakeAttemptTransport: AttemptSyncTransport, @unchecked Sendable {
    var page: AttemptPullPage
    var pushError: Error?
    var onPull: (@Sendable () -> Void)?

    private(set) var pulledSince: Int?
    private(set) var pushCallCount = 0
    private(set) var pushedRows: [AttemptRow] = []

    init(page: AttemptPullPage) { self.page = page }

    func pullAll(table: String, since cursor: Int) async throws -> AttemptPullPage {
        pulledSince = cursor
        onPull?()
        return page
    }

    func push(table: String, rows: [AttemptRow]) async throws {
        pushCallCount += 1
        if let pushError { throw pushError }
        pushedRows = rows
    }
}

private final class FakeAttemptSink: AttemptLocalSink, @unchecked Sendable {
    var localAttempts: [AttemptSyncRecord]
    private(set) var planCallCount = 0
    private(set) var appliedLive: [AttemptSyncRecord]?

    init(localAttempts: [AttemptSyncRecord]) { self.localAttempts = localAttempts }

    func planAndApply(_ makePlan: @Sendable ([AttemptSyncRecord]) -> AttemptSyncReducer.Plan) async -> AttemptSyncReducer.Plan {
        planCallCount += 1
        let plan = makePlan(localAttempts)
        appliedLive = LastWriteWins.live(plan.merged)
        return plan
    }
}

private struct AttemptPushFailed: Error {}

final class AttemptSyncRunnerTests: XCTestCase {
    private let table = "attempts"
    private let household = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let otherHousehold = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private let session = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    private let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func attemptRow(_ id: UUID, updatedAt: Date) -> AttemptRow {
        AttemptRow(
            id: id, householdID: household, profileID: nil, sessionID: session,
            stepID: nil, wordID: nil, expectedWord: "dog", mode: "test",
            recognizedText: "dog", ocrConfidence: nil, autoDecision: "needsReview",
            drawingPath: nil, submittedAt: RFC3339.string(from: updatedAt),
            updatedAt: RFC3339.string(from: updatedAt), deletedAt: nil
        )
    }

    private func localAttempt(_ id: UUID, updatedAt: Date) -> AttemptSyncRecord {
        AttemptSyncRecord(
            sync: SyncMetadata(id: id, householdID: household, profileID: nil, createdAt: updatedAt, updatedAt: updatedAt),
            payload: AttemptSyncPayload(
                sessionID: session, expectedWord: "dog", mode: "test",
                recognizedText: "dog", autoDecision: "needsReview", submittedAt: updatedAt
            )
        )
    }

    func testCursorKeyIsPerHousehold() {
        XCTAssertNotEqual(
            AttemptSyncRunner.cursorKey(table: table, householdID: household),
            AttemptSyncRunner.cursorKey(table: table, householdID: otherHousehold)
        )
    }

    func testPullAndMergeAppliesRemoteAndAdvancesCursor() async throws {
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [attemptRow(id1, updatedAt: at(5))], nextCursor: 42))
        let sink = FakeAttemptSink(localAttempts: [])
        let outcome = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertEqual(transport.pulledSince, 0)
        XCTAssertEqual(sink.planCallCount, 1)
        XCTAssertEqual(sink.appliedLive?.map(\.id), [id1], "リモート attempt が UI に反映される")
        let key = AttemptSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(outcome.state.cursors.pullCursor(for: key), 42)
        XCTAssertTrue(outcome.toPush.isEmpty, "リモートのみは送り返さない")
    }

    func testPullAndMergeReadsLocalAfterPull() async throws {
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [], nextCursor: 0))
        let sink = FakeAttemptSink(localAttempts: [])
        let fresh = localAttempt(id1, updatedAt: at(3))
        transport.onPull = { sink.localAttempts = [fresh] }
        let outcome = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertEqual(sink.planCallCount, 1)
        XCTAssertEqual(outcome.toPush.map(\.id), [id1], "pull 後に読んだローカル attempt が送信対象になる")
    }

    func testPushEncodesRowsAndAdvancesHighWater() async throws {
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [], nextCursor: 0))
        let sink = FakeAttemptSink(localAttempts: [localAttempt(id1, updatedAt: at(10))])
        let merged = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertEqual(merged.toPush.map(\.id), [id1])

        let newState = try await AttemptSyncRunner.push(
            table: table, householdID: household, state: merged.state,
            toPush: merged.toPush, transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 1)
        XCTAssertEqual(transport.pushedRows.map(\.id), [id1])
        let key = AttemptSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(newState.cursors.pushedThrough(for: key), at(10))
    }

    func testPushEmptyIsNoOp() async throws {
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [], nextCursor: 0))
        let state = AttemptSyncState()
        let newState = try await AttemptSyncRunner.push(
            table: table, householdID: household, state: state, toPush: [], transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 0)
        XCTAssertEqual(newState, state)
    }

    func testAlreadyOnServerIsNotRePushed() async throws {
        // ローカルにあるが今回 pull にも含まれる（=サーバ保持済み）attempt は送信対象にしない。
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [attemptRow(id1, updatedAt: at(10))], nextCursor: 7))
        let sink = FakeAttemptSink(localAttempts: [localAttempt(id1, updatedAt: at(10))])
        let outcome = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertTrue(outcome.toPush.isEmpty, "サーバ保持済みの attempt は再送しない（append-only）")
    }

    func testSuccessfulPushDoesNotRePushNextCycleViaHighWater() async throws {
        // サイドカーの無い attempt では high-water が唯一のランナー側再送防止。push 成功で high-water が
        // 前進すれば、次サイクルで pull が空（＝まだサーバから返ってこない）でも再送しないこと。
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [], nextCursor: 0))
        let sink = FakeAttemptSink(localAttempts: [localAttempt(id1, updatedAt: at(10))])

        let first = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertEqual(first.toPush.map(\.id), [id1])
        let afterPush = try await AttemptSyncRunner.push(
            table: table, householdID: household, state: first.state,
            toPush: first.toPush, transport: transport
        )

        // 次サイクル: pull は空のまま（サーバ反映が pull に現れる前）。high-water だけで除外されるべき。
        let second = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: afterPush,
            transport: transport, sink: sink
        )
        XCTAssertTrue(second.toPush.isEmpty, "high-water 未満のローカル attempt は pull が空でも再送しない")
    }

    func testPushFailureKeepsRecordPushableNextCycle() async throws {
        let transport = FakeAttemptTransport(page: AttemptPullPage(rows: [], nextCursor: 0))
        transport.pushError = AttemptPushFailed()
        let sink = FakeAttemptSink(localAttempts: [localAttempt(id1, updatedAt: at(10))])

        let first = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: AttemptSyncState(),
            transport: transport, sink: sink
        )
        XCTAssertEqual(first.toPush.map(\.id), [id1])
        do {
            _ = try await AttemptSyncRunner.push(
                table: table, householdID: household, state: first.state,
                toPush: first.toPush, transport: transport
            )
            XCTFail("push は失敗を伝播すべき")
        } catch is AttemptPushFailed {}

        let second = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: household, state: first.state,
            transport: transport, sink: sink
        )
        XCTAssertEqual(second.toPush.map(\.id), [id1], "push 失敗後の次サイクルで再送対象に残る")
    }
}
