import XCTest
@testable import SpellingSyncCore

/// 固定の基準時刻（決定性のため `Date()` は使わない）。
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ dt: TimeInterval) -> Date { t0.addingTimeInterval(dt) }

private let household = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let profile = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

private func payload(_ text: String, prompt: String = "", order: Int = 0) -> WordPayload {
    WordPayload(text: text, promptText: prompt, source: "parent", stepID: nil, displayOrder: order)
}

private func local(_ id: UUID, _ text: String, prompt: String = "", order: Int = 0, createdAt: Date = t0) -> LocalWord {
    LocalWord(id: id, payload: payload(text, prompt: prompt, order: order), createdAt: createdAt)
}

// MARK: - WordSyncRecord

final class WordSyncRecordTests: XCTestCase {
    func testIdentifiableIdMatchesSyncId() {
        let id = UUID()
        let rec = WordSyncRecord(
            sync: SyncMetadata(id: id, createdAt: t0, updatedAt: t0),
            payload: payload("cat")
        )
        XCTAssertEqual(rec.id, id)
    }

    func testCodableRoundTrip() throws {
        let rec = WordSyncRecord(
            sync: SyncMetadata(id: UUID(), householdID: household, profileID: profile,
                               createdAt: t0, updatedAt: at(10), deletedAt: at(20)),
            payload: WordPayload(text: "dog", promptText: "いぬ", source: "child",
                                 stepID: "step-3", displayOrder: 7)
        )
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(WordSyncRecord.self, from: data)
        XCTAssertEqual(rec, decoded)
    }
}

// MARK: - WordSidecarStore.project

final class WordSidecarProjectTests: XCTestCase {
    func testNewWordMintsMetadataScopedToHousehold() {
        let store = WordSidecarStore()
        let id = UUID()
        let records = store.project(
            localWords: [local(id, "cat", createdAt: at(5))],
            now: at(100), householdID: household, profileID: profile
        )
        XCTAssertEqual(records.count, 1)
        let m = records[0].sync
        XCTAssertEqual(m.id, id)
        XCTAssertEqual(m.householdID, household)
        XCTAssertEqual(m.profileID, profile)
        XCTAssertEqual(m.createdAt, at(5))     // word の registeredAt を踏襲
        XCTAssertEqual(m.updatedAt, at(100))   // 新規はいま触った扱い
        XCTAssertFalse(m.isDeleted)
        XCTAssertEqual(records[0].payload.text, "cat")
    }

    func testUnchangedWordKeepsUpdatedAt() {
        var store = WordSidecarStore()
        let id = UUID()
        // 初回プロジェクト → ingest して「同期済み」状態にする。
        let first = store.project(localWords: [local(id, "cat")],
                                  now: at(100), householdID: household, profileID: profile)
        store.ingest(first)
        // 内容変えずに再プロジェクト：updatedAt は据え置き（dirty にならない）。
        let again = store.project(localWords: [local(id, "cat")],
                                  now: at(200), householdID: household, profileID: profile)
        XCTAssertEqual(again[0].sync.updatedAt, at(100))
    }

    func testEditedWordBumpsUpdatedAt() {
        var store = WordSidecarStore()
        let id = UUID()
        let first = store.project(localWords: [local(id, "cat")],
                                  now: at(100), householdID: household, profileID: profile)
        store.ingest(first)
        let edited = store.project(localWords: [local(id, "cats")],   // text 変更
                                   now: at(200), householdID: household, profileID: profile)
        XCTAssertEqual(edited[0].sync.updatedAt, at(200))
        XCTAssertEqual(edited[0].payload.text, "cats")
        XCTAssertEqual(edited[0].sync.createdAt, first[0].sync.createdAt)  // createdAt は不変
    }

    func testLinkedMetaChangeBumpsUpdatedAt() {
        // Ph4: 紐付けメタ（linkedCourseID 等）だけが変わった語も dirty として検出され再送される。
        // アップグレード後、これまで未同期だった storageStepID/linked を一度だけ push に乗せる土台。
        var store = WordSidecarStore()
        let id = UUID()
        let plain = LocalWord(id: id,
                              payload: WordPayload(text: "cat", promptText: "", source: "parent",
                                                   stepID: nil, displayOrder: 0),
                              createdAt: t0)
        store.ingest(store.project(localWords: [plain], now: at(100),
                                   householdID: household, profileID: profile))
        // 同じ語に保管ステップ＋コース紐付けが付いた（テキストは不変）。
        let linked = LocalWord(id: id,
                               payload: WordPayload(text: "cat", promptText: "", source: "parent",
                                                    stepID: "2026-06-26-AB12CD34", displayOrder: 0,
                                                    linkedCourseID: "eiken-5",
                                                    linkedBeforeStepID: "eiken-5.step-3"),
                               createdAt: t0)
        let projected = store.project(localWords: [linked], now: at(200),
                                      householdID: household, profileID: profile)
        XCTAssertEqual(projected[0].sync.updatedAt, at(200), "紐付けメタ変更は dirty 扱い")
        XCTAssertEqual(projected[0].payload.stepID, "2026-06-26-AB12CD34")
        XCTAssertEqual(projected[0].payload.linkedCourseID, "eiken-5")
        XCTAssertEqual(projected[0].payload.linkedBeforeStepID, "eiken-5.step-3")
    }

