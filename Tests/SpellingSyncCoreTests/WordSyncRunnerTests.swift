import XCTest
@testable import SpellingSyncCore

/// `WordSyncRunner` の同期手順（merge→push）を `swift test` だけで自動検証する。
/// `merge` は純関数（pull 済みページ＋最新ローカル＋現状態 → 新 state / 反映 live / 送信対象）なので
/// フェイクなしで直接検証できる。`push` の I/O だけフェイクのトランスポートで包む。
private final class FakeTransport: WordSyncTransport, @unchecked Sendable {
    var page: WordPullPage
    var pushError: Error?

    private(set) var pushCallCount = 0
    private(set) var pushedRows: [WordRow] = []

    init(page: WordPullPage = WordPullPage(rows: [], nextCursor: 0)) { self.page = page }

    func pullAll(table: String, since cursor: Int) async throws -> WordPullPage { page }

    func push(table: String, rows: [WordRow]) async throws {
        pushCallCount += 1
        if let pushError { throw pushError }
        pushedRows = rows
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

    private func page(_ rows: [WordRow], next: Int) -> WordPullPage { WordPullPage(rows: rows, nextCursor: next) }
    private var key: String { WordSyncRunner.cursorKey(table: table, householdID: household) }

    func testCursorKeyIsPerHousehold() {
        XCTAssertNotEqual(
            WordSyncRunner.cursorKey(table: table, householdID: household),
            WordSyncRunner.cursorKey(table: table, householdID: otherHousehold)
        )
    }

    func testMergeAppliesRemoteAndAdvancesCursor() {
        let outcome = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([wordRow(id1, "dog", updatedAt: at(5))], next: 42),
            localWords: [], now: at(10)
        )
        XCTAssertEqual(outcome.live.map(\.id), [id1], "リモート行が反映 live に載る")
        XCTAssertEqual(outcome.state.cursors.pullCursor(for: key), 42)
        XCTAssertTrue(outcome.toPush.isEmpty, "リモートのみは送り返さない")
    }

    func testMergeIncludesLocalWordsAsToPush() {
        // 呼び出し側が pull 後に読んだ最新ローカルを渡すと、その新語が送信対象になる。
        let outcome = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([], next: 0), localWords: [localWord(id1, "fresh")], now: at(10)
        )
        XCTAssertEqual(outcome.toPush.map(\.id), [id1])
        XCTAssertEqual(outcome.live.map(\.id), [id1])
    }

    func testPushEncodesRowsAndAdvancesHighWater() async throws {
        let transport = FakeTransport()
        let merged = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(10)
        )
        XCTAssertEqual(merged.toPush.map(\.id), [id1])

        let newState = try await WordSyncRunner.push(
            table: table, householdID: household, state: merged.state,
            toPush: merged.toPush, transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 1)
        XCTAssertEqual(transport.pushedRows.map(\.id), [id1])
        XCTAssertEqual(newState.cursors.pushedThrough(for: key), at(10))
    }

    func testPushEmptyIsNoOp() async throws {
        let transport = FakeTransport()
        let state = WordSyncState()
        let newState = try await WordSyncRunner.push(
            table: table, householdID: household, state: state, toPush: [], transport: transport
        )
        XCTAssertEqual(transport.pushCallCount, 0)
        XCTAssertEqual(newState, state)
    }

    func testPushFailurePropagatesAndDoesNotAdvanceHighWater() async throws {
        let transport = FakeTransport()
        transport.pushError = PushFailed()
        let merged = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(10)
        )
        XCTAssertNil(merged.state.cursors.pushedThrough(for: key), "push 前は high-water 未設定")
        do {
            _ = try await WordSyncRunner.push(
                table: table, householdID: household, state: merged.state,
                toPush: merged.toPush, transport: transport
            )
            XCTFail("push は失敗を伝播すべき")
        } catch is PushFailed {
            // 期待通り。high-water は前進しない。
        }
    }

    func testPushFailureKeepsRecordPushableNextCycle() async throws {
        // push が失敗してフェーズ1 state を永続化しても、未送信のローカル変更は
        // 次サイクルで再び toPush に乗ること（サイドカー基準を push 成功後にだけ前進させる保証）。
        let transport = FakeTransport()
        transport.pushError = PushFailed()

        let first = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(10)
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
        let second = WordSyncRunner.merge(
            table: table, householdID: household, state: first.state,
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(20)
        )
        XCTAssertEqual(second.toPush.map(\.id), [id1], "push 失敗後の次サイクルで再送対象に残る")
    }

    func testSuccessfulPushDoesNotRePushNextCycle() async throws {
        // push 成功後はサイドカー基準が前進し、次サイクルで同じレコードを再送（churn）しないこと。
        let transport = FakeTransport()

        let first = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(10)
        )
        XCTAssertEqual(first.toPush.map(\.id), [id1])
        let afterPush = try await WordSyncRunner.push(
            table: table, householdID: household, state: first.state,
            toPush: first.toPush, transport: transport
        )

        let second = WordSyncRunner.merge(
            table: table, householdID: household, state: afterPush,
            page: page([], next: 0), localWords: [localWord(id1, "cat")], now: at(20)
        )
        XCTAssertTrue(second.toPush.isEmpty, "送信成功済みのレコードは再送しない")
    }

    /// 別プロファイルの行でカーソルが世帯最大まで前進しても、後から来る自プロファイルの行を取りこぼさない。
    /// （サーバ採番 `sync_version` は世帯共通ストリーム。`pull since cursor` は全プロファイル行を返し、
    ///  呼び出し側がスコープするので、自プロファイルは高いカーソルからでも新しい自行だけを正しく拾う。）
    func testCursorAdvancePastOtherRowsStillPullsOwnLaterRows() {
        // 1) 別プロファイル相当の行（id2）だけを含むページでカーソルを 100 まで前進。
        let s1 = WordSyncRunner.merge(
            table: table, householdID: household, state: WordSyncState(),
            page: page([wordRow(id2, "sibling", updatedAt: at(5))], next: 100),
            localWords: [], now: at(10)
        )
        XCTAssertEqual(s1.state.cursors.pullCursor(for: key), 100)

        // 2) その後、自プロファイルの行（id1）が sync_version 150 で届く。高いカーソルからでも拾える。
        let s2 = WordSyncRunner.merge(
            table: table, householdID: household, state: s1.state,
            page: page([wordRow(id1, "mine", updatedAt: at(20))], next: 150),
            localWords: [], now: at(25)
        )
        XCTAssertTrue(s2.live.contains { $0.id == id1 }, "後から来た自プロファイル行を反映する")
        XCTAssertEqual(s2.state.cursors.pullCursor(for: key), 150)
    }
}
