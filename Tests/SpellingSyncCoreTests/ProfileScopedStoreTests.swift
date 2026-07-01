import XCTest
@testable import SpellingSyncCore

/// テスト用の in-memory raw ストア。`rawSaveBlocking` の呼び出しキーを記録し、
/// 移行のバリア順序（コピー→台帳確定）を観測できるようにする。
private final class FakeRawStore: ProfileScopedRawStore, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var storage: [String: Data] = [:]
    /// `rawSaveBlocking` で書かれたキーの順序（バリア順の検証用）。
    private(set) var blockingWrites: [String] = []

    func rawLoad(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    func rawSave(_ data: Data, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    func rawSaveBlocking(_ data: Data, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
        blockingWrites.append(key)
    }

    // テスト補助: JSON でセット/取得。
    func seed<T: Encodable>(_ value: T, key: String) {
        storage[key] = try! JSONEncoder().encode(value)
    }
    func decoded<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let d = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: d)
    }
}

final class ProfileScopedStoreTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }
    private func string(_ d: Data?) -> String? { d.map { String(decoding: $0, as: UTF8.self) } }

    // MARK: 名前空間化

    func testChildScopedKeyIsPrefixed() {
        let base = FakeRawStore()
        let id = UUID()
        let store = ProfileScopedStore(base: base, activeProfileID: id)

        store.save(data("hello"), key: "spellingTrainer.words")

        // 実キーは prefix される。
        XCTAssertNil(base.storage["spellingTrainer.words"])
        XCTAssertEqual(string(base.storage["profiles/\(id.uuidString)/spellingTrainer.words"]), "hello")
        // 読み戻しは prefix 透過。
        XCTAssertEqual(string(store.load("spellingTrainer.words")), "hello")
    }

    func testGlobalKeyIsNotPrefixed() {
        let base = FakeRawStore()
        let store = ProfileScopedStore(base: base, activeProfileID: UUID())

        store.save(data("ent"), key: "spellingTrainer.cachedEntitlement")

        XCTAssertEqual(string(base.storage["spellingTrainer.cachedEntitlement"]), "ent")
        XCTAssertEqual(string(store.load("spellingTrainer.cachedEntitlement")), "ent")
    }

    // MARK: 切替往復でデータ非混在（A→B→A）

    func testSwitchingProfilesIsolatesData() {
        let base = FakeRawStore()
        let a = UUID(), b = UUID()
        let store = ProfileScopedStore(base: base, activeProfileID: a)

        store.save(data("A-words"), key: "spellingTrainer.words")

        store.setActiveProfileID(b)
        XCTAssertNil(store.load("spellingTrainer.words"))   // B はまだ空
        store.save(data("B-words"), key: "spellingTrainer.words")

        store.setActiveProfileID(a)
        XCTAssertEqual(string(store.load("spellingTrainer.words")), "A-words")  // A は保たれる
        store.setActiveProfileID(b)
        XCTAssertEqual(string(store.load("spellingTrainer.words")), "B-words")  // B と混ざらない
    }

    func testGlobalKeyIsSharedAcrossProfiles() {
        let base = FakeRawStore()
        let a = UUID(), b = UUID()
        let store = ProfileScopedStore(base: base, activeProfileID: a)

        store.save(data("shared"), key: "spellingTrainer.cachedEntitlement")
        store.setActiveProfileID(b)
        // サブスクは世帯単位＝全プロファイルで共有。
        XCTAssertEqual(string(store.load("spellingTrainer.cachedEntitlement")), "shared")
    }

    // MARK: 移行コピー（冪等・バリア）

    func testMigrateCopiesChildScopedKeysIntoScope() {
        let base = FakeRawStore()
        let id = UUID()
        base.rawSave(data("legacy-words"), key: "spellingTrainer.words")
        base.rawSave(data("legacy-coins"), key: "spellingTrainer.rewardCoins.v2")

        let store = ProfileScopedStore(base: base, activeProfileID: id)
        store.migrateLegacyDataIntoActiveScope()

        XCTAssertEqual(string(store.load("spellingTrainer.words")), "legacy-words")
        XCTAssertEqual(string(store.load("spellingTrainer.rewardCoins.v2")), "legacy-coins")
        // 元（prefix 無し）は残る＝コピー（move ではない・非破壊）。
        XCTAssertEqual(string(base.storage["spellingTrainer.words"]), "legacy-words")
        // コピーはバリア（blocking）で行われる。
        XCTAssertTrue(base.blockingWrites.contains("profiles/\(id.uuidString)/spellingTrainer.words"))
    }

    func testMigrateIsIdempotent() {
        let base = FakeRawStore()
        let id = UUID()
        base.rawSave(data("v1"), key: "spellingTrainer.words")
        let store = ProfileScopedStore(base: base, activeProfileID: id)

        store.migrateLegacyDataIntoActiveScope()
        // 2回目までに子側を編集 → 再migrateで上書きされない（コピー先があればスキップ）。
        store.save(data("edited"), key: "spellingTrainer.words")
        store.migrateLegacyDataIntoActiveScope()

        XCTAssertEqual(string(store.load("spellingTrainer.words")), "edited")
    }

    func testMigrateSkipsMissingSourceKeys() {
        let base = FakeRawStore()
        let id = UUID()
        // 元データ無し。
        let store = ProfileScopedStore(base: base, activeProfileID: id)
        store.migrateLegacyDataIntoActiveScope()

        XCTAssertNil(store.load("spellingTrainer.words"))
        // グローバルキーはコピー対象外（自己コピーしない）。
        XCTAssertFalse(base.blockingWrites.contains("spellingTrainer.cachedEntitlement"))
    }

    // MARK: bootstrap（初回移行）

    func testBootstrapCreatesRegistryFromLegacyChildName() {
        let base = FakeRawStore()
        base.seed("たろう", key: "spellingTrainer.childName")
        base.seed(["a", "b"], key: "spellingTrainer.words")

        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let registry = ProfileStoreMigration.loadOrBootstrap(base: base, now: now, newProfileID: id)

        XCTAssertEqual(registry.profiles.count, 1)
        XCTAssertEqual(registry.activeProfile.id, id)
        XCTAssertEqual(registry.activeProfile.displayName, "たろう")
        // 台帳が保存され、子データが #1 スコープへコピーされている。
        XCTAssertNotNil(base.decoded(ProfileRegistry.self, key: "spellingTrainer.profiles"))
        XCTAssertEqual(base.decoded([String].self, key: "profiles/\(id.uuidString)/spellingTrainer.words"), ["a", "b"])
    }

    func testBootstrapWritesRegistryAfterCopy() {
        // バリア順序: 子データのコピー（blocking）→ 台帳（blocking）が最後。
        let base = FakeRawStore()
        base.seed(["x"], key: "spellingTrainer.words")
        let id = UUID()

        _ = ProfileStoreMigration.loadOrBootstrap(base: base, now: Date(), newProfileID: id)

        let copyKey = "profiles/\(id.uuidString)/spellingTrainer.words"
        let profilesKey = "spellingTrainer.profiles"
        let copyIndex = base.blockingWrites.firstIndex(of: copyKey)
        let profilesIndex = base.blockingWrites.firstIndex(of: profilesKey)
        XCTAssertNotNil(copyIndex)
        XCTAssertNotNil(profilesIndex)
        XCTAssertLessThan(copyIndex!, profilesIndex!, "台帳はコピー完了後に確定すること")
    }

    func testBootstrapIsIdempotentAcrossRuns() {
        let base = FakeRawStore()
        base.seed("なまえ", key: "spellingTrainer.childName")
        let id = UUID()

        let first = ProfileStoreMigration.loadOrBootstrap(base: base, now: Date(), newProfileID: id)
        // 2回目は既存台帳を返す（新 UUID を渡しても無視され #1 が維持される）。
        let second = ProfileStoreMigration.loadOrBootstrap(base: base, now: Date(), newProfileID: UUID())

        XCTAssertEqual(first, second)
        XCTAssertEqual(second.activeProfile.id, id)
    }

    func testBootstrapWithNoLegacyNameYieldsEmptyDisplayName() {
        let base = FakeRawStore()
        let registry = ProfileStoreMigration.loadOrBootstrap(base: base, now: Date())
        XCTAssertEqual(registry.profiles.count, 1)
        XCTAssertEqual(registry.activeProfile.displayName, "")
    }

    // MARK: 書込失敗時は台帳マーカーを確定しない（次回起動で再試行）

    func testBootstrapDoesNotWriteRegistryWhenCopyFails() {
        // rawSaveBlocking が着地しないストア（書込失敗のフォールバック相当）。
        let base = DroppingBlockingStore()
        base.seed(["x"], key: "spellingTrainer.words")

        let registry = ProfileStoreMigration.loadOrBootstrap(base: base, now: Date())

        // コピーが読み戻せないので台帳マーカーは保存されない＝「移行済み」にしない。
        XCTAssertNil(base.rawLoad("spellingTrainer.profiles"))
        // 返り値の registry は使える（このセッションは動く）が、次回起動で bootstrap をやり直せる。
        XCTAssertEqual(registry.profiles.count, 1)
    }

    func testMigrateReturnsFalseWhenCopyDoesNotLand() {
        let base = DroppingBlockingStore()
        base.seed(["y"], key: "spellingTrainer.words")
        let store = ProfileScopedStore(base: base, activeProfileID: UUID())
        XCTAssertFalse(store.migrateLegacyDataIntoActiveScope())
    }
}

/// `rawSaveBlocking` を記録するが**永続化しない**ストア（書込がファイルに着地せずフォールバックした状況を模す）。
private final class DroppingBlockingStore: ProfileScopedRawStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func rawLoad(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    func rawSave(_ data: Data, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    /// 着地しない（読み戻せない）。
    func rawSaveBlocking(_ data: Data, key: String) { /* drop */ }

    func seed<T: Encodable>(_ value: T, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = try! JSONEncoder().encode(value)
    }
}
