import Foundation

/// `words` の 1 サイクル同期の**純粋オーケストレータ**（`merge` は純関数・`push` はトランスポート越し）。
///
/// I/O（Supabase）は `WordSyncTransport` に逃がし、ローカル読取〜反映の原子性は呼び出し側
/// （コーディネータ）が `merge` の前後を await なしで同期実行して保つ。ここは「plan→ingest→カーソル前進」
/// の**手順だけ**を持つ。これにより手順そのもの（世帯ごとカーソル・送れた分だけ high-water 前進）を
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
        /// UI へ反映する生存レコード（`LastWriteWins.live(merged)`）。呼び出し側が原子的に反映する。
        public let live: [WordSyncRecord]
        /// 送信対象（`updatedAt` 昇順）。`push` フェーズに渡す。
        public let toPush: [WordSyncRecord]

        public init(state: WordSyncState, live: [WordSyncRecord], toPush: [WordSyncRecord]) {
            self.state = state
            self.live = live
            self.toPush = toPush
        }
    }

    /// フェーズ1（純粋）: pull 済みページ＋最新ローカル＋現状態 → plan → (新 state, 反映すべき live, toPush)。
    ///
    /// I/O を一切持たない **純関数**。呼び出し側（コーディネータ）が
    /// 「pull(await) → スコープ再確認 → `localWords` 読取 → `merge` → `live` 反映 → 永続化」を
    /// **await を挟まず同期**に連続実行することで原子性を保つ（pull の await 中に入った切替は、
    /// コーディネータのスコープ・ガードで検出して副作用ごと破棄する）。これにより旧 `WordLocalSink`
    /// のアクターホップ跨ぎ原子性トリックが不要になり、手順を `swift test` で純粋に検証できる。
    ///
    /// ⚠️ サイドカー基準は **pull で確定した分（`merged` − `toPush`）だけ**前進させる。送信対象
    /// （`toPush`）の基準前進は **push 成功後**（`push(...)` 内の ingest）に行う。フェーズ1で
    /// 送信対象まで ingest すると、push が失敗してこの state が永続化された場合に次サイクルの
    /// `project` が「変更なし」と誤判定し、未送信のローカル変更が二度と push されず取りこぼす。
    public static func merge(
        table: String,
        householdID: UUID,
        state: WordSyncState,
        page: WordPullPage,
        localWords: [LocalWord],
        now: Date,
        profileID: UUID? = nil
    ) -> MergeOutcome {
        let key = cursorKey(table: table, householdID: householdID)

        let remote = page.rows.compactMap(WordWire.record(from:))
        let pushedThrough = state.cursors.pushedThrough(for: key)

        let plan = WordSyncReducer.plan(
            localWords: localWords,
            remote: remote,
            store: state.sidecar,
            now: now,
            householdID: householdID,
            profileID: profileID,
            pushedThrough: pushedThrough
        )

        // pull で確定した分（送信対象を除く）だけ基準を前進。送信対象は push 成功後に ingest する。
        let toPushIDs = Set(plan.toPush.map(\.id))
        let pullSettled = plan.merged.filter { !toPushIDs.contains($0.id) }

        var newState = state
        newState.sidecar.ingest(pullSettled)
        newState.cursors.advancePull(table: key, to: page.nextCursor)

        return MergeOutcome(state: newState, live: LastWriteWins.live(plan.merged), toPush: plan.toPush)
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
