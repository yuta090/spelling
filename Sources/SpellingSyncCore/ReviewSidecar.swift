import Foundation

/// ローカル側の採点入力（射影の素材）。親がアプリで付けた採点状態を、同期メタ無しで表す。
/// `id` は `ReviewIdentity.reviewID(forAttempt:)` の決定的ID（attempt 1件＝review 1件）。
public struct LocalReview: Equatable, Sendable {
    public var id: UUID
    public var payload: ReviewPayload
    /// 新規採番時に `SyncMetadata.createdAt` に使う（初回採点時刻相当）。
    public var createdAt: Date

    public init(id: UUID, payload: ReviewPayload, createdAt: Date) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
    }

    /// attempt と採点内容から、決定的IDで `LocalReview` を組み立てる便利初期化。
    public init(payload: ReviewPayload, createdAt: Date) {
        self.init(id: ReviewIdentity.reviewID(forAttempt: payload.attemptID), payload: payload, createdAt: createdAt)
    }
}

/// 採点（review）の **サイドカー同期ストア**。`WordSidecarStore` と同じ設計を review に適用。
///
/// アプリの採点 UI 状態（同期列を持たない）を改変せず、`id → (SyncMetadata, 指紋)` を別管理する。
/// `project` がローカル採点に同期メタデータを射影し、内容変化（採点し直し）・論理削除（採点取消）を
/// 検出して `ReviewRecord` 群を返す。`ingest` で「同期済み/取得済みの真実」を取り込み、次回 `project`
/// の dirty 判定基準を前進させる。永続化のため `Codable`。
/// 設計: docs/supabase-adapter-design.md §7.5 / docs/remote-grading-spec.md
public struct ReviewSidecarStore: Equatable, Codable, Sendable {
    private struct Entry: Equatable, Codable, Sendable {
        var metadata: SyncMetadata
        var payload: ReviewPayload
    }

    private var entries: [UUID: Entry]

    /// 変更時刻を過去版より厳密に後へ保つ最小刻み（1ms）。端末クロック逆行でも編集・削除が前版に
    /// タイ/敗北しないことを保証する（`WordSidecarStore` と同じ）。
    private static let minimumTick: TimeInterval = 0.001

    private static func bump(after floor: Date, now: Date) -> Date {
        now > floor ? now : floor.addingTimeInterval(minimumTick)
    }

    public init() {
        entries = [:]
    }

    public func metadata(for id: UUID) -> SyncMetadata? {
        entries[id]?.metadata
    }

    public var count: Int { entries.count }

    /// 「同期済み/取得済みの真実」を取り込み、dirty 判定の基準を前進させる。
    /// 同 id が複数来たら `LastWriteWins` で勝者を採り、順序非依存にする。
    public mutating func ingest(_ records: [ReviewRecord]) {
        for record in records {
            if let existing = entries[record.id] {
                let winner = LastWriteWins.resolve(
                    ReviewRecord(sync: existing.metadata, payload: existing.payload),
                    record
                )
                entries[record.id] = Entry(metadata: winner.sync, payload: winner.payload)
            } else {
                entries[record.id] = Entry(metadata: record.sync, payload: record.payload)
            }
        }
    }

    /// ローカル採点へ同期メタデータを射影し、`ReviewRecord` 群を返す。
    ///
    /// 規則（`WordSidecarStore.project` と同じ）:
    /// - **新規 id**: `createdAt`=初回採点時刻、`updatedAt`=now、世帯/プロファイルを付与。
    /// - **既知・内容不変・生存中**: メタ据え置き。
    /// - **既知・内容変化（採点し直し）/復活**: `updatedAt`=now（bump）、`deletedAt` クリア。
    /// - **サイドカーにあるがローカルに無い id（採点取消）**: 論理削除。既に墓石なら据え置き。
    ///
    /// スコープ: `householdID` が `nil` なら空。墓石化はアクティブ世帯のエントリのみ。
    /// 戻り値は id 昇順で安定ソート。`project` は非破壊（push/pull 成功後に勝者を `ingest`）。
    public func project(
        localReviews: [LocalReview],
        now: Date,
        householdID: UUID?,
        profileID: UUID?
    ) -> [ReviewRecord] {
        guard let householdID else { return [] }

        var byID: [UUID: LocalReview] = [:]
        for review in localReviews { byID[review.id] = review }

        var result: [ReviewRecord] = []

        for (id, review) in byID {
            if let entry = entries[id] {
                let unchanged = entry.payload == review.payload && !entry.metadata.isDeleted
                if unchanged {
                    result.append(ReviewRecord(sync: entry.metadata, payload: entry.payload))
                } else {
                    var meta = entry.metadata
                    meta.updatedAt = Self.bump(after: entry.metadata.updatedAt, now: now)
                    meta.deletedAt = nil
                    result.append(ReviewRecord(sync: meta, payload: review.payload))
                }
            } else {
                let meta = SyncMetadata(
                    id: id,
                    householdID: householdID,
                    profileID: profileID,
                    createdAt: review.createdAt,
                    updatedAt: now
                )
                result.append(ReviewRecord(sync: meta, payload: review.payload))
            }
        }

        for (id, entry) in entries
        where byID[id] == nil && entry.metadata.householdID == householdID {
            if entry.metadata.isDeleted {
                result.append(ReviewRecord(sync: entry.metadata, payload: entry.payload))
            } else {
                var meta = entry.metadata
                let stamp = Self.bump(after: entry.metadata.updatedAt, now: now)
                meta.updatedAt = stamp
                meta.deletedAt = stamp
                result.append(ReviewRecord(sync: meta, payload: entry.payload))
            }
        }

        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
