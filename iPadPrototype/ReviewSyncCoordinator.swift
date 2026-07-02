import Foundation
import SpellingSyncCore

/// アプリの親採点列挙 ⇄ 同期コアの `ReviewDecision` の**網羅的写し替え**。
/// rawValue は一致するが、将来ケース追加時にコンパイルで気づけるよう switch で明示する（黙って写さない）。
extension ParentReviewDecision {
    var syncDecision: ReviewDecision {
        switch self {
        case .unreviewed: return .unreviewed
        case .approved: return .approved
        case .needsPractice: return .needsPractice
        }
    }

    init(sync: ReviewDecision) {
        switch sync {
        case .unreviewed: self = .unreviewed
        case .approved: self = .approved
        case .needsPractice: self = .needsPractice
        }
    }
}

/// `SyncEngine`（Supabase）を `ReviewSyncTransport` に適合させるアダプタ。
/// DTO ⇄ wire 型 `ReviewRow` の写し替えだけを担う（判断ロジックは `ReviewWire`）。
///
/// pull は **captured `profileID` で絞る**（親認証は世帯の全児 review が見えるため、RLS 任せにせず
/// クエリで profile_id フィルタして他児データの混入を防ぐ＝attempts と同方針）。`profileID` はサイクルごとに
/// 生成時固定（不変）なので値型で安全。
struct ReviewsSupabaseTransport: ReviewSyncTransport {
    let engine: SyncEngine
    let profileID: UUID?

    func pullAll(table: String, since cursor: Int) async throws -> ReviewPullPage {
        let result = try await engine.pullAll(ReviewDTO.self, since: cursor, profileID: profileID)
        let rows = result.rows.map { dto in
            ReviewRow(
                id: dto.id, householdID: dto.householdId, profileID: dto.profileId,
                attemptID: dto.attemptId, parentDecision: dto.parentDecision,
                parentExamplePath: dto.parentExamplePath, reviewedBy: dto.reviewedBy,
                reviewedAt: dto.reviewedAt, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt
            )
        }
        return ReviewPullPage(rows: rows, nextCursor: result.nextCursor)
    }

    func push(table: String, rows: [ReviewRow]) async throws {
        let upserts = rows.map { row in
            ReviewUpsert(
                id: row.id, householdId: row.householdID, profileId: row.profileID,
                attemptId: row.attemptID, parentDecision: row.parentDecision,
                parentExamplePath: row.parentExamplePath, reviewedBy: row.reviewedBy,
                reviewedAt: row.reviewedAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt
            )
        }
        try await engine.push(upserts)
    }
}

/// `ReviewLocalSink` を `AppModel` で実装する 1 サイクル用アダプタ。
/// 「最新ローカル採点の読取 → 計画 → 反映」を **await を挟まず**同期に連続実行する（原子性）。
/// 捕捉スコープ `(household, profile)` は生成時に固定する。
@MainActor
final class ReviewAppModelSink: ReviewLocalSink {
    private let appModel: AppModel
    private let householdID: UUID
    private let profileID: UUID

    init(appModel: AppModel, householdID: UUID, profileID: UUID) {
        self.appModel = appModel
        self.householdID = householdID
        self.profileID = profileID
    }

    func planAndApply(
        _ makePlan: @Sendable ([LocalReview]) -> ReviewSyncReducer.Plan
    ) async -> ReviewSyncReducer.Plan {
        let local = appModel.localReviewsForSync(householdID: householdID, profileID: profileID)
        let plan = makePlan(local)
        // pull の await 中にプロファイル切替が入っていたら反映しない（別プロファイルのスコープへ
        // 捕捉分を書かない）。反映（`attempts` への親採点書き戻し）は現在アクティブのスコープに落ちるため、
        // ここで一致を確認してから反映する。push はレコードに household/profile を刻むので切替後でも安全。
        // ⚠️ tombstone（採点取消）も **含めて**渡す（`live` で除外しない）：取消をローカルへ反映し、
        // かつ生存扱いのまま再 push して取消を復活させる resurrection を防ぐため（`applyMergedReviews` 参照）。
        if appModel.canContinueWordSync(householdID: householdID, profileID: profileID) {
            appModel.applyMergedReviews(plan.merged)
        }
        return plan
    }
}

/// `reviews`（採点同期・親判定＋見本画像）の **薄い I/O コーディネータ**。
///
/// 手順と判断は `SpellingSyncCore`（`ReviewSyncRunner`/`ReviewSyncReducer`、TDD 済）に寄せ、ここは
/// トランスポート呼び出し・多重実行ガード・スコープガード・**見本画像の DL/UL** の差し込みだけに保つ
/// （CLAUDE.md: アプリ本体は薄く）。手順:
///   pull（profile 絞り）→ plan＋UI 反映 → 見本 DL（不足分）→ 見本 UL（送信分）→ push。
/// `AttemptSyncCoordinator` と同じ多重実行ガード（`pendingRerun`）・スコープガードを用いる。
/// reviews は attempt を FK 参照するため、`syncNow` では attempts の push 後に本サイクルを回す。
@MainActor
final class ReviewSyncCoordinator {
    private let engine: SyncEngine
    private let storage: DrawingStorage

    private var isSyncing = false
    private var pendingRerun = false
    private var pendingRerunHousehold: UUID?

    private let table = ReviewDTO.table   // "reviews"

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

        let transport = ReviewsSupabaseTransport(engine: engine, profileID: profileID)
        let sink = ReviewAppModelSink(appModel: appModel, householdID: householdID, profileID: profileID)
        var state = appModel.loadReviewSyncState(profileID: profileID)

        // フェーズ1: pull（profile 絞り）→ plan＋反映（sink 内で原子的）→ pull カーソル前進。
        let outcome = try await ReviewSyncRunner.pullAndMerge(
            table: table, householdID: householdID, state: state,
            transport: transport, sink: sink, now: Date(), profileID: profileID
        )
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        state = outcome.state
        appModel.saveReviewSyncState(state, profileID: profileID)

        // フェーズ1c: リモート由来でバイト列が無い見本画像を後追いダウンロード（ベストエフォート）。
        await appModel.downloadMissingReviewExamples(storage: storage, householdID: householdID, profileID: profileID)
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        // フェーズ2: 送信分のローカル見本を先にアップロード → push（送れた分だけ high-water 前進）。
        // 画像 UL 失敗時は throw で push を中止（high-water を進めず次サイクルで丸ごと再試行＝
        // 実体の無い parent_example_path を作らない）。
        guard !outcome.toPush.isEmpty else { return }
        try await appModel.uploadReviewExamples(outcome.toPush, storage: storage)
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        state = try await ReviewSyncRunner.push(
            table: table, householdID: householdID, state: state,
            toPush: outcome.toPush, transport: transport
        )
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        appModel.saveReviewSyncState(state, profileID: profileID)
    }
}
