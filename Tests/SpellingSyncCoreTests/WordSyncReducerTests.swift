import XCTest
@testable import SpellingSyncCore

/// `WordWire`（DTO⇄レコード変換・RFC3339日付）と `WordSyncReducer.plan`
/// （pull→merge→push の純粋計画）のテスト。設計: docs/supabase-adapter-design.md §7.5
final class WordWireTests: XCTestCase {
    private let household = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let profile = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let wordID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private func row(updatedAt: String, deletedAt: String? = nil) -> WordRow {
        WordRow(
            id: wordID,
            householdID: household,
            profileID: profile,
            text: "cat",
            promptText: "ねこ",
            source: "parent",
            displayOrder: 3,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    // MARK: - RFC3339

    func testRFC3339RoundTripWholeSeconds() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let s = WordWire.rfc3339(from: d)
        XCTAssertEqual(WordWire.date(fromRFC3339: s)?.timeIntervalSince1970 ?? .nan, d.timeIntervalSince1970, accuracy: 0.0005)
    }

    func testRFC3339RoundTripMillisecondBump() {
        // サイドカーの最小刻み(0.001s)が ms 精度で往復し、元より後を保てることを保証（churn 防止の前提）。
        let floor = Date(timeIntervalSince1970: 1_700_000_000)
        let d = floor.addingTimeInterval(0.001)
        let parsed = WordWire.date(fromRFC3339: WordWire.rfc3339(from: d))
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.timeIntervalSince1970, d.timeIntervalSince1970, accuracy: 0.0005)
        XCTAssertGreaterThan(parsed!, floor, "ms バンプが往復後も floor より後である")
    }

    func testParseZuluWithoutFractional() {
        let d = WordWire.date(fromRFC3339: "2026-06-26T07:00:00Z")
        XCTAssertEqual(d, Date(timeIntervalSince1970: 1_782_457_200))
    }

    func testParseOffsetForm() {
        let z = WordWire.date(fromRFC3339: "2026-06-26T07:00:00+00:00")
        XCTAssertEqual(z, Date(timeIntervalSince1970: 1_782_457_200))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(WordWire.date(fromRFC3339: "not-a-date"))
    }

    // MARK: - record(from:)

    func testRecordMapsFieldsAndDropsStepID() {
        let r = WordWire.record(from: row(updatedAt: "2026-06-26T07:00:00Z"))
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.sync.id, wordID)
        XCTAssertEqual(r?.sync.householdID, household)
        XCTAssertEqual(r?.sync.profileID, profile)
        XCTAssertEqual(r?.sync.updatedAt, Date(timeIntervalSince1970: 1_782_457_200))
        // createdAt はサーバー DTO に無いため updatedAt を流用。
        XCTAssertEqual(r?.sync.createdAt, r?.sync.updatedAt)
        XCTAssertNil(r?.sync.deletedAt)
        XCTAssertEqual(r?.payload.text, "cat")
        XCTAssertEqual(r?.payload.promptText, "ねこ")
        XCTAssertEqual(r?.payload.source, "parent")
        XCTAssertEqual(r?.payload.displayOrder, 3)
        // §7.5: サーバー step_id(UUID) はローカル String に写さない。
        XCTAssertNil(r?.payload.stepID)
    }

    func testRecordParsesTombstone() {
        let r = WordWire.record(from: row(updatedAt: "2026-06-26T07:00:00Z", deletedAt: "2026-06-26T08:00:00Z"))
        XCTAssertEqual(r?.sync.deletedAt, Date(timeIntervalSince1970: 1_782_460_800))
        XCTAssertEqual(r?.sync.isDeleted, true)
    }

    func testRecordReturnsNilOnBadDate() {
        XCTAssertNil(WordWire.record(from: row(updatedAt: "garbage")))
    }

    func testRecordReturnsNilOnUnparsableTombstone() {
        // 解釈不能な deleted_at を黙って nil 化すると削除済み行が復活してしまうため、行ごと落とす。
        XCTAssertNil(WordWire.record(from: row(updatedAt: "2026-06-26T07:00:00Z", deletedAt: "garbage")))
    }

    // MARK: - wire(from:)

    func testWireFormatsAndDropsStepID() {
        let meta = SyncMetadata(
            id: wordID,
            householdID: household,
            profileID: profile,
            createdAt: Date(timeIntervalSince1970: 1_782_457_200),
            updatedAt: Date(timeIntervalSince1970: 1_782_457_200),
            deletedAt: Date(timeIntervalSince1970: 1_782_460_800)
        )
        let payload = WordPayload(text: "cat", promptText: "ねこ", source: "parent", stepID: "child-words", displayOrder: 3)
        let wire = WordWire.wire(from: WordSyncRecord(sync: meta, payload: payload))
        XCTAssertEqual(wire?.id, wordID)
        XCTAssertEqual(wire?.householdID, household)
        XCTAssertEqual(wire?.profileID, profile)
        XCTAssertEqual(wire?.text, "cat")
        XCTAssertEqual(wire?.displayOrder, 3)
        XCTAssertEqual(wire?.updatedAt, "2026-06-26T07:00:00.000Z")
        XCTAssertEqual(wire?.deletedAt, "2026-06-26T08:00:00.000Z")
    }

    func testWireReturnsNilWithoutHousehold() {
        let meta = SyncMetadata(id: wordID, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
        let payload = WordPayload(text: "x", promptText: "", source: "parent", stepID: nil, displayOrder: 0)
        XCTAssertNil(WordWire.wire(from: WordSyncRecord(sync: meta, payload: payload)))
    }
}

