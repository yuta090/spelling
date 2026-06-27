import Foundation

/// review の **wire 表現**（Supabase `reviews` 行を SDK 非依存のプリミティブで持つ箱）。
///
/// アプリ側 DTO ⇄ コアの変換は単純な写し替えだけをアプリに残し、判断を要するロジック
/// （RFC3339 のパース/整形・壊れた行の扱い・決定的ID整合チェック）は**ここ（コア）に集約してテスト**する。
/// 設計: docs/remote-grading-spec.md / docs/supabase-adapter-design.md §7.5
public struct ReviewRow: Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var profileID: UUID?
    public var attemptID: UUID
    /// `parent_decision`（"unreviewed"/"approved"/"needsPractice"）。
    public var parentDecision: String
    public var parentExamplePath: String?
    public var reviewedBy: UUID?
    /// `reviewed_at`（RFC3339, UTC, 未採点なら nil）。
    public var reviewedAt: String?
    /// クライアント LWW 時刻（RFC3339, UTC）。
    public var updatedAt: String
    /// 論理削除（RFC3339, 未削除なら nil）。
    public var deletedAt: String?

    public init(
        id: UUID,
        householdID: UUID,
        profileID: UUID?,
        attemptID: UUID,
        parentDecision: String,
        parentExamplePath: String?,
        reviewedBy: UUID?,
        reviewedAt: String?,
        updatedAt: String,
        deletedAt: String?
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.attemptID = attemptID
        self.parentDecision = parentDecision
        self.parentExamplePath = parentExamplePath
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// wire 行 ⇄ 正準同期レコード（`ReviewRecord`）の純粋変換。
public enum ReviewWire {
    /// サーバ行 → 正準同期レコード。
    /// - `updatedAt`、または非 nil の `deletedAt` が解釈できなければ **行ごと落とす**（壊れた行・削除復活の防止）。
    /// - 未知の `parent_decision` も取り込まない（不正値で UI を壊さない）。`reviewed_at` は解釈できなければ nil 扱い（業務時刻のため復活問題は無い）。
    /// - `createdAt`(meta) は DTO に無いため `updatedAt` を流用（情報用途のみ。`WordWire` と同方針）。
    public static func record(from row: ReviewRow) -> ReviewRecord? {
        guard let updated = RFC3339.date(from: row.updatedAt) else { return nil }
        guard let decision = ReviewDecision(rawValue: row.parentDecision) else { return nil }
        let deleted: Date?
        if let deletedString = row.deletedAt {
            guard let parsed = RFC3339.date(from: deletedString) else { return nil }
            deleted = parsed
        } else {
            deleted = nil
        }
        let meta = SyncMetadata(
            id: row.id,
            householdID: row.householdID,
            profileID: row.profileID,
            createdAt: updated,
            updatedAt: updated,
            deletedAt: deleted
        )
        let payload = ReviewPayload(
            attemptID: row.attemptID,
            decision: decision,
            exampleStoragePath: row.parentExamplePath,
            reviewedBy: row.reviewedBy,
            reviewedAt: row.reviewedAt.flatMap(RFC3339.date(from:))
        )
        return ReviewRecord(sync: meta, payload: payload)
    }

    /// 正準同期レコード → 送信用 wire 行。
    /// - `householdID` が無いレコードは送れないため **nil**（呼び出し側で除外）。
    /// - `id` は `uuidv5(attempt_id)` の決定的IDのはずなので、`payload.attemptID` から再計算して**整合を検証**し、
    ///   食い違う（不正に組まれた）レコードは送らない（サーバ unique(attempt_id) 衝突や取り違えを防ぐ）。
    public static func wire(from record: ReviewRecord) -> ReviewRow? {
        guard let householdID = record.sync.householdID else { return nil }
        guard record.sync.id == ReviewIdentity.reviewID(forAttempt: record.payload.attemptID) else { return nil }
        return ReviewRow(
            id: record.sync.id,
            householdID: householdID,
            profileID: record.sync.profileID,
            attemptID: record.payload.attemptID,
            parentDecision: record.payload.decision.rawValue,
            parentExamplePath: record.payload.exampleStoragePath,
            reviewedBy: record.payload.reviewedBy,
            reviewedAt: record.payload.reviewedAt.map(RFC3339.string(from:)),
            updatedAt: RFC3339.string(from: record.sync.updatedAt),
            deletedAt: record.sync.deletedAt.map(RFC3339.string(from:))
        )
    }
}
