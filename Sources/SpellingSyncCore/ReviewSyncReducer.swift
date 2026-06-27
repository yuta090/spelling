import Foundation

/// 採点（review）1 同期サイクル（pull → merge → push）の **純粋な計画**。`WordSyncReducer` の review 版。
///
/// I/O（Supabase pull/push、永続化、UI 反映）はアプリ側の薄い層が担い、**何をマージし何を送るかの
/// 判断はここに集約**してテストする。設計: docs/supabase-adapter-design.md §7.5
public enum ReviewSyncReducer {
    public struct Plan: Equatable, Sendable {
        /// id ごとに LWW 統合した「真実」（tombstone 含む）。サイドカーへ `ingest` し、
        /// `LastWriteWins.live` を UI に反映する素材。
        public let merged: [ReviewRecord]
        /// 送信対象（`updatedAt` 昇順）。`merged` の部分集合。
        public let toPush: [ReviewRecord]

        public init(merged: [ReviewRecord], toPush: [ReviewRecord]) {
            self.merged = merged
            self.toPush = toPush
        }
    }

    /// pull 済みリモート行・ローカル採点・サイドカーから、統合結果と送信対象を決める。
    ///
    /// 手順（`WordSyncReducer.plan` と同じ）:
    /// 1. リモートをアクティブ世帯でスコープ。
    /// 2. サイドカーでローカルを射影（新規/採点し直し/採点取消の墓石化）。
    /// 3. `LastWriteWins.reconcile` で id ごとに統合。
    /// 4. 送信不要を除外: 今回 pull 版と完全一致、またはサイドカー基準から `updatedAt` 不変（取込済みの echo）。
    /// 5. 残りを送信 high-water で絞る。
    public static func plan(
        localReviews: [LocalReview],
        remote: [ReviewRecord],
        store: ReviewSidecarStore,
        now: Date,
        householdID: UUID?,
        profileID: UUID?,
        pushedThrough: Date?
    ) -> Plan {
        let scopedRemote = SyncScope.scoped(remote, householdID: householdID)
        let local = store.project(
            localReviews: localReviews,
            now: now,
            householdID: householdID,
            profileID: profileID
        )
        let merged = LastWriteWins.reconcile(local: local, remote: scopedRemote)

        var remoteByID: [UUID: ReviewRecord] = [:]
        for record in scopedRemote { remoteByID[record.id] = record }

        let changed = merged.filter { record in
            remoteByID[record.id] != record
                && store.metadata(for: record.id)?.updatedAt != record.sync.updatedAt
        }
        let toPush = OutboundSync.pending(changed, pushedThrough: pushedThrough)

        return Plan(merged: merged, toPush: toPush)
    }
}
