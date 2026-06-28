import Foundation
import SQLite3
import StoreKit
import SwiftData
import SpellingSyncCore

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
            // 単語編集後の自動同期（同期由来の反映では起こさない）。
            if !isApplyingMergedWords { requestSync() }
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

    /// 課金（保護者プラン）が有効か。`StoreManager` が StoreKit2 から駆動する（`applyEntitlement`）。
    /// 起動直後・オフラインは保存したキャッシュ（失効時刻まで）で復元する。設定で直接は変えない。
    @Published private(set) var isSubscribed: Bool

    /// StoreKit2 の購入・権利・商品を扱うマネージャ（アプリ起動時に `startStoreKit()` で開始）。
    let store = StoreManager()

    /// デバッグ用：有料コンテンツを全解放（StoreKit なしで挙動確認）。
    /// 効果は DEBUG ビルドの `hasFullAccess` のみ。Release では無視される。
    @Published var debugUnlockAll: Bool {
        didSet { persistenceStore.save(debugUnlockAll, key: debugUnlockAllKey) }
    }

    /// デバッグ用：1日の新規導入上限（10語）を無効化して挙動確認する。
    /// 効果は DEBUG ビルドの `dailyCappedPracticeWords` のみ。Release では無視される。
    @Published var debugDisableDailyLimit: Bool {
        didSet { persistenceStore.save(debugDisableDailyLimit, key: debugDisableDailyLimitKey) }
    }

    /// 有料コンテンツへのフルアクセス権があるか（購読中 or デバッグ全解放）。
    /// コンテンツゲートの判定はこの値を使う。
    var hasFullAccess: Bool {
        #if DEBUG
        return isSubscribed || debugUnlockAll
        #else
        return isSubscribed
        #endif
    }

    /// 連続ログイン日数（スタンプ）。
    @Published var loginStreak: Int {
        didSet { persistenceStore.save(loginStreak, key: loginStreakKey) }
    }

    /// 最後にログイン報酬を付与した日。
    @Published var lastLoginDay: Date? {
        didSet { persistenceStore.save(lastLoginDay, key: lastLoginDayKey) }
    }

    /// 最後にテスト満点ボーナスを付与した日（1日1回の判定に使う）。
    @Published var lastPerfectBonusDay: Date? {
        didSet { persistenceStore.save(lastPerfectBonusDay, key: lastPerfectBonusDayKey) }
    }

    @Published var selectedCharacterID: String {
        didSet { saveSelectedCharacterID() }
    }

    @Published var unlockedCharacterIDs: Set<String> {
        didSet { saveUnlockedCharacterIDs() }
    }

    @Published var selectedBackgroundID: String {
        didSet { saveSelectedBackgroundID() }
    }

    @Published var unlockedBackgroundIDs: Set<String> {
        didSet { saveUnlockedBackgroundIDs() }
    }

    @Published var homeReviewWordIDs: Set<UUID> {
        didSet { saveHomeReviewWordIDs() }
    }

    /// 初回オンボーディング完了フラグ。false の間だけ初回フローを出す。
    @Published var hasCompletedOnboarding: Bool {
        didSet { persistenceStore.save(hasCompletedOnboarding, key: hasCompletedOnboardingKey) }
    }

    /// ホームの「タップで きせかえ」ヒントを既に1回出したか。初回起動の1セッションだけ出して以後は出さない。
    @Published var hasShownHomeCharacterHint: Bool {
        didSet { persistenceStore.save(hasShownHomeCharacterHint, key: hasShownHomeCharacterHintKey) }
    }

    /// 子どものニックネーム（任意）。ホームの呼びかけや将来のプロファイル表示名に使う。
    @Published var childName: String {
        didSet { persistenceStore.save(childName, key: childNameKey) }
    }

    /// 選んだ学年（`GradeLevel.rawValue`、未選択は空）。初期単語のシードに使う。
    @Published var selectedGrade: String {
        didSet { persistenceStore.save(selectedGrade, key: selectedGradeKey) }
    }

    /// 例文パーソナライズの登場人物（本人＋友達）。親が親ゲートの奥で登録。
    /// 未成年実名のため **v1 はローカル保存のみ**（Supabase 同期しない・解析に送らない）。
    /// 仕様: docs/personalized-sentences-spec-2026-06-28.md
    @Published var cast: Cast {
        didSet { persistenceStore.save(cast, key: castKey) }
    }

    @Published var focusedPracticeWordIDs = Set<UUID>()

    static let practiceCoinReward = 3
    static let defaultCharacterID = HomeRewardCharacter.defaultID
    static let defaultUnlockedCharacterIDs: Set<String> = HomeRewardCharacter.defaultUnlockedIDs
    static let defaultBackgroundID = HomeBackgroundTheme.defaultID
    static let defaultUnlockedBackgroundIDs: Set<String> = HomeBackgroundTheme.defaultUnlockedIDs

    private let persistenceStore: UserDataStore
    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let practiceSamplesKey = "spellingTrainer.practiceSamples"
    private let schoolTestResultsKey = "spellingTrainer.schoolTestResults"
    private let settingsKey = "spellingTrainer.settings"
    private let selectedWordStepIDKey = "spellingTrainer.selectedWordStepID"
    private let rewardCoinsKey = "spellingTrainer.rewardCoins"
    private let cachedEntitlementKey = "spellingTrainer.cachedEntitlement"
    private let debugUnlockAllKey = "spellingTrainer.debugUnlockAll"
    private let debugDisableDailyLimitKey = "spellingTrainer.debugDisableDailyLimit"
    private let loginStreakKey = "spellingTrainer.loginStreak"
    private let lastLoginDayKey = "spellingTrainer.lastLoginDay"
    private let lastPerfectBonusDayKey = "spellingTrainer.lastPerfectBonusDay"
    private let selectedCharacterIDKey = "spellingTrainer.selectedCharacterID"
    private let unlockedCharacterIDsKey = "spellingTrainer.unlockedCharacterIDs"
    private let selectedBackgroundIDKey = "spellingTrainer.selectedBackgroundID"
    private let unlockedBackgroundIDsKey = "spellingTrainer.unlockedBackgroundIDs"
    private let homeReviewWordIDsKey = "spellingTrainer.homeReviewWordIDs"
    private let hasCompletedOnboardingKey = "spellingTrainer.hasCompletedOnboarding"
    private let hasShownHomeCharacterHintKey = "spellingTrainer.hasShownHomeCharacterHint"
    private let childNameKey = "spellingTrainer.childName"
    private let selectedGradeKey = "spellingTrainer.selectedGrade"
    private let castKey = "spellingTrainer.cast"

    /// オンボーディング初期状態の判定に使う、同梱デフォルト単語（text＋訳語のペア）。
    /// text だけでなく訳語・件数も含めて厳密一致を見て、ユーザーが少しでも触っていたら置き換えない。
    private static let defaultSeedPairs: Set<String> = [
        "cat\u{1}ねこ", "dog\u{1}いぬ", "friend\u{1}友[とも]だち", "school\u{1}学校[がっこう]"
    ]

    init(persistenceStore: UserDataStore = AppPersistenceStore()) {
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
        let cachedEntitlement = persistenceStore.load(CachedEntitlement.self, key: cachedEntitlementKey) ?? .none
        isSubscribed = cachedEntitlement.isActive(now: Date())
        debugUnlockAll = persistenceStore.load(Bool.self, key: debugUnlockAllKey) ?? false
        debugDisableDailyLimit = persistenceStore.load(Bool.self, key: debugDisableDailyLimitKey) ?? false
        loginStreak = max(persistenceStore.load(Int.self, key: loginStreakKey) ?? 0, 0)
        lastLoginDay = persistenceStore.load(Date.self, key: lastLoginDayKey)
        lastPerfectBonusDay = persistenceStore.load(Date.self, key: lastPerfectBonusDayKey)
        let initialUnlockedCharacterIDs = (persistenceStore.load(Set<String>.self, key: unlockedCharacterIDsKey) ?? []).union(Self.defaultUnlockedCharacterIDs)
        unlockedCharacterIDs = initialUnlockedCharacterIDs
        homeReviewWordIDs = persistenceStore.load(Set<UUID>.self, key: homeReviewWordIDsKey) ?? []
        hasCompletedOnboarding = persistenceStore.load(Bool.self, key: hasCompletedOnboardingKey) ?? false
        hasShownHomeCharacterHint = persistenceStore.load(Bool.self, key: hasShownHomeCharacterHintKey) ?? false
        childName = persistenceStore.load(String.self, key: childNameKey) ?? ""
        selectedGrade = persistenceStore.load(String.self, key: selectedGradeKey) ?? ""
        cast = persistenceStore.load(Cast.self, key: castKey) ?? Cast()
        let savedCharacterID = persistenceStore.load(String.self, key: selectedCharacterIDKey) ?? Self.defaultCharacterID
        selectedCharacterID = initialUnlockedCharacterIDs.contains(savedCharacterID) ? savedCharacterID : Self.defaultCharacterID
        let initialUnlockedBackgroundIDs = (persistenceStore.load(Set<String>.self, key: unlockedBackgroundIDsKey) ?? []).union(Self.defaultUnlockedBackgroundIDs)
        unlockedBackgroundIDs = initialUnlockedBackgroundIDs
        let savedBackgroundID = persistenceStore.load(String.self, key: selectedBackgroundIDKey) ?? Self.defaultBackgroundID
        selectedBackgroundID = initialUnlockedBackgroundIDs.contains(savedBackgroundID) ? savedBackgroundID : Self.defaultBackgroundID
        #if DEBUG
        if UITestSupport.isActive {
            hasCompletedOnboarding = true   // UIテストはオンボーディングを飛ばしてホームから開始する
        }
        #endif
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

    // MARK: - 1日の新規導入上限（学習リズム / 課金とは無関係）

    /// これまでに練習・テストで触れた語（正規化テキスト）の集合。
    private var practicedWordTexts: Set<String> {
        let practiced = practiceSamples.map { normalize($0.word) }
        let tested = attempts.map { normalize($0.word) }
        return Set((practiced + tested).filter { !$0.isEmpty })
    }

    /// その語が「未導入かつ未練習の新規候補」か。既習語や導入済み語は false。
    /// 既存データ（`firstIntroducedAt == nil` だが練習済み）は新規候補に含めない。
    func isNewWordCandidate(_ word: SpellingWord, practicedTexts: Set<String>? = nil) -> Bool {
        guard word.firstIntroducedAt == nil else { return false }
        let practiced = practicedTexts ?? practicedWordTexts
        return !practiced.contains(normalize(word.text))
    }

    /// 今日すでに新規導入した語数（全単語の `firstIntroducedAt` から決定的に数える）。
    func newWordsIntroducedToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        NewWordBudget.introducedCount(
            firstIntroducedDates: words.map(\.firstIntroducedAt),
            today: now,
            calendar: calendar
        )
    }

    /// 「アクティブ全語をそのまま練習する」既定選択のときだけ、1日の新規導入上限を適用する。
    /// 明示的な部分選択（復習・フォーカス・リトライ）は `isFullActiveSelection == false` で素通り。
    /// 既習・導入済み語は常に残し、新規候補だけ残り枠ぶんに絞る。
    func dailyCappedPracticeWords(
        _ selected: [SpellingWord],
        isFullActiveSelection: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SpellingWord] {
        #if DEBUG
        if debugDisableDailyLimit { return selected }
        #endif
        guard isFullActiveSelection else { return selected }
        let practiced = practicedWordTexts
        let flags = selected.map { isNewWordCandidate($0, practicedTexts: practiced) }
        let keep = NewWordBudget.cappedIndices(
            isNewCandidate: flags,
            introducedToday: newWordsIntroducedToday(now: now, calendar: calendar)
        )
        return keep.map { selected[$0] }
    }

    /// 練習に新規導入した語へ `firstIntroducedAt` を一度だけスタンプする（冪等）。
    /// 新規候補（未導入かつ未練習）だけを対象にし、既習語の誤スタンプを避ける。
    func stampFirstIntroducedIfNeeded(_ candidates: [SpellingWord], at date: Date = Date()) {
        let practiced = practicedWordTexts
        let ids = Set(candidates.filter { isNewWordCandidate($0, practicedTexts: practiced) }.map(\.id))
        guard !ids.isEmpty else { return }
        // ローカルコピーを一括更新してから 1 回だけ代入する（didSet の保存/同期要求の連発を避ける）。
        var updated = words
        var changed = false
        for i in updated.indices where ids.contains(updated[i].id) && updated[i].firstIntroducedAt == nil {
            updated[i].firstIntroducedAt = date
            changed = true
        }
        if changed { words = updated }
    }

    // MARK: - 課金権利（StoreKit2 / StoreManager から駆動）

    /// アプリ起動時に StoreKit を開始する（商品ロード・取引監視・権利の再検証）。
    func startStoreKit() {
        store.start(appModel: self)
    }

    /// `StoreManager` が検証した権利を反映し、オフライン用キャッシュに保存する。
    /// - active: いずれかの保護者プランの権利が有効か。
    /// - expiresAt: 現在の期間終了（失効）時刻。キャッシュの有効判定に使う。
    func applyEntitlement(active: Bool, expiresAt: Date?) {
        isSubscribed = active
        let cached = CachedEntitlement(isSubscribed: active, expiresAt: expiresAt)
        persistenceStore.save(cached, key: cachedEntitlementKey)
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

    /// 直近 `days` 日（当日含む）の学習レポートを作る。
    /// テスト(attempts)はクリア可否つき、練習(practiceSamples)は「取り組み(=未クリア)」として集計に含める。
    /// 純粋集計は `SpellingSyncCore.LearningReportBuilder`。
    func learningReport(days: Int, now: Date = Date(), calendar: Calendar = .current) -> LearningReport {
        let to = now
        let from = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
        var events: [LearningEvent] = attempts.map {
            LearningEvent(word: normalize($0.word), date: $0.date, cleared: isCleared($0))
        }
        events += practiceSamples.map {
            LearningEvent(word: normalize($0.word), date: $0.date, cleared: false)
        }
        return LearningReportBuilder.build(events: events, from: from, to: to, calendar: calendar)
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

    // MARK: - words 同期（サイドカー方式 / SpellingSyncCore）

    /// `words` の 1 サイクル同期を回すコーディネータ（pull→merge→push）。
    /// AppModel の永続化ストアを共有し、サイドカー/カーソルを端末に保存する。
    private lazy var wordSyncCoordinator = WordSyncCoordinator(persistenceStore: persistenceStore)

    /// UI 単語 → 同期素材（`LocalWord`）。
    /// - `displayOrder` は配列インデックス（並び順をそのまま順序に写す）。
    /// - `stepID` は **同期しない**（ローカルの派生ステップで、サーバー `step_id`(UUID) と一致しない。§7.5）。
    func localWordsForSync() -> [LocalWord] {
        words.enumerated().map { index, word in
            LocalWord(
                id: word.id,
                payload: WordPayload(
                    text: word.text,
                    promptText: word.promptText,
                    source: word.source.rawValue,
                    stepID: nil,
                    displayOrder: index
                ),
                createdAt: word.registeredAt
            )
        }
    }

    /// マージ後の生存レコードを `words` に反映する。
    /// - 既存 id は `stepID`/`registeredAt`（ローカル固有値）を保持し、本文だけ更新する。
    /// - 墓石になった id は除外される（生存レコードのみ渡される前提）。
    /// - 並びは `displayOrder` 昇順（同値は id で安定化）。
    func applyMergedWords(_ live: [WordSyncRecord]) {
        let existingByID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mapped = live
            .sorted {
                $0.payload.displayOrder != $1.payload.displayOrder
                    ? $0.payload.displayOrder < $1.payload.displayOrder
                    : $0.sync.id.uuidString < $1.sync.id.uuidString
            }
            .map { record -> SpellingWord in
                let prior = existingByID[record.sync.id]
                return SpellingWord(
                    id: record.sync.id,
                    text: record.payload.text,
                    promptText: record.payload.promptText,
                    registeredAt: prior?.registeredAt ?? record.sync.createdAt,
                    stepID: prior?.stepID,                                   // ローカルのステップ割当を保持
                    source: WordSource(rawValue: record.payload.source) ?? .parent,
                    firstIntroducedAt: prior?.firstIntroducedAt              // 学習リズムのローカル値を保持（同期で消さない）
                )
            }
        if mapped != words {
            // 同期由来の更新では編集トリガ（requestSync）を起こさない。
            isApplyingMergedWords = true
            words = mapped
            isApplyingMergedWords = false
        }
    }

    /// `words` を 1 サイクル同期する（世帯未選択なら何もしない）。
    func syncWords(householdID: UUID?) async throws {
        try await wordSyncCoordinator.sync(appModel: self, householdID: householdID)
    }

    // MARK: 自動同期トリガ（前面化／編集後／サインイン・世帯確定時）

    /// アクティブ世帯の供給元。アプリ起動時に `SyncSession` を注入する（未設定なら同期は無効）。
    private var householdIDProvider: () -> UUID? = { nil }
    /// 編集連打をまとめるためのデバウンス用タスク。
    private var pendingSyncTask: Task<Void, Never>?
    /// `applyMergedWords` による `words` 更新が、編集トリガを再帰的に誘発しないためのフラグ。
    private var isApplyingMergedWords = false

    /// 学年に合った初期単語をシードする（オンボーディングで学年を選んだとき）。
    /// - ユーザーがまだ単語をいじっていない（＝同梱デフォルトのまま）ときだけ置き換える。
    ///   既存ユーザーのアップグレード時に、本人の単語を消さないための保険。
    func seedStarterWordsIfDefault(for grade: GradeLevel) {
        selectedGrade = grade.rawValue
        let current = Set(words.map { "\($0.text.lowercased())\u{1}\($0.promptText)" })
        guard current == Self.defaultSeedPairs else { return }   // 触っていたら置き換えない
        words = StarterWords.seeds(for: grade).map {
            SpellingWord(text: $0.text, promptText: $0.promptText)
        }
    }

    /// 自動同期の世帯供給元を設定する（アプリ起動時に 1 回）。
    func configureSync(householdIDProvider: @escaping () -> UUID?) {
        self.householdIDProvider = householdIDProvider
    }

    /// 即時に 1 サイクル同期する（前面化・サインイン・世帯確定時など）。
    /// バックグラウンド同期なので失敗は握りつぶす（次トリガで回収。多重実行は coordinator がガード）。
    func syncNow() async {
        guard let household = householdIDProvider() else { return }
        do { try await syncWords(householdID: household) }
        catch { /* バックグラウンド同期: 失敗は次トリガで回収 */ }
    }

    /// デバウンス付きで同期を要求する（単語の編集直後などに呼ぶ）。
    /// 直前の予約はキャンセルし、`seconds` 静かになってから 1 回だけ走らせる。
    /// **発火時に世帯が変わっていたら破棄**する（古い世帯のローカル編集を新世帯へ流さない）。
    func requestSync(debounce seconds: Double = 1.5) {
        guard let scheduledHousehold = householdIDProvider() else { return }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            guard self.householdIDProvider() == scheduledHousehold else { return }
            await self.syncNow()
        }
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

    /// 文づくり等で出会った「知らない語」を、その場で復習に積む軽量登録。
    /// `addChildWords` の満点ゲート/新ステップ生成は通さず、既存のこどもステップへ 1 語足すだけ。
    /// すでに語彙にある語は二重登録しない（既存の SRS/復習にそのまま乗る）。
    /// 戻り値: 実際に新規追加したら true。
    /// 設計: docs/sentence-builder-design-2026-06-27.md（未習語タップ→復習導線）
    @discardableResult
    func enrollReviewWord(_ rawText: String, at now: Date = Date()) -> Bool {
        let key = normalize(rawText)
        guard !key.isEmpty else { return false }
        guard !words.contains(where: { normalize($0.text) == key }) else { return false }
        // 過去の満点済みステップを書き換えないよう、最新のこどもステップへ積む（無ければ正準ID）。
        let stepID = latestChildStep?.id ?? Self.childWordStepID
        words.append(
            SpellingWord(
                text: key,
                promptText: "",
                registeredAt: now,
                stepID: stepID,
                source: .child
            )
        )
        ensureSelectedWordStepStillExists()
        return true
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

    /// 今日まだなら連続ログイン報酬を付与し、結果（連続日数・コイン）を返す。付与済みなら nil。
    func recordDailyLogin(now: Date = Date(), calendar: Calendar = .current) -> CoinRewards.LoginOutcome? {
        guard let outcome = CoinRewards.dailyLogin(
            lastLogin: lastLoginDay, today: now, currentStreak: loginStreak, calendar: calendar
        ) else { return nil }
        loginStreak = outcome.streak
        lastLoginDay = now
        rewardCoins = max(rewardCoins + outcome.coins, 0)
        return outcome
    }

    /// テスト満点ボーナス。**今日まだ**なら単語数に応じた 5〜10 コインを付与し、その額を返す。
    /// すでに今日付与済みなら nil（1日1回）。途中で単語を足していても、完了した問題数で計算する。
    func awardPerfectTestBonusIfEligible(wordCount: Int, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard CoinRewards.canAwardPerfectBonus(lastAward: lastPerfectBonusDay, today: now, calendar: calendar) else {
            return nil
        }
        let bonus = CoinRewards.perfectTestBonus(wordCount: wordCount)
        lastPerfectBonusDay = now
        rewardCoins = max(rewardCoins + bonus, 0)
        return bonus
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

    func selectBackground(id: String) {
        guard unlockedBackgroundIDs.contains(id) else {
            return
        }
        selectedBackgroundID = id
    }

    @discardableResult
    func unlockBackground(id: String, cost: Int) -> Bool {
        if unlockedBackgroundIDs.contains(id) {
            selectedBackgroundID = id
            return true
        }

        let safeCost = max(cost, 0)
        guard rewardCoins >= safeCost else {
            return false
        }

        rewardCoins -= safeCost
        var updatedUnlockedIDs = unlockedBackgroundIDs
        updatedUnlockedIDs.insert(id)
        unlockedBackgroundIDs = updatedUnlockedIDs
        selectedBackgroundID = id
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

    private func saveSelectedBackgroundID() {
        persistenceStore.save(selectedBackgroundID, key: selectedBackgroundIDKey)
    }

    private func saveUnlockedBackgroundIDs() {
        persistenceStore.save(unlockedBackgroundIDs, key: unlockedBackgroundIDsKey)
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

/// ユーザーデータを「キー → Codable 値」で永続化する境界。
///
/// 既定実装はローカルファイル保存の `AppPersistenceStore`。
/// 将来 CloudKit 同期（`NSPersistentCloudKitContainer`）へ移行する際は、この protocol に
/// 準拠した別ストアを `AppModel(persistenceStore:)` に注入するだけで差し替えられる。
/// `AppModel` は具象ストアではなくこの境界にのみ依存する。
/// 設計の全体像は docs/multi-user-cloudkit-sync-design.md を参照。
protocol UserDataStore: Sendable {
    func load<T: Decodable>(_ type: T.Type, key: String) -> T?
    func save<T: Encodable & Sendable>(_ value: T, key: String)
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

// ローカルファイル保存を `UserDataStore` 境界に適合させる。
// `load`/`save` は既存シグネチャと一致するため、宣言のみで準拠が成立する。
extension AppPersistenceStore: UserDataStore {}

// MARK: - UIテスト支援（E2E）

/// UIテスト（XCUITest）からの起動かどうか。**Release では常に false**（`#if DEBUG` で無効）。
/// 起動引数 `-uitests` で、状態リセット（揮発ストア）・親ゲートのバイパス・初期タブを切り替える。
enum UITestSupport {
    static var isActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitests")
        #else
        return false
        #endif
    }

    /// 起動時に親メニューを自動で開く（ホームのギアは bounce 付きで XCUITest の合成タップを飲むため迂回）。
    static var opensParentOnLaunch: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitest-open-parent")
        #else
        return false
        #endif
    }
}

#if DEBUG
/// UIテスト用の**揮発**永続ストア（毎起動まっさら）。実ファイルを汚さない。DEBUG ビルドのみ。
final class InMemoryUserDataStore: UserDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = try? JSONEncoder().encode(value)
    }
}
#endif

// MARK: - StoreManager（StoreKit2）

/// 保護者プランの商品ロード・購入・復元・権利検証を担う薄い I/O 層。
///
/// 開発中はローカルの `Products.storekit` 構成で購入フローをシミュレータ検証できる
/// （Apple Developer 登録・課金は不要）。本番化のときは同じ Product ID で
/// App Store Connect に商品を作るだけ。権利の決定的判定（オフライン）は
/// `SpellingSyncCore.CachedEntitlement` 側にある。
@MainActor
final class StoreManager: ObservableObject {
    /// Product ID（App Store Connect / Products.storekit と一致させること）。
    static let monthlyID = "com.yuta090.SpellingTrainer.parentplan.monthly"
    static let yearlyID = "com.yuta090.SpellingTrainer.parentplan.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    enum PlanKind { case monthly, yearly }
    enum StoreError: Error { case failedVerification }
    enum PurchaseOutcome { case success, pending, cancelled }

    /// ロード済み商品（年額→月額の順）。`.storekit` 未設定時は空のまま。
    @Published private(set) var products: [Product] = []
    /// 現在有効な権利の Product ID 集合。
    @Published private(set) var purchasedProductIDs: Set<String> = []
    /// 無料トライアル（Introductory Offer）の対象か。再課金者には false。
    @Published private(set) var isTrialEligible = false
    /// 購入処理中フラグ（UI のスピナー用）。
    @Published private(set) var purchaseInFlight = false

    private weak var appModel: AppModel?
    private var updatesTask: Task<Void, Never>?

    /// 取引監視を開始し、商品ロードと権利の再検証を行う（多重開始はガード）。
    func start(appModel: AppModel) {
        self.appModel = appModel
        if updatesTask == nil {
            updatesTask = observeTransactionUpdates()
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    /// 指定プランの商品。
    func product(for plan: PlanKind) -> Product? {
        let id = plan == .yearly ? Self.yearlyID : Self.monthlyID
        return products.first { $0.id == id }
    }

    /// 商品をロードする（価格・トライアル文言の表示に使う）。失敗時は空のまま（UI はフォールバック）。
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // 年額（高い方）を先頭に。
            products = loaded.sorted { $0.price > $1.price }
            await refreshTrialEligibility()
        } catch {
            // 取得失敗（`.storekit` 未設定/ネット断など）。UI は固定文言にフォールバックする。
        }
    }

    /// トライアル対象かを更新する（サブスクグループ単位）。
    func refreshTrialEligibility() async {
        guard let subscription = products.first?.subscription else {
            isTrialEligible = false
            return
        }
        isTrialEligible = await subscription.isEligibleForIntroOffer
    }

    /// 購入する。成功・承認待ち・キャンセルを返す。
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return .success
        case .pending:
            // 承認待ち（ファミリー承認など）。後で Transaction.updates が反映する。
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// 購入を復元する（App Store と同期して権利を再検証）。商品ロードに依存しない。
    func restore() async throws {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        try await AppStore.sync()
        await refreshEntitlements()
    }

    /// 現在の権利を集計して AppModel に反映する。
    func refreshEntitlements() async {
        var active: Set<String> = []
        var latestExpiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // 自動更新サブスクのみを権利として扱う（誤設定の非更新商品で永久解放されない保険）。
            guard Self.productIDs.contains(transaction.productID),
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil else { continue }
            active.insert(transaction.productID)
            if let expiration = transaction.expirationDate {
                latestExpiry = max(latestExpiry ?? expiration, expiration)
            }
        }
        // TODO(本番): 課金リトライ/猶予期間(grace)では expirationDate が過去になり得る。
        // オフライン継続のため SubscriptionInfo.Status / gracePeriodExpirationDate からキャッシュ失効を導出する。
        purchasedProductIDs = active
        await refreshTrialEligibility()
        appModel?.applyEntitlement(active: !active.isEmpty, expiresAt: latestExpiry)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }
}
