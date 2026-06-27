import Foundation

/// 解答試行（attempt）1 同期サイクルの **純粋な計画**。
///
/// attempt は **append-only / 作成後は不変**（採点は別行 `reviews`）。よって単語/採点のような
/// 「内容変化の dirty 検出」や「ローカル消滅→墓石化」は不要で、サイドカーも持たない。
/// 送信対象は「サーバにまだ無いローカル attempt」だけ。再送防止は二重で担保する:
///  - サーバに既にある（今回 pull に含まれる）id は除外、
///  - さらに送信 high-water（`pushedThrough`）未満を除外。
/// どちらも漏れても upsert は id 冪等なので安全側。
public enum AttemptSyncReducer {
    public struct Plan: Equatable, Sendable {
        /// id ごとに LWW 統合した「真実」。サーバ反映/UI 用。
        public let merged: [AttemptSyncRecord]
        /// 送信対象（`updatedAt` 昇順）。
        public let toPush: [AttemptSyncRecord]

        public init(merged: [AttemptSyncRecord], toPush: [AttemptSyncRecord]) {
            self.merged = merged
            self.toPush = toPush
        }
    }

    /// - Parameters:
    ///   - localAttempts: ローカルで作成済みの attempt（作成時に `SyncMetadata` を持つ）。
    ///   - remote: pull した行を `AttemptSyncRecord` に変換したもの（スコープ前でよい）。
    ///   - pushedThrough: このテーブルの送信済み最大 `updatedAt`。
    public static func plan(
        localAttempts: [AttemptSyncRecord],
        remote: [AttemptSyncRecord],
        householdID: UUID?,
        pushedThrough: Date?
    ) -> Plan {
        let scopedRemote = SyncScope.scoped(remote, householdID: householdID)
        let scopedLocal = SyncScope.scoped(localAttempts, householdID: householdID)
        let merged = LastWriteWins.reconcile(local: scopedLocal, remote: scopedRemote)

        let remoteIDs = Set(scopedRemote.map { $0.id })
        // append-only: サーバ未保持のローカル分のみ送信候補（内容変化は起き得ない）。
        let candidates = scopedLocal.filter { !remoteIDs.contains($0.id) }
        let toPush = OutboundSync.pending(candidates, pushedThrough: pushedThrough)

        return Plan(merged: merged, toPush: toPush)
    }
}
