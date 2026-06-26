import Foundation

/// `pullAll` の 1 テーブル取得結果（行＋次カーソル）。
public struct WordPullPage: Sendable {
    public let rows: [WordRow]
    /// 次回 pull の起点（サーバー採番 `sync_version` の最大）。
    public let nextCursor: Int

    public init(rows: [WordRow], nextCursor: Int) {
        self.rows = rows
        self.nextCursor = nextCursor
    }
}

/// 同期のネットワーク境界（pull/push）。アプリは Supabase（`SyncEngine`）で実装し、
/// テストはフェイクで差し替える。コアは SDK を知らないので wire 型 `WordRow` を通貨にする。
public protocol WordSyncTransport: Sendable {
    /// `sync_version > cursor` の差分を全ページ取得する（tombstone 含む）。
    func pullAll(table: String, since cursor: Int) async throws -> WordPullPage
    /// 未送信行を upsert する（サーバー LWW ガード前提）。
    func push(table: String, rows: [WordRow]) async throws
}

/// ローカル（UI）側の境界。アプリは `AppModel` で実装する。
///
/// **原子性が要点**: 「最新ローカル読取 → `makePlan(local)` → 生存レコードを UI 反映」を
/// **1 回の呼び出しで連続実行**し、その間に他のローカル編集を割り込ませない。
/// 読取と反映を別メソッドに分けると、その隙（アクターのホップ）に入った編集を
/// stale なマージ結果で上書きしてしまう（= 編集の取りこぼし）。実装は MainActor 上で
/// 内部 await を挟まずに完結させること。
public protocol WordLocalSink: Sendable {
    /// `makePlan` に最新ローカルを渡して計画を作り、`LastWriteWins.live(plan.merged)` を反映し、
    /// 作った plan を返す。読取〜反映は割り込み不可に保つ。
    func planAndApply(_ makePlan: @Sendable ([LocalWord]) -> WordSyncReducer.Plan) async -> WordSyncReducer.Plan
}

/// 永続化する同期状態（サイドカー基準＋テーブル別カーソル/high-water）。
/// アプリは `UserDataStore` に保存する。
public struct WordSyncState: Equatable, Codable, Sendable {
    public var sidecar: WordSidecarStore
    public var cursors: SyncCursors

    public init(sidecar: WordSidecarStore = WordSidecarStore(), cursors: SyncCursors = SyncCursors()) {
        self.sidecar = sidecar
        self.cursors = cursors
    }
}
