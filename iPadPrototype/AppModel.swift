import Foundation
import SQLite3
import SwiftData

/// 同梱 wordbank.sqlite（EJDict訳語＋Tanaka例文）への読み取り専用アクセス。
struct WordExample: Identifiable, Equatable, Sendable {
    let id = UUID()
    let en: String
    let ja: String
}

struct LeveledWord: Identifiable, Equatable, Sendable {
    var id: String { word }
    let word: String
    let ja: String
}

/// 読み取り専用・メインスレッドからの利用を想定（UIから同期参照）。`db` は init で一度だけ設定。
final class WordBank: @unchecked Sendable {
    static let shared = WordBank()
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        guard let url = Bundle.main.url(forResource: "wordbank", withExtension: "sqlite") else {
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// 英単語に対する日本語訳（EJDict）。
    func japanese(for word: String) -> String? {
        let key = normalize(word)
        guard !key.isEmpty, let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT ja FROM gloss WHERE word = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, key, -1, Self.transient)
        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            let value = String(cString: c)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// 英単語を含む例文（英＋日）。短い順。
    func examples(for word: String, limit: Int = 3) -> [WordExample] {
        let key = normalize(word)
        guard !key.isEmpty, let db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT en, ja FROM examples WHERE word = ? ORDER BY n LIMIT ?", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(stmt, 1, key, -1, Self.transient)
        sqlite3_bind_int(stmt, 2, Int32(min(max(limit, 1), 50)))
        var output: [WordExample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let en = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let ja = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if !en.isEmpty {
                output.append(WordExample(en: en, ja: ja))
            }
        }
        return output
    }

    /// レベル別の単語（訳語付き）。dolch（US学年）または band（難易度1〜5）のどちらかで絞る。
    /// `excluding`（正規化済み英単語）に含まれる語は除外。頻度順（やさしい順）。
    func leveledWords(dolch: String?, band: Int?, excluding: Set<String>, limit: Int) -> [LeveledWord] {
        guard let db else { return [] }
        var sql = "SELECT l.word, g.ja FROM level l JOIN gloss g ON g.word = l.word WHERE "
        if dolch != nil {
            sql += "l.dolch = ?"
        } else if band != nil {
            sql += "l.band = ?"
        } else {
            return []
        }
        sql += " ORDER BY (l.ngsl_rank IS NULL), l.ngsl_rank, l.word"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        if let dolch {
            sqlite3_bind_text(stmt, 1, dolch, -1, Self.transient)
        } else if let band {
            sqlite3_bind_int(stmt, 1, Int32(band))
        }
        var output: [LeveledWord] = []
        let cap = min(max(limit, 1), 100)
        while sqlite3_step(stmt) == SQLITE_ROW, output.count < cap {
            let word = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let ja = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if !word.isEmpty, !ja.isEmpty, !excluding.contains(word) {
                output.append(LeveledWord(word: word, ja: ja))
            }
        }
        return output
    }
}

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

    @Published var homeReviewWordIDs: Set<UUID> {
        didSet { saveHomeReviewWordIDs() }
    }

    @Published var focusedPracticeWordIDs = Set<UUID>()

    static let practiceCoinReward = 3
    static let defaultCharacterID = HomeRewardCharacter.defaultID
    static let defaultUnlockedCharacterIDs: Set<String> = HomeRewardCharacter.defaultUnlockedIDs

    private let persistenceStore: AppPersistenceStore
    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let practiceSamplesKey = "spellingTrainer.practiceSamples"
    private let schoolTestResultsKey = "spellingTrainer.schoolTestResults"
    private let settingsKey = "spellingTrainer.settings"
    private let selectedWordStepIDKey = "spellingTrainer.selectedWordStepID"
    private let rewardCoinsKey = "spellingTrainer.rewardCoins"
    private let selectedCharacterIDKey = "spellingTrainer.selectedCharacterID"
    private let unlockedCharacterIDsKey = "spellingTrainer.unlockedCharacterIDs"
    private let homeReviewWordIDsKey = "spellingTrainer.homeReviewWordIDs"

