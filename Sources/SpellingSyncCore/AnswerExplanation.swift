import Foundation

public struct AnswerExplanation: Equatable, Sendable {
    public var wasCorrect: Bool?
    public var headline: String?
    public var correctText: String?
    public var meaningJa: String?
    public var detail: String?
    /// ぶんづくり（並べ替え）の「ただしい ならびかた」ヒント（例: "Yes → I → can のじゅんばん"）。
    public var orderHint: String?
    public var chips: [String]

    public init(
        wasCorrect: Bool? = nil,
        headline: String? = nil,
        correctText: String? = nil,
        meaningJa: String? = nil,
        detail: String? = nil,
        orderHint: String? = nil,
        chips: [String] = []
    ) {
        self.wasCorrect = wasCorrect
        self.headline = headline
        self.correctText = correctText
        self.meaningJa = meaningJa
        self.detail = detail
        self.orderHint = orderHint
        self.chips = chips
    }
}

public enum SentenceFeedback {
    /// ぶんづくりの答え合わせ説明。
    /// 並べ替えの難所は「語順」なので、文に貼られた文法タグ（語順とズレやすく、誤りも混じる）ではなく、
    /// **正解文＋意味＋ならびかたヒント**で「正しい構文」を直接見せる。文法見出し・文法解説は出さない。
    public static func make(item: SentenceItem, submitted: [String], grade: OrderingGrade) -> AnswerExplanation {
        // tokens 空のときは空行を出さないよう correctText を nil にする（カードの空行回避）。
        let joined = item.tokens.joined(separator: " ")
        return AnswerExplanation(
            wasCorrect: grade.isCorrect,
            headline: nil,
            correctText: joined.isEmpty ? nil : joined,
            meaningJa: item.ja,
            detail: nil,
            orderHint: grade.isCorrect ? nil : orderHint(item.tokens),
            chips: []
        )
    }

    /// 正解トークンを矢印でつないだ「ならびかた」ヒント。
    /// 前後の記号は外して読みやすくし（トークナイザと同じ記号セットを共有）、記号だけのトークンは捨てる。
    /// 並べる対象が2語に満たないときは nil（並び順を語る意味がないため）。
    public static func orderHint(_ tokens: [String]) -> String? {
        let words = tokens
            .map(SentenceBankBuilder.stripEdgePunctuation)
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        return words.joined(separator: " → ") + " のじゅんばん"
    }
}
