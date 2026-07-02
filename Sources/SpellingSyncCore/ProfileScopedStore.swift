import Foundation

/// バイト列レベルの永続化ポート（Core が具体 I/O 実装に依存しないための境界）。
///
/// アプリ側の `AppPersistenceStore`（ファイル保存）と `InMemoryUserDataStore`（揮発）が準拠する。
/// `ProfileScopedStore` はこの境界越しにキーを名前空間化する。
public protocol ProfileScopedRawStore: AnyObject, Sendable {
    /// キーに対応するバイト列。無ければ nil。
    func rawLoad(_ key: String) -> Data?
    /// 通常保存（非同期でよい＝呼び出しをブロックしない）。
    func rawSave(_ data: Data, key: String)
    /// 書き込み完了を待つ同期保存。移行のバリア（コピー完了を保証してから台帳を確定）に使う。
    func rawSaveBlocking(_ data: Data, key: String)
    /// キーに対応する値を削除する（プロファイル削除時の孤児データ purge に使う）。
    /// フォールバック退避先（UserDefaults 等）も併せて掃除すること。
    func rawRemove(_ key: String)
}

/// `UserDataStore` を**プロファイル単位に名前空間化**するラッパ（設計 §3 の核心）。
///
/// 子ども別キーは `profiles/<activeProfileID>/<key>` に prefix し、世帯/端末グローバルなキー
/// （サブスク・デバッグ・同期簿記・台帳）は素通しする（判定は `ProfileKeyScope`）。
/// アプリ側の各キー文字列（`"spellingTrainer.words"` 等）は不変のまま、prefix はここが行う。
///
/// Swift 6 並行性: `activeProfileID` は可変で、非同期な同期/テレメトリ経路がストアに触れうるため
/// `NSLock` で保護する（`@unchecked Sendable`）。切替（`setActiveProfileID`）は `@MainActor` から
/// 直列に呼ぶ前提だが、読取りはどのスレッドからでも安全。
public final class ProfileScopedStore: @unchecked Sendable {
    private let base: ProfileScopedRawStore
    private let lock = NSLock()
    private var _activeProfileID: UUID

    public init(base: ProfileScopedRawStore, activeProfileID: UUID) {
        self.base = base
        self._activeProfileID = activeProfileID
    }

    /// 現在アクティブなプロファイル ID（ロック越し）。
    public var activeProfileID: UUID {
        lock.lock(); defer { lock.unlock() }
        return _activeProfileID
    }

    /// アクティブプロファイルを差し替える（切替時に呼ぶ）。以後の load/save はこのスコープになる。
    public func setActiveProfileID(_ id: UUID) {
        lock.lock(); _activeProfileID = id; lock.unlock()
    }

    private func scopedKey(_ key: String) -> String {
        lock.lock(); let id = _activeProfileID; lock.unlock()
        return ProfileKeyScope.scopedKey(key, profileID: id)
    }

    /// アクティブプロファイルのスコープでバイト列を読む。
    public func load(_ key: String) -> Data? {
        base.rawLoad(scopedKey(key))
    }

    /// アクティブプロファイルのスコープでバイト列を保存する（非同期でよい）。
    public func save(_ data: Data, key: String) {
        base.rawSave(data, key: scopedKey(key))
    }

    // MARK: - 明示プロファイルスコープ I/O（同期簿記など「現在アクティブ」に依存させたくない用途）

    /// **指定した** `profileID` のスコープでバイト列を読む（アクティブ prefix に依存しない）。
    /// 同期コーディネータが、サイクル開始時に捕捉したプロファイルへ確実に読み書きするために使う
    /// （pull の await 中に切替が起きても、捕捉したプロファイルの簿記を別スコープへ書かない）。
    public func loadScoped(_ key: String, profileID: UUID) -> Data? {
        base.rawLoad(ProfileKeyScope.scopedKey(key, profileID: profileID))
    }

    /// **指定した** `profileID` のスコープでバイト列を保存する（アクティブ prefix に依存しない）。
    public func saveScoped(_ data: Data, key: String, profileID: UUID) {
        base.rawSave(data, key: ProfileKeyScope.scopedKey(key, profileID: profileID))
    }

    /// 旧・世帯グローバルだったキー（prefix 無し）を、**指定プロファイル**のスコープへ一度だけ移す（冪等）。
    /// Phase 5 で子スコープへ移した同期簿記（サイドカー/カーソル）の初回移行に使う。移行先は
    /// 「世帯 NULL ストリームのオーナー」に固定する（アクティブが別プロファイルでも取り違えない）。
    /// - 冪等: 移行先が既にあればスキップ。
    /// - グローバル分類のままのキー（`dest == key`）は対象外。
    public func migrateGlobalKeys(_ keys: Set<String>, into profileID: UUID) {
        for key in keys {
            let dest = ProfileKeyScope.scopedKey(key, profileID: profileID)
            guard dest != key else { continue }
            guard base.rawLoad(dest) == nil else { continue }   // 冪等
            guard let data = base.rawLoad(key) else { continue } // 旧グローバル値が無ければ何もしない
            // バリア（`rawSaveBlocking`）：着地を待ってから続行する。これで **起動直後の初回同期が
            // 空サイドカー（cursor 0）で走り、ローカル語が now スタンプで墓石に勝って復活する**事故を防ぐ。
            base.rawSaveBlocking(data, key: dest)
        }
    }

