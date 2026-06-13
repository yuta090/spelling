import CoreGraphics
import Foundation

struct SpellingWord: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var text: String
    var promptText = ""
    var registeredAt = Date()
    var stepID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case promptText
        case registeredAt
        case stepID
    }

    init(id: UUID = UUID(), text: String, promptText: String = "", registeredAt: Date = Date(), stepID: String? = nil) {
        self.id = id
        self.text = text
        self.promptText = promptText
        self.registeredAt = registeredAt
        self.stepID = stepID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        promptText = try container.decodeIfPresent(String.self, forKey: .promptText) ?? ""
        registeredAt = try container.decodeIfPresent(Date.self, forKey: .registeredAt) ?? Date()
        stepID = try container.decodeIfPresent(String.self, forKey: .stepID)
    }
}

struct WordStep: Identifiable, Equatable, Sendable {
    var id: String
    var number: Int
    var registeredDate: Date
    var words: [SpellingWord]

    func title(language: AppLanguage) -> String {
        language.text(japanese: "ステップ \(number)", english: "Step \(number)")
    }
}

struct TodayStepProgress: Equatable, Sendable {
    var totalWords: Int
    var clearedWords: [SpellingWord]
    var remainingWords: [SpellingWord]
    var hasTestActivity: Bool
    var hasPerfectRun: Bool

    var clearedCount: Int {
        clearedWords.count
    }

    var remainingCount: Int {
        remainingWords.count
    }

    var isComplete: Bool {
        totalWords > 0 && remainingWords.isEmpty
    }
}

struct SchoolTestResult: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    var stepID: String?
    var stepTitle: String
    var score: Int
    var total: Int
    var missedWords: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case stepID
        case stepTitle
        case score
        case total
        case missedWords
        case note
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        stepID: String? = nil,
        stepTitle: String,
        score: Int,
        total: Int,
        missedWords: String = "",
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.stepID = stepID
        self.stepTitle = stepTitle
        self.score = max(score, 0)
        self.total = max(total, 1)
        self.missedWords = missedWords
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        stepID = try container.decodeIfPresent(String.self, forKey: .stepID)
        stepTitle = try container.decodeIfPresent(String.self, forKey: .stepTitle) ?? ""
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        total = max(try container.decodeIfPresent(Int.self, forKey: .total) ?? 1, 1)
        missedWords = try container.decodeIfPresent(String.self, forKey: .missedWords) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct OCRCandidate: Equatable, Sendable {
    var text: String
    var normalizedText: String
    var confidence: Float
    var isFallback: Bool = false
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
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

func formattedLocalizedDate(_ date: Date, language: AppLanguage) -> String {
    formattedStepDate(date, language: language)
}

func formattedLocalizedDateTime(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language == .japanese ? Locale(identifier: "ja_JP") : Locale(identifier: "en_US")
    formatter.dateFormat = language == .japanese ? "yyyy年M月d日 H:mm" : "MMM d, yyyy h:mm a"
    return formatter.string(from: date)
}

func formattedLocalizedTime(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language == .japanese ? Locale(identifier: "ja_JP") : Locale(identifier: "en_US")
    formatter.dateFormat = language == .japanese ? "H:mm" : "h:mm a"
    return formatter.string(from: date)
}

enum GradeDecision: String, Equatable, Codable, Sendable {
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

enum ParentReviewDecision: String, Equatable, Codable, Sendable {
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

struct DrawingCanvasSize: Equatable, Codable, Sendable {
    var width: Double
    var height: Double
    var contentOffsetX: Double
    var contentOffsetY: Double

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case contentOffsetX
        case contentOffsetY
    }

    init(width: Double, height: Double, contentOffsetX: Double = 0, contentOffsetY: Double = 0) {
        self.width = width
        self.height = height
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        contentOffsetX = try container.decodeIfPresent(Double.self, forKey: .contentOffsetX) ?? 0
        contentOffsetY = try container.decodeIfPresent(Double.self, forKey: .contentOffsetY) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(contentOffsetX, forKey: .contentOffsetX)
        try container.encode(contentOffsetY, forKey: .contentOffsetY)
    }

    var isUsable: Bool {
        width > 0 && height > 0
    }

    var cgSize: CGSize {
        CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    var contentOffset: CGPoint {
        CGPoint(x: CGFloat(contentOffsetX), y: CGFloat(contentOffsetY))
    }

    var aspectRatio: Double? {
        guard isUsable else {
            return nil
        }
        return width / height
    }
}

struct SpellingAttempt: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var word: String
    var recognizedText: String
    var decision: GradeDecision
    var drawingData: Data?
    var canvasSize: DrawingCanvasSize?
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
        case canvasSize
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
        canvasSize: DrawingCanvasSize? = nil,
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
        self.canvasSize = canvasSize
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
        canvasSize = try container.decodeIfPresent(DrawingCanvasSize.self, forKey: .canvasSize)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? id
        parentReviewDecision = try container.decodeIfPresent(ParentReviewDecision.self, forKey: .parentReviewDecision) ?? .unreviewed
        parentExampleDrawingData = try container.decodeIfPresent(Data.self, forKey: .parentExampleDrawingData)
        parentReviewedAt = try container.decodeIfPresent(Date.self, forKey: .parentReviewedAt)
    }
}

struct PracticeSample: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var word: String
    var drawingData: Data
    var canvasSize: DrawingCanvasSize?
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
        case canvasSize
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
        canvasSize: DrawingCanvasSize? = nil,
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
        self.canvasSize = canvasSize
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
        canvasSize = try container.decodeIfPresent(DrawingCanvasSize.self, forKey: .canvasSize)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? SessionMode.practice.rawValue
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? id
        parentReviewDecision = try container.decodeIfPresent(ParentReviewDecision.self, forKey: .parentReviewDecision) ?? .unreviewed
        parentExampleDrawingData = try container.decodeIfPresent(Data.self, forKey: .parentExampleDrawingData)
        parentReviewedAt = try container.decodeIfPresent(Date.self, forKey: .parentReviewedAt)
    }
}

