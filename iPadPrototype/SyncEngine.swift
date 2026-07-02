import Foundation

/// Supabase との差分同期エンジン（第1段：プル）。
///
/// プルは **`sync_version`（サーバー採番の単調増加 bigint）カーソル**で差分取得する。
/// 単一列・厳密単調・タイ無しなので、ページングや同時刻でも取りこぼさない
/// （`server_changed_at` の文字列比較/同時刻タイ問題を回避）。
/// tombstone（`deleted_at`）行も取得し、呼び出し側のローカルキャッシュで削除を反映する。
///
/// 次段：プッシュ（upsert＋サーバーLWWガード）、SpellingSyncCore.LastWriteWins でのマージ、
/// 決定論UUID、Storage。設計: docs/supabase-adapter-design.md
@MainActor
final class SyncEngine {
    private let service: SupabaseService
    /// 1ページの最大件数。返却件数がこれ未満なら最終ページ。
    let pageSize: Int

    init(service: SupabaseService = .shared, pageSize: Int = 500) {
        self.service = service
        self.pageSize = pageSize
    }

    struct Page<T: SyncedRow> {
        let rows: [T]
        let nextCursor: Int
        let hasMore: Bool
    }

    /// 1ページ分を `sync_version > cursor` の昇順で取得する。
    /// - Parameters:
    ///   - cursor: 前回同期で得た最大 sync_version（初回は 0）
    ///   - profileID: 指定すると `profile_id = profileID` に絞る（Phase 5b: 親認証は世帯の全子行が
    ///     見えるため、RLS 任せにせずクエリ側で明示フィルタして他児データの混入を防ぐ）。`nil` は絞らない。
    func pullPage<T: SyncedRow>(_ type: T.Type, since cursor: Int, profileID: UUID? = nil) async throws -> Page<T> {
        var query = service.client
            .from(T.table)
            .select()
            .gt("sync_version", value: cursor)
        if let profileID {
            query = query.eq("profile_id", value: profileID.uuidString)
        }
        let rows: [T] = try await query
            .order("sync_version", ascending: true)
            .limit(pageSize)
            .execute()
            .value
        // 昇順なので最後の行が最大。max() ではなく順序済み結果の末尾を採る。
        let nextCursor = rows.last?.syncVersion ?? cursor
        return Page(rows: rows, nextCursor: nextCursor, hasMore: rows.count == pageSize)
    }

    /// 最終ページまで全ページを取得する（tombstone含む）。`profileID` で 1 プロファイルに絞れる。
    func pullAll<T: SyncedRow>(_ type: T.Type, since cursor: Int, profileID: UUID? = nil) async throws -> (rows: [T], nextCursor: Int) {
        var all: [T] = []
        var c = cursor
        while true {
            let page = try await pullPage(type, since: c, profileID: profileID)
            all.append(contentsOf: page.rows)
            c = page.nextCursor
            if !page.hasMore { break }
        }
        return (all, c)
    }

    // MARK: - プッシュ

    /// 未送信レコード（`SpellingSyncCore.OutboundSync.pending` で選んだもの）を upsert する。
    /// 競合解決はサーバーの LWW ガード（古い `updated_at` は無視）が担保するため、
    /// クライアントは素直に upsert してよい。論理削除は `deletedAt` を立てた行を送る。
    ///
    /// ⚠️ 適用範囲: `onConflict: "id"` のため、**id 主キー以外の論理unique制約を持たないテーブル
    /// （現状 profiles / words）に限定**する。`srs_cards`(profile_id,word_id) 等は、別IDで
    /// 論理重複を作らないよう **決定論UUID 導入後**に対応する（それまで push 対象にしない）。
    /// ⚠️ `returning: .minimal` のため、ガードに弾かれた行は判別できない。high-water は
    /// 「**送信済**」を意味し「サーバー適用済」ではない。整合は後続の pull で取る。
    /// ⚠️ `updatedAt` は **UTCのISO8601(RFC3339)** 文字列で渡すこと（LWW比較の一貫性のため）。
    func push<T: UpsertRow>(_ rows: [T]) async throws {
        guard !rows.isEmpty else { return }
        try await service.client
            .from(T.table)
            .upsert(rows, onConflict: "id", returning: .minimal)
            .execute()
    }
}
