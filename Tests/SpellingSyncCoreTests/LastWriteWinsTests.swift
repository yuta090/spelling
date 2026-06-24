import XCTest
@testable import SpellingSyncCore

/// テスト用の最小同期レコード。
private struct StubRecord: SyncableRecord, Equatable {
    var sync: SyncMetadata
    var payload: String
}

/// 固定の基準時刻（テストの決定性のため `Date()` は使わない）。
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRecord(
    id: UUID,
    updatedAt: TimeInterval,
    deleted: Bool = false,
    payload: String
) -> StubRecord {
    StubRecord(
        sync: SyncMetadata(
            id: id,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(updatedAt),
            deletedAt: deleted ? t0.addingTimeInterval(updatedAt) : nil
        ),
        payload: payload
    )
}

final class SyncMetadataTests: XCTestCase {
    func testIsDeletedReflectsTombstone() {
        let live = SyncMetadata(id: UUID(), createdAt: t0, updatedAt: t0)
        let dead = SyncMetadata(id: UUID(), createdAt: t0, updatedAt: t0, deletedAt: t0)
        XCTAssertFalse(live.isDeleted)
        XCTAssertTrue(dead.isDeleted)
    }

    func testIdentifiableIdMatchesSyncId() {
        let id = UUID()
        let record = makeRecord(id: id, updatedAt: 0, payload: "x")
        XCTAssertEqual(record.id, id)
    }

    func testCodableRoundTrip() throws {
        let original = SyncMetadata(
            id: UUID(),
            householdID: UUID(),
            profileID: UUID(),
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(10),
            deletedAt: t0.addingTimeInterval(20)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMetadata.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

final class LastWriteWinsResolveTests: XCTestCase {
    private let id = UUID()

    func testNewerUpdatedAtWins() {
        let older = makeRecord(id: id, updatedAt: 0, payload: "old")
        let newer = makeRecord(id: id, updatedAt: 100, payload: "new")
        XCTAssertEqual(LastWriteWins.resolve(older, newer).payload, "new")
    }

    func testResolveIsSymmetric() {
        let older = makeRecord(id: id, updatedAt: 0, payload: "old")
        let newer = makeRecord(id: id, updatedAt: 100, payload: "new")
        XCTAssertEqual(LastWriteWins.resolve(older, newer), LastWriteWins.resolve(newer, older))
    }

    func testTombstoneWinsOnTimestampTie() {
        // 同時刻なら削除を優先（復活させない）。
        let live = makeRecord(id: id, updatedAt: 50, deleted: false, payload: "live")
        let dead = makeRecord(id: id, updatedAt: 50, deleted: true, payload: "dead")
        XCTAssertTrue(LastWriteWins.resolve(live, dead).sync.isDeleted)
        XCTAssertTrue(LastWriteWins.resolve(dead, live).sync.isDeleted)
    }

    func testNewerLiveBeatsOlderTombstone() {
        // 新しい復活（編集）は古い削除に勝つ。
        let oldDelete = makeRecord(id: id, updatedAt: 10, deleted: true, payload: "dead")
        let newEdit = makeRecord(id: id, updatedAt: 99, deleted: false, payload: "revived")
        XCTAssertEqual(LastWriteWins.resolve(oldDelete, newEdit).payload, "revived")
        XCTAssertFalse(LastWriteWins.resolve(oldDelete, newEdit).sync.isDeleted)
    }

    func testDeterministicTieBreakById() {
        // updatedAt も削除状態も同じなら id.uuidString が大きい方。
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        let a = makeRecord(id: lowID, updatedAt: 50, payload: "a")
        let b = makeRecord(id: highID, updatedAt: 50, payload: "b")
        // resolve は本来同一 id 前提だが、タイブレークの決定性を確認するため id 違いで検証。
        XCTAssertEqual(LastWriteWins.resolve(a, b), LastWriteWins.resolve(b, a))
        XCTAssertEqual(LastWriteWins.resolve(a, b).id, highID)
    }
}

final class LastWriteWinsReconcileTests: XCTestCase {
    func testReconcileMergesDisjointSets() {
        let a = makeRecord(id: UUID(), updatedAt: 0, payload: "a")
        let b = makeRecord(id: UUID(), updatedAt: 0, payload: "b")
        let merged = LastWriteWins.reconcile(local: [a], remote: [b])
        XCTAssertEqual(Set(merged.map(\.id)), Set([a.id, b.id]))
    }

    func testReconcilePicksNewerVersionPerId() {
        let id = UUID()
        let localOld = makeRecord(id: id, updatedAt: 0, payload: "local-old")
        let remoteNew = makeRecord(id: id, updatedAt: 100, payload: "remote-new")
        let merged = LastWriteWins.reconcile(local: [localOld], remote: [remoteNew])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.payload, "remote-new")
    }

    func testReconcileIsOrderIndependent() {
        let id = UUID()
        let v1 = makeRecord(id: id, updatedAt: 0, payload: "v1")
        let v2 = makeRecord(id: id, updatedAt: 100, payload: "v2")
        let ab = LastWriteWins.reconcile(local: [v1], remote: [v2])
        let ba = LastWriteWins.reconcile(local: [v2], remote: [v1])
        XCTAssertEqual(ab, ba)
    }

    func testReconcileKeepsTombstones() {
        let id = UUID()
        let deleted = makeRecord(id: id, updatedAt: 100, deleted: true, payload: "gone")
        let merged = LastWriteWins.reconcile(local: [], remote: [deleted])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged.first?.sync.isDeleted ?? false)
    }

    func testLiveExcludesTombstones() {
        let alive = makeRecord(id: UUID(), updatedAt: 0, payload: "alive")
        let dead = makeRecord(id: UUID(), updatedAt: 0, deleted: true, payload: "dead")
        let live = LastWriteWins.live([alive, dead])
        XCTAssertEqual(live.map(\.payload), ["alive"])
    }
}
