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

    @Published var schoolTestResults: [SchoolTestResult] {
        didSet { saveSchoolTestResults() }
    }

    @Published var settings: TestSettings {
        didSet { saveSettings() }
    }

    @Published var selectedWordStepID: String {
        didSet { saveSelectedWordStepID() }
    }

    @Published var rewardCoins: Int {
        didSet { saveRewardCoins() }
    }

    @Published var selectedCharacterID: String {
        didSet { saveSelectedCharacterID() }
    }

    @Published var unlockedCharacterIDs: Set<String> {
        didSet { saveUnlockedCharacterIDs() }
    }

    @Published var focusedPracticeWordIDs = Set<UUID>()

    static let practiceCoinReward = 3
    static let defaultCharacterID = "bear"
    static let defaultUnlockedCharacterIDs: Set<String> = ["bear", "cat", "dog"]

    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let practiceSamplesKey = "spellingTrainer.practiceSamples"
    private let schoolTestResultsKey = "spellingTrainer.schoolTestResults"
    private let settingsKey = "spellingTrainer.settings"
    private let selectedWordStepIDKey = "spellingTrainer.selectedWordStepID"
    private let rewardCoinsKey = "spellingTrainer.rewardCoins"
    private let selectedCharacterIDKey = "spellingTrainer.selectedCharacterID"
    private let unlockedCharacterIDsKey = "spellingTrainer.unlockedCharacterIDs"

    init() {
        let loadedWords = Self.load([SpellingWord].self, key: wordsKey) ?? [
            SpellingWord(text: "cat", promptText: "ねこ"),
            SpellingWord(text: "dog", promptText: "いぬ"),
            SpellingWord(text: "friend", promptText: "友[とも]だち"),
            SpellingWord(text: "school", promptText: "学校[がっこう]")
        ]
        words = loadedWords
        attempts = Self.load([SpellingAttempt].self, key: attemptsKey) ?? []
        practiceSamples = Self.load([PracticeSample].self, key: practiceSamplesKey) ?? []
        schoolTestResults = Self.load([SchoolTestResult].self, key: schoolTestResultsKey) ?? []
        settings = Self.load(TestSettings.self, key: settingsKey) ?? TestSettings()
        selectedWordStepID = UserDefaults.standard.string(forKey: selectedWordStepIDKey) ?? Self.defaultWordStepID(for: loadedWords)
        rewardCoins = max(Self.load(Int.self, key: rewardCoinsKey) ?? 0, 0)
        let initialUnlockedCharacterIDs = (Self.load(Set<String>.self, key: unlockedCharacterIDsKey) ?? []).union(Self.defaultUnlockedCharacterIDs)
        unlockedCharacterIDs = initialUnlockedCharacterIDs
        let savedCharacterID = UserDefaults.standard.string(forKey: selectedCharacterIDKey) ?? Self.defaultCharacterID
        selectedCharacterID = initialUnlockedCharacterIDs.contains(savedCharacterID) ? savedCharacterID : Self.defaultCharacterID
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

    var testWordsForSelectedStep: [SpellingWord] {
        guard let selectedWordStep else {
            return words
        }
        return testWords(for: selectedWordStep)
    }

    var carryOverReviewWordsForSelectedStep: [SpellingWord] {
        guard let selectedWordStep else {
            return []
        }
        return carryOverReviewWords(for: selectedWordStep)
    }

    var todayStepProgress: TodayStepProgress {
        todayStepProgress(for: testWordsForSelectedStep)
    }

    var nextTestWords: [SpellingWord] {
        let testWords = testWordsForSelectedStep
        let progress = todayStepProgress(for: testWords)
        guard progress.totalWords > 0 else {
            return []
        }

        if progress.hasTestActivity && !progress.isComplete {
            return progress.remainingWords
        }

        return testWords
    }

    var reviewWords: [SpellingWord] {
        uniqueWords(wordSteps.flatMap { unresolvedReviewWords(for: $0) })
    }

    var selectedReviewWords: [SpellingWord] {
        guard let selectedWordStep else {
            return []
        }
        return unresolvedReviewWords(for: selectedWordStep)
    }

    func testWords(for step: WordStep) -> [SpellingWord] {
        uniqueWords(step.words + carryOverReviewWords(for: step))
    }

    func carryOverReviewWords(for step: WordStep) -> [SpellingWord] {
        guard let previousStep = previousWordStep(before: step) else {
            return []
        }
        return unresolvedReviewWords(for: previousStep)
    }

    func unresolvedReviewWords(for step: WordStep) -> [SpellingWord] {
        let latestAttempts = latestAttemptsByWord(for: step.words, in: attempts)
        let latestSchoolMissDates = latestSchoolMissDatesByWord(for: step)

        return step.words.filter { word in
            let key = normalize(word.text)
            let latestAttempt = latestAttempts[key]
            let appNeedsReview = latestAttempt.map { !isCleared($0) } ?? false

            let schoolNeedsReview: Bool
            if let schoolMissDate = latestSchoolMissDates[key] {
                if let latestAttempt, latestAttempt.date > schoolMissDate, isCleared(latestAttempt) {
                    schoolNeedsReview = false
                } else {
                    schoolNeedsReview = true
                }
            } else {
                schoolNeedsReview = false
            }

            return appNeedsReview || schoolNeedsReview
        }
    }

    func schoolTestResults(for step: WordStep) -> [SchoolTestResult] {
        schoolTestResults
            .filter { schoolTestResult($0, belongsTo: step) }
            .sorted { $0.date > $1.date }
    }

    private func previousWordStep(before step: WordStep) -> WordStep? {
        let steps = wordSteps
        guard let index = steps.firstIndex(where: { $0.id == step.id }), index > 0 else {
            return nil
        }
        return steps[index - 1]
    }

    private func latestSchoolMissDatesByWord(for step: WordStep) -> [String: Date] {
        let stepTexts = Set(step.words.map { normalize($0.text) })
        var datesByWord: [String: Date] = [:]

        for result in schoolTestResults(for: step) {
            for entry in parseWordListEntries(from: result.missedWords) {
                let key = normalize(entry.text)
                guard stepTexts.contains(key) else {
                    continue
                }
                if datesByWord[key] == nil || result.date > datesByWord[key]! {
                    datesByWord[key] = result.date
                }
            }
        }

        return datesByWord
    }

    private func schoolTestResult(_ result: SchoolTestResult, belongsTo step: WordStep) -> Bool {
        if result.stepID == step.id {
            return true
        }

        let stepTitles = [
            step.title(language: .japanese),
            step.title(language: .english)
        ]
        return result.stepID == nil && stepTitles.contains(result.stepTitle)
    }

    private func uniqueWords(_ sourceWords: [SpellingWord]) -> [SpellingWord] {
        var seen = Set<String>()
        return sourceWords.filter { word in
            let key = normalize(word.text)
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
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
        let entries = parseWordListEntries(from: rawText)
        let now = Date()
        var existingWordsByText: [String: SpellingWord] = [:]
        for word in words {
            let key = normalize(word.text)
            if existingWordsByText[key] == nil {
                existingWordsByText[key] = word
            }
        }

        let updatedWords = entries.map { entry in
            let key = normalize(entry.text)
            var word = existingWordsByText[key] ?? SpellingWord(text: key, registeredAt: now)
            word.text = key
            if let promptText = entry.promptText {
                word.promptText = promptText
            }
            return word
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
        var updatedAttempts = attempts
        updatedAttempts[index].decision = decision
        attempts = updatedAttempts
    }

    func updateAttemptParentReview(_ attempt: SpellingAttempt, decision parentDecision: ParentReviewDecision, exampleDrawingData: Data? = nil) {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }) else {
            return
        }

        var updatedAttempts = attempts
        updatedAttempts[index].parentReviewDecision = parentDecision
        if let exampleDrawingData {
            updatedAttempts[index].parentExampleDrawingData = exampleDrawingData
        } else if parentDecision == .approved {
            updatedAttempts[index].parentExampleDrawingData = nil
        }
        updatedAttempts[index].parentReviewedAt = Date()

        switch parentDecision {
        case .approved:
            updatedAttempts[index].decision = .autoCorrect
        case .needsPractice:
            updatedAttempts[index].decision = .autoIncorrect
        case .unreviewed:
            break
        }

        attempts = updatedAttempts
    }

    func updatePracticeSampleParentReview(_ sample: PracticeSample, decision parentDecision: ParentReviewDecision, exampleDrawingData: Data? = nil) {
        guard let index = practiceSamples.firstIndex(where: { $0.id == sample.id }) else {
            return
        }

        var updatedSamples = practiceSamples
        updatedSamples[index].parentReviewDecision = parentDecision
        if let exampleDrawingData {
            updatedSamples[index].parentExampleDrawingData = exampleDrawingData
        } else if parentDecision == .approved {
            updatedSamples[index].parentExampleDrawingData = nil
        }
        updatedSamples[index].parentReviewedAt = Date()
        practiceSamples = updatedSamples
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

    func addSchoolTestResult(_ result: SchoolTestResult) {
        schoolTestResults.append(result)
    }

    func deleteSchoolTestResult(_ result: SchoolTestResult) {
        schoolTestResults.removeAll { $0.id == result.id }
    }

    func awardPracticeCoins(_ amount: Int = AppModel.practiceCoinReward) {
        rewardCoins = max(rewardCoins + max(amount, 0), 0)
    }

    func selectCharacter(id: String) {
        guard unlockedCharacterIDs.contains(id) else {
            return
        }
        selectedCharacterID = id
    }

    @discardableResult
    func unlockCharacter(id: String, cost: Int) -> Bool {
        if unlockedCharacterIDs.contains(id) {
            selectedCharacterID = id
            return true
        }

        let safeCost = max(cost, 0)
        guard rewardCoins >= safeCost else {
            return false
        }

        rewardCoins -= safeCost
        var updatedUnlockedIDs = unlockedCharacterIDs
        updatedUnlockedIDs.insert(id)
        unlockedCharacterIDs = updatedUnlockedIDs
        selectedCharacterID = id
        return true
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

    private func saveSchoolTestResults() {
        Self.save(schoolTestResults, key: schoolTestResultsKey)
    }

    private func saveSettings() {
        Self.save(settings, key: settingsKey)
    }

    private func saveSelectedWordStepID() {
        UserDefaults.standard.set(selectedWordStepID, forKey: selectedWordStepIDKey)
    }

    private func saveRewardCoins() {
        Self.save(max(rewardCoins, 0), key: rewardCoinsKey)
    }

    private func saveSelectedCharacterID() {
        UserDefaults.standard.set(selectedCharacterID, forKey: selectedCharacterIDKey)
    }

    private func saveUnlockedCharacterIDs() {
        Self.save(unlockedCharacterIDs, key: unlockedCharacterIDsKey)
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