final class WordSyncReducerTests: XCTestCase {
    private let household = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let otherHousehold = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private let profile = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000")!
    private let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func payload(_ text: String, order: Int = 0) -> WordPayload {
        WordPayload(text: text, promptText: "", source: "parent", stepID: nil, displayOrder: order)
    }

    private func record(_ id: UUID, _ text: String, updated: TimeInterval, household h: UUID? = nil, deleted: TimeInterval? = nil) -> WordSyncRecord {
        let hh = h ?? household
        let meta = SyncMetadata(
            id: id,
            householdID: hh,
            profileID: profile,
            createdAt: t0,
            updatedAt: at(updated),
            deletedAt: deleted.map(at)
        )
        return WordSyncRecord(sync: meta, payload: payload(text))
    }

    private func storeIngesting(_ records: [WordSyncRecord]) -> WordSidecarStore {
        var s = WordSidecarStore()
        s.ingest(records)
        return s
    }

    func testLocalOnlyNewWordIsMergedAndPushed() {
        let local = [LocalWord(id: id1, payload: payload("cat"), createdAt: t0)]
        let plan = WordSyncReducer.plan(
            localWords: local, remote: [], store: WordSidecarStore(),
            now: at(10), householdID: household, profileID: profile, pushedThrough: nil
        )
        XCTAssertEqual(plan.merged.count, 1)
        XCTAssertEqual(plan.toPush.map(\.id), [id1])
        XCTAssertEqual(plan.toPush.first?.sync.updatedAt, at(10))
    }

    func testRemoteOnlyIsMergedButNotPushed() {
        let remote = [record(id1, "dog", updated: 5)]
        let plan = WordSyncReducer.plan(
            localWords: [], remote: remote, store: WordSidecarStore(),
            now: at(10), householdID: household, profileID: profile, pushedThrough: nil
        )
        XCTAssertEqual(plan.merged.map(\.id), [id1])
        XCTAssertTrue(plan.toPush.isEmpty, "サーバーが既に持つ版は送り返さない")
    }

    func testLocalEditBeatsOlderRemoteAndPushes() {
        let baseline = record(id1, "cat", updated: 1)
        let store = storeIngesting([baseline])
        let local = [LocalWord(id: id1, payload: payload("CATS"), createdAt: t0)] // 内容変化
        let remote = [record(id1, "cat", updated: 1)] // 古い
        let plan = WordSyncReducer.plan(
            localWords: local, remote: remote, store: store,
            now: at(20), householdID: household, profileID: profile, pushedThrough: at(1)
        )
        XCTAssertEqual(plan.merged.first?.payload.text, "CATS")
        XCTAssertEqual(plan.merged.first?.sync.updatedAt, at(20))
        XCTAssertEqual(plan.toPush.map(\.id), [id1])
    }

