import Foundation

/// 解答試行（attempts）の 1 サイクル同期を **ポート越しに**実行する純粋オーケストレータ。
///
/// attempt は **append-only / 作成後は不変**（採点は別行 `reviews`）。よってサイドカー（dirty 検出・
/// 墓石化）は不要で、状態はカーソル/high-water のみ。手順は「pull→plan→UI 反映→push（サーバ未保持分）」。
/// 再送防止は二重（pull に含まれる id 除外＋送信 high-water 未満除外）で、どちらも漏れても upsert は
/// id 冪等なので安全側。設計: docs/supabase-adapter-design.md §7.5 / docs/remote-grading-spec.md
public enum AttemptSyncRunner {
    /// 世帯ごとのカーソルキー（`WordSyncRunner.cursorKey` と同義）。
    public static func cursorKey(table: String, householdID: UUID) -> String {
        "\(table):\(householdID.uuidString)"
    }

    public struct MergeOutcome: Sendable {
        /// pull カーソルを前進させた状態。呼び出し側が永続化する。
        public let state: AttemptSyncState
        /// 送信対象（サーバ未保持のローカル attempt・`updatedAt` 昇順）。`push` フェーズに渡す。
        public let toPush: [AttemptSyncRecord]

        public init(state: AttemptSyncState, toPush: [AttemptSyncRecord]) {
            self.state = state
            self.toPush = toPush
        }
    }

    /// フェーズ1: pull → （原子的に）plan＋UI 反映 → pull カーソル前進。
    /// サイドカーが無いので ingest は無く、pull カーソルのみ前進させる。送信対象の high-water 前進は
    /// push 成功後（`push(...)`）に行う。
    public static func pullAndMerge(
        table: String,
        householdID: UUID,
        state: AttemptSyncState,
        transport: some AttemptSyncTransport,
        sink: some AttemptLocalSink
    ) async throws -> MergeOutcome {
        let key = cursorKey(table: table, householdID: householdID)

        let page = try await transport.pullAll(table: table, since: state.cursors.pullCursor(for: key))
        let remote = page.rows.compactMap(AttemptWire.record(from:))
        let pushedThrough = state.cursors.pushedThrough(for: key)

        // 最新ローカル attempt の読取・計画・反映を sink 側で原子的に行う。
        let plan = await sink.planAndApply { localAttempts in
            AttemptSyncReducer.plan(
                localAttempts: localAttempts,
                remote: remote,
                householdID: householdID,
                pushedThrough: pushedThrough
            )
        }

        var newState = state
        newState.cursors.advancePull(table: key, to: page.nextCursor)

        return MergeOutcome(state: newState, toPush: plan.toPush)
    }

    /// フェーズ2: エンコード → push → （成功後に）high-water 前進。
    /// high-water は **実際に送れた record** からのみ算出する。push が空なら state を変えずに返す。
    /// 失敗時は例外を伝播し high-water を進めない（→ 次サイクルで再送・取りこぼさない）。
    public static func push(
        table: String,
        householdID: UUID,
        state: AttemptSyncState,
        toPush: [AttemptSyncRecord],
        transport: some AttemptSyncTransport
    ) async throws -> AttemptSyncState {
        let key = cursorKey(table: table, householdID: householdID)

        let pushable = toPush.compactMap { record in
            AttemptWire.wire(from: record).map { (record: record, row: $0) }
        }
        guard !pushable.isEmpty else { return state }

        try await transport.push(table: table, rows: pushable.map(\.row))

        var newState = state
        if let highWater = OutboundSync.highWater(pushable.map(\.record), current: state.cursors.pushedThrough(for: key)) {
            newState.cursors.advancePush(table: key, to: highWater)
        }
        return newState
    }
}
