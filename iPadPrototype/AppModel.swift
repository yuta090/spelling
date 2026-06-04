import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var words: [SpellingWord] {
        didSet { saveWords() }
    }

    @Published var attempts: [SpellingAttempt] {
        didSet { saveAttempts() }
    }

    @Published var settings: TestSettings {
        didSet { saveSettings() }
    }

    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let settingsKey = "spellingTrainer.settings"

    init() {
        words = Self.load([SpellingWord].self, key: wordsKey) ?? [
            SpellingWord(text: "cat"),
            SpellingWord(text: "dog"),
            SpellingWord(text: "friend"),
            SpellingWord(text: "school")
        ]
        attempts = Self.load([SpellingAttempt].self, key: attemptsKey) ?? []
        settings = Self.load(TestSettings.self, key: settingsKey) ?? TestSettings()
    }

    var reviewWords: [SpellingWord] {
        let reviewTexts = attempts
            .filter { $0.decision != .autoCorrect }
            .map { normalize($0.word) }

        let unique = Array(NSOrderedSet(array: reviewTexts)).compactMap { $0 as? String }
        let mapped = unique.compactMap { reviewText in
            words.first { normalize($0.text) == reviewText }
        }

        return mapped
    }

    var todaysAttempts: [SpellingAttempt] {
        attempts.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todaysCorrectCount: Int {
        todaysAttempts.filter { $0.decision == .autoCorrect }.count
    }

    func replaceWords(from rawText: String) {
        let parsed = rawText
            .components(separatedBy: CharacterSet.newlines.union(.punctuationCharacters).union(.whitespaces))
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        let unique = Array(NSOrderedSet(array: parsed)).compactMap { $0 as? String }
        words = unique.map { SpellingWord(text: $0) }
    }

    func addAttempt(word: String, recognizedText: String, decision: GradeDecision, drawingData: Data? = nil) {
        attempts.append(
            SpellingAttempt(
                word: normalize(word),
                recognizedText: normalize(recognizedText),
                decision: decision,
                drawingData: drawingData
            )
        )
    }

    func updateAttempt(_ attempt: SpellingAttempt, decision: GradeDecision) {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }) else {
            return
        }
        attempts[index].decision = decision
    }

    func resetResults() {
        attempts = []
    }

    private func saveWords() {
        Self.save(words, key: wordsKey)
    }

    private func saveAttempts() {
        Self.save(attempts, key: attemptsKey)
    }

    private func saveSettings() {
        Self.save(settings, key: settingsKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        let data = try? JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: key)
    }
}
