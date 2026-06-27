import Foundation

/// 子の解答試行（attempt）の**同期レコード契約**。リモート採点の同期（本筋B）の土台。
///
/// サーバ `public.attempts` に対応。attempt は **append-only / 作成後は不変**（採点は別行 `reviews`）。
/// そのため LWW で競合することは実質無いが、`SyncableRecord` で統一して扱う（汎用 `LastWriteWins` /
/// `SyncScope` をそのまま再利用でき、論理削除＝tombstone も表現できる）。
/// コアは enum を知らないので `mode`/`autoDecision` は raw 値の String で持つ（`WordPayload.source` と同方針）。
public struct AttemptSyncPayload: Equatable, Codable, Sendable {
    public var sessionID: UUID
    public var stepID: UUID?
    public var wordID: UUID?
    /// 出題語のスナップショット（後から語が変わっても採点文脈を保つ）。
    public var expectedWord: String
    /// "practice" / "test" / "review"。
    public var mode: String
    /// 端末OCRの認識結果。
    public var recognizedText: String
    public var ocrConfidence: Double?
    /// 端末側の自動判定（"needsReview" 等）。最終判定は親の `reviews`。
    public var autoDecision: String
    /// 手書き画像の Storage/R2 キー。
    public var drawingPath: String?
    public var submittedAt: Date

    public init(
        sessionID: UUID,
        stepID: UUID? = nil,
        wordID: UUID? = nil,
        expectedWord: String,
        mode: String,
        recognizedText: String,
        ocrConfidence: Double? = nil,
        autoDecision: String,
        drawingPath: String? = nil,
        submittedAt: Date
    ) {
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
    }
}

/// 同期1レコードとしての attempt。`SyncableRecord` 準拠で汎用 LWW / SyncScope にそのまま載る。
public struct AttemptSyncRecord: SyncableRecord, Equatable, Codable, Sendable {
    public var sync: SyncMetadata
    public var payload: AttemptSyncPayload

    public init(sync: SyncMetadata, payload: AttemptSyncPayload) {
        self.sync = sync
        self.payload = payload
    }
}
