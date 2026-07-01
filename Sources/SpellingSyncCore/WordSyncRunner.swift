import Foundation

/// `words` の 1 サイクル同期を **ポート越しに**実行する純粋オーケストレータ。
///
/// I/O（Supabase・UserDefaults・AppModel）は `WordSyncTransport`/`WordLocalSink` の
/// 実装に逃がし、ここは「pull→plan→ingest→反映→push」の**手順だけ**を持つ。これにより
/// 手順そのもの（世帯ごとカーソル・pull 後のローカル再読込・送れた分だけ high-water 前進）を
/// アプリの XCTest ターゲット無しで `swift test` で検証できる。
/// 設計: docs/supabase-adapter-design.md §7.5
public enum WordSyncRunner {
    /// 世帯ごとのカーソルキー。`pullAll` は RLS 範囲の全世帯を返すため、テーブル単位だと
    /// 世帯切替時に前世帯のカーソルが進んでいて新世帯の行を取りこぼす。世帯ごとに分けて防ぐ。
    public static func cursorKey(table: String, householdID: UUID) -> String {
        "\(table):\(householdID.uuidString)"
    }

    public struct MergeOutcome: Sendable {
        /// pull 由来を確定したあとの状態（ingest 済み＋pull カーソル前進）。呼び出し側が永続化する。
        public let state: WordSyncState
        /// 送信対象（`updatedAt` 昇順）。`push` フェーズに渡す。
        public let toPush: [WordSyncRecord]

        public init(state: WordSyncState, toPush: [WordSyncRecord]) {
            self.state = state
            self.toPush = toPush
        }
    }

    /// フェーズ1: pull → （原子的に）plan＋UI 反映 → ingest → pull カーソル前進。
    /// ローカル読取と反映は `sink.planAndApply` 内で **割り込み不可** に行うため、pull の await 中や
    /// 計画中に入った編集を stale なマージで上書きしない。push が失敗しても、ここで返す `state` を
    /// 永続化すれば取得済みデータは保持される。
    ///
    /// ⚠️ サイドカー基準は **pull で確定した分（`merged` − `toPush`）だけ**前進させる。送信対象
    /// （`toPush`）の基準前進は **push 成功後**（`push(...)` 内の ingest）に行う。フェーズ1で
    /// 送信対象まで ingest すると、push が失敗してこの state が永続化された場合に次サイクルの
    /// `project` が「変更なし」と誤判定し、未送信のローカル変更が二度と push されず取りこぼす。
    public static func pullAndMerge(
        table: String,
        householdID: UUID,
        state: WordSyncState,
        transport: some WordSyncTransport,
        sink: some WordLocalSink,
        now: Date,
        profileID: UUID? = nil
    ) async throws -> MergeOutcome {
        let key = cursorKey(table: table, householdID: householdID)

        let page = try await transport.pullAll(table: table, since: state.cursors.pullCursor(for: key))
        let remote = page.rows.compactMap(WordWire.record(from:))
        let pushedThrough = state.cursors.pushedThrough(for: key)
        let sidecar = state.sidecar

        // 最新ローカルの読取・計画・反映を sink 側で原子的に行う。
        let plan = await sink.planAndApply { localWords in
            WordSyncReducer.plan(
                localWords: localWords,
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
    /// high-water は **実際に送れた record** からのみ算出する（エンコード失敗分で進めない）。
    /// push が空なら state を変えずに返す。失敗時は例外を伝播し、サイドカー基準も high-water も
    /// 進めない（→ 次サイクルの `project` が同じ変更を再び `toPush` に乗せ、取りこぼさない）。
    public static func push(
        table: String,
        householdID: UUID,
        state: WordSyncState,
        toPush: [WordSyncRecord],
        transport: some WordSyncTransport
    ) async throws -> WordSyncState {
        let key = cursorKey(table: table, householdID: householdID)

        let pushable = toPush.compactMap { record in
            WordWire.wire(from: record).map { (record: record, row: $0) }
        }
        guard !pushable.isEmpty else { return state }

        try await transport.push(table: table, rows: pushable.map(\.row))

        // 送信成功後にのみ基準を前進。これでエンコード可能だった送信済みレコードが
        // 次サイクルで churn せず（再 project が「変更なし」になる）、かつ未送信分は残る。
        var newState = state
        newState.sidecar.ingest(pushable.map(\.record))
        if let highWater = OutboundSync.highWater(pushable.map(\.record), current: state.cursors.pushedThrough(for: key)) {
            newState.cursors.advancePush(table: key, to: highWater)
        }
        return newState
    }
}
