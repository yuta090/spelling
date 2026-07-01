import Foundation
import SpellingSyncCore

/// `SyncEngine`（Supabase）を `WordSyncTransport` に適合させるアダプタ。
/// DTO ⇄ wire 型 `WordRow` の単純な写し替えだけを担う（変換の判断ロジックは `WordWire`）。
struct WordsSupabaseTransport: WordSyncTransport {
    let engine: SyncEngine

    func pullAll(table: String, since cursor: Int) async throws -> WordPullPage {
        let result = try await engine.pullAll(WordDTO.self, since: cursor)
        let rows = result.rows.map { dto in
            WordRow(
                id: dto.id, householdID: dto.householdId, profileID: dto.profileId,
                text: dto.text, promptText: dto.promptText, source: dto.source,
                displayOrder: dto.displayOrder, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt,
                storageStepID: dto.storageStepId,
                linkedCourseID: dto.linkedCourseId,
                linkedBeforeStepID: dto.linkedBeforeStepId
            )
        }
        return WordPullPage(rows: rows, nextCursor: result.nextCursor)
    }

    func push(table: String, rows: [WordRow]) async throws {
        let upserts = rows.map { row in
            WordUpsert(
                id: row.id, householdId: row.householdID, profileId: row.profileID,
                stepId: nil,                         // §7.5: サーバー UUID step_id は当面同期しない（storage_step_id text で往復）
                text: row.text, promptText: row.promptText, source: row.source,
                displayOrder: row.displayOrder, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
                storageStepId: row.storageStepID,    // Ph4: ローカル String の保管ステップ
                linkedCourseId: row.linkedCourseID,
                linkedBeforeStepId: row.linkedBeforeStepID
            )
        }
        try await engine.push(upserts)
    }
}

/// `AppModel` を `WordLocalSink` に適合させるアダプタ。
/// `planAndApply` は @MainActor かつ内部に await を持たないので、読取〜反映が原子的になる
/// （同期中に入ったローカル編集を stale なマージで上書きしない）。
@MainActor
struct AppModelWordSink: WordLocalSink {
    let model: AppModel

    func planAndApply(_ makePlan: @Sendable ([LocalWord]) -> WordSyncReducer.Plan) async -> WordSyncReducer.Plan {
        let plan = makePlan(model.localWordsForSync())
        model.applyMergedWords(LastWriteWins.live(plan.merged))
        return plan
    }
}

/// `words` 同期の **薄い I/O コーディネータ**。
///
/// 手順（pull→merge→push）と判断は `SpellingSyncCore`（`WordSyncRunner`/`WordSyncReducer`、TDD 済）に
/// 寄せ、ここは「ポートの組み立て」「多重実行ガード」「`UserDataStore` への永続化」だけに保つ
/// （CLAUDE.md: アプリ本体は薄く）。
/// 設計: docs/supabase-adapter-design.md §7.5
@MainActor
final class WordSyncCoordinator {
    private let transport: any WordSyncTransport
    private let store: UserDataStore
    private let now: () -> Date

    private var state: WordSyncState
    /// 多重実行ガード（pull の await 中に再入して二重反映しないため）。
    private var isSyncing = false
    /// 実行中に届いた同期要求の取りこぼし防止。実行後にもう一度だけ回す。
    private var pendingRerun = false
    /// 取りこぼし分の再実行に使う最新の世帯。
    private var pendingRerunHousehold: UUID?

    private let sidecarKey = "spellingTrainer.sync.wordSidecar"
    private let cursorsKey = "spellingTrainer.sync.cursors"
    private let table = WordDTO.table   // "words"

    init(
        persistenceStore: UserDataStore,
        transport: (any WordSyncTransport)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = persistenceStore
        self.transport = transport ?? WordsSupabaseTransport(engine: SyncEngine())
        self.now = now
        self.state = WordSyncState(
            sidecar: persistenceStore.load(WordSidecarStore.self, key: sidecarKey) ?? WordSidecarStore(),
            cursors: persistenceStore.load(SyncCursors.self, key: cursorsKey) ?? SyncCursors()
        )
    }

    /// 1 サイクル同期する。世帯未選択（`householdID == nil`）なら何もしない。
    ///
    /// 多重実行はガードするが、**取りこぼさない**: 実行中に来た要求は `pendingRerun` に畳み込み、
    /// 現在のサイクル後にもう一度だけ回す（実行中に入った編集が次トリガまで未送信で残らないように）。
    func sync(appModel: AppModel, householdID: UUID?) async throws {
        guard let householdID else { return }
        guard !isSyncing else {
            // 実行中: 取りこぼさないよう再実行を予約（最新世帯で）。
            pendingRerun = true
            pendingRerunHousehold = householdID
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        var current = householdID
        repeat {
            pendingRerun = false
            try await runOneCycle(appModel: appModel, householdID: current)
            if pendingRerun, let next = pendingRerunHousehold { current = next }
        } while pendingRerun
    }

    private func runOneCycle(appModel: AppModel, householdID: UUID) async throws {
        let sink = AppModelWordSink(model: appModel)

        // フェーズ1: pull→（原子的に）merge＋反映（pull 由来はここで確定・永続化。push 失敗でも保持）。
        let outcome = try await WordSyncRunner.pullAndMerge(
            table: table, householdID: householdID, state: state,
            transport: transport, sink: sink, now: now()
        )
        state = outcome.state
        persist()

        // フェーズ2: push（送れた分だけ high-water 前進）。
        guard !outcome.toPush.isEmpty else { return }
        state = try await WordSyncRunner.push(
            table: table, householdID: householdID, state: state,
            toPush: outcome.toPush, transport: transport
        )
        persist()
    }

    private func persist() {
        store.save(state.sidecar, key: sidecarKey)
        store.save(state.cursors, key: cursorsKey)
    }
}
