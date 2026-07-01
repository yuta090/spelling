import XCTest
@testable import SpellingSyncCore

/// `WordSyncRunner` の同期手順（pull→merge→push）を、フェイクのトランスポート/シンクで
/// `swift test` だけで自動検証する。アプリ側 I/O 層の手順バグ（世帯ごとカーソル・
/// pull 後にローカル再読込・送れた分だけ high-water 前進）をここで捕まえる。
private final class FakeTransport: WordSyncTransport, @unchecked Sendable {
    var page: WordPullPage
    var pushError: Error?
    /// pull が呼ばれた時点で実行するフック（pull 後にローカルが変わる状況の再現に使う）。
    var onPull: (@Sendable () -> Void)?

    private(set) var pulledSince: Int?
    private(set) var pushCallCount = 0
    private(set) var pushedRows: [WordRow] = []

    init(page: WordPullPage) { self.page = page }

    func pullAll(table: String, since cursor: Int) async throws -> WordPullPage {
        pulledSince = cursor
        onPull?()
        return page
    }

    func push(table: String, rows: [WordRow]) async throws {
        pushCallCount += 1
        if let pushError { throw pushError }
        pushedRows = rows
    }
}

private final class FakeSink: WordLocalSink, @unchecked Sendable {
    var localWords: [LocalWord]
    private(set) var planCallCount = 0
    private(set) var appliedLive: [WordSyncRecord]?

    init(localWords: [LocalWord]) { self.localWords = localWords }

    func planAndApply(_ makePlan: @Sendable ([LocalWord]) -> WordSyncReducer.Plan) async -> WordSyncReducer.Plan {
        planCallCount += 1
        let plan = makePlan(localWords)
        appliedLive = LastWriteWins.live(plan.merged)
        return plan
    }
}

private struct PushFailed: Error {}

final class WordSyncRunnerTests: XCTestCase {
    private let table = "words"
    private let household = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let otherHousehold = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func wordRow(_ id: UUID, _ text: String, updatedAt: Date) -> WordRow {
        WordRow(id: id, householdID: household, profileID: nil, text: text, promptText: "",
                source: "parent", displayOrder: 0, updatedAt: WordWire.rfc3339(from: updatedAt), deletedAt: nil)
    }

    private func localWord(_ id: UUID, _ text: String) -> LocalWord {
        LocalWord(id: id, payload: WordPayload(text: text, promptText: "", source: "parent", stepID: nil, displayOrder: 0), createdAt: t0)
    }

    func testCursorKeyIsPerHousehold() {
        XCTAssertNotEqual(
            WordSyncRunner.cursorKey(table: table, householdID: household),
            WordSyncRunner.cursorKey(table: table, householdID: otherHousehold)
        )
    }

    func testPullAndMergeAppliesRemoteAndAdvancesCursor() async throws {
        let transport = FakeTransport(page: WordPullPage(rows: [wordRow(id1, "dog", updatedAt: at(5))], nextCursor: 42))
        let sink = FakeSink(localWords: [])
        let outcome = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(transport.pulledSince, 0)
        XCTAssertEqual(sink.planCallCount, 1, "読取〜反映は 1 回の原子的呼び出し")
        XCTAssertEqual(sink.appliedLive?.map(\.id), [id1], "リモート行が UI に反映される")
        let key = WordSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(outcome.state.cursors.pullCursor(for: key), 42)
        XCTAssertTrue(outcome.toPush.isEmpty, "リモートのみは送り返さない")
    }

    func testPullAndMergeReadsLocalAfterPull() async throws {
        // pull 後にローカルへ新語が増える状況。merge がその新語を拾えば「pull 後に読んだ」証拠。
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        let sink = FakeSink(localWords: [])
        let fresh = localWord(id1, "fresh")
        transport.onPull = { sink.localWords = [fresh] }
        let outcome = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(sink.planCallCount, 1)
        XCTAssertEqual(outcome.toPush.map(\.id), [id1], "pull 後に読んだローカル新語が送信対象になる")
    }

    func testPushEncodesRowsAndAdvancesHighWater() async throws {
        // ローカル新語 → pullAndMerge で toPush に乗る → push で送信＆high-water 前進。
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        let sink = FakeSink(localWords: [localWord(id1, "cat")])
        let merged = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(merged.toPush.map(\.id), [id1])

        let newState = try await WordSyncRunner.push(
            table: table, householdID: household, state: merged.state,
            toPush: merged.toPush, transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 1)
        XCTAssertEqual(transport.pushedRows.map(\.id), [id1])
        let key = WordSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertEqual(newState.cursors.pushedThrough(for: key), at(10))
    }

    func testPushEmptyIsNoOp() async throws {
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        let state = WordSyncState()
        let newState = try await WordSyncRunner.push(
            table: table, householdID: household, state: state, toPush: [], transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 0)
        XCTAssertEqual(newState, state)
    }

    func testPushFailurePropagatesAndDoesNotAdvanceHighWater() async throws {
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        transport.pushError = PushFailed()
        let sink = FakeSink(localWords: [localWord(id1, "cat")])
        let merged = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        let key = WordSyncRunner.cursorKey(table: table, householdID: household)
        XCTAssertNil(merged.state.cursors.pushedThrough(for: key), "push 前は high-water 未設定")
        do {
            _ = try await WordSyncRunner.push(
                table: table, householdID: household, state: merged.state,
                toPush: merged.toPush, transport: transport
            )
            XCTFail("push は失敗を伝播すべき")
        } catch is PushFailed {
            // 期待通り。high-water は呼び出し側に返らない（前進しない）。
        }
    }

    func testPushFailureKeepsRecordPushableNextCycle() async throws {
        // push が失敗してフェーズ1 state を永続化しても、未送信のローカル変更は
        // 次サイクルで再び toPush に乗ること（サイドカー基準を push 成功後にだけ前進させる保証）。
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        transport.pushError = PushFailed()
        let sink = FakeSink(localWords: [localWord(id1, "cat")])

        let first = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(first.toPush.map(\.id), [id1], "初回は送信対象に乗る")
        do {
            _ = try await WordSyncRunner.push(
                table: table, householdID: household, state: first.state,
                toPush: first.toPush, transport: transport
            )
            XCTFail("push は失敗を伝播すべき")
        } catch is PushFailed {}

        // フェーズ1で確定した state（toPush は基準前進していない）を引き継いで再実行。
        let second = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: first.state,
            transport: transport, sink: sink, now: at(20)
        )
        XCTAssertEqual(second.toPush.map(\.id), [id1], "push 失敗後の次サイクルで再送対象に残る")
    }

    func testSuccessfulPushDoesNotRePushNextCycle() async throws {
        // push 成功後はサイドカー基準が前進し、次サイクルで同じレコードを再送（churn）しないこと。
        let transport = FakeTransport(page: WordPullPage(rows: [], nextCursor: 0))
        let sink = FakeSink(localWords: [localWord(id1, "cat")])

        let first = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: WordSyncState(),
            transport: transport, sink: sink, now: at(10)
        )
        XCTAssertEqual(first.toPush.map(\.id), [id1])
        let afterPush = try await WordSyncRunner.push(
            table: table, householdID: household, state: first.state,
            toPush: first.toPush, transport: transport
        )

        let second = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: household, state: afterPush,
            transport: transport, sink: sink, now: at(20)
        )
        XCTAssertTrue(second.toPush.isEmpty, "送信成功済みのレコードは再送しない")
    }
}
