import Foundation

/// 送信（プッシュ）側の純粋ロジック。
///
/// 「どのローカルレコードがまだサーバーへ送られていないか」を、
/// クライアントの `updatedAt`（LWW時刻）に対する high-water mark で判定する。
/// I/O（Supabaseへの upsert）はアプリ側の薄い層が担い、ここはテスト可能な選択ロジックに専念する。
public enum OutboundSync {
    /// `pushedThrough` より後に更新された未送信レコードを `updatedAt` 昇順で返す。
    /// tombstone（論理削除）も「変更」として送信対象に含める。
    /// - Parameter pushedThrough: 送信済みの最大 updatedAt（nil なら全件が対象）
    public static func pending<R: SyncableRecord>(_ records: [R], pushedThrough: Date?) -> [R] {
        records
            .filter { record in
                guard let cutoff = pushedThrough else { return true }
                return record.sync.updatedAt > cutoff
            }
            .sorted { $0.sync.updatedAt < $1.sync.updatedAt }
    }

    /// 送信に成功したレコード群から、新しい high-water mark を求める。
    /// 送信が空なら `current` を維持する。
    ///
    /// ⚠️ 契約: high-water は **対象テーブルの pending 全件を push し終えてから** 進めること。
    /// 部分送信の途中で進めると、同時刻(`updatedAt` が等しい)の未送信行を `pending` の strict `>` が
    /// 恒久的に除外してしまう。バッチ全体の成功後にのみ `highWater` を適用する。
    public static func highWater<R: SyncableRecord>(_ pushed: [R], current: Date?) -> Date? {
        guard let maxPushed = pushed.map({ $0.sync.updatedAt }).max() else { return current }
        guard let current else { return maxPushed }
        return Swift.max(maxPushed, current)
    }
}
