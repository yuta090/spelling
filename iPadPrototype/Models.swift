import Foundation

struct SpellingWord: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    var registeredAt = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case registeredAt
    }

    init(id: UUID = UUID(), text: String, registeredAt: Date = Date()) {
        self.id = id
        self.text = text
        self.registeredAt = registeredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        registeredAt = try container.decodeIfPresent(Date.self, forKey: .registeredAt) ?? Date()
    }
}

struct WordStep: Identifiable, Equatable {
    var id: String
    var number: Int
    var registeredDate: Date
    var words: [SpellingWord]

    func title(language: AppLanguage) -> String {
        language.text(japanese: "ステップ \(number)", english: "Step \(number)")
    }
}

struct OCRCandidate: Equatable {
    var text: String
    var normalizedText: String
    var confidence: Float
    var isFallback: Bool = false
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        case .english:
            return "English"
        }
    }

    func text(japanese: String, english: String) -> String {
        switch self {
        case .japanese:
            return japanese
        case .english:
            return english
        }
    }
}

func formattedStepDate(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language == .japanese ? Locale(identifier: "ja_JP") : Locale(identifier: "en_US")
    formatter.dateFormat = language == .japanese ? "yyyy年M月d日" : "MMM d, yyyy"
    return formatter.string(from: date)
}

enum GradeDecision: String, Equatable, Codable {
    case autoCorrect
    case autoIncorrect
    case needsReview
    case rewrite
    case timeExpired

    var label: String {
        label(language: .english)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .autoCorrect:
            return language.text(japanese: "正解", english: "Correct")
        case .autoIncorrect:
            return language.text(japanese: "もう一度", english: "Try Again")
        case .needsReview:
            return language.text(japanese: "確認待ち", english: "Check Later")
        case .rewrite:
            return language.text(japanese: "書き直し", english: "Rewrite")
        case .timeExpired:
            return language.text(japanese: "時間切れ", english: "Time Up")
        }
    }
}

enum ParentReviewDecision: String, Equatable, Codable {
    case unreviewed
    case approved
    case needsPractice

    func label(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "未採点", english: "Not Graded")
        case .approved:
            return "OK"
        case .needsPractice:
            return language.text(japanese: "直そう", english: "Needs Fix")
        }
    }
}

struct SpellingAttempt: Identifiable, Equatable, Codable {
    var id = UUID()
    var word: String
    var recognizedText: String
    var decision: GradeDecision
    var drawingData: Data?
    var date = Date()
    var sessionID = UUID()
    var parentReviewDecision: ParentReviewDecision = .unreviewed
    var parentExampleDrawingData: Data?
    var parentReviewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case recognizedText
        case decision
        case drawingData
        case date
        case sessionID
        case parentReviewDecision
        case parentExampleDrawingData
        case parentReviewedAt
    }

    init(
        id: UUID = UUID(),
        word: String,
        recognizedText: String,
        decision: GradeDecision,
        drawingData: Data? = nil,
        date: Date = Date(),
        sessionID: UUID = UUID(),
        parentReviewDecision: ParentReviewDecision = .unreviewed,
        parentExampleDrawingData: Data? = nil,
        parentReviewedAt: Date? = nil
    ) {
        self.id = id
        self.word = word
        self.recognizedText = recognizedText
        self.decision = decision
        self.drawingData = drawingData
        self.date = date
        self.sessionID = sessionID
        self.parentReviewDecision = parentReviewDecision
        self.parentExampleDrawingData = parentExampleDrawingData
        self.parentReviewedAt = parentReviewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        word = try container.decode(String.self, forKey: .word)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText) ?? ""
        decision = try container.decodeIfPresent(GradeDecision.self, forKey: .decision) ?? .needsReview
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? id
        parentReviewDecision = try container.decodeIfPresent(ParentReviewDecision.self, forKey: .parentReviewDecision) ?? .unreviewed
        parentExampleDrawingData = try container.decodeIfPresent(Data.self, forKey: .parentExampleDrawingData)
        parentReviewedAt = try container.decodeIfPresent(Date.self, forKey: .parentReviewedAt)
    }
}

