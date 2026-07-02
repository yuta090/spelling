import Foundation
import SpellingSyncCore

/// `SyncEngine`（Supabase）を `AttemptSyncTransport` に適合させるアダプタ。
/// DTO ⇄ wire 型 `AttemptRow` の写し替えだけを担う（判断ロジックは `AttemptWire`）。
///
/// pull は **captured `profileID` で絞る**（親認証は世帯の全児 attempt が見えるため、RLS 任せにせず
/// クエリで profile_id フィルタして他児データの混入を防ぐ＝words と同方針）。`profileID` はサイクルごとに
/// 生成時固定（不変）なので値型で安全。
struct AttemptsSupabaseTransport: AttemptSyncTransport {
    let engine: SyncEngine
    let profileID: UUID?

    func pullAll(table: String, since cursor: Int) async throws -> AttemptPullPage {
        let result = try await engine.pullAll(AttemptDTO.self, since: cursor, profileID: profileID)
        let rows = result.rows.map { dto in
            AttemptRow(
                id: dto.id, householdID: dto.householdId, profileID: dto.profileId,
                sessionID: dto.sessionId, stepID: dto.stepId, wordID: dto.wordId,
                expectedWord: dto.expectedWord, mode: dto.mode,
                recognizedText: dto.recognizedText, ocrConfidence: dto.ocrConfidence,
                autoDecision: dto.autoDecision, drawingPath: dto.drawingPath,
                submittedAt: dto.submittedAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            )
        }
        return AttemptPullPage(rows: rows, nextCursor: result.nextCursor)
    }

    func push(table: String, rows: [AttemptRow]) async throws {
        let upserts = rows.map { row in
            AttemptUpsert(
                id: row.id, householdId: row.householdID, profileId: row.profileID,
                sessionId: row.sessionID, stepId: row.stepID, wordId: row.wordID,
                expectedWord: row.expectedWord, mode: row.mode,
                recognizedText: row.recognizedText, ocrConfidence: row.ocrConfidence,
                autoDecision: row.autoDecision, drawingPath: row.drawingPath,
                submittedAt: row.submittedAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt
            )
        }
        try await engine.push(upserts)
    }
}

/// `AttemptLocalSink` を `AppModel` で実装する 1 サイクル用アダプタ。
/// 「最新ローカル答案の読取 → 計画 → 反映」を **await を挟まず**同期に連続実行する（原子性）。
/// 捕捉スコープ `(household, profile)` は生成時に固定する。
@MainActor
final class AttemptAppModelSink: AttemptLocalSink {
    private let appModel: AppModel
    private let householdID: UUID
    private let profileID: UUID

    init(appModel: AppModel, householdID: UUID, profileID: UUID) {
        self.appModel = appModel
        self.householdID = householdID
        self.profileID = profileID
    }

    func planAndApply(
        _ makePlan: @Sendable ([AttemptSyncRecord]) -> AttemptSyncReducer.Plan
    ) async -> AttemptSyncReducer.Plan {
        let local = appModel.localAttemptsForSync(householdID: householdID, profileID: profileID)
        let plan = makePlan(local)
        // pull の await 中にプロファイル切替が入っていたら反映しない（別プロファイルのスコープへ
        // 捕捉分を書かない）。localAttemptsForSync は捕捉スコープで読むが、`attempts` への書き戻しは
        // 現在アクティブのスコープに落ちるため、ここで一致を確認してから反映する。push（送信）は
        // レコードに household/profile を刻んでいるので切替後でも安全＝別途ガードしない。
        if appModel.canContinueWordSync(householdID: householdID, profileID: profileID) {
            appModel.applyMergedAttempts(plan.merged)
        }
        return plan
    }
}

/// `attempts`（採点同期・append-only）の **薄い I/O コーディネータ**。
///
/// 手順と判断は `SpellingSyncCore`（`AttemptSyncRunner`/`AttemptSyncReducer`、TDD 済）に寄せ、ここは
/// トランスポート呼び出し・多重実行ガード・スコープガード・**画像の DL/UL** の差し込みだけに保つ
/// （CLAUDE.md: アプリ本体は薄く）。手順:
///   pull（profile 絞り）→ plan＋UI 反映 → 画像 DL（不足分）→ 画像 UL（送信分）→ push。
/// `WordSyncCoordinator` と同じ多重実行ガード（`pendingRerun`）・スコープガード（`canContinueWordSync`）を用いる。
@MainActor
final class AttemptSyncCoordinator {
    private let engine: SyncEngine
    private let storage: DrawingStorage

    private var isSyncing = false
    private var pendingRerun = false
    private var pendingRerunHousehold: UUID?

    private let table = AttemptDTO.table   // "attempts"

    init(engine: SyncEngine? = nil, storage: DrawingStorage = DrawingStorage()) {
        self.engine = engine ?? SyncEngine()
        self.storage = storage
    }

    /// 1 サイクル同期する。世帯未選択なら何もしない。多重実行はガードしつつ取りこぼさない
    /// （実行中の要求は `pendingRerun` に畳み込み、サイクル後にもう一度だけ回す）。
    func sync(appModel: AppModel, householdID: UUID?) async throws {
        guard let householdID else { return }
        guard !isSyncing else {
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
        let profileID = appModel.activeProfileIDForSync
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        let transport = AttemptsSupabaseTransport(engine: engine, profileID: profileID)
        let sink = AttemptAppModelSink(appModel: appModel, householdID: householdID, profileID: profileID)
        var state = appModel.loadAttemptSyncState(profileID: profileID)

        // フェーズ1: pull（profile 絞り）→ plan＋反映（sink 内で原子的）→ pull カーソル前進。
        let outcome = try await AttemptSyncRunner.pullAndMerge(
            table: table, householdID: householdID, state: state,
            transport: transport, sink: sink
        )
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        state = outcome.state
        appModel.saveAttemptSyncState(state, profileID: profileID)

        // フェーズ1c: リモート由来でバイト列が無い答案の画像を後追いダウンロード（ベストエフォート）。
        await appModel.downloadMissingAttemptDrawings(storage: storage, householdID: householdID, profileID: profileID)
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        // フェーズ2: 送信分のローカル手書きを先にアップロード → push（送れた分だけ high-water 前進）。
        // 画像 UL 失敗時は throw で push を中止（high-water を進めず次サイクルで丸ごと再試行＝
        // 実体の無い drawing_path を作らない）。
        guard !outcome.toPush.isEmpty else { return }
        try await appModel.uploadAttemptDrawings(outcome.toPush, storage: storage)
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        state = try await AttemptSyncRunner.push(
            table: table, householdID: householdID, state: state,
            toPush: outcome.toPush, transport: transport
        )
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        appModel.saveAttemptSyncState(state, profileID: profileID)
    }
}
