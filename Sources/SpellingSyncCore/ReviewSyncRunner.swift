import Foundation

/// 採点（reviews）の 1 サイクル同期を **ポート越しに**実行する純粋オーケストレータ。`WordSyncRunner` の review 版。
///
/// I/O（Supabase・UserDefaults・AppModel）は `ReviewSyncTransport`/`ReviewLocalSink` の実装に逃がし、
/// ここは「pull→plan→ingest→反映→push」の**手順だけ**を持つ。手順そのもの（世帯ごとカーソル・
/// pull 後のローカル再読込・送れた分だけ high-water 前進）を `swift test` で検証できるようにする。
/// 設計: docs/supabase-adapter-design.md §7.5 / docs/remote-grading-spec.md
public enum ReviewSyncRunner {
    /// 世帯ごとのカーソルキー（`WordSyncRunner.cursorKey` と同義。世帯切替での取りこぼし防止）。
    public static func cursorKey(table: String, householdID: UUID) -> String {
        "\(table):\(householdID.uuidString)"
    }

    public struct MergeOutcome: Sendable {
        /// pull 由来を確定したあとの状態（ingest 済み＋pull カーソル前進）。呼び出し側が永続化する。
        public let state: ReviewSyncState
        /// 送信対象（`updatedAt` 昇順）。`push` フェーズに渡す。
        public let toPush: [ReviewRecord]

        public init(state: ReviewSyncState, toPush: [ReviewRecord]) {
            self.state = state
            self.toPush = toPush
        }
    }

    /// フェーズ1: pull → （原子的に）plan＋UI 反映 → ingest → pull カーソル前進。
    ///
    /// ⚠️ サイドカー基準は **pull で確定した分（`merged` − `toPush`）だけ**前進させる。送信対象
    /// （`toPush`）の基準前進は **push 成功後**（`push(...)` 内の ingest）に行う。フェーズ1で送信対象
    /// まで ingest すると、push が失敗してこの state が永続化された場合に次サイクルの `project` が
    /// 「変更なし」と誤判定し、未送信のローカル採点が二度と push されず取りこぼす。
    public static func pullAndMerge(
        table: String,
        householdID: UUID,
        state: ReviewSyncState,
        transport: some ReviewSyncTransport,
        sink: some ReviewLocalSink,
        now: Date,
        profileID: UUID? = nil
    ) async throws -> MergeOutcome {
        let key = cursorKey(table: table, householdID: householdID)

        let page = try await transport.pullAll(table: table, since: state.cursors.pullCursor(for: key))
        let remote = page.rows.compactMap(ReviewWire.record(from:))
        let pushedThrough = state.cursors.pushedThrough(for: key)
        let sidecar = state.sidecar

        // 最新ローカル採点の読取・計画・反映を sink 側で原子的に行う。
        let plan = await sink.planAndApply { localReviews in
            ReviewSyncReducer.plan(
                localReviews: localReviews,
                remote: remote,
                store: sidecar,
                now: now,
                householdID: householdID,
                profileID: profileID,
                pushedThrough: pushedThrough
            )
        }

        // pull で確定した分（送信対象を除く）だけ基準を前進。送信対象は push 成功後に ingest する。
        let toPushIDs = Set(plan.toPush.map(\.id))
        let pullSettled = plan.merged.filter { !toPushIDs.contains($0.id) }

        var newState = state
        newState.sidecar.ingest(pullSettled)
        newState.cursors.advancePull(table: key, to: page.nextCursor)

        return MergeOutcome(state: newState, toPush: plan.toPush)
    }

    /// フェーズ2: エンコード → push → （成功後に）サイドカー基準前進＋high-water 前進。
    /// high-water は **実際に送れた record** からのみ算出する。push が空なら state を変えずに返す。
    /// 失敗時は例外を伝播し、サイドカー基準も high-water も進めない（→ 次サイクルで再送・取りこぼさない）。
    public static func push(
        table: String,
        householdID: UUID,
        state: ReviewSyncState,
        toPush: [ReviewRecord],
        transport: some ReviewSyncTransport
    ) async throws -> ReviewSyncState {
        let key = cursorKey(table: table, householdID: householdID)

        let pushable = toPush.compactMap { record in
            ReviewWire.wire(from: record).map { (record: record, row: $0) }
        }
        guard !pushable.isEmpty else { return state }

        try await transport.push(table: table, rows: pushable.map(\.row))

        // 送信成功後にのみ基準を前進（次サイクルの再 project が「変更なし」になり churn しない）。
        var newState = state
        newState.sidecar.ingest(pushable.map(\.record))
        if let highWater = OutboundSync.highWater(pushable.map(\.record), current: state.cursors.pushedThrough(for: key)) {
            newState.cursors.advancePush(table: key, to: highWater)
        }
        return newState
    }
}
