import Foundation
import SpellingSyncCore

/// `words` の 1 サイクル同期（pull → merge → push）を束ねる **薄い I/O コーディネータ**。
///
/// 判断ロジック（マージ・送信対象の選定・カーソル前進）は `SpellingSyncCore`（TDD 済）に置き、
/// ここは「Supabase の pull/push」「UserDefaults への永続化」「AppModel への反映」を順序立てて
/// 呼ぶだけに保つ（CLAUDE.md: アプリ本体は薄く）。
/// サイドカー（`WordSidecarStore`）と各テーブルのカーソル（`SyncCursors`）を端末に永続化する。
/// 設計: docs/supabase-adapter-design.md §7.5
@MainActor
final class WordSyncCoordinator {
    private let engine: SyncEngine
    private let store: UserDataStore
    private let now: () -> Date

    /// 直近の同期基準（dirty 検出・LWW のベースライン）。永続化される。
    private var sidecar: WordSidecarStore
    /// プルカーソル（sync_version）と送信 high-water（updatedAt）。永続化される。
    private var cursors: SyncCursors

    private let sidecarKey = "spellingTrainer.sync.wordSidecar"
    private let cursorsKey = "spellingTrainer.sync.cursors"
    private let table = WordDTO.table   // "words"

    /// 多重実行ガード（同時 sync で words を二重反映しないため）。
    private var isSyncing = false

    /// カーソル/high-water は **世帯ごと**に持つ。`pullAll` はテーブル全体（RLS 範囲の全世帯）を
    /// 返すため、テーブル単位のカーソルだと世帯を切り替えたとき前の世帯のカーソルが進んでいて
    /// 新しい世帯の行を取りこぼす。世帯ごとに分けることで切り替えても全件取得できる。
    private func cursorKey(_ householdID: UUID) -> String {
        "\(table):\(householdID.uuidString)"
    }

    init(
        persistenceStore: UserDataStore,
        engine: SyncEngine = SyncEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = persistenceStore
        self.engine = engine
        self.now = now
        self.sidecar = persistenceStore.load(WordSidecarStore.self, key: sidecarKey) ?? WordSidecarStore()
        self.cursors = persistenceStore.load(SyncCursors.self, key: cursorsKey) ?? SyncCursors()
    }

    /// 1 サイクル同期する。世帯未選択（`householdID == nil`）なら何もしない。
    ///
    /// 手順:
    /// 1. AppModel の単語を同期素材（`LocalWord`）として読む。
    /// 2. `sync_version` カーソルで差分を pull し `WordSyncRecord` に変換。
    /// 3. `WordSyncReducer.plan` でマージ結果と送信対象を決める。
    /// 4. **pull 由来の真実はここで確定**（ingest＋AppModel 反映＋プルカーソル前進＋永続化）。
    ///    push が失敗しても取得済みデータは保持する。
    /// 5. 送信対象を upsert し、成功したら送信 high-water を前進＋永続化。
    func sync(appModel: AppModel, householdID: UUID?) async throws {
        guard let householdID else { return }
        // 多重実行を防ぐ（pull の await 中に再入すると stale なスナップショットで上書きしうる）。
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let key = cursorKey(householdID)

        // pull（差分）。await 中に words が変わりうるので、ローカル素材は **pull 後**に読む。
        let cursor = cursors.pullCursor(for: key)
        let pulled = try await engine.pullAll(WordDTO.self, since: cursor)
        let remote = pulled.rows.compactMap(Self.record(from:))

        // pull 完了後（同期的・await なし）の最新 words からマージ計画を作る。
        let localWords = appModel.localWordsForSync()
        let plan = WordSyncReducer.plan(
            localWords: localWords,
            remote: remote,
            store: sidecar,
            now: now(),
            householdID: householdID,
            profileID: nil,
            pushedThrough: cursors.pushedThrough(for: key)
        )

        // pull 由来の真実を確定（push 失敗でも保持する）。ここまで await を挟まない。
        sidecar.ingest(plan.merged)
        appModel.applyMergedWords(LastWriteWins.live(plan.merged))
        cursors.advancePull(table: key, to: pulled.nextCursor)
        persist()

        // push（未送信のみ）。エンコードできた (record, upsert) のみを対象にし、
        // high-water は **実際に送った record** からのみ算出する（未送信分で進めない）。
        let pushable = plan.toPush.compactMap { record in
            Self.upsert(from: record).map { (record: record, upsert: $0) }
        }
        guard !pushable.isEmpty else { return }
        try await engine.push(pushable.map(\.upsert))
        if let highWater = OutboundSync.highWater(pushable.map(\.record), current: cursors.pushedThrough(for: key)) {
            cursors.advancePush(table: key, to: highWater)
            persist()
        }
    }

    private func persist() {
        store.save(sidecar, key: sidecarKey)
        store.save(cursors, key: cursorsKey)
    }

    // MARK: - DTO ⇄ レコード（変換ロジックは WordWire に集約。ここは単純な写し替え）

    private static func record(from dto: WordDTO) -> WordSyncRecord? {
        WordWire.record(from: WordRow(
            id: dto.id,
            householdID: dto.householdId,
            profileID: dto.profileId,
            text: dto.text,
            promptText: dto.promptText,
            source: dto.source,
            displayOrder: dto.displayOrder,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        ))
    }

    private static func upsert(from record: WordSyncRecord) -> WordUpsert? {
        guard let row = WordWire.wire(from: record) else { return nil }
        return WordUpsert(
            id: row.id,
            householdId: row.householdID,
            profileId: row.profileID,
            stepId: nil,                 // §7.5: step_id(UUID) は当面同期しない
            text: row.text,
            promptText: row.promptText,
            source: row.source,
            displayOrder: row.displayOrder,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt
        )
    }
}
