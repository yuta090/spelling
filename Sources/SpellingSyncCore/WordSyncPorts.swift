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
    /// `profileID` を渡すと **そのプロファイルの行だけ** に絞る（Phase 5b: 親認証は世帯の全子行が
    /// 見えるため、RLS 任せにせずクエリ側で profile_id を明示フィルタして他児データの混入を防ぐ）。
    /// `nil` は絞り込みなし（後方互換・テスト用）。
    func pullAll(table: String, since cursor: Int, profileID: UUID?) async throws -> WordPullPage
    /// 未送信行を upsert する（サーバー LWW ガード前提）。
    func push(table: String, rows: [WordRow]) async throws
}

/// ローカル読取〜反映の原子性は、コーディネータが `WordSyncRunner.merge`（純関数）の前後で
/// **await を挟まず同期**に「localWords 読取 → merge → live 反映 → 永続化」を実行して保つ。
/// 旧 `WordLocalSink`（アクターホップ跨ぎの原子性トリック）は不要になったため撤去した。

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
