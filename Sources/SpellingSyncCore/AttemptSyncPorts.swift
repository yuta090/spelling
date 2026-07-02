import Foundation

/// `pullAll`（attempts）の 1 テーブル取得結果（行＋次カーソル）。`WordPullPage` の attempt 版。
public struct AttemptPullPage: Sendable {
    public let rows: [AttemptRow]
    /// 次回 pull の起点（サーバー採番 `sync_version` の最大）。
    public let nextCursor: Int

    public init(rows: [AttemptRow], nextCursor: Int) {
        self.rows = rows
        self.nextCursor = nextCursor
    }
}

/// 解答試行（attempts）同期のネットワーク境界。attempt は **append-only**（作成後は不変）。
public protocol AttemptSyncTransport: Sendable {
    /// `sync_version > cursor` の差分を全ページ取得する。
    func pullAll(table: String, since cursor: Int) async throws -> AttemptPullPage
    /// サーバー未保持のローカル attempt を upsert する（id 冪等）。
    func push(table: String, rows: [AttemptRow]) async throws
}

/// ローカル（UI）側の境界。アプリは `AppModel` で実装する。
///
/// attempt はサイドカーを持たない（append-only で内容変化しない）ため、`makePlan` に渡すのは
/// ローカルで作成済みの `AttemptSyncRecord`（作成時に `SyncMetadata` を持つ）。原子性の要点は
/// `WordLocalSink`/`ReviewLocalSink` と同じ（読取〜反映を割り込み不可に）。
public protocol AttemptLocalSink: Sendable {
    /// `makePlan` に最新ローカル attempt を渡して計画を作り、`LastWriteWins.live(plan.merged)` を反映し、
    /// 作った plan を返す。読取〜反映は割り込み不可に保つ。
    func planAndApply(_ makePlan: @Sendable ([AttemptSyncRecord]) -> AttemptSyncReducer.Plan) async -> AttemptSyncReducer.Plan
}

/// 永続化する attempt 同期状態。attempt はサイドカー不要なのでカーソル/high-water のみ。
public struct AttemptSyncState: Equatable, Codable, Sendable {
    public var cursors: SyncCursors

    public init(cursors: SyncCursors = SyncCursors()) {
        self.cursors = cursors
    }
}