    func testVanishedWordBecomesTombstone() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        // ローカルから消えた → 論理削除を生成。
        let records = store.project(localWords: [],
                                    now: at(300), householdID: household, profileID: profile)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].sync.isDeleted)
        XCTAssertEqual(records[0].sync.deletedAt, at(300))
        XCTAssertEqual(records[0].sync.updatedAt, at(300))
        XCTAssertEqual(records[0].payload.text, "cat")  // 最後に見た内容を保持
    }

    func testAlreadyTombstonedStaysStableWhenStillAbsent() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        let tomb = store.project(localWords: [], now: at(300),
                                 householdID: household, profileID: profile)
        store.ingest(tomb)
        // 再度欠席：すでに墓石なので updatedAt を再度進めない（churn 防止）。
        let again = store.project(localWords: [], now: at(999),
                                  householdID: household, profileID: profile)
        XCTAssertEqual(again[0].sync.deletedAt, at(300))
        XCTAssertEqual(again[0].sync.updatedAt, at(300))
    }

    func testReaddingDeletedIdResurrects() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        store.ingest(store.project(localWords: [], now: at(300),
                                   householdID: household, profileID: profile))
        // 同 id を復活：deletedAt クリア・updatedAt=now。
        let revived = store.project(localWords: [local(id, "cat")],
                                    now: at(400), householdID: household, profileID: profile)
        XCTAssertFalse(revived[0].sync.isDeleted)
        XCTAssertEqual(revived[0].sync.updatedAt, at(400))
    }

    func testProjectIsSortedById() {
        let store = WordSidecarStore()
        let lo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hi = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        let records = store.project(
            localWords: [local(hi, "b"), local(lo, "a")],
            now: at(10), householdID: household, profileID: profile
        )
        XCTAssertEqual(records.map(\.id), [lo, hi])
    }

    func testIngestRemoteWinnerPreventsFalseDirty() {
        var store = WordSidecarStore()
        let id = UUID()
        // ローカルで作って同期済みに。
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        // リモートが勝った版（別端末の編集）を ingest。
        let remoteWinner = WordSyncRecord(
            sync: SyncMetadata(id: id, householdID: household, profileID: profile,
                               createdAt: t0, updatedAt: at(500)),
            payload: payload("kitten")
        )
        store.ingest([remoteWinner])
        // ローカル UI も "kitten" に更新された前提で再プロジェクト → dirty にならない。
        let again = store.project(localWords: [local(id, "kitten")],
                                  now: at(600), householdID: household, profileID: profile)
        XCTAssertEqual(again[0].sync.updatedAt, at(500))
        XCTAssertFalse(again[0].sync.isDeleted)
    }

    // MARK: クロック逆行ガード（変更時刻は過去版より厳密に後）

    func testEditWithRegressedClockStaysStrictlyAfterStored() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        // ローカル時計が巻き戻った状態で編集（now < 既知 updatedAt）。
        let edited = store.project(localWords: [local(id, "cats")],
                                   now: at(50), householdID: household, profileID: profile)
        XCTAssertGreaterThan(edited[0].sync.updatedAt, at(100))      // 後退しない
        XCTAssertEqual(edited[0].sync.updatedAt, at(100).addingTimeInterval(0.001))
    }

    func testTombstoneWithRegressedClockStaysStrictlyAfterStored() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        let tomb = store.project(localWords: [], now: at(10),
                                 householdID: household, profileID: profile)
        XCTAssertGreaterThan(tomb[0].sync.updatedAt, at(100))
        XCTAssertEqual(tomb[0].sync.deletedAt, tomb[0].sync.updatedAt)
    }

    func testResurrectWithRegressedClockStaysStrictlyAfterStored() {
        var store = WordSidecarStore()
        let id = UUID()
        store.ingest(store.project(localWords: [local(id, "cat")],
                                   now: at(100), householdID: household, profileID: profile))
        store.ingest(store.project(localWords: [], now: at(300),
                                   householdID: household, profileID: profile))
        let revived = store.project(localWords: [local(id, "cat")],
                                    now: at(120), householdID: household, profileID: profile)
        XCTAssertFalse(revived[0].sync.isDeleted)
        XCTAssertGreaterThan(revived[0].sync.updatedAt, at(300))    // 墓石の updatedAt より後
    }

    // MARK: スコープ

    func testNilHouseholdReturnsEmpty() {
        let store = WordSidecarStore()
        XCTAssertTrue(store.project(localWords: [local(UUID(), "cat")],
                                    now: at(10), householdID: nil, profileID: profile).isEmpty)
    }

    func testAbsentEntryFromOtherHouseholdNotTombstoned() {
        var store = WordSidecarStore()
        let otherHousehold = UUID()
        // 別世帯の単語をストアに入れておく。
        let foreign = WordSyncRecord(
            sync: SyncMetadata(id: UUID(), householdID: otherHousehold, profileID: profile,
                               createdAt: t0, updatedAt: at(10)),
            payload: payload("foreign")
        )
        store.ingest([foreign])
        // アクティブ世帯で空のローカルを射影：別世帯のエントリは墓石化されない。
        let records = store.project(localWords: [], now: at(500),
                                    householdID: household, profileID: profile)
        XCTAssertTrue(records.isEmpty)
    }

    func testDuplicateLocalIdProducesSingleRecord() {
        let store = WordSidecarStore()
        let id = UUID()
        let records = store.project(
            localWords: [local(id, "cat"), local(id, "cats")],   // 同 id 重複
            now: at(10), householdID: household, profileID: profile
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].payload.text, "cats")          // 最後の版
    }

    func testStoreCodableRoundTrip() throws {
        var store = WordSidecarStore()
        store.ingest(store.project(localWords: [local(UUID(), "cat"), local(UUID(), "dog")],
                                   now: at(100), householdID: household, profileID: profile))
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(WordSidecarStore.self, from: data)
        XCTAssertEqual(store, decoded)
    }
}

