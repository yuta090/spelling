import Foundation

struct SpellingWord: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
}

struct OCRCandidate: Equatable {
    var text: String
    var normalizedText: String
    var confidence: Float
}

enum GradeDecision: String, Equatable, Codable {
    case autoCorrect
    case autoIncorrect
    case needsReview
    case rewrite
    case timeExpired

    var label: String {
        switch self {
        case .autoCorrect:
            return "Correct"
        case .autoIncorrect:
            return "Try Again"
        case .needsReview:
            return "Check Later"
        case .rewrite:
            return "Rewrite"
        case .timeExpired:
            return "Time Up"
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
}

struct TestSettings: Equatable, Codable {
    var language = "en-US"
    var speechRate: Float = 0.42
    var secondsPerWord = 30
    var maxReplays = 2
    var autoCorrectConfidence: Float = 0.80
    var lowConfidence: Float = 0.35
}

enum SessionMode: String, Identifiable {
    case practice
    case test
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice:
            return "Practice"
        case .test:
            return "Test"
        case .review:
            return "Review"
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
    var highConfidence: Float
    var lowConfidence: Float

    init(settings: TestSettings = TestSettings()) {
        highConfidence = settings.autoCorrectConfidence
        lowConfidence = settings.lowConfidence
    }

    func grade(candidates: [OCRCandidate], expected: String) -> GradeDecision {
        let expectedText = normalize(expected)
        guard let best = candidates.first, !best.normalizedText.isEmpty else {
            return .rewrite
        }

        let distance = levenshtein(best.normalizedText, expectedText)
        let hasStrongAlternative = candidates.dropFirst().contains {
            $0.confidence >= 0.75 && $0.normalizedText != best.normalizedText
        }

        if best.normalizedText == expectedText && best.confidence >= highConfidence && !hasStrongAlternative {
            return .autoCorrect
        }

        if best.confidence < lowConfidence {
            return .rewrite
        }

        if best.normalizedText == expectedText {
            return .needsReview
        }

        let clearMissThreshold = max(2, Int(ceil(Double(max(expectedText.count, 1)) * 0.34)))
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