struct PracticeSessionResumeState: Equatable, Sendable {
    var wordIDs: [UUID]
    var index: Int
    var repeatIndex: Int
    var sessionID: UUID
}

struct TestSettings: Equatable, Codable, Sendable {
    var appLanguage: AppLanguage = .japanese
    var language = "en-US"
    var testPromptMode: TestPromptMode = .audioOnly
    var speechRate: Float = 0.42
    var secondsPerWord = 30
    var maxReplays = 2
    var practiceRepetitions = 3
    var writingAreaSize: WritingAreaSize = .standard
    var autoCorrectConfidence: Float = 0.80
    var lowConfidence: Float = 0.35

    enum CodingKeys: String, CodingKey {
        case appLanguage
        case language
        case testPromptMode
        case speechRate
        case secondsPerWord
        case maxReplays
        case practiceRepetitions
        case writingAreaSize
        case autoCorrectConfidence
        case lowConfidence
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .japanese
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en-US"
        testPromptMode = try container.decodeIfPresent(TestPromptMode.self, forKey: .testPromptMode) ?? .audioOnly
        speechRate = try container.decodeIfPresent(Float.self, forKey: .speechRate) ?? 0.42
        secondsPerWord = try container.decodeIfPresent(Int.self, forKey: .secondsPerWord) ?? 30
        maxReplays = try container.decodeIfPresent(Int.self, forKey: .maxReplays) ?? 2
        practiceRepetitions = try container.decodeIfPresent(Int.self, forKey: .practiceRepetitions) ?? 3
        writingAreaSize = try container.decodeIfPresent(WritingAreaSize.self, forKey: .writingAreaSize) ?? .standard
        autoCorrectConfidence = try container.decodeIfPresent(Float.self, forKey: .autoCorrectConfidence) ?? 0.80
        lowConfidence = try container.decodeIfPresent(Float.self, forKey: .lowConfidence) ?? 0.35
    }
}

