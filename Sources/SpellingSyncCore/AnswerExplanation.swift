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
        // tokens 空のときは空行を出さないよう correctText を nil にする（カードの空行回避）。
        let joined = item.tokens.joined(separator: " ")
        return AnswerExplanation(
            wasCorrect: grade.isCorrect,
            headline: item.grammar?.titleJa,
            correctText: joined.isEmpty ? nil : joined,
            meaningJa: item.ja,
            detail: grade.isCorrect ? nil : item.grammar?.explanationJa,
            chips: []
        )
    }
}
