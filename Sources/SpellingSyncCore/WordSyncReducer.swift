import Foundation

/// 1 同期サイクル（pull → merge → push）の **純粋な計画**。
///
/// I/O（Supabase の pull/push、UserDefaults 永続化、UI への反映）はアプリ側の薄い
/// `WordSyncCoordinator` が担い、**何をマージし何を送るかの判断はすべてここに集約**してテストする。
/// 設計: docs/supabase-adapter-design.md §7.5
public enum WordSyncReducer {
    public struct Plan: Equatable, Sendable {
        /// id ごとに LWW 統合した「真実」（tombstone 含む）。
        /// サイドカーへ `ingest` し、`LastWriteWins.live` を UI に反映する素材。
        public let merged: [WordSyncRecord]
        /// 送信対象（`updatedAt` 昇順）。`merged` の部分集合。
        public let toPush: [WordSyncRecord]

        public init(merged: [WordSyncRecord], toPush: [WordSyncRecord]) {
            self.merged = merged
            self.toPush = toPush
        }
    }

    /// pull 済みリモート行・ローカル単語・サイドカーから、統合結果と送信対象を決める。
    ///
    /// 手順:
    /// 1. リモートをアクティブ世帯でスコープ（別世帯の混入・誤削除を防ぐ）。
    /// 2. サイドカーでローカルを射影（新規採番・内容変化・消滅の墓石化）。
    /// 3. `LastWriteWins.reconcile` で id ごとに統合。
    /// 4. **送信不要なレコードを除外**:
    ///    - 今回 pull した版と完全一致（サーバーが既に持つ）。
    ///    - サイドカー基準（前回 ingest 済みの版）から `updatedAt` が変わっていない
    ///      ＝ローカル変更が無く同期済み。これにより、過去に pull して取り込んだだけの
    ///      リモート行を、次サイクル以降に**送り返さない**（送り返すと push high-water が
    ///      リモートの（未来かもしれない）`updatedAt` まで進み、以後の新規ローカル語が
    ///      strict `>` で恒久的に弾かれる事故を防ぐ）。
    /// 5. 残りを送信 high-water (`pushedThrough`) で絞る（送信済みの再送を防ぐ）。
    ///
    /// - Parameters:
    ///   - remote: pull した行を `WordSyncRecord` に変換したもの（スコープ前でよい）。
    ///   - store: 現在のサイドカー（前回までの同期基準。非破壊で参照のみ）。
    ///   - now: 射影の基準時刻（呼び出し側が渡す）。
    ///   - pushedThrough: このテーブルの送信済み最大 `updatedAt`。
    public static func plan(
        localWords: [LocalWord],
        remote: [WordSyncRecord],
        store: WordSidecarStore,
        now: Date,
        householdID: UUID?,
        profileID: UUID?,
        pushedThrough: Date?
    ) -> Plan {
        let scopedRemote = SyncScope.scoped(remote, householdID: householdID)
        let local = store.project(
            localWords: localWords,
            now: now,
            householdID: householdID,
            profileID: profileID
        )
        let merged = LastWriteWins.reconcile(local: local, remote: scopedRemote)

        var remoteByID: [UUID: WordSyncRecord] = [:]
        for record in scopedRemote { remoteByID[record.id] = record }

        // 送信対象から除外: (a) 今回 pull した版と完全一致、(b) サイドカー基準から
        // updatedAt が不変（＝ローカル変更が無く、取り込み済みのリモート行の echo）。
        // project は内容変更時に updatedAt を厳密前進させるので、updatedAt 不変＝未変更。
        let changed = merged.filter { record in
            remoteByID[record.id] != record
                && store.metadata(for: record.id)?.updatedAt != record.sync.updatedAt
        }
        let toPush = OutboundSync.pending(changed, pushedThrough: pushedThrough)

        return Plan(merged: merged, toPush: toPush)
    }
}