struct PracticeSample: Identifiable, Equatable, Codable {
    var id = UUID()
    var word: String
    var drawingData: Data
    var mode: String
    var date = Date()
    var sessionID = UUID()
    var parentReviewDecision: ParentReviewDecision = .unreviewed
    var parentExampleDrawingData: Data?
    var parentReviewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case drawingData
        case mode
        case date
        case sessionID
        case parentReviewDecision
        case parentExampleDrawingData
        case parentReviewedAt
    }

    init(
        id: UUID = UUID(),
        word: String,
        drawingData: Data,
        mode: String,
        date: Date = Date(),
        sessionID: UUID = UUID(),
        parentReviewDecision: ParentReviewDecision = .unreviewed,
        parentExampleDrawingData: Data? = nil,
        parentReviewedAt: Date? = nil
    ) {
        self.id = id
        self.word = word
        self.drawingData = drawingData
        self.mode = mode
        self.date = date
        self.sessionID = sessionID
        self.parentReviewDecision = parentReviewDecision
        self.parentExampleDrawingData = parentExampleDrawingData
        self.parentReviewedAt = parentReviewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        word = try container.decode(String.self, forKey: .word)
        drawingData = try container.decode(Data.self, forKey: .drawingData)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? SessionMode.practice.rawValue
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? id
        parentReviewDecision = try container.decodeIfPresent(ParentReviewDecision.self, forKey: .parentReviewDecision) ?? .unreviewed
        parentExampleDrawingData = try container.decodeIfPresent(Data.self, forKey: .parentExampleDrawingData)
        parentReviewedAt = try container.decodeIfPresent(Date.self, forKey: .parentReviewedAt)
    }
}

struct TestSettings: Equatable, Codable {
    var appLanguage: AppLanguage = .japanese
    var language = "en-US"
    var speechRate: Float = 0.42
    var secondsPerWord = 30
    var maxReplays = 2
    var practiceRepetitions = 3
    var autoCorrectConfidence: Float = 0.80
    var lowConfidence: Float = 0.35

    enum CodingKeys: String, CodingKey {
        case appLanguage
        case language
        case speechRate
        case secondsPerWord
        case maxReplays
        case practiceRepetitions
        case autoCorrectConfidence
        case lowConfidence
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .japanese
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en-US"
        speechRate = try container.decodeIfPresent(Float.self, forKey: .speechRate) ?? 0.42
        secondsPerWord = try container.decodeIfPresent(Int.self, forKey: .secondsPerWord) ?? 30
        maxReplays = try container.decodeIfPresent(Int.self, forKey: .maxReplays) ?? 2
        practiceRepetitions = try container.decodeIfPresent(Int.self, forKey: .practiceRepetitions) ?? 3
        autoCorrectConfidence = try container.decodeIfPresent(Float.self, forKey: .autoCorrectConfidence) ?? 0.80
        lowConfidence = try container.decodeIfPresent(Float.self, forKey: .lowConfidence) ?? 0.35
    }
}

enum SessionMode: String, Identifiable {
    case practice
    case test
    case review

    var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .practice:
            return language.text(japanese: "れんしゅうモード", english: "Practice Mode")
        case .test:
            return language.text(japanese: "テストモード", english: "Test Mode")
        case .review:
            return language.text(japanese: "ふくしゅうモード", english: "Review Mode")
        }
    }

    var showsWord: Bool {
        switch self {
        case .practice, .review:
            return true
        case .test:
            return false
        }
    }

    var canvasMode: PracticeMode {
        switch self {
        case .practice, .review:
            return .practice
        case .test:
            return .test
        }
    }
}

struct OCRGrader {
    var lowConfidence: Float

    init(settings: TestSettings = TestSettings()) {
        lowConfidence = settings.lowConfidence
    }

    func grade(candidates: [OCRCandidate], expected: String, hasInk: Bool = false) -> GradeDecision {
        let expectedText = normalize(expected)
        guard let best = candidates.first, !best.normalizedText.isEmpty else {
            return hasInk ? .needsReview : .rewrite
        }

        let distance = levenshtein(best.normalizedText, expectedText)
        let hasExpectedAlternative = candidates.dropFirst().contains {
            $0.confidence >= 0.45 && $0.normalizedText == expectedText
        }

        if best.normalizedText == expectedText {
            return .autoCorrect
        }

        if best.confidence < lowConfidence {
            return .rewrite
        }

        if hasExpectedAlternative {
            return .autoCorrect
        }

        let clearMissThreshold = max(3, Int(ceil(Double(max(expectedText.count, 1)) * 0.50)))
        if distance >= clearMissThreshold && best.confidence >= 0.65 {
            return .autoIncorrect
        }

        return .needsReview
    }
}

func normalize(_ text: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyz")
    return String(text.lowercased().filter { allowed.contains($0) })
}

func levenshtein(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)

    if aChars.isEmpty { return bChars.count }
    if bChars.isEmpty { return aChars.count }

    var previous = Array(0...bChars.count)
    var current = Array(repeating: 0, count: bChars.count + 1)

    for i in 1...aChars.count {
        current[0] = i
        for j in 1...bChars.count {
            let substitution = previous[j - 1] + (aChars[i - 1] == bChars[j - 1] ? 0 : 1)
            let insertion = current[j - 1] + 1
            let deletion = previous[j] + 1
            current[j] = min(substitution, insertion, deletion)
        }
        swap(&previous, &current)
    }

    return previous[bChars.count]
}