enum WritingAreaSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var heightMultiplier: Double {
        switch self {
        case .compact:
            return 0.95
        case .standard:
            return 1.0
        case .large:
            return 1.16
        case .extraLarge:
            return 1.32
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .compact:
            return language.text(japanese: "小", english: "Small")
        case .standard:
            return language.text(japanese: "ふつう", english: "Normal")
        case .large:
            return language.text(japanese: "大", english: "Large")
        case .extraLarge:
            return language.text(japanese: "特大", english: "XL")
        }
    }

    func description(language: AppLanguage) -> String {
        switch self {
        case .compact:
            return language.text(japanese: "画面内に収まりやすい大きさです。", english: "Fits more comfortably on screen.")
        case .standard:
            return language.text(japanese: "いつもの大きさです。", english: "The default size.")
        case .large:
            return language.text(japanese: "少し大きく書けます。", english: "Gives more room to write.")
        case .extraLarge:
            return language.text(japanese: "大きく書きたい子向けです。", english: "Best for children who write big.")
        }
    }
}

enum TestPromptMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case audioOnly
    case textOnly
    case audioAndText

    var id: String { rawValue }

    var includesAudio: Bool {
        switch self {
        case .audioOnly, .audioAndText:
            return true
        case .textOnly:
            return false
        }
    }

    var showsPromptText: Bool {
        switch self {
        case .textOnly, .audioAndText:
            return true
        case .audioOnly:
            return false
        }
    }

    func shortLabel(language: AppLanguage) -> String {
        switch self {
        case .audioOnly:
            return language.text(japanese: "音だけ", english: "Audio")
        case .textOnly:
            return language.text(japanese: "文字だけ", english: "Text")
        case .audioAndText:
            return language.text(japanese: "音+文字", english: "Audio+Text")
        }
    }

    func description(language: AppLanguage) -> String {
        switch self {
        case .audioOnly:
            return language.text(japanese: "英語の発音だけを聞いて書きます。", english: "The child hears only the English pronunciation.")
        case .textOnly:
            return language.text(japanese: "単語リストに入れた日本語や説明だけを見て書きます。", english: "The child sees only the Japanese hint or meaning from the word list.")
        case .audioAndText:
            return language.text(japanese: "英語の発音と、日本語や説明のヒントを見て書きます。", english: "The child hears the word and sees the Japanese hint or meaning.")
        }
    }
}

enum SessionMode: String, Identifiable, Sendable {
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

struct WordListEntry: Equatable, Sendable {
    var text: String
    var promptText: String?
}

func wordListEditorText(_ words: [SpellingWord]) -> String {
    words.map { word in
        let prompt = word.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return word.text
        }
        return "\(word.text) | \(prompt)"
    }
    .joined(separator: "\n")
}

func parseWordListEntries(from rawText: String) -> [WordListEntry] {
    var entriesByText: [String: WordListEntry] = [:]
    var orderedTexts: [String] = []

    func append(_ entry: WordListEntry) {
        let text = normalize(entry.text)
        guard !text.isEmpty else {
            return
        }

        if var existing = entriesByText[text] {
            if let promptText = entry.promptText {
                existing.promptText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                entriesByText[text] = existing
            }
        } else {
            orderedTexts.append(text)
            entriesByText[text] = WordListEntry(
                text: text,
                promptText: entry.promptText?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    for rawLine in rawText.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            continue
        }

        if let entry = parsePromptLine(line) {
            append(entry)
            continue
        }

        let parts = line.components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
        for part in parts {
            let text = normalize(part)
            if !text.isEmpty {
                append(WordListEntry(text: text, promptText: nil))
            }
        }
    }

    return orderedTexts.compactMap { entriesByText[$0] }
}

private func parsePromptLine(_ line: String) -> WordListEntry? {
    for separator in ["|", "=", "：", ":"] {
        if let range = line.range(of: separator) {
            let text = normalize(String(line[..<range.lowerBound]))
            let prompt = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return WordListEntry(text: text, promptText: prompt)
        }
    }

    let pieces = line.split(whereSeparator: { $0.isWhitespace })
    guard pieces.count >= 2, let first = pieces.first else {
        return nil
    }

    let text = normalize(String(first))
    guard !text.isEmpty else {
        return nil
    }

    let remaining = String(line.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard remaining.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0.value > 127 }) else {
        return nil
    }

    return WordListEntry(text: text, promptText: remaining)
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