    init(persistenceStore: AppPersistenceStore = AppPersistenceStore()) {
        self.persistenceStore = persistenceStore

        let loadedWords = persistenceStore.load([SpellingWord].self, key: wordsKey) ?? [
            SpellingWord(text: "cat", promptText: "ねこ"),
            SpellingWord(text: "dog", promptText: "いぬ"),
            SpellingWord(text: "friend", promptText: "友[とも]だち"),
            SpellingWord(text: "school", promptText: "学校[がっこう]")
        ]
        words = loadedWords
        attempts = persistenceStore.load([SpellingAttempt].self, key: attemptsKey) ?? []
        practiceSamples = persistenceStore.load([PracticeSample].self, key: practiceSamplesKey) ?? []
        schoolTestResults = persistenceStore.load([SchoolTestResult].self, key: schoolTestResultsKey) ?? []
        settings = persistenceStore.load(TestSettings.self, key: settingsKey) ?? TestSettings()
        selectedWordStepID = persistenceStore.load(String.self, key: selectedWordStepIDKey) ?? Self.defaultWordStepID(for: loadedWords)
        rewardCoins = max(persistenceStore.load(Int.self, key: rewardCoinsKey) ?? 0, 0)
        let initialUnlockedCharacterIDs = (persistenceStore.load(Set<String>.self, key: unlockedCharacterIDsKey) ?? []).union(Self.defaultUnlockedCharacterIDs)
        unlockedCharacterIDs = initialUnlockedCharacterIDs
        homeReviewWordIDs = persistenceStore.load(Set<UUID>.self, key: homeReviewWordIDsKey) ?? []
        let savedCharacterID = persistenceStore.load(String.self, key: selectedCharacterIDKey) ?? Self.defaultCharacterID
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

    var totalLearnedWordCount: Int {
        let practicedWords = practiceSamples.map { normalize($0.word) }
        let testedWords = attempts.map { normalize($0.word) }
        return Set((practicedWords + testedWords).filter { !$0.isEmpty }).count
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

    func todayProgress(for step: WordStep) -> TodayStepProgress {
        todayStepProgress(for: step.words)
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
        // こども専用ステップは前のステップの復習を引き継がない（親の単語と混ざらないように）。
        guard !step.isChildStep, let previousStep = previousWordStep(before: step) else {
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
        // こども専用ステップはスキップして直前の親ステップを探す。
        for previousIndex in stride(from: index - 1, through: 0, by: -1) where !steps[previousIndex].isChildStep {
            return steps[previousIndex]
        }
        return nil
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
        hasPerfectRun(for: sourceWords, in: todayAttempts)
    }

    /// 1セッション内で対象単語をすべて一発正解（満点）にしたことがあるか。
    private func hasPerfectRun(for sourceWords: [SpellingWord], in attempts: [SpellingAttempt]) -> Bool {
        let sourceTexts = Set(sourceWords.map { normalize($0.text) })
        guard !sourceTexts.isEmpty else {
            return false
        }

        let sessions = Dictionary(grouping: attempts) { $0.sessionID }
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

    /// こどもが登録した単語をまとめる専用ステップのID（最初のこどもステップ）。
    static let childWordStepID = "child-words"

    /// こどもステップのIDか判定する（旧来の固定ID＋連番つきの新IDの両方）。
    /// 別IDの誤判定を避けるため、完全一致か "child-words-" 接頭辞のみを許可する。
    static func isChildStepID(_ id: String) -> Bool {
        id == childWordStepID || id.hasPrefix(childWordStepID + "-")
    }

    /// 2つめ以降のこどもステップ用にユニークなIDを作る。
    private static func uniqueChildStepID() -> String {
        "\(childWordStepID)-\(UUID().uuidString.prefix(8))"
    }

    /// 今いちばん新しいこどものたんごステップ。
    var latestChildStep: WordStep? {
        wordSteps.last { $0.isChildStep }
    }

    /// そのこどもステップを満点（1セッション一発全正解）でクリアしたか。
    /// 過去ぶんも含めて判定するので、いちど満点にすれば次の追加が解放される。
    func childStepIsMastered(_ step: WordStep) -> Bool {
        hasPerfectRun(for: step.words, in: attempts)
    }

    /// 指定IDの単語をまとめて削除する（親メニューの一括削除用）。
    func deleteWords(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }
        let remaining = words.filter { !ids.contains($0.id) }
        if remaining.count != words.count {
            words = remaining
        }
    }

    func replaceWords(from rawText: String) {
        let entries = parseWordListEntries(from: rawText)
        let now = Date()
        // こどもが登録した単語は親の一括編集の対象外として残す。
        let childWords = words.filter { $0.source == .child }
        let parentWords = words.filter { $0.source != .child }
        var existingWordsByText: [String: SpellingWord] = [:]
        for word in parentWords {
            let key = normalize(word.text)
            if existingWordsByText[key] == nil {
                existingWordsByText[key] = word
            }
        }

        let updatedParentWords = entries.map { entry in
            let key = normalize(entry.text)
            var word = existingWordsByText[key] ?? SpellingWord(text: key, registeredAt: now)
            word.text = key
            if let promptText = entry.promptText {
                word.promptText = promptText
            }
            return word
        }
        let addedNewWords = updatedParentWords.contains { existingWordsByText[normalize($0.text)] == nil }

        words = updatedParentWords + childWords
        if addedNewWords {
            selectedWordStepID = Self.defaultWordStepID(for: words)
        }
    }

    /// こどもが自分のたんごメニューから登録する。
    /// ルール: 今いちばん新しいこどもステップを満点にするまでは追加できない。
    /// 満点になったら、追加ぶんは「こどものたんご（連番）」の新しいステップとして作る。
    @discardableResult
    func addChildWords(from rawText: String) -> ChildWordAddResult {
        let entries = parseWordListEntries(from: rawText)
        guard !entries.isEmpty else {
            return .noNewWords
        }

        // 今のこどもステップが満点（100点）未達なら、新しい追加をブロックする。
        if let current = latestChildStep, !childStepIsMastered(current) {
            return .blocked
        }

        let now = Date()
        // 最初のこどもステップは旧来の固定IDを使い、2つめ以降はユニークIDで新ステップを作る。
        let hasExistingChildStep = words.contains { Self.isChildStepID($0.stepID ?? "") }
        let targetStepID = hasExistingChildStep ? Self.uniqueChildStepID() : Self.childWordStepID

        var updatedWords = words
        // 既存のこどもステップにある単語はキーに含めて重複登録を防ぐ。
        // （同じ単語で新ステップを作って満点ゲートをすり抜けるのも抑止できる）
        var addedKeys = Set(
            words.filter { Self.isChildStepID($0.stepID ?? "") }.map { normalize($0.text) }
        )
        var addedCount = 0

        for entry in entries {
            let key = normalize(entry.text)
            guard !key.isEmpty, !addedKeys.contains(key) else {
                continue
            }
            addedKeys.insert(key)
            let promptText = entry.promptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            updatedWords.append(
                SpellingWord(
                    text: key,
                    promptText: promptText,
                    registeredAt: now,
                    stepID: targetStepID,
                    source: .child
                )
            )
            addedCount += 1
        }

        guard addedCount > 0 else {
            return .noNewWords
        }

        words = updatedWords
        // 表示ステップは勝手に切り替えない（親が選んでいた表示を維持。ステップえらびから移動できる）。
        ensureSelectedWordStepStillExists()

        return .added(addedCount)
    }

    @discardableResult
    func replaceWords(in step: WordStep, from rawText: String) -> Int {
        let entries = parseWordListEntries(from: rawText)
        guard !entries.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        let stepWords = words.filter { wordBelongs($0, to: step, calendar: calendar) }
        let explicitStepID = step.words.first { $0.stepID == step.id }?.stepID
        let fallbackRegisteredAt = stepWords.first?.registeredAt
            ?? Self.registrationDate(on: calendar.startOfDay(for: step.registeredDate), calendar: calendar)
        var existingWordsByText: [String: SpellingWord] = [:]

        for word in stepWords {
            let key = normalize(word.text)
            if existingWordsByText[key] == nil {
                existingWordsByText[key] = word
            }
        }

        // こども専用ステップを編集する場合は、新しい単語にも .child を付けて区別を保つ。
        let stepSource: WordSource = (step.isChildStep || step.id == Self.childWordStepID) ? .child : .parent

        let replacementWords = entries.map { entry in
            let key = normalize(entry.text)
            var word = existingWordsByText[key] ?? SpellingWord(
                text: key,
                registeredAt: fallbackRegisteredAt,
                stepID: explicitStepID,
                source: stepSource
            )
            word.text = key
            word.promptText = entry.promptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            word.stepID = explicitStepID
            word.source = stepSource
            return word
        }

        let untouchedWords = words.filter { !wordBelongs($0, to: step, calendar: calendar) }
        words = untouchedWords + replacementWords
        selectedWordStepID = step.id
        return replacementWords.count
    }

    @discardableResult
    func addWordsToStep(from rawText: String, registeredAt: Date = Date()) -> (added: Int, updated: Int) {
        let entries = parseWordListEntries(from: rawText)
        guard !entries.isEmpty else {
            return (0, 0)
        }

        let calendar = Calendar.current
        let stepDate = calendar.startOfDay(for: registeredAt)
        let storedDate = Self.registrationDate(on: stepDate, calendar: calendar)
        let stepID = Self.uniqueStepID(for: stepDate, calendar: calendar)
        var updatedWords = words
        var addedCount = 0

        for entry in entries {
            let key = normalize(entry.text)
            guard !key.isEmpty else {
                continue
            }

            let promptText = entry.promptText?.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedWords.append(SpellingWord(text: key, promptText: promptText ?? "", registeredAt: storedDate, stepID: stepID))
            addedCount += 1
        }

        if updatedWords != words {
            words = updatedWords
        }
        if addedCount > 0 {
            selectedWordStepID = stepID
        }

        return (addedCount, 0)
    }

    private func wordBelongs(_ word: SpellingWord, to step: WordStep, calendar: Calendar) -> Bool {
        if let stepID = word.stepID {
            return stepID == step.id
        }

        let wordDate = calendar.startOfDay(for: word.registeredAt)
        return Self.stepID(for: wordDate, calendar: calendar) == step.id
    }

    @discardableResult
    func addAttempt(
        word: String,
        recognizedText: String,
        decision: GradeDecision,
        drawingData: Data? = nil,
        canvasSize: DrawingCanvasSize? = nil,
        date: Date = Date(),
        sessionID: UUID = UUID()
    ) -> SpellingAttempt {
        let attempt = SpellingAttempt(
            word: normalize(word),
            recognizedText: normalize(recognizedText),
            decision: decision,
            drawingData: drawingData,
            canvasSize: canvasSize,
            date: date,
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

    @discardableResult
    func addSchoolTestResult(_ result: SchoolTestResult) -> SchoolTestResult {
        var savedResult = result
        if let index = schoolTestResults.firstIndex(where: { existingResult in
            schoolTestResultsShareSlot(existingResult, result)
        }) {
            savedResult.id = schoolTestResults[index].id
            schoolTestResults[index] = savedResult
        } else {
            schoolTestResults.append(savedResult)
        }
        return savedResult
    }

    func deleteSchoolTestResult(_ result: SchoolTestResult) {
        schoolTestResults.removeAll { $0.id == result.id }
    }

    private func schoolTestResultsShareSlot(_ lhs: SchoolTestResult, _ rhs: SchoolTestResult) -> Bool {
        Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date)
            && schoolTestResultsShareStep(lhs, rhs)
    }

    private func schoolTestResultsShareStep(_ lhs: SchoolTestResult, _ rhs: SchoolTestResult) -> Bool {
        if let lhsStepID = lhs.stepID, let rhsStepID = rhs.stepID {
            return lhsStepID == rhsStepID
        }
        if let lhsStepID = lhs.stepID {
            return schoolTestResultTitle(rhs.stepTitle, matchesStepID: lhsStepID)
        }
        if let rhsStepID = rhs.stepID {
            return schoolTestResultTitle(lhs.stepTitle, matchesStepID: rhsStepID)
        }
        return lhs.stepTitle == rhs.stepTitle
    }

    private func schoolTestResultTitle(_ title: String, matchesStepID stepID: String) -> Bool {
        guard let step = wordSteps.first(where: { $0.id == stepID }) else {
            return false
        }
        return [
            step.title(language: .japanese),
            step.title(language: .english)
        ].contains(title)
    }

    func sendReviewWordsToHome(_ wordIDs: Set<UUID>, stepID: String) {
        selectedWordStepID = stepID
        homeReviewWordIDs = wordIDs
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
        persistenceStore.save(words, key: wordsKey)
    }

    private func saveAttempts() {
        persistenceStore.save(attempts, key: attemptsKey)
    }

    private func savePracticeSamples() {
        persistenceStore.save(practiceSamples, key: practiceSamplesKey)
    }

    private func saveSchoolTestResults() {
        persistenceStore.save(schoolTestResults, key: schoolTestResultsKey)
    }

    private func saveSettings() {
        persistenceStore.save(settings, key: settingsKey)
    }

    private func saveSelectedWordStepID() {
        persistenceStore.save(selectedWordStepID, key: selectedWordStepIDKey)
    }

    private func saveRewardCoins() {
        persistenceStore.save(max(rewardCoins, 0), key: rewardCoinsKey)
    }

    private func saveSelectedCharacterID() {
        persistenceStore.save(selectedCharacterID, key: selectedCharacterIDKey)
    }

    private func saveUnlockedCharacterIDs() {
        persistenceStore.save(unlockedCharacterIDs, key: unlockedCharacterIDsKey)
    }

    private func saveHomeReviewWordIDs() {
        persistenceStore.save(homeReviewWordIDs, key: homeReviewWordIDsKey)
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
        var groups: [String: (date: Date, sortDate: Date, words: [SpellingWord])] = [:]

        for word in words {
            let date = calendar.startOfDay(for: word.registeredAt)
            let id = word.stepID ?? stepID(for: date, calendar: calendar)
            if groups[id] == nil {
                groups[id] = (date: date, sortDate: word.registeredAt, words: [])
            } else if let currentSortDate = groups[id]?.sortDate, word.registeredAt < currentSortDate {
                groups[id]?.sortDate = word.registeredAt
            }
            groups[id]?.words.append(word)
        }

        let sortedIDs = groups.keys.sorted {
            guard let left = groups[$0], let right = groups[$1] else {
                return $0 < $1
            }
            if left.date != right.date {
                return left.date < right.date
            }
            if left.sortDate != right.sortDate {
                return left.sortDate < right.sortDate
            }
            return $0 < $1
        }

        // こどもステップの総数。2つ以上あるときだけ連番を振る（1つなら番号なし）。
        let childStepIDs = sortedIDs.filter { isChildStepID($0) }
        let childOrdinalByID: [String: Int]
        if childStepIDs.count > 1 {
            childOrdinalByID = Dictionary(
                uniqueKeysWithValues: childStepIDs.enumerated().map { ($0.element, $0.offset + 1) }
            )
        } else {
            childOrdinalByID = [:]
        }

        return sortedIDs.enumerated().compactMap { index, id in
            guard let group = groups[id] else {
                return nil
            }
            return WordStep(
                id: id,
                number: index + 1,
                registeredDate: group.date,
                words: group.words,
                isChildStep: isChildStepID(id),
                childNumber: childOrdinalByID[id]
            )
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

    private static func uniqueStepID(for date: Date, calendar: Calendar) -> String {
        "\(stepID(for: date, calendar: calendar))-\(UUID().uuidString.prefix(8))"
    }

    private static func registrationDate(on day: Date, calendar: Calendar) -> Date {
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        ) ?? day
    }

}

/// iOS 17 でのみ存在した旧 SwiftData レコード。
/// iOS 16 対応に伴いファイル保存へ移行したため、いまは既存ユーザーのデータ移行(読み出し)専用。
@available(iOS 17, *)
@Model
final class PersistentJSONRecord {
    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var data: Data
    var updatedAt: Date

    init(key: String, data: Data, updatedAt: Date = Date()) {
        self.key = key
        self.data = data
        self.updatedAt = updatedAt
    }
}

/// キー → JSON Data のローカル保存。iOS 16 でも動くようファイル(Application Support)を主役にする。
/// 旧 SwiftData ストアにデータがある端末(iOS 17)では、初回に一度だけファイルへ移行する。
final class AppPersistenceStore: @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let persistenceQueue = DispatchQueue(
        label: "com.local.SpellingTrainer.filePersistence",
        qos: .utility
    )

    init() {
        if #available(iOS 17, *) {
            Self.migrateFromSwiftDataIfNeeded()
        }
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        if let data = Self.loadFileData(for: key),
           let value = try? decoder.decode(type, from: data) {
            return value
        }

        // 旧 UserDefaults 保存（文字列）からの取り込み。
        if let legacyString = UserDefaults.standard.string(forKey: key),
           let value = legacyString as? T {
            save(legacyString, key: key)
            return value
        }

        // 旧 UserDefaults 保存（Data）からの取り込み。
        guard let legacyData = UserDefaults.standard.data(forKey: key),
              let value = try? decoder.decode(type, from: legacyData) else {
            return nil
        }

        Self.persistenceQueue.async {
            // ファイル書き込みが成功したときだけ旧 UserDefaults を消す。
            // 失敗時は writeFileData が UserDefaults に退避するため、消すとデータを失う。
            if Self.writeFileData(legacyData, key: key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        return value
    }

    func save<T: Encodable & Sendable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        Self.persistenceQueue.async {
            // ファイル書き込み成功時のみ旧 UserDefaults を掃除する（失敗時は退避先なので残す）。
            if Self.writeFileData(data, key: key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// 旧 SwiftData ストアの全レコードを、対応するファイルが無ければファイルへ書き出す（初回のみ）。
    @available(iOS 17, *)
    private static func migrateFromSwiftDataIfNeeded() {
        let migrationFlagKey = "spellingTrainer.migratedFromSwiftData.v1"
        guard !UserDefaults.standard.bool(forKey: migrationFlagKey) else {
            return
        }

        let schema = Schema([PersistentJSONRecord.self])
        let configuration = ModelConfiguration("SpellingTrainerData", schema: schema)

        // コンテナ生成や fetch に失敗したらフラグを立てず、次回起動で再試行する
        // （一時的な失敗で既存データの移行機会を恒久的に失わないように）。
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]),
              let records = try? ModelContext(container).fetch(FetchDescriptor<PersistentJSONRecord>()) else {
            return
        }

        for record in records where loadFileData(for: record.key) == nil {
            writeFileData(record.data, key: record.key)
        }

        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    private static func loadFileData(for key: String) -> Data? {
        guard let url = storageURL(for: key, createDirectory: false) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// ファイルへ保存できたら true。失敗時は UserDefaults に退避して false を返す。
    @discardableResult
    private static func writeFileData(_ data: Data, key: String) -> Bool {
        guard let url = storageURL(for: key, createDirectory: true) else {
            UserDefaults.standard.set(data, forKey: key)
            return false
        }

        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            UserDefaults.standard.set(data, forKey: key)
            return false
        }
    }

    private static func storageURL(for key: String, createDirectory: Bool) -> URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directoryURL = baseURL.appendingPathComponent("SpellingTrainer", isDirectory: true)
        if createDirectory {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let safeName = key
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "_"
            }
        return directoryURL.appendingPathComponent(String(safeName)).appendingPathExtension("json")
    }
}
