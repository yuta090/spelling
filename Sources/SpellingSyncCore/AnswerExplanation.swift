import Foundation

public struct AnswerExplanation: Equatable, Sendable {
    public var wasCorrect: Bool?
    public var headline: String?
    public var correctText: String?
    public var meaningJa: String?
    public var detail: String?
    public var chips: [String]

    public init(
        wasCorrect: Bool? = nil,
        headline: String? = nil,
        correctText: String? = nil,
        meaningJa: String? = nil,
        detail: String? = nil,
        chips: [String] = []
    ) {
        self.wasCorrect = wasCorrect
        self.headline = headline
        self.correctText = correctText
        self.meaningJa = meaningJa
        self.detail = detail
        self.chips = chips
    }
}

public enum SentenceFeedback {
    public static func make(item: SentenceItem, submitted: [String], grade: OrderingGrade) -> AnswerExplanation {
        AnswerExplanation(
            wasCorrect: grade.isCorrect,
            headline: item.grammar?.titleJa,
            correctText: item.tokens.joined(separator: " "),
            meaningJa: item.ja,
            detail: grade.isCorrect ? nil : item.grammar?.explanationJa,
            chips: []
        )
    }
}