    func testRemoteNewerWinsAndIsNotPushed() {
        let baseline = record(id1, "cat", updated: 1)
        let store = storeIngesting([baseline])
        let local = [LocalWord(id: id1, payload: payload("cat"), createdAt: t0)] // 変化なし
        let remote = [record(id1, "REMOTE", updated: 30)] // 新しい
        let plan = WordSyncReducer.plan(
            localWords: local, remote: remote, store: store,
            now: at(20), householdID: household, profileID: profile, pushedThrough: at(1)
        )
        XCTAssertEqual(plan.merged.first?.payload.text, "REMOTE")
        XCTAssertTrue(plan.toPush.isEmpty)
    }

    func testHighWaterPreventsRepushOfAlreadyPushed() {
        let baseline = record(id1, "cat", updated: 5)
        let store = storeIngesting([baseline])
        let local = [LocalWord(id: id1, payload: payload("cat"), createdAt: t0)] // 変化なし
        let plan = WordSyncReducer.plan(
            localWords: local, remote: [], store: store,
            now: at(20), householdID: household, profileID: profile, pushedThrough: at(5)
        )
        XCTAssertTrue(plan.toPush.isEmpty, "送信済み high-water 以降に変更が無ければ再送しない")
    }

    func testNilHouseholdYieldsEmptyPlan() {
        let local = [LocalWord(id: id1, payload: payload("cat"), createdAt: t0)]
        let plan = WordSyncReducer.plan(
            localWords: local, remote: [record(id1, "x", updated: 1)], store: WordSidecarStore(),
            now: at(10), householdID: nil, profileID: profile, pushedThrough: nil
        )
        XCTAssertTrue(plan.merged.isEmpty)
        XCTAssertTrue(plan.toPush.isEmpty)
    }

    func testRemoteFromOtherHouseholdIsIgnored() {
        let remote = [record(id2, "stranger", updated: 50, household: otherHousehold)]
        let local = [LocalWord(id: id1, payload: payload("cat"), createdAt: t0)]
        let plan = WordSyncReducer.plan(
            localWords: local, remote: remote, store: WordSidecarStore(),
            now: at(10), householdID: household, profileID: profile, pushedThrough: nil
        )
        XCTAssertEqual(plan.merged.map(\.id), [id1], "別世帯のリモート行は混入しない")
    }

    func testIngestedRemoteIsNotEchoedOnLaterCycle() {
        // 取り込み済みのリモート行を、次サイクル（pull 無し）で送り返さない（high-water を
        // リモートの updatedAt まで進めて新規ローカル語を恒久的に弾く事故を防ぐ）。
        let remoteR = record(id1, "dog", updated: 5)
        let store = storeIngesting([remoteR])                       // 前サイクルで ingest 済み
        let local = [LocalWord(id: id1, payload: payload("dog"), createdAt: t0)] // 内容不変
        let plan = WordSyncReducer.plan(
            localWords: local, remote: [], store: store,            // 今回は pull 無し
            now: at(40), householdID: household, profileID: profile, pushedThrough: nil
        )
        XCTAssertEqual(plan.merged.map(\.id), [id1])
        XCTAssertTrue(plan.toPush.isEmpty, "取り込み済みリモート行は echo しない")
    }

    func testLocalDeletionPushesTombstone() {
        let baseline = record(id1, "cat", updated: 1)
        let store = storeIngesting([baseline])
        // ローカルから消滅 → 墓石化して送信。
        let plan = WordSyncReducer.plan(
            localWords: [], remote: [], store: store,
            now: at(20), householdID: household, profileID: profile, pushedThrough: at(1)
        )
        XCTAssertEqual(plan.toPush.map(\.id), [id1])
        XCTAssertEqual(plan.toPush.first?.sync.isDeleted, true)
        XCTAssertEqual(plan.toPush.first?.sync.deletedAt, at(20))
    }
}
