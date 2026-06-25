import Foundation

/// 自動採点の判定。アプリの `GradeDecision` に対応する同期コア側の表現（raw 値は一致）。
public enum GradeDecisionState: String, Codable, Sendable {
    case autoCorrect
    case autoIncorrect
    case needsReview
    case rewrite
    case timeExpired
}

// MARK: - Legacy DTOs（旧 JSON をそのまま読むための入力）

/// 旧 `SpellingAttempt` の JSON 形。省略キーは nil（synthesized Decodable）。
public struct LegacyAttemptDTO: Decodable {
    public var id: UUID?
    public var word: String
    public var recognizedText: String?
    public var decision: String?
    public var date: Date?
    public var sessionID: UUID?
    public var parentReviewDecision: String?
    public var parentReviewedAt: Date?
}

/// 旧 `SchoolTestResult` の JSON 形。
public struct LegacySchoolTestDTO: Decodable {
    public var id: UUID?
    public var date: Date?
    public var stepID: String?
    public var stepTitle: String?
    public var score: Int?
    public var total: Int?
    public var missedWords: String?
    public var note: String?
}

// MARK: - Canonical sync records（正準モデル：新フォーマットで対称な Codable）

/// 子の答案（immutable）。Architect 指摘により親採点は別レコードに分離する設計。
public struct AttemptRecord: SyncableRecord, ReviewableItem, Codable, Equatable, Sendable {
    public var sync: SyncMetadata
    public var word: String
    public var recognizedText: String
    public var decision: GradeDecisionState
    public var sessionID: UUID
    public var parentReviewState: ParentReviewState

    public init(
        sync: SyncMetadata,
        word: String,
        recognizedText: String,
        decision: GradeDecisionState,
        sessionID: UUID,
        parentReviewState: ParentReviewState
    ) {
        self.sync = sync
        self.word = word
        self.recognizedText = recognizedText
        self.decision = decision
        self.sessionID = sessionID
        self.parentReviewState = parentReviewState
    }

    /// 親確認が必要 = 自動採点が `needsReview`。
    public var requiresParentReview: Bool {
        decision == .needsReview
    }
}

/// 学校テスト結果。
public struct SchoolTestRecord: SyncableRecord, Codable, Equatable, Sendable {
    public var sync: SyncMetadata
    public var stepID: String?
    public var stepTitle: String
    public var score: Int
    public var total: Int
    public var missedWords: String
    public var note: String

    public init(
        sync: SyncMetadata,
        stepID: String?,
        stepTitle: String,
        score: Int,
        total: Int,
        missedWords: String,
        note: String
    ) {
        self.sync = sync
        self.stepID = stepID
        self.stepTitle = stepTitle
        self.score = score
        self.total = total
        self.missedWords = missedWords
        self.note = note
    }
}

// MARK: - Migration（旧 DTO → 正準レコード）

/// 旧ローカル JSON から正準同期レコードへの一度きりの移行。
/// 既存の id は踏襲し、`updatedAt` は最後に触れた時刻（親採点済みならその時刻）を採る。
public enum Migration {
    /// 日付が欠落した古いレコードのための安定したフォールバック（非決定的な現在時刻を避ける）。
    private static let epoch = Date(timeIntervalSince1970: 0)

    public static func migrate(_ dto: LegacyAttemptDTO) -> AttemptRecord {
        // id は一度だけ採番する（sync.id と sessionID フォールバックで同じ値を使うため）。
        let id = dto.id ?? UUID()
        let createdAt = dto.date ?? epoch
        return AttemptRecord(
            sync: SyncMetadata(
                id: id,
                createdAt: createdAt,
                // 親採点済みならその時刻が最終更新。未採点なら作成時刻。
                updatedAt: dto.parentReviewedAt ?? createdAt
            ),
            word: dto.word,
            recognizedText: dto.recognizedText ?? "",
            decision: dto.decision.flatMap(GradeDecisionState.init(rawValue:)) ?? .needsReview,
            sessionID: dto.sessionID ?? id,
            parentReviewState: dto.parentReviewDecision.flatMap(ParentReviewState.init(rawValue:)) ?? .unreviewed
        )
    }

    public static func migrate(_ dto: LegacySchoolTestDTO) -> SchoolTestRecord {
        let createdAt = dto.date ?? epoch
        return SchoolTestRecord(
            sync: SyncMetadata(
                id: dto.id ?? UUID(),
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            stepID: dto.stepID,
            stepTitle: dto.stepTitle ?? "",
            score: max(dto.score ?? 0, 0),
            total: max(dto.total ?? 1, 1),
            missedWords: dto.missedWords ?? "",
            note: dto.note ?? ""
        )
    }
}