    /// 指定プロファイルの **子スコープ全キー** を削除する（プロファイル削除時の孤児データ prefix 一括 purge）。
    /// グローバルキーは `scopedKey` が prefix しないため対象に入らない（`keys` は子スコープキーのみ渡す）。
    /// 退避先（UserDefaults 等）も含めて掃除するのは `base.rawRemove` の責務。
    public func purgeProfile(_ profileID: UUID, keys: Set<String> = ProfileKeyScope.childScopedKeys) {
        for key in keys {
            let scoped = ProfileKeyScope.scopedKey(key, profileID: profileID)
            // 子スコープキーは必ず prefix される。万一グローバル分類のキーが混ざっても素通しキーは消さない。
            guard scoped != key else { continue }
            base.rawRemove(scoped)
        }
    }

    /// 既存の単一子データ（prefix 無しキー）を、アクティブプロファイルのスコープへ一度だけコピーする。
    ///
    /// - 冪等: コピー先が既にあればスキップ（2回流しても二重化しない・途中失敗でも再開できる）。
    /// - バリア: `rawSaveBlocking` で書き込み完了を待つ（コピー未完のまま台帳が確定するのを防ぐ）。
    /// - 対象: `ProfileKeyScope.childScopedKeys`（キー分類の単一ソース）。
    /// - 戻り値: 全コピーが**読み戻せる形で着地**したか（＝台帳マーカーを確定してよいか）。
    ///   1件でも着地検証に失敗したら `false` を返し、呼び出し側はマーカーを保存せず次回起動で再試行させる
    ///   （ストレージ書込失敗が握りつぶされて「移行済みなのにデータが読めない」状態になるのを防ぐ）。
    @discardableResult
    public func migrateLegacyDataIntoActiveScope(
        childScopedKeys: Set<String> = ProfileKeyScope.childScopedKeys
    ) -> Bool {
        let id = activeProfileID
        var allCopiesDurable = true
        for key in childScopedKeys {
            let dest = ProfileKeyScope.scopedKey(key, profileID: id)
            // 子スコープキーは必ず prefix される（= dest != key）。万一グローバル分類なら自己コピーを避ける。
            guard dest != key else { continue }
            // 既にコピー済みならスキップ（冪等）。
            guard base.rawLoad(dest) == nil else { continue }
            // 元データが無ければ何もしない（未使用キーはコピー不要）。
            guard let data = base.rawLoad(key) else { continue }
            base.rawSaveBlocking(data, key: dest)
            // 書き込みが読み戻せる形で着地したか検証（失敗を握りつぶさない）。
            if base.rawLoad(dest) == nil { allCopiesDurable = false }
        }
        return allCopiesDurable
    }
}

/// 単一子（prefix 無し）→ プロファイル#1 への初回移行と、以後の台帳ロードを司る。
///
/// 台帳（`ProfileRegistry`）は `spellingTrainer.profiles` グローバルキーに保存する。
/// **「このキーが存在すること」自体が移行済みマーカー**（別フラグは持たない＝単一ソース）。
/// 移行順序（設計 §5・レビュー指摘②）:
///   ① 子スコープキーを #1 へ**バリアコピー**（`rawSaveBlocking`・冪等）
///   ② その後で台帳を**バリア保存**（コピー完了後に確定）
/// この順なので、途中でプロセスが落ちても台帳が未保存 → 次回また bootstrap → コピーは冪等に再開。
public enum ProfileStoreMigration {
    /// 台帳（`ProfileRegistry`）の保存キー。移行マーカー兼、実行時の改名/切替の保存先（アプリからも使う）。
    public static let profilesKey = "spellingTrainer.profiles"
    static let legacyChildNameKey = "spellingTrainer.childName"

    /// アプリ起動時に一度だけ呼ぶ。既に台帳があればそれを返し、無ければ #1 を生成して移行する。
    public static func loadOrBootstrap(
        base: ProfileScopedRawStore,
        now: Date,
        newProfileID: UUID = UUID()
    ) -> ProfileRegistry {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        // 既に移行済み: 台帳を読んで返す（壊れていれば bootstrap にフォールバック）。
        if let data = base.rawLoad(profilesKey),
           let registry = try? decoder.decode(ProfileRegistry.self, from: data) {
            return registry
        }

        // 未移行: プロファイル#1 を生成（displayName = 既存 childName）。
        let legacyName = base.rawLoad(legacyChildNameKey)
            .flatMap { try? decoder.decode(String.self, from: $0) } ?? ""
        let profile = ChildProfile(id: newProfileID, displayName: legacyName, createdAt: now)
        let registry = ProfileRegistry(bootstrapping: profile)

        // ① 子スコープキーを #1 スコープへバリアコピー（冪等）。全コピーが着地したかを受け取る。
        let scoped = ProfileScopedStore(base: base, activeProfileID: profile.id)
        let copiesDurable = scoped.migrateLegacyDataIntoActiveScope()

        // ② コピーが全て着地したときだけ台帳を確定（バリア保存＝これが移行済みマーカー）。
        //    着地検証に失敗したらマーカーを保存しない → 次回起動で bootstrap をやり直す（冪等再試行）。
        if copiesDurable, let data = try? encoder.encode(registry) {
            base.rawSaveBlocking(data, key: profilesKey)
        }
        return registry
    }
}
