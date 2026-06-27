import Foundation

/// attempt の **wire 表現**（Supabase `attempts` 行を SDK 非依存のプリミティブで持つ箱）。
/// 判断を要するロジック（RFC3339 のパース/整形・壊れた行の扱い）は**ここ（コア）に集約してテスト**する。
/// 設計: docs/remote-grading-spec.md / docs/supabase-adapter-design.md §7.5
public struct AttemptRow: Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var profileID: UUID?
    public var sessionID: UUID
    public var stepID: UUID?
    public var wordID: UUID?
    public var expectedWord: String
    public var mode: String
    public var recognizedText: String
    public var ocrConfidence: Double?
    public var autoDecision: String
    public var drawingPath: String?
    /// `submitted_at`（RFC3339, UTC）。
    public var submittedAt: String
    /// クライアント LWW 時刻（RFC3339, UTC）。
    public var updatedAt: String
    /// 論理削除（RFC3339, 未削除なら nil）。
    public var deletedAt: String?

    public init(
        id: UUID,
        householdID: UUID,
        profileID: UUID?,
        sessionID: UUID,
        stepID: UUID?,
        wordID: UUID?,
        expectedWord: String,
        mode: String,
        recognizedText: String,
        ocrConfidence: Double?,
        autoDecision: String,
        drawingPath: String?,
        submittedAt: String,
        updatedAt: String,
        deletedAt: String?
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.sessionID = sessionID
        self.stepID = stepID
        self.wordID = wordID
        self.expectedWord = expectedWord
        self.mode = mode
        self.recognizedText = recognizedText
        self.ocrConfidence = ocrConfidence
        self.autoDecision = autoDecision
        self.drawingPath = drawingPath
        self.submittedAt = submittedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// wire 行 ⇄ 正準同期レコード（`AttemptSyncRecord`）の純粋変換。
public enum AttemptWire {
    /// サーバ行 → 正準同期レコード。
    /// - `updatedAt`/`submittedAt`、または非 nil の `deletedAt` が解釈できなければ **行ごと落とす**
    ///   （壊れた行・削除復活の防止）。
    /// - `createdAt`(meta) は `submittedAt` を採用（attempt の自然な作成時刻。情報用途）。
    public static func record(from row: AttemptRow) -> AttemptSyncRecord? {
        guard let updated = RFC3339.date(from: row.updatedAt) else { return nil }
        guard let submitted = RFC3339.date(from: row.submittedAt) else { return nil }
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
            createdAt: submitted,
            updatedAt: updated,
            deletedAt: deleted
        )
        let payload = AttemptSyncPayload(
            sessionID: row.sessionID,
            stepID: row.stepID,
            wordID: row.wordID,
            expectedWord: row.expectedWord,
            mode: row.mode,
            recognizedText: row.recognizedText,
            ocrConfidence: row.ocrConfidence,
            autoDecision: row.autoDecision,
            drawingPath: row.drawingPath,
            submittedAt: submitted
        )
        return AttemptSyncRecord(sync: meta, payload: payload)
    }

    /// 正準同期レコード → 送信用 wire 行。`householdID` が無いレコードは送れないため nil。
    public static func wire(from record: AttemptSyncRecord) -> AttemptRow? {
        guard let householdID = record.sync.householdID else { return nil }
        return AttemptRow(
            id: record.sync.id,
            householdID: householdID,
            profileID: record.sync.profileID,
            sessionID: record.payload.sessionID,
            stepID: record.payload.stepID,
            wordID: record.payload.wordID,
            expectedWord: record.payload.expectedWord,
            mode: record.payload.mode,
            recognizedText: record.payload.recognizedText,
            ocrConfidence: record.payload.ocrConfidence,
            autoDecision: record.payload.autoDecision,
            drawingPath: record.payload.drawingPath,
            submittedAt: RFC3339.string(from: record.payload.submittedAt),
            updatedAt: RFC3339.string(from: record.sync.updatedAt),
            deletedAt: record.sync.deletedAt.map(RFC3339.string(from:))
        )
    }
}
