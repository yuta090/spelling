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

    /// 英単語の英語の主品詞（"noun" / "verb" / "adjective"）。
    /// おぼえる練習で英文フレーム（I like ___ / I can ___ / It is ___）を選ぶのに使う。
    /// 同梱の `pos` テーブル（Moby PD 由来）に無い語（約6%）は nil ＝意味のみ4択へフォールバック。
    func partOfSpeech(for word: String) -> String? {
        // 非ASCII英字（アクセント・記号）を含む語は弾く。normalize は a-z だけ残すため、
        // "naïve" → "nave" のように**別語へ衝突**して誤った品詞/フレームを引くのを防ぐ。
        let lowered = word.lowercased()
        guard lowered.allSatisfy({ $0 == "-" || $0 == " " || ($0.isASCII && $0.isLetter) }) else { return nil }
        let key = normalize(word)
        guard !key.isEmpty, let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT pos FROM pos WHERE word = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
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

    /// コース生成用：訳ありの leveled 語を**全件**頻度順で返す（rank での範囲スライスは Core `CourseCatalog` 側）。
    /// 決定論のため NULL rank は除外し `(ngsl_rank, word)` で並べる。
    func rankedLeveledRows() -> [LeveledRow] {
        guard let db else { return [] }
        let sql = """
        SELECT l.word, g.ja, l.ngsl_rank FROM level l \
        JOIN gloss g ON g.word = l.word \
        WHERE l.ngsl_rank IS NOT NULL ORDER BY l.ngsl_rank, l.word
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        var output: [LeveledRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let word = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let ja = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let rank = Int(sqlite3_column_int(stmt, 2))
            if !word.isEmpty, !ja.isEmpty {
                output.append(LeveledRow(word: word, gloss: ja, ngslRank: rank))
            }
        }
        return output
    }

    /// Dolch コース生成用：`level.dolch` に値がある語＋訳を返す（帯順・フィルタは Core `buildDolchSteps` 側）。
    /// 安定のため word 昇順（最終順序は Core が決める）。
    func dolchRows() -> [DolchRow] {
        guard let db else { return [] }
        let sql = """
        SELECT l.word, g.ja, l.dolch FROM level l \
        JOIN gloss g ON g.word = l.word \
        WHERE l.dolch IS NOT NULL AND l.dolch <> '' ORDER BY l.word
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        var output: [DolchRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let word = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let ja = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let dolch = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            if !word.isEmpty, !ja.isEmpty, !dolch.isEmpty {
                output.append(DolchRow(word: word, gloss: ja, dolch: dolch))
            }
        }
        return output
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var words: [SpellingWord] = [] {
        didSet {
            // プロファイル再ロード中は didSet を止める（派生修復・同期要求が「間違ったプロファイルで」
            // 発火するのを防ぐ。設計§4・レビュー指摘④）。値は loadChildScopedState が正規スコープから入れる。
            guard !isReloadingProfile else { return }
            saveWords()
            ensureSelectedWordStepStillExists()
            // 単語編集後の自動同期（同期由来の反映では起こさない）。
            if !isApplyingMergedWords { requestSync() }
        }
    }

    @Published var attempts: [SpellingAttempt] = [] {
        didSet { guard !isReloadingProfile else { return }; saveAttempts() }
    }

    @Published var practiceSamples: [PracticeSample] = [] {
        didSet { guard !isReloadingProfile else { return }; savePracticeSamples() }
    }

    @Published var schoolTestResults: [SchoolTestResult] = [] {
        didSet { guard !isReloadingProfile else { return }; saveSchoolTestResults() }
    }

    @Published var settings: TestSettings = TestSettings() {
        didSet { guard !isReloadingProfile else { return }; saveSettings() }
    }

    /// 選択中のコース（personal / grade-N / eiken-xx）。学年×英検の2軸＋自分のトラック。
    @Published var selectedCourseID: String = "" {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(selectedCourseID, key: selectedCourseIDKey) }
    }

    /// コースごとに「選択中ステップ」を別々に覚える（コース切替で地図とステップが入れ替わる）。
    @Published private var selectedStepIDByCourse: [String: String] = [:] {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(selectedStepIDByCourse, key: selectedStepIDByCourseKey) }
    }

    /// アクティブコースに対する選択ステップID（既存呼出は無改修・computed で dict に橋渡し）。
    /// 見つからない場合の最終フォールバックは `selectedWordStep`（wordSteps.last）が担う。
    var selectedWordStepID: String {
        get { selectedStepIDByCourse[selectedCourseID] ?? "" }
        set { selectedStepIDByCourse[selectedCourseID] = newValue }
    }

    /// 子が自分でコースを切り替えてよいか。**既定はロック（親が決める）**。
    /// 親が設定で ON にしたときだけ、子は全コースを自分で選べる（gating は `CourseAccess`）。
    @Published var childCanSwitchCourses: Bool = false {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(childCanSwitchCourses, key: childCanSwitchCoursesKey) }
    }

    /// 親が「子に選ばせるコース」を絞り込む許可サブセット。
    /// **空 = 制限なし（全コース許可）＝既定**。非空 = その集合のみ（＋現在コースは常に選べる）。
    /// 効くのは `childCanSwitchCourses == true` のときだけ（ロック時は現在コースのみ）。
    @Published var allowedCourseIDs: Set<String> = [] {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(Array(allowedCourseIDs), key: allowedCourseIDsKey) }
    }

    /// 子の画面で選べるコースID（ロック時は現在コースのみ＝切替不可）。純ロジックは `CourseAccess`。
    var childSelectableCourseIDs: [String] {
        CourseAccess.childSelectableCourseIDs(
            allCourseIDs: CourseDirectory.all.map(\.id),
            activeCourseID: selectedCourseID,
            childCanSwitch: childCanSwitchCourses,
            allowedCourseIDs: allowedCourseIDs
        )
    }

    /// 親UI用：許可コースのトグル（含まれていれば外す／無ければ足す）。
    /// 空集合 = 制限なし（全部許可）の意味なので、UI 側は「何も選ばなければ全部」と案内する。
    func toggleAllowedCourse(_ id: String) {
        if allowedCourseIDs.contains(id) {
            allowedCourseIDs.remove(id)
        } else {
            allowedCourseIDs.insert(id)
        }
    }

    /// 利用可能コースから現在のコースを解決（不明は personal）。
    var activeCourse: Course {
        CourseDirectory.course(id: selectedCourseID) ?? CourseDirectory.personal
    }

    /// 仮想コース（学年/英検）のステップ供給（wordbank から合成・読み取り専用・キャッシュ）。
    private let courseProvider = CourseProvider()

    /// 永続「できた」（満点を一度取ったら固定）。stepID にコースIDが埋まるのでコース別タプル不要。
    @Published private var requiredCompletion: RequiredCompletion = RequiredCompletion() {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(requiredCompletion, key: requiredCompletionKey) }
    }

    @Published var rewardCoins: Int = 0 {
        didSet { guard !isReloadingProfile else { return }; saveRewardCoins() }
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

    #if DEBUG
    /// デバッグ用：テストで1問終わるごとに、手書きを3モデルのAI(VLM)へ送って判定を比較保存する。
    @Published var debugAIJudgeOnTest: Bool {
        didSet { persistenceStore.save(debugAIJudgeOnTest, key: debugAIJudgeOnTestKey) }
    }

    /// AI判定の比較レコード（最新が末尾）。デバッグページで親採点風に表示する。
    @Published var aiJudgments: [AIJudgmentRecord] = [] {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(aiJudgments, key: aiJudgmentsKey) }
    }

    /// AI判定の実行パラメータ（モデル/temperature/max_tokens）。ページで編集し送信時に反映。
    @Published var aiJudgeConfig: AIJudgeConfig {
        didSet { persistenceStore.save(aiJudgeConfig, key: aiJudgeConfigKey) }
    }

    /// 一括判定の進捗（実行中のみ非nil）。UIのボタン無効化・進捗表示に使う。
    @Published var aiBulkProgress: AIBulkProgress?
    #endif

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
    @Published var loginStreak: Int = 0 {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(loginStreak, key: loginStreakKey) }
    }

    /// 最後にログイン報酬を付与した日。
    @Published var lastLoginDay: Date? = nil {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(lastLoginDay, key: lastLoginDayKey) }
    }

    /// 最後にテスト満点ボーナスを付与した日（1日1回の判定に使う）。
    @Published var lastPerfectBonusDay: Date? = nil {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(lastPerfectBonusDay, key: lastPerfectBonusDayKey) }
    }

    /// ことばパズルを最後に「完了」した日（無料プランの1日2回ゲートの日替わり判定に使う）。
    @Published var puzzleLastPlayedDay: Date? = nil {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(puzzleLastPlayedDay, key: puzzleLastPlayedDayKey) }
    }
    /// その日にことばパズルを完了した回数。日付が変わると `DailyPlayLimiter` が 0 扱いにする。
    @Published var puzzlePlaysToday: Int = 0 {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(puzzlePlaysToday, key: puzzlePlaysTodayKey) }
    }

    /// 無料プランのことばパズル1日上限（完了＝1回）。プレミアム/デバッグ解放は別枠で無制限にする。
    private let puzzleLimiter = DailyPlayLimiter(dailyLimit: 2)

    /// 今日あと何回ことばパズルを遊べるか。プレミアム（フルアクセス）・デバッグ解放時は無制限。
    var puzzlePlaysRemainingToday: Int {
        if hasFullAccess { return Int.max }
        #if DEBUG
        if debugDisableDailyLimit { return Int.max }
        #endif
        return puzzleLimiter.remaining(lastPlayedDay: puzzleLastPlayedDay, storedCount: puzzlePlaysToday, today: Date())
    }

    /// ことばパズルを今すぐ始められるか（無料は1日2回まで）。
    var canPlayPuzzleToday: Bool { puzzlePlaysRemainingToday > 0 }

    /// ことばパズルを1回完了したときに呼ぶ（カウントを進めて永続化）。
    /// プレミアム/デバッグ時も記録自体は行うが、残り回数判定では無制限なので影響しない。
    func recordPuzzleCompletion() {
        let result = puzzleLimiter.recordingCompletion(
            lastPlayedDay: puzzleLastPlayedDay,
            storedCount: puzzlePlaysToday,
            today: Date()
        )
        puzzleLastPlayedDay = result.day
        puzzlePlaysToday = result.count
    }

    @Published var selectedCharacterID: String = "" {
        didSet { guard !isReloadingProfile else { return }; saveSelectedCharacterID() }
    }

    @Published var unlockedCharacterIDs: Set<String> = [] {
        didSet { guard !isReloadingProfile else { return }; saveUnlockedCharacterIDs() }
    }

    @Published var selectedBackgroundID: String = "" {
        didSet { guard !isReloadingProfile else { return }; saveSelectedBackgroundID() }
    }

    @Published var unlockedBackgroundIDs: Set<String> = [] {
        didSet { guard !isReloadingProfile else { return }; saveUnlockedBackgroundIDs() }
    }

    @Published var homeReviewWordIDs: Set<UUID> = [] {
        didSet { guard !isReloadingProfile else { return }; saveHomeReviewWordIDs() }
    }

    /// アプリ前面滞在時間の日別バケット（"yyyy-MM-dd" → 秒）。保護者「ようす」タブの利用時間表示用。
    /// 純粋操作は `SpellingSyncCore.UsageLog`。古い日は記録時にプルーンして保存量を抑える。
    @Published var usageLog: [String: Int] = [:] {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(usageLog, key: usageLogKey) }
    }

    /// 文づくり（文法クイズ）の復習キュー。間違えた文を「1度正解で即消す」のではなく、
    /// 今後のラウンドに少数（+1〜2問）ずつ追加問題として混ぜ、数回の正解で段階的に卒業させる。
    /// 純粋ロジックは `SpellingSyncCore.ReviewQueue`。`id` は `SentenceItem.id`。
    /// スペル側の復習（attempt 由来の導出型）とは別キューで独立管理する（活動ごとに分離）。
    @Published var grammarReviewStates: [ReviewItemState] = [] {
        didSet { guard !isReloadingProfile else { return }; saveGrammarReviewStates() }
    }

    /// 文法クイズの単調増加ステップ番号（再出題間隔の「刻み」）。1ラウンド完了ごとに +1。
    @Published var grammarReviewStep: Int = 0 {
        didSet { guard !isReloadingProfile else { return }; saveGrammarReviewStep() }
    }

    /// スペルテストの復習キュー（`id` は `SpellingWord.id`）。間違えた語を「1回正解で即消す」のではなく、
    /// 今後のテストに少数（最大2語）ずつ追加問題として混ぜ、数回の正解で段階的に卒業させる。
    /// 親向けの「見直しが必要な単語」表示（attempt 由来の導出型 = `unresolvedReviewWords`/`reviewWords`/
    /// `homeReviewWordIDs`）はこれとは別物として残す（子の練習スケジューリング専用）。純粋ロジックは `ReviewQueue`。
    @Published var spellingReviewStates: [ReviewItemState] = [] {
        didSet { guard !isReloadingProfile else { return }; saveSpellingReviewStates() }
    }

    /// スペルテストの単調増加ステップ番号（再出題間隔の「刻み」）。1テストセッション完了ごとに +1。
    @Published var spellingReviewStep: Int = 0 {
        didSet { guard !isReloadingProfile else { return }; saveSpellingReviewStep() }
    }

    /// 既存の未クリア語を復習キューへ一度だけ移行（シード）したか。
    @Published var spellingReviewSeeded: Bool = false {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(spellingReviewSeeded, key: spellingReviewSeededKey) }
    }

    /// 初回オンボーディング完了フラグ。false の間だけ初回フローを出す。
    @Published var hasCompletedOnboarding: Bool = false {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(hasCompletedOnboarding, key: hasCompletedOnboardingKey) }
    }

    /// ホームの「タップで きせかえ」ヒントを既に1回出したか。初回起動の1セッションだけ出して以後は出さない。
    @Published var hasShownHomeCharacterHint: Bool = false {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(hasShownHomeCharacterHint, key: hasShownHomeCharacterHintKey) }
    }

    /// 満点クリア後の「あたらしいクイズがでた！」アンロック演出を、各ステップ（単語セット署名）ごとに
    /// 1回だけ出すための記録。クリア判定そのものではない（クリア＝満点ゲートが唯一の基準）。
    @Published var stepUnlockCelebration: StepUnlockCelebration = StepUnlockCelebration() {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(stepUnlockCelebration, key: stepUnlockCelebrationKey) }
    }

    /// 子どものニックネーム（任意）。ホームの呼びかけや将来のプロファイル表示名に使う。
    /// **単一の真実（SSOT）は `profileRegistry.activeProfile.displayName`**（設計§3/§6・レビュー指摘⑥）。
    /// 旧 `spellingTrainer.childName` キーは Phase 2 の移行元として displayName に写した後は書かない
    /// （二重ソース化を防ぐ）。書き込みは Registry の改名として反映し、その場で台帳を永続化する。
    var childName: String {
        get { profileRegistry.activeProfile.displayName }
        set {
            guard newValue != profileRegistry.activeProfile.displayName else { return }
            profileRegistry = profileRegistry.renaming(profileRegistry.activeProfileID, to: newValue)
            persistRegistry()
        }
    }

    /// 選んだ学年（`GradeLevel.rawValue`、未選択は空）。オンボーディングで学年コースを選ぶ根拠、
    /// および漢字ゲート（`childMaxKanjiGrade`）／出題ティアの判断に使う。
    @Published var selectedGrade: String = "" {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(selectedGrade, key: selectedGradeKey) }
    }

    /// 子に見せる和訳で許す「漢字配当学年」(0…6)。1学年前ルール（小1→0＝ひらがな）。
    /// 学年未選択のときは安全側でひらがな（0）にする。例文・意味ヒントの漢字/かな出し分けに使う。
    var childMaxKanjiGrade: Int {
        guard let grade = GradeLevel(rawValue: selectedGrade) else { return 0 }
        return KanjiLevelGate.maxGrade(forSchoolGrade: grade.schoolGrade)
    }

    /// 子に英語例文を見せるか。低学年（小1・小2）は同梱例文にまだ習っていない語が混ざるため出さない
    /// （単語＋意味だけに割り切る）。学年未選択は安全側（tier a 相当）で非表示。意味（訳）は別軸で常に出す。
    var showsChildExampleSentence: Bool {
        let tier = GradeLevel(rawValue: selectedGrade)?.tier.contentTier ?? .a
        return ExampleSentencePolicy.showsEnglishExample(tier: tier)
    }

    /// 子の学年＋親トグルから決まる「出題プールの絞り込み制約」（Core・spec §10）。
    /// ことばパズルのプール組み立て入口で適用する。学年未選択は入門(a)扱いで安全側。
    var contentPolicy: ContentPolicy {
        let tier = GradeLevel(rawValue: selectedGrade)?.tier.contentTier ?? .a
        return ContentPolicy.standard(tier: tier, humorEnabled: settings.humorEnabled)
    }

    /// 例文パーソナライズの登場人物（本人＋友達）。親が親ゲートの奥で登録。
    /// 未成年実名のため **v1 はローカル保存のみ**（Supabase 同期しない・解析に送らない）。
    /// 仕様: docs/personalized-sentences-spec-2026-06-28.md
    @Published var cast: Cast = Cast() {
        didSet { guard !isReloadingProfile else { return }; persistenceStore.save(cast, key: castKey) }
    }

    @Published var focusedPracticeWordIDs = Set<UUID>()

    static let practiceCoinReward = 30
    static let defaultCharacterID = HomeRewardCharacter.defaultID
    static let defaultUnlockedCharacterIDs: Set<String> = HomeRewardCharacter.defaultUnlockedIDs
    static let defaultBackgroundID = HomeBackgroundTheme.defaultID
    static let defaultUnlockedBackgroundIDs: Set<String> = HomeBackgroundTheme.defaultUnlockedIDs

    private let persistenceStore: UserDataStore
    /// プロファイル台帳（複数子）。**この端末で誰がいるか＋今アクティブな子**の単一ソース。
    /// Phase 2 では移行で#1が入るだけ（切替UIは Phase 3）。同期の安全判定にも使う。
    @Published private(set) var profileRegistry: ProfileRegistry
    /// キー名前空間化の Core ラッパ（切替時に `setActiveProfileID` する）。
    /// 名前空間化できないストアが注入された場合は nil（単一子フォールバック）。
    private let profileScopedStore: ProfileScopedStore?
    /// 台帳（`profiles` キー）を実書き込みする生ストア。改名・切替で `persistRegistry()` が使う。
    /// フォールバック（名前空間化不可）時は nil＝台帳は永続化せずメモリ内のみ。
    private let profileRegistryStore: ProfileScopedRawStore?
    /// プロファイル再ロード中フラグ。true の間、子スコープ @Published の didSet（保存・派生修復・
    /// 同期要求）を止める。値は `loadChildScopedState()` が正規スコープから入れ直す（設計§4）。
    private var isReloadingProfile = false
    private let wordsKey = "spellingTrainer.words"
    private let attemptsKey = "spellingTrainer.attempts"
    private let practiceSamplesKey = "spellingTrainer.practiceSamples"
    private let schoolTestResultsKey = "spellingTrainer.schoolTestResults"
    private let settingsKey = "spellingTrainer.settings"
    private let selectedWordStepIDKey = "spellingTrainer.selectedWordStepID"   // 旧（personal 単一トラック）→ 移行元
    private let selectedCourseIDKey = "spellingTrainer.selectedCourseID"
    private let selectedStepIDByCourseKey = "spellingTrainer.selectedStepIDByCourse"
    private let childCanSwitchCoursesKey = "spellingTrainer.childCanSwitchCourses"
    private let allowedCourseIDsKey = "spellingTrainer.allowedCourseIDs"
    private let requiredCompletionKey = "spellingTrainer.requiredCompletion"
    /// 旧コイン単位の残高キー（×10 移行前）。**二度と書き換えない**＝再倍化を防ぐ不変の移行元。
    private let legacyRewardCoinsKey = "spellingTrainer.rewardCoins"
    /// 新コイン単位（×10）の残高キー。これが存在すれば移行済み。以後の入出金はすべてここへ保存する。
    /// 旧キーから1回だけ ×10 して書き出すため、保存途中でプロセスが落ちても再倍化しない（冪等・クラッシュ安全）。
    private let rewardCoinsKey = "spellingTrainer.rewardCoins.v2"
    private let cachedEntitlementKey = "spellingTrainer.cachedEntitlement"
    private let debugUnlockAllKey = "spellingTrainer.debugUnlockAll"
    private let debugDisableDailyLimitKey = "spellingTrainer.debugDisableDailyLimit"
    #if DEBUG
    private let debugAIJudgeOnTestKey = "spellingTrainer.debugAIJudgeOnTest"
    private let aiJudgmentsKey = "spellingTrainer.aiJudgments"
    private let aiJudgeConfigKey = "spellingTrainer.aiJudgeConfig"
    #endif
    private let loginStreakKey = "spellingTrainer.loginStreak"
    private let lastLoginDayKey = "spellingTrainer.lastLoginDay"
    private let lastPerfectBonusDayKey = "spellingTrainer.lastPerfectBonusDay"
    private let puzzleLastPlayedDayKey = "spellingTrainer.puzzleLastPlayedDay"
    private let puzzlePlaysTodayKey = "spellingTrainer.puzzlePlaysToday"
    private let selectedCharacterIDKey = "spellingTrainer.selectedCharacterID"
    private let unlockedCharacterIDsKey = "spellingTrainer.unlockedCharacterIDs"
    private let selectedBackgroundIDKey = "spellingTrainer.selectedBackgroundID"
    private let unlockedBackgroundIDsKey = "spellingTrainer.unlockedBackgroundIDs"
    private let homeReviewWordIDsKey = "spellingTrainer.homeReviewWordIDs"
    private let usageLogKey = "spellingTrainer.usageLog"
    private let grammarReviewStatesKey = "spellingTrainer.grammarReviewStates"
    private let grammarReviewStepKey = "spellingTrainer.grammarReviewStep"
    private let spellingReviewStatesKey = "spellingTrainer.spellingReviewStates"
    private let spellingReviewStepKey = "spellingTrainer.spellingReviewStep"
    private let spellingReviewSeededKey = "spellingTrainer.spellingReviewSeeded"
    private let hasCompletedOnboardingKey = "spellingTrainer.hasCompletedOnboarding"
    private let hasShownHomeCharacterHintKey = "spellingTrainer.hasShownHomeCharacterHint"
    private let stepUnlockCelebrationKey = "spellingTrainer.stepUnlockCelebration"
    // 旧 `spellingTrainer.childName` キーは廃止。名前は `profileRegistry.activeProfile.displayName` が
    // 単一の真実（SSOT）。移行元としての読み出しは Core `ProfileStoreMigration.legacyChildNameKey` が担う。
    private let selectedGradeKey = "spellingTrainer.selectedGrade"
    private let castKey = "spellingTrainer.cast"

    init(persistenceStore rawStore: UserDataStore = AppPersistenceStore()) {
        // プロファイル名前空間化: 生の store を Core `ProfileScopedStore` で包み、子スコープキーだけ
        // `profiles/<activeProfileID>/` に prefix する。初回は単一子データを#1へ移行（冪等・バリア）。
        // 以後 `persistenceStore.save(x, key)` はキー文字列を変えずに自動でスコープされる（設計 §3-§5）。
        if let rawCapable = rawStore as? ProfileScopedRawStore {
            let registry = ProfileStoreMigration.loadOrBootstrap(base: rawCapable, now: Date())
            let core = ProfileScopedStore(base: rawCapable, activeProfileID: registry.activeProfileID)
            self.profileRegistry = registry
            self.profileScopedStore = core
            self.profileRegistryStore = rawCapable
            self.persistenceStore = ProfileScopedUserDataStore(scoped: core)
        } else {
            // 名前空間化できないストア（想定外）はそのまま使う＝単一子フォールバック。
            self.profileRegistry = ProfileRegistry(bootstrapping: ChildProfile(displayName: "", createdAt: Date()))
            self.profileScopedStore = nil
            self.profileRegistryStore = nil
            self.persistenceStore = rawStore
        }

        // グローバル（世帯・端末レベル。プロファイルを跨いで共有）はここで直接ロードする（切替では変えない）。
        let cachedEntitlement = persistenceStore.load(CachedEntitlement.self, key: cachedEntitlementKey) ?? .none
        isSubscribed = cachedEntitlement.isActive(now: Date())
        debugUnlockAll = persistenceStore.load(Bool.self, key: debugUnlockAllKey) ?? false
        debugDisableDailyLimit = persistenceStore.load(Bool.self, key: debugDisableDailyLimitKey) ?? false
        #if DEBUG
        debugAIJudgeOnTest = persistenceStore.load(Bool.self, key: debugAIJudgeOnTestKey) ?? false
        #endif

        // 子スコープの全 @Published をアクティブプロファイルから読み込む（切替時と共用）。
        // 各プロパティは宣言時デフォルトで初期化済みなので、ここで正規スコープの値へ入れ替える。
        loadChildScopedState()
        // 派生修復・シードは再ロードガードの外で1回だけ（意図的に）実行する。
        ensureSelectedWordStepStillExists()
        // 既存の未クリア語を復習キューへ一度だけ取り込む（描画経路では行わない）。
        seedSpellingReviewIfNeeded()
    }

    /// アクティブプロファイルの子スコープ状態を全 @Published へロードする。`init` と `activateProfile` で共用。
    /// 実行中は `isReloadingProfile` を立て、子スコープ didSet の保存・派生修復・同期要求を止める
    /// （値は今この正規スコープから入れているので保存は不要／派生修復は呼び出し側がガードの外で1回だけ行う）。
    /// 移行の明示 `save` は didSet の外なので継続する（＝ガード中でも新プロファイルの初期値は永続化される）。
    private func loadChildScopedState() {
        isReloadingProfile = true
        defer { isReloadingProfile = false }

        let loadedWords: [SpellingWord]
        if let storedWords = persistenceStore.load([SpellingWord].self, key: wordsKey) {
            loadedWords = storedWords
        } else {
            loadedWords = [
                SpellingWord(text: "cat", promptText: "ねこ"),
                SpellingWord(text: "dog", promptText: "いぬ"),
                SpellingWord(text: "friend", promptText: "友[とも]だち"),
                SpellingWord(text: "school", promptText: "学校[がっこう]")
            ]
            // 新スコープの初期化：既定語を明示的に永続化して word.id（UUID）を安定させる。
            // 再ロードガード中は words.didSet が保存しないため、ここで保存しないと再ロードのたびに
            // 別UUIDの既定語が生成され、ステップ署名・クリア判定・復習状態（word.id キー）が壊れる
            // （レビュー指摘・Critical）。移行の明示 save と同じ扱い。
            persistenceStore.save(loadedWords, key: wordsKey)
        }
        words = loadedWords
        // セッション限りの選択（永続化なし）。切替時に前の子の選択を持ち越さない。
        focusedPracticeWordIDs = []
        attempts = persistenceStore.load([SpellingAttempt].self, key: attemptsKey) ?? []
        practiceSamples = persistenceStore.load([PracticeSample].self, key: practiceSamplesKey) ?? []
        schoolTestResults = persistenceStore.load([SchoolTestResult].self, key: schoolTestResultsKey) ?? []
        settings = persistenceStore.load(TestSettings.self, key: settingsKey) ?? TestSettings()
        // コース選択状態（学年×英検2軸＋personal）。コース別に「選択中ステップ」を覚える。
        selectedCourseID = persistenceStore.load(String.self, key: selectedCourseIDKey) ?? CourseDirectory.personal.id
        if let loadedCourseStepMap = persistenceStore.load([String: String].self, key: selectedStepIDByCourseKey) {
            selectedStepIDByCourse = loadedCourseStepMap
        } else {
            // 旧 single-track の選択を personal トラックへ移行（1回限り）。
            let legacyStepID = persistenceStore.load(String.self, key: selectedWordStepIDKey)
                ?? Self.defaultWordStepID(for: loadedWords)
            let migrated = ["personal": legacyStepID]
            selectedStepIDByCourse = migrated
            // 再ロードガード中は didSet が保存しないため、移行値を明示的に永続化する。
            persistenceStore.save(migrated, key: selectedStepIDByCourseKey)
        }
        // 子のコース切替は既定でロック（親が決める）。親が設定で ON にしたときだけ解放。
        childCanSwitchCourses = persistenceStore.load(Bool.self, key: childCanSwitchCoursesKey) ?? false
        // 許可サブセット（空 = 制限なし＝全コース許可）。配列で永続化し Set へ復元。
        allowedCourseIDs = Set(persistenceStore.load([String].self, key: allowedCourseIDsKey) ?? [])
        requiredCompletion = persistenceStore.load(RequiredCompletion.self, key: requiredCompletionKey) ?? RequiredCompletion()
        // コイン単位 ×10 リリースの一回限り移行（純粋ロジックは CoinScaleMigration、判定/保存はここ）。
        // v2 キーがあればそれを使い、無ければ旧キー残高 ×10 で確定する。旧キーは不変なので、
        // v2 保存前にプロセスが落ちても次回また同じ値を再計算するだけで再倍化しない（冪等・クラッシュ安全）。
        let storedV2RewardCoins = persistenceStore.load(Int.self, key: rewardCoinsKey)
        let legacyRewardCoins = persistenceStore.load(Int.self, key: legacyRewardCoinsKey)
        let resolvedRewardCoins = CoinScaleMigration.resolveBalance(storedV2: storedV2RewardCoins, legacy: legacyRewardCoins)
        if CoinScaleMigration.needsPersist(storedV2: storedV2RewardCoins) {
            // 再ロードガード中は didSet が保存しないため、移行値を明示的に永続化する。
            persistenceStore.save(resolvedRewardCoins, key: rewardCoinsKey)
        }
        rewardCoins = resolvedRewardCoins
        #if DEBUG
        // 起動時：前回のTaskはもう生きていないので、残った「送信中」フラグは落とす（永久スピナー防止）。
        aiJudgments = (persistenceStore.load([AIJudgmentRecord].self, key: aiJudgmentsKey) ?? [])
            .map { var record = $0; record.isRunning = false; return record }
        aiJudgeConfig = persistenceStore.load(AIJudgeConfig.self, key: aiJudgeConfigKey) ?? .default
        #endif
        loginStreak = max(persistenceStore.load(Int.self, key: loginStreakKey) ?? 0, 0)
        lastLoginDay = persistenceStore.load(Date.self, key: lastLoginDayKey)
        lastPerfectBonusDay = persistenceStore.load(Date.self, key: lastPerfectBonusDayKey)
        puzzleLastPlayedDay = persistenceStore.load(Date.self, key: puzzleLastPlayedDayKey)
        puzzlePlaysToday = max(persistenceStore.load(Int.self, key: puzzlePlaysTodayKey) ?? 0, 0)
        let initialUnlockedCharacterIDs = (persistenceStore.load(Set<String>.self, key: unlockedCharacterIDsKey) ?? []).union(Self.defaultUnlockedCharacterIDs)
        unlockedCharacterIDs = initialUnlockedCharacterIDs
        homeReviewWordIDs = persistenceStore.load(Set<UUID>.self, key: homeReviewWordIDsKey) ?? []
        usageLog = persistenceStore.load([String: Int].self, key: usageLogKey) ?? [:]
        grammarReviewStates = persistenceStore.load([ReviewItemState].self, key: grammarReviewStatesKey) ?? []
        grammarReviewStep = max(persistenceStore.load(Int.self, key: grammarReviewStepKey) ?? 0, 0)
        spellingReviewStates = persistenceStore.load([ReviewItemState].self, key: spellingReviewStatesKey) ?? []
        spellingReviewStep = max(persistenceStore.load(Int.self, key: spellingReviewStepKey) ?? 0, 0)
        spellingReviewSeeded = persistenceStore.load(Bool.self, key: spellingReviewSeededKey) ?? false
        hasCompletedOnboarding = persistenceStore.load(Bool.self, key: hasCompletedOnboardingKey) ?? false
        hasShownHomeCharacterHint = persistenceStore.load(Bool.self, key: hasShownHomeCharacterHintKey) ?? false
        stepUnlockCelebration = persistenceStore.load(StepUnlockCelebration.self, key: stepUnlockCelebrationKey) ?? StepUnlockCelebration()
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
    }

    /// 台帳（`profiles` キー）を実ストアへ永続化する（改名・切替時）。
    /// 実行時なので非同期書き込みで十分（起動時の書き込みバリアは移行 `loadOrBootstrap` が担う）。
    /// フォールバック（名前空間化不可）時は永続先が無いので何もしない（メモリ内のみ）。
    private func persistRegistry() {
        guard let base = profileRegistryStore,
              let data = try? JSONEncoder().encode(profileRegistry) else { return }
        base.rawSave(data, key: ProfileStoreMigration.profilesKey)
    }

    /// アクティブな子プロファイルを切り替える（原子的・設計§4・レビュー指摘④）。
    /// ①切替前の子に紐づく保留同期を破棄（新しい子へ流さない）→ ②台帳・スコープを差し替え →
    /// ③子スコープ状態を再ロード（ガード中＝didSet 副作用は止まる）→ ④ガードの外で派生修復・シード・
    /// 同期要求を1回だけ。`AppModel` インスタンスは作り直さない（View ツリーが依存するため中身を入れ替える）。
    func activateProfile(_ id: UUID) {
        guard let scoped = profileScopedStore else { return }   // フォールバック時は切替不可
        guard id != profileRegistry.activeProfileID else { return }
        let updated = profileRegistry.activating(id)
        guard updated.activeProfileID == id else { return }     // 未知IDは無視（活性化されない）
        pendingSyncTask?.cancel()
        pendingSyncTask = nil
        profileRegistry = updated
        persistRegistry()
        scoped.setActiveProfileID(id)
        loadChildScopedState()
        // ガードの外で意図的に：派生修復・シード・（安全なら）同期要求。
        ensureSelectedWordStepStillExists()
        seedSpellingReviewIfNeeded()
        requestSync()
    }

    #if DEBUG
    /// DEBUG専用：切替配線を手動確認するためのダミー子プロファイルを1人追加する。
    /// 親向けの追加/改名/削除 UI は Phase 4。ここは開発用の最小導線（プロダクトUIには出さない）。
    func debugAddTestProfile() {
        guard profileScopedStore != nil else { return }   // フォールバック時は台帳を持たない
        // 同期サイクル進行中は人数を増やさない（in-flight push が2人以上でサーバ到達する窓を作らない）。
        guard !isSyncCycleInFlight else { return }
        let number = profileRegistry.profiles.count + 1
        let profile = ChildProfile(displayName: "テスト\(number)", createdAt: Date())
        profileRegistry = profileRegistry.adding(profile)
        persistRegistry()
    }
    #endif

    /// アクティブコースに応じてステップ供給元を切り替える（personal は既存導出・無改修／
    /// 学年・英検は wordbank から合成した仮想ステップ＝非永続）。
    var wordSteps: [WordStep] {
        switch activeCourse.kind {
        case .personal:
            return Self.makeWordSteps(from: words)
        case .grade, .eiken, .dolch:
            let base = courseProvider.steps(for: activeCourse)
            return Self.composeLinkedSteps(base: base, personalWords: words, courseID: activeCourse.id)
        }
    }

    /// 合成コースの階段（`base`）に、personal 保管で「このコースへ紐付いた」語を差し込んで materialize する。
    /// 純ロジック（バッチ化＋forward dedup＋空除去＋番号振り直し）は `SpellingSyncCore.LinkedStepComposer`
    /// に委譲し、ここは「`WordToken.id` → 実 `SpellingWord` の対応付け」だけを担う薄いグルー。
    /// 保管は personal のまま動かさない（表示専用）。id ベースで戻すので同じ綴りの別語を取り違えない。
    static func composeLinkedSteps(base: [WordStep], personalWords: [SpellingWord], courseID: String) -> [WordStep] {
        let linkedWords = personalWords.filter { $0.linkedCourseID == courseID }
        guard !linkedWords.isEmpty else { return base }

        // id → 実語（両側）。計画後の materialize はこの id 引きだけで行う。
        var wordByID: [String: SpellingWord] = [:]
        var baseByStepID: [String: WordStep] = [:]
        for step in base {
            baseByStepID[step.id] = step
            for w in step.words { wordByID[w.id.uuidString] = w }
        }
        for w in linkedWords { wordByID[w.id.uuidString] = w }

        let baseDesc = base.map { step in
            LinkedStepComposer.BaseStep(
                stepID: step.id,
                words: step.words.map { .init(id: $0.id.uuidString, normalized: normalize($0.text)) })
        }
        let inputs = linkedWords.map { w in
            LinkedStepComposer.LinkedWordInput(
                id: w.id.uuidString, normalized: normalize(w.text),
                storageStepID: w.stepID, beforeStepID: w.linkedBeforeStepID)
        }
        let planned = LinkedStepComposer.plan(base: baseDesc,
                                              linked: LinkedStepComposer.buildGroups(from: inputs))

        return planned.map { p in
            switch p.origin {
            case .synthetic(let stepID):
                let words = p.words.compactMap { wordByID[$0.id] }
                return WordStep(id: stepID, number: p.number,
                                registeredDate: baseByStepID[stepID]?.registeredDate ?? Self.linkedEpoch,
                                words: words, isChildStep: false, childNumber: nil)
            case .custom(let storageStepID):
                let stepID = "\(Self.linkedStepIDPrefix)\(courseID).\(storageStepID)"
                // 実 personal 語の id（同期キー）は保ちつつ、表示ステップ整合のため stepID だけ揃える。
                let words = p.words.compactMap { wordByID[$0.id] }.map { w -> SpellingWord in
                    var w = w; w.stepID = stepID; return w
                }
                return WordStep(id: stepID, number: p.number,
                                registeredDate: words.first?.registeredAt ?? Self.linkedEpoch,
                                words: words, isChildStep: false, childNumber: nil)
            }
        }
    }

    private static let linkedEpoch = Date(timeIntervalSince1970: 0)
    /// 紐付け custom ステップの `WordStep.id` 接頭辞（合成ステップIDと区別＝アンカーに使わない）。
    static let linkedStepIDPrefix = "linked."

    // MARK: - コース紐付け（学校テスト語を「いまのコースの途中」に出す）

    /// いま追加するなら、このコースのどの合成ステップ手前に出すか（=「子の現在地のすぐ次」）。
    /// 現在地＝**子が実際に見る合成ラダー（既存の紐付けも反映＝完了判定と同じ土俵）**の最初の未クリア
    /// 「合成」ステップ。その手前に差し込むと子の次にやる階段として出る。custom ステップ（"linked." 接頭）は
    /// アンカーに使えないので飛ばす。personal コース／全クリア時は nil（末尾フォールバック）。
    func linkAnchorBeforeStepID(for course: Course) -> String? {
        guard course.kind != .personal else { return nil }
        let composed = Self.composeLinkedSteps(
            base: courseProvider.steps(for: course), personalWords: words, courseID: course.id)
        for step in composed
        where !step.id.hasPrefix(Self.linkedStepIDPrefix)
            && !requiredCompletion.isCleared(completionSignature(for: step)) {
            return step.id
        }
        return nil
    }

    /// あるpersonalステップ（=1バッチ）の全語を、合成コースへ紐付ける/解除する（表示メタのみ更新）。
    /// `courseID == nil` で解除。保管（words 自体・stepID）は動かさない。
    func setCourseLink(forStepID stepID: String, courseID: String?, beforeStepID: String?) {
        var updated = words
        var changed = false
        for i in updated.indices where updated[i].stepID == stepID {
            if updated[i].linkedCourseID != courseID || updated[i].linkedBeforeStepID != beforeStepID {
                updated[i].linkedCourseID = courseID
                updated[i].linkedBeforeStepID = beforeStepID
                changed = true
            }
        }
        if changed { words = updated }
    }

    var selectedWordStep: WordStep? {
        wordSteps.first { $0.id == selectedWordStepID } ?? wordSteps.last
    }

    var activeWords: [SpellingWord] {
        selectedWordStep?.words ?? words
    }

    /// このステップを親が**その場で編集できるか**（＝personal トラックに実在するステップか）。
    /// 合成コース／`linked.` 差し込みの表示ステップは保管とID が1:1でないため false（読み取り表示）。
    /// 判定は純ロジック `SpellingSyncCore.StepEditability` に委譲する。
    func isEditableStep(_ step: WordStep) -> Bool {
        StepEditability.isEditable(
            stepID: step.id,
            personalStepIDs: Set(personalWordSteps.map(\.id)))
    }

    // MARK: - personal トラック専用アクセサ
    //  親/子の単語“管理”（編集・子追加ゲート・学校テスト・親の復習送り）は、子が今どのコースを開いていても
    //  常に自分の単語（personal）を対象にする。学習者(ホーム/マップ/練習)はコース別の `wordSteps` を見る。
    //  この2つを混ぜないことで「コース選択が管理側に漏れる」回帰を防ぐ（codex レビュー指摘）。

    /// personal トラックのステップ（自分の登録語から導出・コース選択に非依存）。
    var personalWordSteps: [WordStep] {
        Self.makeWordSteps(from: words)
    }

    /// personal トラックの選択ステップID（dict["personal"] を直接指す・アクティブコースに非依存）。
    var personalSelectedWordStepID: String {
        get { selectedStepIDByCourse["personal"] ?? "" }
        set { selectedStepIDByCourse["personal"] = newValue }
    }

    /// personal トラックの選択ステップ（親管理が見る“いまのステップ”）。
    var personalSelectedWordStep: WordStep? {
        personalWordSteps.first { $0.id == personalSelectedWordStepID } ?? personalWordSteps.last
    }

    /// コースを切り替える。未選択コースは先頭ステップを既定にして“いまここ”が定まるようにする。
    func selectCourse(_ id: String) {
        selectedCourseID = id
        if (selectedStepIDByCourse[id] ?? "").isEmpty, let first = wordSteps.first {
            selectedStepIDByCourse[id] = first.id
        }
    }

    // MARK: - 永続「できた」（満点を一度取ったら固定）

    /// ステップの (stepID＋語構成) 署名（永続完了キー）。
    func completionSignature(for step: WordStep) -> StepSignature {
        RequiredCompletionSignature.make(stepID: step.id, wordStableIDs: step.words.map(\.id.uuidString))
    }

    /// 現在コースで「ずっとできた」ステップID集合（冒険マップの緑チェック／ホームのサマリが読む）。
    var completedStepIDs: Set<String> {
        Set(wordSteps.filter { requiredCompletion.isCleared(completionSignature(for: $0)) }.map(\.id))
    }

    /// 現在コースのステップ完了サマリ（ホームの「Xこ できた / Yこ」）。
    var courseStepProgress: StepMapLayout.Progress {
        StepMapLayout.progress(orderedIDs: wordSteps.map(\.id), completed: completedStepIDs)
    }

    // MARK: - 練習抑制（マスター済みは練習で出さない／テストには出す／ミスで復帰）
    //  既存の missed/review 基盤（attempts の最新クリア＋ReviewQueue）だけから算出。新ストアは持たない。

    private var latestAttemptByText: [String: SpellingAttempt] {
        var latest: [String: SpellingAttempt] = [:]
        for a in attempts {
            let key = normalize(a.word)
            guard !key.isEmpty else { continue }
            if let existing = latest[key], existing.date >= a.date { continue }
            latest[key] = a
        }
        return latest
    }

    /// 最新 attempt がクリア（ノーミス正解）の語テキスト。
    private var latestClearedTexts: Set<String> {
        Set(latestAttemptByText.filter { isCleared($0.value) }.keys)
    }

    /// 復習中（未マスター）の語テキスト。review state の id を既知語(personal＋現コース)で text へ写像。
    private var activeReviewTexts: Set<String> {
        guard !spellingReviewStates.isEmpty else { return [] }
        var idToText: [UUID: String] = [:]
        for w in words { idToText[w.id] = normalize(w.text) }
        for step in wordSteps { for w in step.words { idToText[w.id] = normalize(w.text) } }
        var out = Set<String>()
        for state in spellingReviewStates where !ReviewQueue.isMastered(state, currentStep: spellingReviewStep) {
            if let text = idToText[state.id], !text.isEmpty { out.insert(text) }
        }
        return out
    }

    /// 練習から外す語テキスト＝「最新クリア かつ 未解決でない かつ 復習アクティブでない」（codex Architect の真理値表）。
    /// app のミスは latestClearedTexts から自動的に外れる（最新がミス）。学校テスト未解決の加味は将来拡張。
    var practiceSuppressedTexts: Set<String> {
        PracticeSelection.suppressedPracticeKeys(
            latestClearedTexts: latestClearedTexts,
            unresolvedTexts: [],
            activeReviewTexts: activeReviewTexts
        )
    }

    /// 練習ドリル用の語（抑制を除く）。テスト/完了判定は従来どおり全語のまま。
    func practiceWords(for step: WordStep) -> [SpellingWord] {
        PracticeSelection.practiceWords(step.words, suppressed: practiceSuppressedTexts,
                                        keyOf: { normalize($0.text) })
    }

    var practiceWordsForSelectedStep: [SpellingWord] {
        let base = selectedWordStep?.words ?? words
        return PracticeSelection.practiceWords(base, suppressed: practiceSuppressedTexts,
                                               keyOf: { normalize($0.text) })
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
    ///
    /// 上限は **いま練習する集合（＝選択中ステップ）の中だけ** で数える（ステップ単位）。
    /// 登録は無制限・親が学習セットを前もって何個でも用意できる前提なので、別ステップを
    /// その日に練習しても、新しく登録したステップの練習を巻き添えで止めない。「練習できる
    /// 単語が1日10」はステップごとに独立して効く（全語横断のグローバル枠にはしない）。
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
        // このステップ内で今日すでに新規導入した語数だけを数える（他ステップは無関係）。
        let introducedTodayInStep = NewWordBudget.introducedCount(
            firstIntroducedDates: selected.map(\.firstIntroducedAt),
            today: now,
            calendar: calendar
        )
        let keep = NewWordBudget.cappedIndices(
            isNewCandidate: flags,
            introducedToday: introducedTodayInStep
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
        uniqueWords(personalWordSteps.flatMap { unresolvedReviewWords(for: $0) })
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

    /// テストに「追加問題」として混ぜる復習語（最大2語）。間違えた語を `ReviewQueue` が box/ステップで
    /// 管理し、due なものだけを少数注入する（1回正解では消えず、数回の正解で卒業）。語は他ステップ由来でもよい
    /// （＝「今後 別のステップでも」自然に再出題）。`testWords`/ホームの「ふくしゅうN」表示の両方がこれを使う。
    /// こども専用ステップは従来どおり対象外（親の単語と混ざらないように）。
    func carryOverReviewWords(for step: WordStep, cap: Int = 2) -> [SpellingWord] {
        guard !step.isChildStep else { return [] }
        let baseIDs = step.words.map(\.id)
        let baseSet = Set(baseIDs)
        let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 注入候補は「生存かつ親由来」の語に限定（削除済みIDが cap を浪費するのと、子由来語の混入を防ぐ）。
        let eligible = spellingReviewStates.filter { state in
            guard let word = byID[state.id] else { return false }
            return !isChildWord(word)
        }
        let injectedIDs = ReviewQueue
            .composeRound(base: baseIDs, states: eligible, currentStep: spellingReviewStep, cap: cap)
            .filter { !baseSet.contains($0) }   // base を除いた「追加で混ざる復習語」だけ
        return injectedIDs.compactMap { byID[$0] }
    }

    /// その語がこども由来か（親の単語と混ざらないよう復習対象から外す判定に使う）。
    /// 同期で取り込んだ子の語は `stepID` が落ちて `source == .child` だけが残るため、両方を見る。
    private func isChildWord(_ word: SpellingWord) -> Bool {
        if word.source == .child { return true }
        guard let stepID = word.stepID else { return false }
        return Self.isChildStepID(stepID)
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

    /// 1セッション内で対象単語をすべて「達成」したことがあるか（＝子どもの進行ゲート＝満点）。
    ///
    /// 「達成」は `SpellingAttempt.satisfiesAchievement`（`ChildGrading`）のやさしいルール:
    /// 対象語がすべて揃い、各語が達成を満たせば満点。字が汚くて端末OCRが読めなかっただけ（本人は実際に
    /// 書いた）は満たす＝「字が汚い＝間違い」でパズル解放/追加/永続できたがロックされる問題を防ぐ。一方で
    /// **パス（未記入）・時間切れは満たさない**＝ズルで解放させない。親レポートの厳密なマスター判定
    /// （`isCleared`）とは別軸（あちらは needsReview を未確認＝未マスター扱い）。
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

            return ChildGrading.isAchieved(satisfied: latestInSession.values.map { $0.satisfiesAchievement })
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
        return LearningReportBuilder.build(events: allLearningEvents(), from: from, to: to, calendar: calendar)
    }

    /// テスト(attempts)＋練習(practiceSamples)を学習イベントへ正規化したもの。
    /// テストはクリア可否つき、練習は「取り組み(=未クリア)」として扱う（learningReport と同じ意味論）。
    private func allLearningEvents() -> [LearningEvent] {
        var events: [LearningEvent] = attempts.map {
            LearningEvent(word: normalize($0.word), date: $0.date, cleared: isCleared($0))
        }
        events += practiceSamples.map {
            LearningEvent(word: normalize($0.word), date: $0.date, cleared: false)
        }
        // 空テキスト（空白のみ等）は除外。totalLearnedWordCount と数え方を揃え、マスター率が 1 を超えないようにする。
        return events.filter { !$0.word.isEmpty }
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

    /// きょう手書きした語数（テスト=attempts＋練習=practiceSamples、語で重複排除）。
    /// 子の結果画面「きょう かいた かず」用：練習だけの日も 0 にならないよう両方を数える。
    /// 語の重複はまとめる（同じ語を練習→テストや、練習で繰り返しても水増ししない）。
    var todaysWrittenWordCount: Int {
        var written = Set<String>()
        // 空語（空白のみ等）は数えない＆表記ゆれをまとめる（totalLearnedWordCount 等と数え方を揃える）。
        for attempt in todaysAttempts {
            let word = normalize(attempt.word)
            if !word.isEmpty { written.insert(word) }
        }
        for sample in todaysPracticeSamples {
            let word = normalize(sample.word)
            if !word.isEmpty { written.insert(word) }
        }
        return written.count
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
        personalWordSteps.last { $0.isChildStep }
    }

    /// そのこどもステップを満点（1セッション一発全正解）でクリアしたか。
    /// 過去ぶんも含めて判定するので、いちど満点にすれば次の追加が解放される。
    func childStepIsMastered(_ step: WordStep) -> Bool {
        hasPerfectRun(for: step.words, in: attempts)
    }

    // MARK: - 必須→満点→パズル(自由)の自動フロー（docs/age-tiered-generation-spec-2026-06-29.md §2）

    /// いま選んでいるステップを満点でクリア済みか（親/子どちらのステップでも判定）。
    /// 単語を足す/入れ替えると新セットの満点は無いので自動で未クリアに戻る（再ロック）。
    var selectedStepIsMastered: Bool {
        guard let step = selectedWordStep else { return false }
        return hasPerfectRun(for: step.words, in: attempts)
    }

    /// いま選んでいるステップの焦点（必須をやる段階 / 満点後の自由＝パズル解放）。
    var selectedStepFocus: StepFocus {
        StepFocusResolver.focus(isMastered: selectedStepIsMastered)
    }

    /// いま選んでいるステップの (stepID, 単語構成) 署名。アンロック演出を単語セット単位で1回だけにするキー。
    /// 単語の安定IDは現状 `SpellingWord.id`（永続化される UUID）を使う。
    var selectedStepSignature: StepSignature? {
        guard let step = selectedWordStep else { return nil }
        return RequiredCompletionSignature.make(stepID: step.id,
                                                wordStableIDs: step.words.map { $0.id.uuidString })
    }

    /// いま「あたらしいクイズがでた！」のアンロック演出を出すべきか（満点になった瞬間に1回だけ）。
    var shouldCelebrateSelectedStepUnlock: Bool {
        guard let signature = selectedStepSignature else { return false }
        return StepFocusResolver.shouldCelebrateUnlock(signature: signature,
                                                       isMastered: selectedStepIsMastered,
                                                       celebration: stepUnlockCelebration)
    }

    /// いま選んでいるステップのアンロック演出を「出した」と記録する（以後その単語セットでは出さない）。
    func markSelectedStepUnlockCelebrated() {
        guard let signature = selectedStepSignature else { return }
        stepUnlockCelebration.markCelebrated(signature)
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
                    stepID: word.stepID,                     // Ph4: 保管ステップを storage_step_id で往復
                    displayOrder: index,
                    linkedCourseID: word.linkedCourseID,     // Ph4: コース紐付け（表示メタ）を同期
                    linkedBeforeStepID: word.linkedBeforeStepID
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
        // 複数プロファイル中はローカルへ反映しない。pull の await 中に `activateProfile` で
        // 2人以上へ切り替わっていたら、この merge を別プロファイルのスコープへ書き込まない
        // （レビュー指摘・Critical）。1人なら従来どおり反映（切替は起きえない）。
        // 取りこぼしは次トリガ／pendingRerun で回収される。
        guard isSyncSafeForActiveProfile else { return }
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
                    // Ph4: 保管ステップ／コース紐付けはサーバー往復値を権威とする（多端末伝搬・解除の両方が効く）。
                    // ローカル編集は project→reconcile を経て record.payload に載るため取りこぼさない。
                    stepID: record.payload.stepID,
                    source: WordSource(rawValue: record.payload.source) ?? .parent,
                    firstIntroducedAt: prior?.firstIntroducedAt,             // 学習リズムのローカル値を保持（同期で消さない）
                    linkedCourseID: record.payload.linkedCourseID,
                    linkedBeforeStepID: record.payload.linkedBeforeStepID
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
        // 複数プロファイル中は同期を止める（世帯グローバルな同期簿記のままなので、子切替時に
        // 他児の単語を誤って墓石化しうる。設計§6・レビュー指摘①）。`syncNow`/`requestSync` の
        // 入口だけでなく唯一のチョークポイントであるここにも張り、DEBUG の手動同期直呼びも塞ぐ。
        // 進行中サイクルの各境界（開始／pull後／push後）でも `WordSyncCoordinator` が同じ不変条件を
        // 再確認するので、pull の await 中に切替が入っても他児スコープへ反映・push しない。
        guard isSyncSafeForActiveProfile else { return }
        // サイクル中はプロファイル人数を増やせないようにする（`debugAddTestProfile` がこれを見る）。
        // これで push の await 中に count が 2 になり、A の push が「2人以上」でサーバへ届く窓を消す。
        // カウンタ増減にして、重複呼び出しの defer が先行サイクル進行中に 0 へ落とさないようにする。
        syncCycleDepth += 1
        defer { syncCycleDepth -= 1 }
        try await wordSyncCoordinator.sync(appModel: self, householdID: householdID)
    }

    // MARK: 自動同期トリガ（前面化／編集後／サインイン・世帯確定時）

    /// アクティブ世帯の供給元。アプリ起動時に `SyncSession` を注入する（未設定なら同期は無効）。
    private var householdIDProvider: () -> UUID? = { nil }
    /// 編集連打をまとめるためのデバウンス用タスク。
    private var pendingSyncTask: Task<Void, Never>?
    /// 進行中の `syncWords` サイクル数（pull/push の await 含む）。プロファイル人数を増やす操作は
    /// これが 0 でない間ブロックする＝サイクル中は `profiles.count` を不変に固定し、in-flight の
    /// push/tombstone が「2人以上の状態でサーバへ届く」窓自体を作らない（設計§6・レビュー指摘①。
    /// 本対応は Phase 5）。**カウンタにするのは重要**：`syncWords` は @MainActor async で再入しうるため、
    /// 単純な Bool だと重複呼び出し側の `defer` が先行サイクルの push await 中にフラグを消してしまう。
    private var syncCycleDepth = 0
    /// 同期サイクルが1つ以上進行中か（人数増加をブロックする判定に使う）。
    private var isSyncCycleInFlight: Bool { syncCycleDepth > 0 }
    /// `applyMergedWords` による `words` 更新が、編集トリガを再帰的に誘発しないためのフラグ。
    private var isApplyingMergedWords = false

    /// オンボーディングで学年を選んだときの確定処理（方針A）。
    /// - 学年は事実として記録（漢字ゲート／出題ティアの判断に使う）。
    /// - **その学年のコースを子のアクティブコースにする**＝personal へ単語シードはしない。
    ///   grade コースは wordbank 合成の中身を持ち、親の学校テスト語もこのコースへ差し込まれる
    ///   （course-linked words）。子には級/学年ラベルは出ない（childTitle は世界名）。
    func applyOnboardingGrade(_ grade: GradeLevel) {
        selectedGrade = grade.rawValue
        selectCourse(GradeBand.courseID(schoolGrade: grade.schoolGrade))
    }

    /// 自動同期の世帯供給元を設定する（アプリ起動時に 1 回）。
    func configureSync(householdIDProvider: @escaping () -> UUID?) {
        self.householdIDProvider = householdIDProvider
    }

    /// 同期を今のプロファイル構成で安全に走らせてよいか。
    /// **子が2人以上いる間は同期を止める**（Phase 5 で同期をプロファイル別に本対応するまでの安全ネット）。
    /// 同期簿記（`sync.cursors`/`sync.wordSidecar`）が世帯グローバルのままなので、複数プロファイルで
    /// 同期すると子切替時に他児の単語を誤って墓石化しうる（設計 §6・レビュー指摘①）。1人なら従来通り安全。
    /// **これが唯一の同期安全不変条件**：`syncWords` 入口・`applyMergedWords`・`WordSyncCoordinator`
    /// の各サイクル境界（開始／pull後／push後）で必ずこれを確認する。切替は必ず2人以上の状態でしか
    /// 起きない（＝切替が絡む間は常に false）ため、これを全境界で見れば in-flight／pendingRerun の
    /// どの割り込みでも他児スコープへの反映・push・墓石化を止められる（coordinator から読むため internal）。
    var isSyncSafeForActiveProfile: Bool {
        profileRegistry.profiles.count <= 1
    }

    /// 即時に 1 サイクル同期する（前面化・サインイン・世帯確定時など）。
    /// バックグラウンド同期なので失敗は握りつぶす（次トリガで回収。多重実行は coordinator がガード）。
    func syncNow() async {
        guard isSyncSafeForActiveProfile else { return }
        guard let household = householdIDProvider() else { return }
        do { try await syncWords(householdID: household) }
        catch {
            // バックグラウンド同期: 失敗は次トリガで回収。運用テレメトリにだけ薄く残す
            // （詳細メッセージや単語内容は送らない＝低カーディナリティのフラグのみ）。
            TelemetryCoordinator.shared.record(.syncPushFailed, payload: ["op": .string("syncWords")])
        }
    }

    /// デバウンス付きで同期を要求する（単語の編集直後などに呼ぶ）。
    /// 直前の予約はキャンセルし、`seconds` 静かになってから 1 回だけ走らせる。
    /// **発火時に世帯が変わっていたら破棄**する（古い世帯のローカル編集を新世帯へ流さない）。
    func requestSync(debounce seconds: Double = 1.5) {
        guard isSyncSafeForActiveProfile else { return }
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
            personalSelectedWordStepID = Self.defaultWordStepID(for: words)
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

        // このステップ（=1バッチ）がコースへ紐付いていれば、編集で増えた語にも同じ紐付けを継がせて
        // バッチ全体の一貫性を保つ（一部だけコース非表示になり「表示中」バッジと食い違う事故を防ぐ）。
        let linkSource = stepWords.first { $0.linkedCourseID != nil }
        let batchLinkedCourseID = linkSource?.linkedCourseID
        let batchLinkedBeforeStepID = linkSource?.linkedBeforeStepID

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
            word.linkedCourseID = batchLinkedCourseID
            word.linkedBeforeStepID = batchLinkedBeforeStepID
            return word
        }

        let untouchedWords = words.filter { !wordBelongs($0, to: step, calendar: calendar) }
        words = untouchedWords + replacementWords
        personalSelectedWordStepID = step.id
        return replacementWords.count
    }

    @discardableResult
    /// - Parameters:
    ///   - linkedCourseID/linkedBeforeStepID: 新ステップ（=1バッチ）を合成コースの階段へ「表示だけ」紐付ける
    ///     表示メタ。保管は常に personal。学校テスト語を「コースを切り替えず途中に出す」用途（→ `wordSteps`）。
    func addWordsToStep(from rawText: String, registeredAt: Date = Date(),
                        linkedCourseID: String? = nil, linkedBeforeStepID: String? = nil) -> (added: Int, updated: Int) {
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
            updatedWords.append(SpellingWord(text: key, promptText: promptText ?? "", registeredAt: storedDate,
                                             stepID: stepID,
                                             linkedCourseID: linkedCourseID, linkedBeforeStepID: linkedBeforeStepID))
            addedCount += 1
        }

        if updatedWords != words {
            words = updatedWords
        }
        if addedCount > 0 {
            personalSelectedWordStepID = stepID
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
        guard let step = personalWordSteps.first(where: { $0.id == stepID }) else {
            return false
        }
        return [
            step.title(language: .japanese),
            step.title(language: .english)
        ].contains(title)
    }

    func sendReviewWordsToHome(_ wordIDs: Set<UUID>, stepID: String) {
        // 復習語は自分の単語（personal）。子が別コースを開いていても personal の該当ステップを見せる。
        selectedCourseID = CourseDirectory.personal.id
        personalSelectedWordStepID = stepID
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

    /// テスト満点ボーナス。**今日まだ**なら単語数に応じた 50〜100 コインを付与し、その額を返す。
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

    #if DEBUG
    // MARK: - AI-OCR 判定比較（DEBUG専用）

    /// テストで1問終わったときに、トグルが ON なら AI 判定を発火する。
    func enqueueAIJudgmentIfEnabled(for attempt: SpellingAttempt) {
        guard debugAIJudgeOnTest else { return }
        runAIJudgment(for: attempt)
    }

    /// 手書きを（設定中の）各モデルへ並行送信し、結果を比較レコードに保存する（子は待たせない＝非同期）。
    func runAIJudgment(for attempt: SpellingAttempt) {
        Task { await runAIJudgmentAsync(for: attempt) }
    }

    /// 現在表示中の答案すべてに順番に判定を適用する（モデル/パラメータを変えたあとの一括再判定用）。
    /// 答案ごとは各モデルへ並行だが、答案は**順番に**処理して同時接続を抑える（コスト/レート対策）。
    func runAIJudgmentForAll(_ attempts: [SpellingAttempt]) {
        guard aiBulkProgress == nil, !attempts.isEmpty else { return }
        aiBulkProgress = AIBulkProgress(done: 0, total: attempts.count)
        Task { [weak self] in
            for attempt in attempts {
                await self?.runAIJudgmentAsync(for: attempt)
                self?.aiBulkProgress?.done += 1
            }
            self?.aiBulkProgress = nil
        }
    }

    /// 1答案ぶんの判定を実行して結果を保存する（await 可能な本体）。実行中の答案は二重送信しない。
    @discardableResult
    private func runAIJudgmentAsync(for attempt: SpellingAttempt) async -> Bool {
        // 同じ答案の送信が実行中なら二重送信しない（自動発火・手動送信・一括の重複を防ぐ）。
        if aiJudgments.first(where: { $0.id == attempt.id })?.isRunning == true {
            return false
        }
        guard let png = AIJudgmentImage.png(for: attempt) else { return false }

        let config = aiJudgeConfig
        let models = config.sanitizedModels
        let runID = UUID()
        let target = attempt.word
        upsertAIJudgment(
            AIJudgmentRecord(
                id: attempt.id,
                runID: runID,
                target: target,
                localRecognizedText: attempt.recognizedText,
                localDecision: attempt.decision.rawValue,
                date: attempt.date,
                results: [],
                isRunning: true
            )
        )

        let client = OpenRouterClient()
        var results: [AIModelResult] = []
        await withTaskGroup(of: AIModelResult.self) { group in
            for model in models {
                group.addTask {
                    await client.judge(imagePNG: png, target: target, model: model,
                                       temperature: config.temperature, maxTokens: config.maxTokens)
                }
            }
            for await result in group {
                results.append(result)
            }
        }
        // TaskGroup は完了順なので、モデル定義順に並べ替えて表示を安定させる。
        let ordered = models.compactMap { slug in results.first { $0.modelSlug == slug } }
        completeAIJudgment(attemptID: attempt.id, runID: runID, results: ordered)
        return true
    }

    private func upsertAIJudgment(_ record: AIJudgmentRecord) {
        var list = aiJudgments.filter { $0.id != record.id }
        list.append(record)
        if list.count > 60 {
            list.removeFirst(list.count - 60)
        }
        aiJudgments = list
    }

    private func completeAIJudgment(attemptID: UUID, runID: UUID, results: [AIModelResult]) {
        guard let index = aiJudgments.firstIndex(where: { $0.id == attemptID }) else { return }
        // clear→再送で世代が変わっていたら、古いTaskの結果は捨てる（新しいレコードを上書きしない）。
        guard aiJudgments[index].runID == runID else { return }
        aiJudgments[index].results = results
        aiJudgments[index].isRunning = false
    }

    func clearAIJudgments() {
        aiJudgments = []
    }
    #endif

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

    private func saveGrammarReviewStates() {
        persistenceStore.save(grammarReviewStates, key: grammarReviewStatesKey)
    }

    private func saveGrammarReviewStep() {
        persistenceStore.save(grammarReviewStep, key: grammarReviewStepKey)
    }

    // MARK: - 文法クイズの復習（ReviewQueue 配線）

    /// 1ラウンドの出題順を組む。`base`（通常出題の文ID・順序維持）に、この `grammarReviewStep` で
    /// due な復習文を「追加問題」として最大 `cap` 件足して返す。`cap` が「+1〜2問」。
    func composeGrammarRound(base: [UUID], cap: Int = 2) -> [UUID] {
        ReviewQueue.composeRound(base: base, states: grammarReviewStates, currentStep: grammarReviewStep, cap: cap)
    }

    /// 文1問の正誤を復習キューに反映する。誤=box1で登録/リセット、正=box+1（数回で卒業）。
    func recordGrammarResult(itemID: UUID, correct: Bool) {
        grammarReviewStates = ReviewQueue.apply(grammarReviewStates, itemID: itemID, correct: correct, step: grammarReviewStep)
    }

    /// 1ラウンド完了。卒業済みを掃除してステップを進める（次ラウンドの再出題間隔の基準）。
    func advanceGrammarRound() {
        grammarReviewStates = ReviewQueue.pruneMastered(grammarReviewStates, currentStep: grammarReviewStep)
        grammarReviewStep += 1
    }

    // MARK: - スペルテストの復習（ReviewQueue 配線）

    private func saveSpellingReviewStates() {
        persistenceStore.save(spellingReviewStates, key: spellingReviewStatesKey)
    }

    private func saveSpellingReviewStep() {
        persistenceStore.save(spellingReviewStep, key: spellingReviewStepKey)
    }

    /// 既存の「見直しが必要な単語」（attempt 由来の導出型）を、初回だけ復習キューへ box1 で取り込む。
    /// 以後は `ReviewQueue` が注入を担う。cap で守られるので一度に流れ込んでも出題は最大2語/回。
    /// **init から呼ぶ**（描画経路では呼ばない）。init 中は didSet が発火しないため永続化も明示的に行う。
    private func seedSpellingReviewIfNeeded() {
        guard !spellingReviewSeeded else { return }
        spellingReviewSeeded = true
        let existingIDs = Set(spellingReviewStates.map(\.id))
        // box1（間隔1）で「1つ前のステップに出した」扱い → 次のテストから due になる。
        let seedLastSeen = spellingReviewStep - ReviewQueue.stepInterval(box: SRSScheduler.minBox)
        let seeded = reviewWords
            .filter { !existingIDs.contains($0.id) && !isChildWord($0) }
            .map { ReviewItemState(id: $0.id, box: SRSScheduler.minBox, lastSeenStep: seedLastSeen, addedAtStep: spellingReviewStep) }
        if !seeded.isEmpty {
            spellingReviewStates += seeded
        }
        // init 中の呼び出しでは didSet が走らないため、シード結果とフラグを明示保存する。
        saveSpellingReviewStates()
        persistenceStore.save(spellingReviewSeeded, key: spellingReviewSeededKey)
    }

    /// 1テストセッションの結果を復習キューに反映する（セッション完了時に1回だけ呼ぶ）。
    /// 語ごとに最新の自動判定で評価：`.autoCorrect`=正（box+1、数回で卒業）／それ以外=誤（box1で登録/リセット）。
    /// 反映後にステップを +1（次テストの再出題間隔の基準）。`apply` は「正×未登録=no-op」なので一発正解の新語は積まれない。
    /// `sessionWords` は実際に出題した語。text→id はこの集合で解決する（同綴り別ステップでも正しい語を更新する）。
    /// こども専用ステップ由来の語は積まない（親の単語と混ざらないように）。
    func recordSpellingTestResults(_ sessionAttempts: [SpellingAttempt], words sessionWords: [SpellingWord]) {
        // 語（正規化テキスト）ごとに最新の attempt を採用（同語が複数回出ても1ステップ1回反映）。
        var latestByText: [String: SpellingAttempt] = [:]
        for attempt in sessionAttempts.sorted(by: { $0.date < $1.date }) {
            latestByText[normalize(attempt.word)] = attempt
        }
        let wordByText = Dictionary(sessionWords.map { (normalize($0.text), $0) }, uniquingKeysWith: { first, _ in first })
        for (text, attempt) in latestByText {
            guard let word = wordByText[text], !isChildWord(word) else { continue }
            spellingReviewStates = ReviewQueue.apply(
                spellingReviewStates, itemID: word.id, correct: attempt.decision == .autoCorrect, step: spellingReviewStep
            )
        }
        spellingReviewStates = ReviewQueue.pruneMastered(spellingReviewStates, currentStep: spellingReviewStep)
        spellingReviewStep += 1

        // 永続「できた」：選択中ステップが満点(perfect run)に達したら固定する（コース横断・stepID名前空間で一意）。
        // テスト=全語が対象なので、練習(抑制で語が減る)では満点に届かず＝完了は“仕上げテスト”基準のまま。
        if let step = selectedWordStep, hasPerfectRun(for: step.words, in: attempts) {
            let signature = completionSignature(for: step)
            if !requiredCompletion.isCleared(signature) {
                requiredCompletion.markCleared(signature)
            }
        }

        // 運用テレメトリ: 1セッション1件の要約（低カーディナリティのみ。
        // 単語・氏名・手書き・自由入力・生の数値は送らない＝バケットだけ）。
        let correctCount = latestByText.values.filter { $0.decision == .autoCorrect }.count
        TelemetryCoordinator.shared.record(.practiceSessionSummary, payload: [
            "result": .string("completed"),
            "word_count_bucket": .string(TelemetryBucket.count(sessionWords.count)),
            "correct_count_bucket": .string(TelemetryBucket.count(correctCount))
        ])
    }

    // MARK: - 親レポート（スコアボード・採点待ち・まちがい復習の明細）

    /// 採点待ち件数：自動正解で確定していない（=親の確認が要る）テスト答案のうち、まだ未採点のもの。
    /// 自動正解は確認不要なので数えない（CTA を「やることがある時だけ」出すため）。
    var pendingGradingCount: Int {
        attempts.reduce(into: 0) { acc, attempt in
            if attempt.parentReviewDecision == .unreviewed && attempt.decision != .autoCorrect {
                acc += 1
            }
        }
    }

    /// 復習中（未卒業）かつ「いま明細に出せる」スペル語の (状態, 語)。
    /// カウントと明細を必ず一致させる（削除済み語・子由来・卒業済みは除外＝注入の eligible と同条件）。
    private func eligibleSpellingReview() -> [(state: ReviewItemState, word: SpellingWord)] {
        let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return spellingReviewStates.compactMap { state in
            guard let word = byID[state.id], !isChildWord(word),
                  !ReviewQueue.isMastered(state, currentStep: spellingReviewStep) else { return nil }
            return (state, word)
        }
    }

    /// 復習中（未卒業・明細に出せる）のスペル語数（「まちがい復習 スペルN」）。明細件数と一致する。
    var spellingReviewActiveCount: Int {
        eligibleSpellingReview().count
    }

    /// 復習中（未卒業）のことばパズル文数（「まちがい復習 文N」）。
    var grammarReviewActiveCount: Int {
        ReviewQueue.activeCount(grammarReviewStates, currentStep: grammarReviewStep)
    }

    /// 親ダッシュボードのスコアボード集計（連続学習日数・直近7日の取り組み数・まちがい復習件数・採点待ち）。
    func parentScoreboard(now: Date = Date(), calendar: Calendar = .current) -> ParentScoreboard {
        let weekly = learningReport(days: 7, now: now, calendar: calendar)
        let monthly = learningReport(days: 30, now: now, calendar: calendar)
        return ParentScoreboard(
            streakDays: monthly.currentStreakDays,
            weeklyCount: weekly.totalEvents,
            spellingReviewCount: spellingReviewActiveCount,
            grammarReviewCount: grammarReviewActiveCount,
            pendingGradingCount: pendingGradingCount
        )
    }

    // MARK: - 利用時間（保護者「ようす」タブ）

    /// 1区切りで積む滞在秒の上限（時計の異常や長時間放置で巨大化しないよう抑える）。
    private let maxUsageChunkSeconds: TimeInterval = 6 * 60 * 60

    /// いま前面に居る間の起点。背面化で確定（`endUsageSession`）。表示では未確定ぶんも足す。
    private(set) var usageSessionStart: Date?

    /// 前面化したので利用時間の計測を開始する（起点を記録するだけ）。
    /// 冪等：すでに計測中（起点あり）なら上書きしない＝起動直後の `.task` と `.active` 変化が
    /// 重なっても、先に立った起点ぶんの経過を落とさない。
    func beginUsageSession(now: Date = Date()) {
        guard usageSessionStart == nil else { return }
        usageSessionStart = now
    }

    /// 前面を離れたので、起点〜現在の滞在を利用時間へ確定して起点をクリアする。
    func endUsageSession(now: Date = Date(), calendar: Calendar = .current) {
        guard let start = usageSessionStart else { return }
        usageSessionStart = nil
        recordUsageInterval(start: start, end: now, calendar: calendar)
    }

    /// 滞在区間 `[start, end]` を暦日ごとに分割して利用時間へ加算する。
    /// 日付またぎを正しく振り分け、上限でクランプ。古い日はプルーンして保存量を抑える。
    /// 区間分割は `SpellingSyncCore.UsageInterval`、バケット操作は `UsageLog`。
    func recordUsageInterval(start: Date, end: Date, calendar: Calendar = .current) {
        guard end > start else { return }
        let clampedEnd = min(end, start.addingTimeInterval(maxUsageChunkSeconds))
        var log = usageLog
        for segment in UsageInterval.split(start: start, end: clampedEnd, calendar: calendar) {
            log = UsageLog.add(log, dayKey: usageDayKey(segment.dayStart, calendar: calendar), seconds: segment.seconds)
        }
        let keep = Set(recentDayKeys(now: end, calendar: calendar, days: 35))
        usageLog = UsageLog.pruned(log, keeping: keep)
    }

    /// 確定ぶん（`usageLog`）に、いま前面に居る未確定ぶん（起点〜now）を足した表示用ログ。永続はしない。
    private func liveUsageLog(now: Date, calendar: Calendar) -> [String: Int] {
        guard let start = usageSessionStart, now > start else { return usageLog }
        let clampedEnd = min(now, start.addingTimeInterval(maxUsageChunkSeconds))
        var log = usageLog
        for segment in UsageInterval.split(start: start, end: clampedEnd, calendar: calendar) {
            log = UsageLog.add(log, dayKey: usageDayKey(segment.dayStart, calendar: calendar), seconds: segment.seconds)
        }
        return log
    }

    /// 保護者「ようす」タブのひと目サマリーを合成する。学習イベントは1回だけ組み立てて使い回す。
    func overviewStats(now: Date = Date(), calendar: Calendar = .current) -> OverviewStats {
        let events = allLearningEvents()
        func report(days: Int) -> LearningReport {
            let from = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
            return LearningReportBuilder.build(events: events, from: from, to: now, calendar: calendar)
        }
        let weekly = report(days: 7)
        let monthly = report(days: 30)
        let recent = report(days: 14)
        let allTime = report(days: 3650)
        let weekStarts = currentWeekDayStarts(now: now, calendar: calendar)
        let weekKeys = weekStarts.map { usageDayKey($0, calendar: calendar) }
        let liveLog = liveUsageLog(now: now, calendar: calendar)
        return OverviewStats(
            childName: childName,
            grade: selectedGrade,
            avatarCharacterID: selectedCharacterID,
            streakDays: monthly.currentStreakDays,
            weeklyCount: weekly.totalEvents,
            totalWords: totalLearnedWordCount,
            masteredWords: allTime.learnedWords,
            accuracy: recent.accuracy,
            accuracyBand: AccuracyBand.classify(accuracy: recent.accuracy, totalEvents: recent.totalEvents),
            usageTodaySeconds: UsageLog.seconds(liveLog, on: usageDayKey(now, calendar: calendar)),
            usageWeekSeconds: UsageLog.total(liveLog, days: weekKeys),
            usageWeekSeries: UsageLog.series(liveLog, days: weekKeys),
            weeklyActivity: DailyActivity.counts(events: events, dayStarts: weekStarts, calendar: calendar),
            spellingReviewCount: spellingReviewActiveCount,
            grammarReviewCount: grammarReviewActiveCount,
            pendingGradingCount: pendingGradingCount
        )
    }

    /// 今いる週の月曜〜日曜の各暦頭（7件・月始まり）。
    private func currentWeekDayStarts(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        // weekday: 1=日…7=土。月曜を先頭にするため、月曜からの経過日数を求める。
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// 末日(=今日)から遡って `days` 日ぶんの日キー。プルーンの保持集合に使う。
    private func recentDayKeys(now: Date, calendar: Calendar, days: Int) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(days, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { usageDayKey($0, calendar: calendar) }
        }
    }

    private static let usageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 安定した日キー（"yyyy-MM-dd"）。暦のタイムゾーンに合わせる。@MainActor 上で直列化されるため共有可。
    private func usageDayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = Self.usageDayFormatter
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    /// まちがい復習（スペル）の明細：復習中の語を「定着の進み」順（box 昇順＝苦手が上）に。
    /// `lastAnsweredCorrect` は box>=2（=直近の解答が正解で箱が上がっている）から導出。件数は `spellingReviewActiveCount` と一致。
    func spellingReviewDetails(now: Date = Date()) -> [ReviewWordDetail] {
        eligibleSpellingReview()
            .map { pair in
                ReviewWordDetail(
                    id: pair.state.id,
                    text: pair.word.text,
                    box: pair.state.box,
                    lastAnsweredCorrect: pair.state.box >= SRSScheduler.minBox + 1
                )
            }
            .sorted { lhs, rhs in
                if lhs.box != rhs.box { return lhs.box < rhs.box }
                return lhs.text < rhs.text
            }
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

// バイト列レベルの永続化ポート（Core `ProfileScopedStore` がキー名前空間化に使う）。
// ファイルが真実の源（SwiftData→file 移行後）なので rawLoad はファイルのみ見る。
extension AppPersistenceStore: ProfileScopedRawStore {
    func rawLoad(_ key: String) -> Data? {
        Self.loadFileData(for: key)
    }
    func rawSave(_ data: Data, key: String) {
        Self.persistenceQueue.async {
            if Self.writeFileData(data, key: key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    /// 書き込み完了を待つ同期保存（移行のバリア用）。serial queue の `sync` で先行 async 保存の後に実行される。
    func rawSaveBlocking(_ data: Data, key: String) {
        Self.persistenceQueue.sync {
            if Self.writeFileData(data, key: key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// Core `ProfileScopedStore`（バイト列＋キー名前空間化）を、アプリの `UserDataStore`（型付き）境界に適合させる薄いアダプタ。
/// JSON encode/decode だけを担い、キーの prefix 判定・切替は Core 側に委ねる。
final class ProfileScopedUserDataStore: UserDataStore, @unchecked Sendable {
    let scoped: ProfileScopedStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(scoped: ProfileScopedStore) {
        self.scoped = scoped
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = scoped.load(key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        scoped.save(data, key: key)
    }
}

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

extension InMemoryUserDataStore: ProfileScopedRawStore {
    func rawLoad(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    func rawSave(_ data: Data, key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    func rawSaveBlocking(_ data: Data, key: String) {
        rawSave(data, key: key)
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
