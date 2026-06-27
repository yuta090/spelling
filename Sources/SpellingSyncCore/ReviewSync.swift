import Foundation

/// 親の採点（review）の**同期レコード契約と決定的ID**。リモート採点の同期（本筋B）の土台。
///
/// サーバ `public.reviews(attempt_id unique, parent_decision, parent_example_path, reviewed_by, ...)` に対応。
/// reviews は **attempt 1件につき1件**（`unique(attempt_id)`）なので、レコードIDは `uuidv5(attempt_id)` で
/// 決定的に採番する → 複数端末が同時に同じ attempt を採点しても**同一IDに収束**する。
/// 競合解決は汎用の `LastWriteWins`（updatedAt 新しい方・同時刻は削除優先・タイは id 順）を再利用。
/// 設計: docs/remote-grading-spec.md / docs/supabase-adapter-design.md

/// 親の採点判定。rawValue はサーバ `reviews.parent_decision` の check 値に一致。
public enum ReviewDecision: String, Codable, Equatable, Sendable {
    case unreviewed
    case approved
    case needsPractice
}

/// review の内容（同期メタ以外）。
public struct ReviewPayload: Equatable, Codable, Sendable {
    /// 採点対象の attempt（`public.attempts.id`）。
    public var attemptID: UUID
    public var decision: ReviewDecision
    /// 親が描いたお手本画像の Storage キー（`parent_example_path`）。無ければ nil。
    public var exampleStoragePath: String?
    /// 採点した親（`reviewed_by` = auth.uid）。
    public var reviewedBy: UUID?

    public init(attemptID: UUID, decision: ReviewDecision, exampleStoragePath: String? = nil, reviewedBy: UUID? = nil) {
        self.attemptID = attemptID
        self.decision = decision
        self.exampleStoragePath = exampleStoragePath
        self.reviewedBy = reviewedBy
    }
}

/// 同期1レコードとしての review。`SyncableRecord` 準拠で汎用 LWW にそのまま載る。
public struct ReviewRecord: SyncableRecord, Equatable, Codable, Sendable {
    public var sync: SyncMetadata
    public var payload: ReviewPayload

    public init(sync: SyncMetadata, payload: ReviewPayload) {
        self.sync = sync
        self.payload = payload
    }
}

/// review の決定的IDの採番。
public enum ReviewIdentity {
    /// reviews 専用の uuidv5 namespace。**サーバ（Edge Function / Postgres）と一致させる契約値**。
    /// 変更すると既存の review ID が全てズレるので固定。
    public static let namespace = UUID(uuidString: "8F2B0E14-1C3A-4D5E-9A6B-7C8D9E0F1A2B")!

    /// attempt 1件に対する review の安定ID。`uuidv5(namespace, attempt_id の小文字正規形)`。
    /// - 重要: name は **小文字・ハイフン区切りの正規 UUID 文字列**で固定する。
    ///   Swift の `UUID.uuidString` は大文字、Postgres の `uuid::text` は小文字なので、
    ///   小文字に揃えないとサーバ側 `uuid_generate_v5` と ID がズレる（クロスシステム契約）。
    public static func reviewID(forAttempt attemptID: UUID) -> UUID {
        DeterministicID.uuidV5(namespace: namespace, name: attemptID.uuidString.lowercased())
    }

    /// 新規 review レコードを、決定的IDで組み立てる。
    public static func makeRecord(
        attemptID: UUID,
        decision: ReviewDecision,
        householdID: UUID?,
        profileID: UUID?,
        exampleStoragePath: String? = nil,
        reviewedBy: UUID? = nil,
        now: Date
    ) -> ReviewRecord {
        let meta = SyncMetadata(
            id: reviewID(forAttempt: attemptID),
            householdID: householdID,
            profileID: profileID,
            createdAt: now,
            updatedAt: now
        )
        let payload = ReviewPayload(
            attemptID: attemptID,
            decision: decision,
            exampleStoragePath: exampleStoragePath,
            reviewedBy: reviewedBy
        )
        return ReviewRecord(sync: meta, payload: payload)
    }
}
