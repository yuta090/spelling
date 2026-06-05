import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var words: [SpellingWord] {
        didSet {
            saveWords()
            ensureSelectedWordStepStillExists()
        }
    }

    @Published var attempts: [SpellingAttempt] {
        didSet { saveAttempts() }
    }

    @Published var practiceSamples: [PracticeSample] {
        didSet { savePracticeSamples() }
    }

    @Published var settings: TestSettings {
        didSet { saveSettings() }
    }

    @Published var selectedWordStepID: String {
        didSet { saveSelectedWordStepID() }
    }

    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let practiceSamplesKey = "spellingTrainer.practiceSamples"
    private let settingsKey = "spellingTrainer.settings"
    private let selectedWordStepIDKey = "spellingTrainer.selectedWordStepID"

    init() {
        let loadedWords = Self.load([SpellingWord].self, key: wordsKey) ?? [
            SpellingWord(text: "cat"),
            SpellingWord(text: "dog"),
            SpellingWord(text: "friend"),
            SpellingWord(text: "school")
        ]
        words = loadedWords
        attempts = Self.load([SpellingAttempt].self, key: attemptsKey) ?? []
        practiceSamples = Self.load([PracticeSample].self, key: practiceSamplesKey) ?? []
        settings = Self.load(TestSettings.self, key: settingsKey) ?? TestSettings()
        selectedWordStepID = UserDefaults.standard.string(forKey: selectedWordStepIDKey) ?? Self.defaultWordStepID(for: loadedWords)
        ensureSelectedWordStepStillExists()
    }

    var wordSteps: [WordStep] {
        Self.makeWordSteps(from: words)
    }

    var selectedWordStep: WordStep? {
        wordSteps.first { $0.id == selectedWordStepID } ?? wordSteps.last
    }

    var activeWords: [SpellingWord] {
        selectedWordStep?.words ?? words
    }

    var todayStepProgress: TodayStepProgress {
        todayStepProgress(for: activeWords)
    }

    var nextTestWords: [SpellingWord] {
        let progress = todayStepProgress
        guard progress.totalWords > 0 else {
            return []
        }

        if progress.hasTestActivity && !progress.isComplete {
            return progress.remainingWords
        }

        return activeWords
    }

    var reviewWords: [SpellingWord] {
        reviewWords(for: words)
    }

    var selectedReviewWords: [SpellingWord] {
        reviewWords(for: activeWords)
    }

    private func reviewWords(for sourceWords: [SpellingWord]) -> [SpellingWord] {
        let latestAttempts = latestAttemptsByWord(for: sourceWords, in: attempts)
        return sourceWords.filter { word in
            guard let attempt = latestAttempts[normalize(word.text)] else {
                return false
            }
            return !isCleared(attempt)
        }
    }

    private func todayStepProgress(for sourceWords: [SpellingWord]) -> TodayStepProgress {
        let todayAttempts = attempts.filter { Calendar.current.isDateInToday($0.date) }
        let latestAttempts = latestAttemptsByWord(for: sourceWords, in: todayAttempts)
        let clearedWords = sourceWords.filter { word in
            guard let attempt = latestAttempts[normalize(word.text)] else {
                return false
            }
            return isCleared(attempt)
        }
        let remainingWords = sourceWords.filter { word in
            !clearedWords.contains { normalize($0.text) == normalize(word.text) }
        }
        let sourceTexts = Set(sourceWords.map { normalize($0.text) })
        let hasTestActivity = todayAttempts.contains { sourceTexts.contains(normalize($0.word)) }

        return TodayStepProgress(
            totalWords: sourceWords.count,
            clearedWords: clearedWords,
            remainingWords: remainingWords,
            hasTestActivity: hasTestActivity,
            hasPerfectRun: hasPerfectRunToday(for: sourceWords, in: todayAttempts)
        )
    }

    private func latestAttemptsByWord(for sourceWords: [SpellingWord], in sourceAttempts: [SpellingAttempt]) -> [String: SpellingAttempt] {
        let sourceTexts = Set(sourceWords.map { normalize($0.text) })
        var latest: [String: SpellingAttempt] = [:]

        for attempt in sourceAttempts.sorted(by: { $0.date < $1.date }) {
            let key = normalize(attempt.word)
            guard sourceTexts.contains(key) else {
                continue
            }
            latest[key] = attempt
        }

        return latest
    }

    private func hasPerfectRunToday(for sourceWords: [SpellingWord], in todayAttempts: [SpellingAttempt]) -> Bool {
        let sourceTexts = Set(sourceWords.map { normalize($0.text) })
        guard !sourceTexts.isEmpty else {
            return false
        }

        let sessions = Dictionary(grouping: todayAttempts) { $0.sessionID }
        return sessions.values.contains { sessionAttempts in
            var latestInSession: [String: SpellingAttempt] = [:]
            for attempt in sessionAttempts.sorted(by: { $0.date < $1.date }) {
                let key = normalize(attempt.word)
                guard sourceTexts.contains(key) else {
                    continue
                }
                latestInSession[key] = attempt
            }

            guard Set(latestInSession.keys) == sourceTexts else {
                return false
            }

            return latestInSession.values.allSatisfy { isCleared($0) }
        }
    }

    private func isCleared(_ attempt: SpellingAttempt) -> Bool {
        if attempt.parentReviewDecision == .approved {
            return true
        }
        if attempt.parentReviewDecision == .needsPractice {
            return false
        }
        return attempt.decision == .autoCorrect
    }

    var todaysAttempts: [SpellingAttempt] {
        attempts.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todaysCorrectCount: Int {
        todaysAttempts.filter { $0.decision == .autoCorrect }.count
    }

    var todaysPracticeSamples: [PracticeSample] {
        practiceSamples.filter { Calendar.current.isDateInToday($0.date) }
    }

    func replaceWords(from rawText: String) {
        let parsed = rawText
            .components(separatedBy: CharacterSet.newlines.union(.punctuationCharacters).union(.whitespaces))
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        let unique = Array(NSOrderedSet(array: parsed)).compactMap { $0 as? String }
        let now = Date()
        var existingWordsByText: [String: SpellingWord] = [:]
        for word in words {
            let key = normalize(word.text)
            if existingWordsByText[key] == nil {
                existingWordsByText[key] = word
            }
        }

        let updatedWords = unique.map { text in
            existingWordsByText[text] ?? SpellingWord(text: text, registeredAt: now)
        }
        let addedNewWords = updatedWords.contains { existingWordsByText[normalize($0.text)] == nil }

        words = updatedWords
        if addedNewWords {
            selectedWordStepID = Self.defaultWordStepID(for: updatedWords)
        }
    }

    @discardableResult
    func addAttempt(
        word: String,
        recognizedText: String,
        decision: GradeDecision,
        drawingData: Data? = nil,
        sessionID: UUID = UUID()
    ) -> SpellingAttempt {
        let attempt = SpellingAttempt(
            word: normalize(word),
            recognizedText: normalize(recognizedText),
            decision: decision,
            drawingData: drawingData,
            sessionID: sessionID
        )
        attempts.append(attempt)
        return attempt
    }

    func updateAttempt(_ attempt: SpellingAttempt, decision: GradeDecision) {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }) else {
            return
        }
        attempts[index].decision = decision
    }

    func updateAttemptParentReview(_ attempt: SpellingAttempt, decision parentDecision: ParentReviewDecision, exampleDrawingData: Data? = nil) {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }) else {
            return
        }

        attempts[index].parentReviewDecision = parentDecision
        if let exampleDrawingData {
            attempts[index].parentExampleDrawingData = exampleDrawingData
        } else if parentDecision == .approved {
            attempts[index].parentExampleDrawingData = nil
        }
        attempts[index].parentReviewedAt = Date()

        switch parentDecision {
        case .approved:
            attempts[index].decision = .autoCorrect
        case .needsPractice:
            attempts[index].decision = .autoIncorrect
        case .unreviewed:
            break
        }
    }

    func updatePracticeSampleParentReview(_ sample: PracticeSample, decision parentDecision: ParentReviewDecision, exampleDrawingData: Data? = nil) {
        guard let index = practiceSamples.firstIndex(where: { $0.id == sample.id }) else {
            return
        }

        practiceSamples[index].parentReviewDecision = parentDecision
        if let exampleDrawingData {
            practiceSamples[index].parentExampleDrawingData = exampleDrawingData
        } else if parentDecision == .approved {
            practiceSamples[index].parentExampleDrawingData = nil
        }
        practiceSamples[index].parentReviewedAt = Date()
    }

    func resetResults() {
        attempts = []
    }

    func addPracticeSample(_ sample: PracticeSample) {
        practiceSamples.append(sample)
    }

    func resetPracticeSamples() {
        practiceSamples = []
    }

    private func saveWords() {
        Self.save(words, key: wordsKey)
    }

    private func saveAttempts() {
        Self.save(attempts, key: attemptsKey)
    }

    private func savePracticeSamples() {
        Self.save(practiceSamples, key: practiceSamplesKey)
    }

    private func saveSettings() {
        Self.save(settings, key: settingsKey)
    }

    private func saveSelectedWordStepID() {
        UserDefaults.standard.set(selectedWordStepID, forKey: selectedWordStepIDKey)
    }

    private func ensureSelectedWordStepStillExists() {
        let steps = wordSteps
        guard !steps.isEmpty else {
            if !selectedWordStepID.isEmpty {
                selectedWordStepID = ""
            }
            return
        }

        if !steps.contains(where: { $0.id == selectedWordStepID }) {
            selectedWordStepID = steps.last?.id ?? ""
        }
    }

    private static func makeWordSteps(from words: [SpellingWord], calendar: Calendar = .current) -> [WordStep] {
        var groups: [String: (date: Date, words: [SpellingWord])] = [:]

        for word in words {
            let date = calendar.startOfDay(for: word.registeredAt)
            let id = stepID(for: date, calendar: calendar)
            if groups[id] == nil {
                groups[id] = (date: date, words: [])
            }
            groups[id]?.words.append(word)
        }

        let sortedIDs = groups.keys.sorted {
            guard let left = groups[$0]?.date, let right = groups[$1]?.date else {
                return $0 < $1
            }
            return left < right
        }

        return sortedIDs.enumerated().compactMap { index, id in
            guard let group = groups[id] else {
                return nil
            }
            return WordStep(id: id, number: index + 1, registeredDate: group.date, words: group.words)
        }
    }

    private static func defaultWordStepID(for words: [SpellingWord]) -> String {
        makeWordSteps(from: words).last?.id ?? ""
    }

    private static func stepID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
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