// MARK: - SyncScope（世帯スコープ）

final class SyncScopeTests: XCTestCase {
    private func rec(_ household: UUID?) -> WordSyncRecord {
        WordSyncRecord(
            sync: SyncMetadata(id: UUID(), householdID: household, createdAt: t0, updatedAt: t0),
            payload: payload("x")
        )
    }

    func testKeepsOnlyActiveHousehold() {
        let other = UUID()
        let a = rec(household), b = rec(other), c = rec(household)
        let scoped = SyncScope.scoped([a, b, c], householdID: household)
        XCTAssertEqual(Set(scoped.map(\.id)), Set([a.id, c.id]))
    }

    func testNilActiveHouseholdYieldsEmpty() {
        XCTAssertTrue(SyncScope.scoped([rec(household)], householdID: nil).isEmpty)
    }

    func testExcludesNilHouseholdRecords() {
        XCTAssertTrue(SyncScope.scoped([rec(nil)], householdID: household).isEmpty)
    }
}

// MARK: - SyncCursors（カーソル/high-water 永続化）

final class SyncCursorsTests: XCTestCase {
    func testPullCursorDefaultsToZero() {
        let cursors = SyncCursors()
        XCTAssertEqual(cursors.pullCursor(for: "words"), 0)
    }

    func testAdvancePullTakesMaxAndIsPerTable() {
        var cursors = SyncCursors()
        cursors.advancePull(table: "words", to: 40)
        cursors.advancePull(table: "words", to: 25)   // 後退しない
        cursors.advancePull(table: "profiles", to: 7)
        XCTAssertEqual(cursors.pullCursor(for: "words"), 40)
        XCTAssertEqual(cursors.pullCursor(for: "profiles"), 7)
    }

    func testPushHighWaterDefaultsToNil() {
        XCTAssertNil(SyncCursors().pushedThrough(for: "words"))
    }

    func testAdvancePushTakesMax() {
        var cursors = SyncCursors()
        cursors.advancePush(table: "words", to: at(50))
        cursors.advancePush(table: "words", to: at(20))  // 後退しない
        XCTAssertEqual(cursors.pushedThrough(for: "words"), at(50))
    }

    func testCodableRoundTrip() throws {
        var cursors = SyncCursors()
        cursors.advancePull(table: "words", to: 12)
        cursors.advancePush(table: "words", to: at(30))
        let data = try JSONEncoder().encode(cursors)
        let decoded = try JSONDecoder().decode(SyncCursors.self, from: data)
        XCTAssertEqual(cursors, decoded)
    }
}
