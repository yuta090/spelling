import Foundation

/// `pullAll`（reviews）の 1 テーブル取得結果（行＋次カーソル）。`WordPullPage` の review 版。
public struct ReviewPullPage: Sendable {
    public let rows: [ReviewRow]
    /// 次回 pull の起点（サーバー採番 `sync_version` の最大）。
    public let nextCursor: Int

    public init(rows: [ReviewRow], nextCursor: Int) {
        self.rows = rows
        self.nextCursor = nextCursor
    }
}

/// 採点（reviews）同期のネットワーク境界。アプリは Supabase（`SyncEngine`）で実装し、
/// テストはフェイクで差し替える。コアは SDK を知らないので wire 型 `ReviewRow` を通貨にする。
public protocol ReviewSyncTransport: Sendable {
    /// `sync_version > cursor` の差分を全ページ取得する（tombstone 含む）。
    func pullAll(table: String, since cursor: Int) async throws -> ReviewPullPage
    /// 未送信行を upsert する（`id` は決定的なのでサーバー `unique(attempt_id)` と衝突しない）。
    func push(table: String, rows: [ReviewRow]) async throws
}

/// ローカル（UI）側の境界。アプリは `AppModel` で実装する。
///
/// **原子性が要点**（`WordLocalSink` と同じ）: 「最新ローカル読取 → `makePlan(local)` → 生存
/// レコードを UI 反映」を **1 回の呼び出しで連続実行**し、その間に他のローカル編集（親の採点）を
/// 割り込ませない。実装は MainActor 上で内部 await を挟まずに完結させること。
public protocol ReviewLocalSink: Sendable {
    /// `makePlan` に最新ローカル採点を渡して計画を作り、`LastWriteWins.live(plan.merged)` を反映し、
    /// 作った plan を返す。読取〜反映は割り込み不可に保つ。
    func planAndApply(_ makePlan: @Sendable ([LocalReview]) -> ReviewSyncReducer.Plan) async -> ReviewSyncReducer.Plan
}

/// 永続化する採点同期状態（サイドカー基準＋テーブル別カーソル/high-water）。
/// アプリは `UserDataStore` に保存する。`WordSyncState` の review 版。
public struct ReviewSyncState: Equatable, Codable, Sendable {
    public var sidecar: ReviewSidecarStore
    public var cursors: SyncCursors

    public init(sidecar: ReviewSidecarStore = ReviewSidecarStore(), cursors: SyncCursors = SyncCursors()) {
        self.sidecar = sidecar
        self.cursors = cursors
    }
}
