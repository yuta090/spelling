import SwiftUI
import UIKit
import SpellingSyncCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SyncSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var iris = IrisController()
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingParentGate = false
    @State private var pendingParentOpen = false
    @State private var showingResults = false
    @State private var showingWordPreview = false
    @State private var showingPuzzle = false
    /// パズルを開いた瞬間の「この回に完了できる回数」。提示中は model 追従で揺れないよう固定する
    /// （完了→model更新でcoverが再評価されても、この回の許可数は開いた時点のまま保つ）。
    @State private var puzzleAllowanceSnapshot = 0
    /// 無料プランで今日のことばパズルを遊びきった時の「またあした」案内。
    @State private var showingPuzzleLimit = false
    @State private var showingCharacterPicker = false
    /// このセッションでホームのキャラヒントを出すか（初回起動の1回だけ true になる）。
    @State private var showCharHint = false
    /// 連続ログイン報酬（受け取り済みなら nil）。本日初回ホーム表示で 1 回だけ判定する。
    @State private var loginReward: CoinRewards.LoginOutcome?
    @State private var didCheckLogin = false
    @State private var showingStepPicker = false
    @State private var showingPracticeRetryPicker = false
    @State private var selectedPracticeWordIDs = Set<UUID>()
    #if DEBUG
    /// UIテストで親メニューを一度だけ自動オープンしたか。
    @State private var didUITestAutoOpenParent = false
    #endif
    /// 現在の練習選択が「既定（アクティブ全語）」由来か。復習・フォーカス・リトライの明示選択では false。
    /// 1日の新規導入上限はこれが true のときだけ適用する。
    @State private var isDefaultPracticeSelection = false
    @State private var retryPracticeWordIDs = Set<UUID>()
    @State private var lastPracticeWordIDs = Set<UUID>()
    @State private var completedPracticeWordIDs = Set<UUID>()
    @State private var practiceResumeState: PracticeSessionResumeState?

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    private var selectedPracticeWords: [SpellingWord] {
        let selected = model.activeWords.filter { selectedPracticeWordIDs.contains($0.id) }
        // 1日の新規導入上限は「既定（アクティブ全語）選択」のときだけ適用する。
        // 復習・フォーカス・リトライの明示選択は対象外（等価判定では誤爆するためソースをフラグで持つ）。
        return model.dailyCappedPracticeWords(selected, isFullActiveSelection: isDefaultPracticeSelection)
    }

    private var selectedPracticeWordIDsInOrder: [UUID] {
        selectedPracticeWords.map(\.id)
    }

    private var activeHomeReviewWordIDs: Set<UUID> {
        model.homeReviewWordIDs.intersection(Set(model.activeWords.map(\.id)))
    }

    private var isHomeReviewActive: Bool {
        !activeHomeReviewWordIDs.isEmpty
    }

    private var activePracticeResumeState: PracticeSessionResumeState? {
        guard let practiceResumeState,
              practiceResumeState.wordIDs == selectedPracticeWordIDsInOrder,
              practiceResumeState.index < selectedPracticeWords.count
        else {
            return nil
        }
        return practiceResumeState
    }

    private var activePracticeRemainingCount: Int? {
        guard let activePracticeResumeState else {
            return nil
        }
        return max(selectedPracticeWords.count - activePracticeResumeState.index, 1)
    }

    private var hasFinishedCurrentPracticeRound: Bool {
        !completedPracticeWordIDs.isEmpty && completedPracticeWordIDs == Set(selectedPracticeWordIDsInOrder)
    }

    private var selectedCharacter: HomeRewardCharacter {
        HomeRewardCharacter.character(id: model.selectedCharacterID)
    }

    private var latestTestButtonSummary: HomeLatestTestButtonSummary? {
        let sourceKeys = Set(model.testWordsForSelectedStep.map { normalize($0.text) })
        guard !sourceKeys.isEmpty else {
            return nil
        }

        let relatedAttempts = model.attempts.filter { sourceKeys.contains(normalize($0.word)) }
        let sessions = Dictionary(grouping: relatedAttempts, by: \.sessionID)
            .compactMap { sessionID, attempts -> HomeLatestTestButtonSummary? in
                let sortedAttempts = attempts.sorted { $0.date < $1.date }
                guard let date = sortedAttempts.last?.date else {
                    return nil
                }

                return HomeLatestTestButtonSummary(
                    sessionID: sessionID,
                    date: date,
                    score: sortedAttempts.filter { $0.decision == .autoCorrect }.count
                )
            }
            .sorted { $0.date < $1.date }

        guard let latest = sessions.last else {
            return nil
        }

        return latest.numbered(sessions.count)
    }

    var body: some View {
        ZStack {
            NavigationStack {
            ZStack(alignment: .bottom) {
                HomeBackground(themeID: model.selectedBackgroundID)

                VStack(spacing: 20) {
                    header

                    Spacer(minLength: 22)

                    VStack(spacing: 12) {
                        HomeLearnedWordMilestone(count: model.totalLearnedWordCount, language: language)

                        ChildMissionPanel(
                            stepTitle: model.selectedWordStep?.title(language: language) ?? language.text(japanese: "いまのステップ", english: "Current step"),
                            practiceCount: selectedPracticeWords.count,
                            carryOverCount: model.carryOverReviewWordsForSelectedStep.count,
                            progress: model.todayStepProgress,
                            language: language,
                            canPractice: !selectedPracticeWords.isEmpty,
                            canTest: !model.nextTestWords.isEmpty,
                            canSwitchSteps: model.wordSteps.count > 1,
                            hasFinishedPracticeRound: hasFinishedCurrentPracticeRound,
                            hasPracticeResume: activePracticeResumeState != nil,
                            remainingPracticeCount: activePracticeRemainingCount,
                            isReviewPractice: isHomeReviewActive,
                            latestTestSummary: latestTestButtonSummary,
                            character: selectedCharacter,
                            showCharacterHint: showCharHint,
                            startPractice: startPractice,
                            showWords: { showingWordPreview = true },
                            showPuzzle: { tryOpenPuzzle() },
                            showStepPicker: { showingStepPicker = true },
                            showCharacters: {
                                showCharHint = false   // タップしたらこのセッションでも消す
                                showingCharacterPicker = true
                            },
                            startTest: {
                                iris.cover(animated: !reduceMotion) {
                                    activeMode = .test
                                }
                            }
                        )
                    }
                    .frame(maxWidth: 760)

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 36)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .navigationDestination(isPresented: Binding(
                get: { activeMode != nil },
                set: { isPresented in
                    if !isPresented { activeMode = nil }
                }
            )) {
                if let mode = activeMode {
                let resumeState = mode == .practice ? activePracticeResumeState : nil
                SpellingSessionView(
                    mode: mode,
                    words: sessionWords(for: mode),
                    resumeState: resumeState,
                    onPracticeProgressChange: { state in
                        practiceResumeState = state
                    },
                    onPracticeCompleted: {
                        finishCurrentPracticeRound()
                    },
                    onPracticeStartTest: {
                        practiceResumeState = nil
                        activeMode = nil
                        DispatchQueue.main.async {
                            activeMode = .test
                        }
                    },
                    onPracticeRetryWords: { words in
                        startPracticeAgain(words: words)
                    },
                    onRequestClose: {
                        iris.cover(animated: !reduceMotion) {
                            activeMode = nil
                        }
                    }
                )
                }
            }
            .fullScreenCover(isPresented: $showingParent) {
                ParentDashboardView()
                    .environmentObject(model)
                    .environmentObject(session)
            }
            #if DEBUG
            .onAppear {
                if UITestSupport.opensParentOnLaunch && !didUITestAutoOpenParent {
                    didUITestAutoOpenParent = true
                    showingParent = true
                }
            }
            #endif
            // 親メニューは「かんたんな大人ゲート」の奥に隠す（子の誤操作で開かない）。
            .sheet(isPresented: $showingParentGate, onDismiss: {
                if pendingParentOpen {
                    pendingParentOpen = false
                    showingParent = true
                }
            }) {
                ParentGateView {
                    pendingParentOpen = true
                    showingParentGate = false
                }
            }
            .sheet(isPresented: $showingResults) {
                ResultsView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingWordPreview) {
                PracticeWordPreviewSheet(
                    words: selectedPracticeWords,
                    stepTitle: model.selectedWordStep?.title(language: language) ?? language.text(japanese: "いまのステップ", english: "Current step"),
                    language: language
                )
                .environmentObject(model)
            }
            .fullScreenCover(isPresented: $showingPuzzle) {
                // 子の学年＋親トグルでプールを絞ってから出題（やさしい文だけ／ユーモアON-OFF）。
                // maxKanjiGrade は解説の漢字ふりがな出し分けに使う（例文和訳と同じ基準）。
                // playAllowance＝この回に完了できる回数（無料は今日の残り。完了ごとに記録）。
                PuzzleSessionView(
                    policy: model.contentPolicy,
                    maxKanjiGrade: model.childMaxKanjiGrade,
                    playAllowance: puzzleAllowanceSnapshot,
                    onCompleted: { model.recordPuzzleCompletion() }
                )
            }
            // 無料プランで今日のことばパズルを遊びきった時の、やさしい「またあした」案内。
            .sheet(isPresented: $showingPuzzleLimit) {
                PuzzleDailyLimitSheet(language: language)
            }
            .sheet(isPresented: $showingPracticeRetryPicker) {
                PracticeRetryPickerSheet(
                    words: selectedPracticeWords,
                    selectedIDs: $retryPracticeWordIDs,
                    language: language,
                    onStart: startSelectedPracticeRetry
                )
            }
            .sheet(isPresented: $showingCharacterPicker) {
                CharacterPickerSheet(language: language)
                    .environmentObject(model)
                    .presentationDetents([.large])
                    .presentationContentInteraction(.scrolls)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingStepPicker) {
                ChildStepPickerSheet(language: language)
                    .environmentObject(model)
                    .presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            schedulePracticeSelectionSync()
            // キャラヒントは初回起動の1回だけ。次回からは出さない（毎回起動では出さない）。
            if !model.hasShownHomeCharacterHint {
                showCharHint = true
                model.hasShownHomeCharacterHint = true
            }
            // 連続ログイン報酬（本日初回のみ）。UIテストではオーバーレイのノイズを避けて出さない。
            if !didCheckLogin && !UITestSupport.isActive {
                didCheckLogin = true
                if let reward = model.recordDailyLogin() {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { loginReward = reward }
                }
            }
        }
        .overlay {
            if let reward = loginReward {
                LoginRewardView(streak: reward.streak, coins: reward.coins, language: language) {
                    withAnimation(.easeOut(duration: 0.2)) { loginReward = nil }
                }
                .transition(.opacity)
            }
        }
        .onValueChange(of: model.activeWords.map(\.id)) { _ in
            schedulePracticeSelectionSync()
        }
        .onValueChange(of: model.homeReviewWordIDs) { _ in
            schedulePracticeSelectionSync()
        }
        .onValueChange(of: model.focusedPracticeWordIDs) { _ in
            schedulePracticeSelectionSync()
        }
        .onValueChange(of: selectedPracticeWordIDs) { _ in
            clearCompletedPracticeRoundIfWordsChanged()
            clearPracticeResumeIfWordsChanged()
        }

            IrisTransitionOverlay(controller: iris)
        }
    }

    /// ことばパズルを開く。無料プランで今日のぶん（1日2回）を遊びきっていたら、
    /// 出題せず「またあした」案内を出す（プレミアム/デバッグ解放は無制限）。
    private func tryOpenPuzzle() {
        if model.canPlayPuzzleToday {
            // この回の許可数を開いた時点で固定（提示中の model 更新で揺れないように）。
            puzzleAllowanceSnapshot = model.puzzlePlaysRemainingToday
            showingPuzzle = true
        } else {
            showingPuzzleLimit = true
        }
    }

    private func startPractice() {
        guard !selectedPracticeWords.isEmpty else {
            return
        }

        if hasFinishedCurrentPracticeRound {
            retryPracticeWordIDs = Set(selectedPracticeWordIDsInOrder)
            showingPracticeRetryPicker = true
            return
        }

        completedPracticeWordIDs = []
        clearPracticeResumeIfWordsChanged()
        // 実際に練習へ出す（キャップ適用後の）新規語に導入スタンプを押す。
        model.stampFirstIntroducedIfNeeded(selectedPracticeWords)
        iris.cover(animated: !reduceMotion) {
            activeMode = .practice
        }
    }

    private func startPracticeAgain(words: [String]) {
        let wordTexts = Set(words.map { normalize($0) })
        let activeIDs = Set(model.activeWords.map(\.id))
        let retryIDs = Set(model.activeWords.filter { wordTexts.contains(normalize($0.text)) }.map(\.id))
        guard !retryIDs.isEmpty else {
            return
        }

        selectedPracticeWordIDs = retryIDs
        isDefaultPracticeSelection = false
        lastPracticeWordIDs = activeIDs
        completedPracticeWordIDs = []
        practiceResumeState = nil
        activeMode = nil
        DispatchQueue.main.async {
            activeMode = .practice
        }
    }

    private func startSelectedPracticeRetry() {
        let availableIDs = Set(selectedPracticeWords.map(\.id))
        let retryIDs = retryPracticeWordIDs.intersection(availableIDs)
        guard !retryIDs.isEmpty else {
            return
        }

        selectedPracticeWordIDs = retryIDs
        isDefaultPracticeSelection = false
        completedPracticeWordIDs = []
        practiceResumeState = nil
        showingPracticeRetryPicker = false
        activeMode = nil
        iris.cover(animated: !reduceMotion) {
            activeMode = .practice
        }
    }

    private func sessionWords(for mode: SessionMode) -> [SpellingWord] {
        switch mode {
        case .practice:
            return selectedPracticeWords
        case .test:
            return model.nextTestWords
        case .review:
            return model.todayStepProgress.remainingWords
        }
    }

    private func schedulePracticeSelectionSync() {
        DispatchQueue.main.async {
            syncPracticeSelectionIfNeeded()
        }
    }

    private func syncPracticeSelectionIfNeeded() {
        let activeIDs = Set(model.activeWords.map(\.id))
        if applyHomeReviewSelectionIfNeeded(activeIDs: activeIDs) {
            return
        }

        if applyFocusedPracticeSelectionIfNeeded(activeIDs: activeIDs) {
            return
        }

        guard activeIDs != lastPracticeWordIDs else {
            selectedPracticeWordIDs = selectedPracticeWordIDs.intersection(activeIDs)
            clearCompletedPracticeRoundIfWordsChanged()
            clearPracticeResumeIfWordsChanged()
            return
        }

        selectedPracticeWordIDs = activeIDs
        isDefaultPracticeSelection = true
        lastPracticeWordIDs = activeIDs
        completedPracticeWordIDs = []
        clearPracticeResumeIfWordsChanged()
    }

    @discardableResult
    private func applyHomeReviewSelectionIfNeeded(activeIDs: Set<UUID>? = nil) -> Bool {
        let activeIDs = activeIDs ?? Set(model.activeWords.map(\.id))
        let reviewIDs = model.homeReviewWordIDs.intersection(activeIDs)
        guard !reviewIDs.isEmpty else {
            return false
        }

        selectedPracticeWordIDs = reviewIDs
        isDefaultPracticeSelection = false
        lastPracticeWordIDs = activeIDs
        completedPracticeWordIDs = []
        clearPracticeResumeIfWordsChanged()
        return true
    }

    @discardableResult
    private func applyFocusedPracticeSelectionIfNeeded(activeIDs: Set<UUID>? = nil) -> Bool {
        let activeIDs = activeIDs ?? Set(model.activeWords.map(\.id))
        let focusedIDs = model.focusedPracticeWordIDs.intersection(activeIDs)
        guard !focusedIDs.isEmpty else {
            return false
        }

        selectedPracticeWordIDs = focusedIDs
        isDefaultPracticeSelection = false
        lastPracticeWordIDs = activeIDs
        completedPracticeWordIDs = []
        model.focusedPracticeWordIDs = []
        clearPracticeResumeIfWordsChanged()
        return true
    }

    private func finishCurrentPracticeRound() {
        let completedIDs = Set(selectedPracticeWordIDsInOrder)
        practiceResumeState = nil
        guard !completedIDs.isEmpty else {
            return
        }

        completedPracticeWordIDs = completedIDs
        lastPracticeWordIDs = Set(model.activeWords.map(\.id))
    }

    private func clearPracticeResumeIfWordsChanged() {
        guard let practiceResumeState else {
            return
        }
        if practiceResumeState.wordIDs != selectedPracticeWordIDsInOrder {
            self.practiceResumeState = nil
        }
    }

    private func clearCompletedPracticeRoundIfWordsChanged() {
        guard !completedPracticeWordIDs.isEmpty else {
            return
        }
        if completedPracticeWordIDs != Set(selectedPracticeWordIDsInOrder) {
            completedPracticeWordIDs = []
        }
    }

    private var homeTitle: String {
        let name = model.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return language.text(japanese: "ホーム", english: "Home") }
        return language.text(japanese: "\(name)の ホーム", english: "\(name)'s Home")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Label(homeTitle, systemImage: "house.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.10, green: 0.32, blue: 0.74))

            Spacer()

            Button {
                showingResults = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .tapFeedback(scale: 0.88, bounce: true)
            .accessibilityLabel(language.text(japanese: "結果", english: "Results"))

            Button {
                #if DEBUG
                if UITestSupport.isActive {
                    showingParent = true   // UIテストは親ゲートをバイパスして親メニューを開く
                    return
                }
                #endif
                showingParentGate = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .accessibilityIdentifier("home.parentButton")
            .tapFeedback(scale: 0.88, bounce: true)
            .accessibilityLabel(language.text(japanese: "保護者メニュー", english: "Parent menu"))
        }
    }
}

private struct ChildMissionPanel: View {
    var stepTitle: String
    var practiceCount: Int
    var carryOverCount: Int
    var progress: TodayStepProgress
    var language: AppLanguage
    var canPractice: Bool
    var canTest: Bool
    var canSwitchSteps: Bool
    var hasFinishedPracticeRound: Bool
    var hasPracticeResume: Bool
    var remainingPracticeCount: Int?
    var isReviewPractice: Bool
    var latestTestSummary: HomeLatestTestButtonSummary?
    var character: HomeRewardCharacter
    var showCharacterHint: Bool = false
    var startPractice: () -> Void
    var showWords: () -> Void
    var showPuzzle: () -> Void
    var showStepPicker: () -> Void
    var showCharacters: () -> Void
    var startTest: () -> Void

    @State private var hintPulse = false

    private var missionText: String {
        if hasFinishedPracticeRound {
            return isReviewPractice
                ? language.text(japanese: "もういちど ふくしゅう", english: "Review again")
                : language.text(japanese: "もういちど れんしゅう", english: "Practice again")
        }
        if practiceCount == 0 {
            return language.text(japanese: "たんごがない", english: "No words")
        }
        if let remainingPracticeCount {
            if isReviewPractice {
                return language.text(japanese: "あと \(remainingPracticeCount)こ ふくしゅう", english: "\(remainingPracticeCount) review left")
            }
            return language.text(japanese: "あと \(remainingPracticeCount)こ れんしゅう", english: "\(remainingPracticeCount) practice left")
        }
        if isReviewPractice {
            return language.text(japanese: "\(practiceCount)こ ふくしゅう", english: "\(practiceCount) review words")
        }
        if carryOverCount > 0 {
            return language.text(japanese: "\(practiceCount)こ + ふくしゅう\(carryOverCount)こ", english: "\(practiceCount) + \(carryOverCount) review")
        }
        return language.text(japanese: "\(practiceCount)こ れんしゅう", english: "\(practiceCount) words")
    }

    private var progressValue: Double {
        guard progress.totalWords > 0 else {
            return 0
        }
        return Double(progress.clearedCount) / Double(progress.totalWords)
    }

    private var primaryButtonTitle: String {
        if hasFinishedPracticeRound {
            return isReviewPractice
                ? language.text(japanese: "えらんで ふくしゅう", english: "Choose Review")
                : language.text(japanese: "えらんで れんしゅう", english: "Choose Practice")
        }
        if hasPracticeResume {
            return isReviewPractice
                ? language.text(japanese: "ふくしゅうのつづき", english: "Continue Review")
                : language.text(japanese: "つづきから", english: "Continue")
        }
        return isReviewPractice
            ? language.text(japanese: "ふくしゅうする", english: "Review")
            : language.text(japanese: "はじめる", english: "Start")
    }

    private var primaryButtonIcon: String {
        if hasFinishedPracticeRound {
            return "arrow.clockwise"
        }
        return hasPracticeResume ? "arrow.forward.circle.fill" : "play.fill"
    }

    private var isPrimaryButtonDisabled: Bool {
        !canPractice
    }

    private var testButtonTitle: String {
        latestTestSummary?.title(language: language) ?? language.text(japanese: "テスト", english: "Test")
    }

    private var primaryButtonTint: Color {
        Color(red: 0.16, green: 0.42, blue: 0.84)
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 22) {
                VStack(spacing: 8) {
                    if showCharacterHint {
                        Label(language.text(japanese: "タップで きせかえ", english: "Tap to change"), systemImage: "hand.tap.fill")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.84))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.95)))
                            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                            .scaleEffect(hintPulse ? 1.08 : 1.0)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    hintPulse = true
                                }
                            }
                    }

                    Button(action: showCharacters) {
                        RewardCharacterAvatar(character: character)
                            .frame(width: 118, height: 118)
                    }
                    .buttonStyle(.plain)
                    .tapFeedback(scale: 0.92, bounce: true)
                    .accessibilityLabel(language.text(japanese: "\(character.name(language: language))を選ぶ", english: "Choose \(character.name(language: language))"))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(language.text(japanese: "きょうのミッション", english: "Today"))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Button(action: showStepPicker) {
                        HStack(spacing: 8) {
                            Text(stepTitle)
                                .font(.title2.monospacedDigit().weight(.heavy))
                                .lineLimit(1)
                            if canSwitchSteps {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.headline.weight(.heavy))
                            }
                        }
                        .foregroundStyle(Color(red: 0.14, green: 0.35, blue: 0.76))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(red: 0.91, green: 0.96, blue: 1.0).opacity(0.90))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                    .tapFeedback(scale: 0.93, bounce: true)
                    .disabled(!canSwitchSteps)
                    .accessibilityLabel(language.text(japanese: "\(stepTitle)を変える", english: "Change \(stepTitle)"))

                    Text(missionText)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                }

                Spacer(minLength: 0)
            }

            ProgressView(value: progressValue)
                .tint(Color(red: 0.32, green: 0.68, blue: 0.28))
                .scaleEffect(x: 1, y: 1.8, anchor: .center)
                .accessibilityLabel(language.text(
                    japanese: "きょうできた \(progress.clearedCount) / \(progress.totalWords)",
                    english: "Today \(progress.clearedCount) of \(progress.totalWords)"
                ))

            Button(action: startPractice) {
                Label(
                    primaryButtonTitle,
                    systemImage: primaryButtonIcon
                )
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderedProminent)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .tapFeedback(scale: 0.92, bounce: true)
            .tint(primaryButtonTint)
            .disabled(isPrimaryButtonDisabled)

            HStack(spacing: 12) {
                MissionSmallButton(
                    title: language.text(japanese: "たんご", english: "Words"),
                    systemImage: "list.bullet",
                    tint: Color(red: 0.49, green: 0.30, blue: 0.78),
                    disabled: practiceCount == 0,
                    action: showWords
                )

                MissionSmallButton(
                    title: testButtonTitle,
                    systemImage: "checklist.checked",
                    tint: Color(red: 0.20, green: 0.58, blue: 0.24),
                    disabled: !canTest,
                    action: startTest
                )

                MissionSmallButton(
                    title: language.text(japanese: "ことばパズル", english: "Puzzle"),
                    systemImage: "puzzlepiece.fill",
                    tint: Color(red: 0.96, green: 0.62, blue: 0.10),
                    disabled: false,
                    action: showPuzzle
                )
            }
        }
        .padding(24)
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 10)
    }
}

private struct HomeLatestTestButtonSummary: Equatable {
    var sessionID: UUID
    var date: Date
    var score: Int
    var attemptNumber: Int = 0

    func numbered(_ number: Int) -> HomeLatestTestButtonSummary {
        HomeLatestTestButtonSummary(
            sessionID: sessionID,
            date: date,
            score: score,
            attemptNumber: number
        )
    }

    func title(language: AppLanguage) -> String {
        language.text(
            japanese: "テスト \(attemptNumber)回め \(score)点",
            english: "Test #\(attemptNumber) \(score) pts"
        )
    }
}

private struct MissionSmallButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.vertical, 14)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.bordered)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback(scale: 0.93, bounce: true)
        .tint(tint)
        .disabled(disabled)
    }
}

/// 無料プランで今日のことばパズル（1日2回）を遊びきった時の、子ども向け「またあした」案内。
/// 専門用語・課金訴求は出さず、やさしく次の遊び（れんしゅう・たんご）へ気持ちを向ける。
private struct PuzzleDailyLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Text("🌙")
                .font(.system(size: 72))
            Text(language.text(japanese: "きょうの ことばパズルは おしまい！",
                               english: "That's all the puzzles for today!"))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text(japanese: "また あした あそぼうね。\nきょうは れんしゅうや たんごで あそべるよ 🌟",
                               english: "Come back tomorrow!\nFor now, try practice or words 🌟"))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text(language.text(japanese: "わかった！", english: "OK!"))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .tapFeedback(bounce: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
    }
}

private struct ChildStepPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    // 昇順（[0]=下=スタート/ステップ1）。マップは下から上へ登る。
    private var orderedSteps: [WordStep] {
        model.wordSteps
    }

    // 今日ぶんを終えたステップ＝マップ上で「できた（緑チェック）」になる。
    private var completedToday: Set<String> {
        Set(orderedSteps.filter { model.todayProgress(for: $0).isComplete }.map(\.id))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if orderedSteps.isEmpty {
                    HomeBackground(themeID: model.selectedBackgroundID)
                    EmptyStateView(
                        language.text(japanese: "まだステップがありません", english: "No steps yet"),
                        systemImage: "book.closed.fill",
                        description: Text(language.text(japanese: "保護者メニューで単語を登録してください。", english: "Add words in the parent menu."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    StepMapView(
                        steps: orderedSteps,
                        completedStepIDs: completedToday,
                        selectedStepID: model.selectedWordStepID,
                        language: language,
                        character: HomeRewardCharacter.character(id: model.selectedCharacterID)
                    ) { stepID in
                        model.selectedWordStepID = stepID
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(language.text(japanese: "ステップをえらぼう", english: "Choose a Step"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
        }
    }
}

private func sheetContentWidth(in geometry: GeometryProxy, maxWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
    let safeWidth = geometry.size.width - geometry.safeAreaInsets.leading - geometry.safeAreaInsets.trailing
    return min(maxWidth, max(1, safeWidth - horizontalPadding * 2))
}

private struct SheetHomeBackground: View {
    var themeID: String

    var body: some View {
        GeometryReader { geometry in
            HomeBackground(themeID: themeID, ignoresSafeArea: false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                // 写実的・濃い背景でも中身（タイトルやカード）が読めるよう、薄い白で覆ってコントラストを確保。
                .overlay(Color.white.opacity(0.62))
        }
        .allowsHitTesting(false)
    }
}

private struct PracticeWordPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()
    var words: [SpellingWord]
    var stepTitle: String
    var language: AppLanguage

    @State private var showingChildAddWords = false
    @State private var expandedWordID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = sheetContentWidth(in: geometry, maxWidth: 760, horizontalPadding: 28)

                ZStack {
                    SheetHomeBackground(themeID: model.selectedBackgroundID)

                    VStack(spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(language.text(japanese: "きょうのたんご", english: "Words"))
                                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                                Text(stepTitle)
                                    .font(.title3.monospacedDigit().weight(.heavy))
                                    .foregroundStyle(Color(red: 0.14, green: 0.35, blue: 0.76))
                            }

                            Spacer()

                            Button {
                                showingChildAddWords = true
                            } label: {
                                Label(
                                    language.text(japanese: "ことばをふやす", english: "Add Words"),
                                    systemImage: "plus.circle.fill"
                                )
                                .font(.title3.weight(.heavy))
                                .padding(.vertical, 12)
                                .padding(.horizontal, 18)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.49, green: 0.30, blue: 0.78))
                            .tapFeedback(scale: 0.93, bounce: true)
                            .accessibilityLabel(language.text(japanese: "じぶんでことばをふやす", english: "Add your own words"))
                        }

                        if words.isEmpty {
                            EmptyStateView(
                                language.text(japanese: "たんごがありません", english: "No words"),
                                systemImage: "list.bullet",
                                description: Text(language.text(japanese: "保護者メニューで単語を入れてください。", english: "Add words in the parent menu."))
                            )
                        } else {
                            ScrollView {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                    ForEach(words) { word in
                                        PracticeWordPreviewChip(
                                            word: word,
                                            language: language,
                                            isExpanded: expandedWordID == word.id,
                                            onTap: { tapWord(word) },
                                            speak: { text in
                                                speech.speak(text, language: model.settings.language, rate: model.settings.speechRate)
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                }
            }
            .sheet(isPresented: $showingChildAddWords) {
                ChildAddWordSheet(language: language) {
                    // 登録できたらプレビューを閉じてホームへ。こども専用ステップが選ばれている。
                    dismiss()
                }
                .environmentObject(model)
            }
        }
    }

    private func tapWord(_ word: SpellingWord) {
        // タップで発音。あわせて例文の表示/非表示をトグル（同時に開くのは1つだけ）。
        speech.speak(word.text, language: model.settings.language, rate: model.settings.speechRate)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            expandedWordID = (expandedWordID == word.id) ? nil : word.id
        }
    }
}

private struct ChildAddWordSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage
    var onRegistered: () -> Void

    @State private var rawText = ""
    @State private var showingCamera = false
    @State private var isReadingImage = false
    @State private var statusMessage: String?
    @StateObject private var scanProgress = ScanProgressModel()

    private var canRegister: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground(themeID: model.selectedBackgroundID)

                VStack(alignment: .leading, spacing: 16) {
                    Text(language.text(japanese: "じぶんで ことばを ふやそう", english: "Add Your Own Words"))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))

                    Text(language.text(
                        japanese: "1ぎょうに 1つ えいごを かいてね。いみは「cat | ねこ」のように かけるよ。",
                        english: "One word per line. Add a meaning like \"cat | ねこ\"."
                    ))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    ImportJapaneseOptionsView(language: language, draftText: $rawText)

                    Button {
                        showingCamera = true
                    } label: {
                        Label(
                            isReadingImage
                                ? language.text(japanese: "よみとり中…", english: "Reading…")
                                : language.text(japanese: "カメラでとりこむ", english: "Use Camera"),
                            systemImage: "camera.fill"
                        )
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.14, green: 0.35, blue: 0.76))
                    .tapFeedback(scale: 0.95, bounce: true)
                    .disabled(!cameraAvailable || isReadingImage)

                    if isReadingImage {
                        ScanProgressBar(
                            fraction: scanProgress.fraction,
                            label: language.text(japanese: "よみとり中", english: "Reading"),
                            tint: Color(red: 0.14, green: 0.35, blue: 0.76)
                        )
                    }

                    if !cameraAvailable {
                        Text(language.text(japanese: "このタブレットには カメラが ないみたい。", english: "No camera on this device."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $rawText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1.5)
                        )

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.58, blue: 0.24))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        register()
                    } label: {
                        Label(language.text(japanese: "とうろくする", english: "Register"), systemImage: "checkmark.circle.fill")
                            .font(.title2.weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.20, green: 0.58, blue: 0.24))
                    .tapFeedback(scale: 0.93, bounce: true)
                    .disabled(!canRegister)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 680)
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                WordCameraImportSheet(language: language) { image in
                    readImage(image)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func register() {
        switch model.addChildWords(from: rawText) {
        case .added:
            onRegistered()
        case .blocked:
            statusMessage = language.text(
                japanese: "いまの たんごを ぜんぶ 100てんに してから、あたらしい ことばを ふやせるよ。",
                english: "Get 100 on your current words first, then you can add new ones."
            )
        case .noNewWords:
            statusMessage = language.text(japanese: "あたらしい ことばが ないみたい。", english: "No new words to add.")
        }
    }

    private func readImage(_ image: UIImage) {
        isReadingImage = true
        statusMessage = nil
        scanProgress.start()
        Task {
            do {
                let recognized = try await WordListImageTextRecognizer(language: model.settings.language)
                    .recognizeWords(in: image) { fraction in
                        Task { @MainActor in scanProgress.report(fraction) }
                    }
                await MainActor.run {
                    scanProgress.finish()
                    appendWords(recognized)
                    isReadingImage = false
                }
            } catch {
                await MainActor.run {
                    scanProgress.reset()
                    statusMessage = language.text(japanese: "よみとれなかったよ。もういちど ためしてね。", english: "Couldn't read it. Try again.")
                    isReadingImage = false
                }
            }
        }
    }

    private func appendWords(_ recognized: [String]) {
        let cleaned = recognized
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            statusMessage = language.text(japanese: "ことばが 見つからなかったよ。", english: "No words found.")
            return
        }
        let lines = cleaned.map {
            formattedImportedWordLine(
                $0,
                knownWords: model.words,
                attachJapanese: model.settings.importAttachJapanese,
                useKanji: model.settings.importUseKanji
            )
        }.filter { !$0.isEmpty }
        let existing = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let appended = lines.joined(separator: "\n")
        rawText = existing.isEmpty ? appended : existing + "\n" + appended
        statusMessage = language.text(japanese: "\(cleaned.count)こ よみとったよ！", english: "Read \(cleaned.count) words!")
    }
}

private struct PracticeWordPreviewChip: View {
    var word: SpellingWord
    var language: AppLanguage
    var isExpanded: Bool
    var onTap: () -> Void
    var speak: (String) -> Void

    @State private var example: WordExample?

    private var prompt: String {
        word.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.text)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Spacer(minLength: 4)

                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78).opacity(0.8))
                }

                if !prompt.isEmpty {
                    RubyPromptText(
                        text: prompt,
                        baseFontSize: 18,
                        rubyFontSize: 8,
                        baseColor: Color(red: 0.18, green: 0.38, blue: 0.72),
                        rubyColor: Color(red: 0.46, green: 0.32, blue: 0.64),
                        maxLines: 1
                    )
                }

                if isExpanded {
                    exampleSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(14)
            .background(.white.opacity(isExpanded ? 0.96 : 0.90))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isExpanded ? Color(red: 0.49, green: 0.30, blue: 0.78).opacity(0.7) : Color(red: 0.72, green: 0.82, blue: 0.96),
                        lineWidth: isExpanded ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .tapFeedback(scale: 0.96, bounce: true)
        .onValueChange(of: isExpanded) { expanded in
            if expanded, example == nil {
                example = WordBank.shared.examples(for: word.text, limit: 1).first
            }
        }
    }

    @ViewBuilder
    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if let example {
                HStack(alignment: .top, spacing: 8) {
                    Text(example.en)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.24, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        speak(example.en)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                    }
                    .buttonStyle(.plain)
                    .tapFeedback(scale: 0.9, bounce: true)
                    .accessibilityLabel(language.text(japanese: "れいぶんを よむ", english: "Play example"))
                }
                Text(example.ja)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(language.text(japanese: "れいぶんは ないよ", english: "No example"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PracticeRetryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var words: [SpellingWord]
    @Binding var selectedIDs: Set<UUID>
    var language: AppLanguage
    var onStart: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 12)
    ]

    private var selectedCount: Int {
        words.filter { selectedIDs.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(language.text(japanese: "もういちど やるたんご", english: "Practice Again"))
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                        Text(language.text(japanese: "\(selectedCount)/\(words.count)こ", english: "\(selectedCount)/\(words.count) selected"))
                            .font(.title2.monospacedDigit().weight(.heavy))
                            .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                    }
                    .frame(maxWidth: .infinity)

                    if words.isEmpty {
                        EmptyStateView(
                            language.text(japanese: "たんごがありません", english: "No words"),
                            systemImage: "list.bullet"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(words) { word in
                                    PracticeWordToggleChip(
                                        word: word,
                                        isSelected: selectedIDs.contains(word.id),
                                        language: language
                                    ) {
                                        toggle(word.id)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }

                        HStack(spacing: 12) {
                            Button {
                                selectedIDs = Set(words.map(\.id))
                            } label: {
                                Label(language.text(japanese: "ぜんぶ", english: "All"), systemImage: "checkmark.square.fill")
                                    .frame(minHeight: 44)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.bordered)
                            .contentShape(Capsule())
                            .tapFeedback()

                            Button {
                                selectedIDs = []
                            } label: {
                                Label(language.text(japanese: "はずす", english: "Clear"), systemImage: "square")
                                    .frame(minHeight: 44)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.bordered)
                            .contentShape(Capsule())
                            .tapFeedback()

                            Spacer(minLength: 0)
                        }
                        .font(.headline.weight(.bold))

                        Button(action: onStart) {
                            Label(language.text(japanese: "これを れんしゅう", english: "Practice These"), systemImage: "pencil.line")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.borderedProminent)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .tapFeedback()
                        .tint(Color(red: 0.16, green: 0.42, blue: 0.84))
                        .disabled(selectedCount == 0)
                    }
                }
                .frame(maxWidth: 760)
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct PracticeWordSelectionSummaryPanel: View {
    var words: [SpellingWord]
    var selectedIDs: Set<UUID>
    var stepTitle: String
    var language: AppLanguage
    var openPicker: () -> Void

    private var selectedWords: [SpellingWord] {
        words.filter { selectedIDs.contains($0.id) }
    }

    private var selectedSummary: String {
        if selectedWords.isEmpty {
            return language.text(japanese: "まだ選んでいません", english: "No words selected")
        }
        return selectedWords.map(\.text).prefix(4).joined(separator: " / ")
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                .frame(width: 58, height: 58)
                .background(Color(red: 0.96, green: 0.91, blue: 1.0))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(language.text(japanese: "きょう れんしゅうする たんご", english: "Words to Practice Today"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                Text(language.text(
                    japanese: "\(stepTitle) から \(selectedWords.count)/\(words.count) こ選んでいます",
                    english: "\(selectedWords.count)/\(words.count) selected from \(stepTitle)"
                ))
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                Text(selectedSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: openPicker) {
                Label(language.text(japanese: "単語をえらぶ", english: "Choose Words"), systemImage: "square.grid.2x2.fill")
                    .font(.headline.weight(.heavy))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderedProminent)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .tapFeedback()
            .tint(Color(red: 0.49, green: 0.30, blue: 0.78))
            .disabled(words.isEmpty)
        }
        .padding(14)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.78, green: 0.68, blue: 0.94), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.text(
            japanese: "今日練習する単語。\(selectedWords.count)個選んでいます。単語を選ぶボタンで変更できます。",
            english: "Practice words. \(selectedWords.count) selected. Use Choose Words to change them."
        ))
    }
}

private struct PracticeWordPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var words: [SpellingWord]
    @Binding var selectedIDs: Set<UUID>
    var stepTitle: String
    var language: AppLanguage

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()

                PracticeWordPickerPanel(
                    words: words,
                    selectedIDs: $selectedIDs,
                    stepTitle: stepTitle,
                    language: language
                )
                .frame(maxWidth: 760)
                .padding(28)
            }
            .navigationTitle(language.text(japanese: "単語をえらぶ", english: "Choose Words"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "できた", english: "Done"), systemImage: "checkmark")
                    }
                    .font(.headline.weight(.bold))
                }
            }
        }
    }
}

private struct PracticeWordPickerPanel: View {
    var words: [SpellingWord]
    @Binding var selectedIDs: Set<UUID>
    var stepTitle: String
    var language: AppLanguage

    private let columns = [
        GridItem(.adaptive(minimum: 138, maximum: 210), spacing: 10)
    ]

    private var selectedCount: Int {
        words.filter { selectedIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(language.text(japanese: "きょう れんしゅうする たんご", english: "Words to Practice Today"), systemImage: "checkmark.square.fill")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                    Text(language.text(
                        japanese: "\(stepTitle) の中から、やる単語にチェックをつけてね。",
                        english: "Check the words from \(stepTitle) that you want to practice."
                    ))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(language.text(japanese: "\(selectedCount)/\(words.count) こ", english: "\(selectedCount)/\(words.count)"))
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(Color(red: 0.96, green: 0.91, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if words.isEmpty {
                Text(language.text(japanese: "単語がまだありません", english: "No words yet"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(words) { word in
                            PracticeWordToggleChip(
                                word: word,
                                isSelected: selectedIDs.contains(word.id),
                                language: language
                            ) {
                                toggle(word.id)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 178)

                HStack(spacing: 10) {
                    Button {
                        selectedIDs = Set(words.map(\.id))
                    } label: {
                        Label(language.text(japanese: "ぜんぶチェック", english: "Select All"), systemImage: "checkmark.square.fill")
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.bordered)
                    .contentShape(Capsule())
                    .tapFeedback()

                    Button {
                        selectedIDs = []
                    } label: {
                        Label(language.text(japanese: "チェックをはずす", english: "Clear"), systemImage: "square")
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.bordered)
                    .contentShape(Capsule())
                    .tapFeedback()

                    Spacer()
                }
                .font(.subheadline.weight(.bold))
            }
        }
        .padding(14)
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.78, green: 0.68, blue: 0.94), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct PracticeWordToggleChip: View {
    var word: SpellingWord
    var isSelected: Bool
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(isSelected ? Color(red: 0.49, green: 0.30, blue: 0.78) : Color(red: 0.48, green: 0.50, blue: 0.56))

                Text(word.text)
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 10)
            .background(isSelected ? Color(red: 0.96, green: 0.91, blue: 1.0) : Color(red: 0.97, green: 0.98, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(red: 0.57, green: 0.38, blue: 0.82) : Color(red: 0.78, green: 0.82, blue: 0.90), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .accessibilityLabel(language.text(japanese: "\(word.text)を\(isSelected ? "えらんでいます" : "えらんでいません")", english: "\(word.text) is \(isSelected ? "selected" : "not selected")"))
    }
}

struct ChildTaskBanner: View {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 14 : 18) {
            Image(systemName: systemImage)
                .font(compact ? .title.weight(.heavy) : .largeTitle.weight(.heavy))
                .foregroundStyle(tint)
                .frame(width: compact ? 54 : 66, height: compact ? 54 : 66)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                Text(title)
                    .font(compact ? .title2.weight(.heavy) : .largeTitle.weight(.heavy))
                    .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(message)
                    .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 12 : 16)
        .padding(.horizontal, compact ? 14 : 18)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.10),
                    Color.white.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.28), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(message)")
    }
}

private struct StepSelectorPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(language.text(japanese: "単語セット", english: "Word Set"), systemImage: "rectangle.stack.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.30, blue: 0.70))

                Spacer()

                if let step = model.selectedWordStep {
                    Text("\(step.title(language: language)) ・ \(step.words.count)")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                }
            }

            if orderedSteps.isEmpty {
                Text(language.text(japanese: "単語がまだありません", english: "No words yet"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(orderedSteps) { step in
                            StepSelectorChip(
                                step: step,
                                language: language,
                                isSelected: step.id == model.selectedWordStepID
                            ) {
                                model.selectedWordStepID = step.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.68, green: 0.80, blue: 0.96), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

private struct StepSelectorChip: View {
    var step: WordStep
    var language: AppLanguage
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title(language: language))
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .lineLimit(1)
                Text(formattedStepDate(step.registeredDate, language: language))
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(language.text(japanese: "\(step.words.count)単語", english: "\(step.words.count) words"))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Color(red: 0.11, green: 0.30, blue: 0.70))
            .frame(width: 142, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color(red: 0.16, green: 0.40, blue: 0.82) : Color(red: 0.94, green: 0.98, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(red: 0.16, green: 0.40, blue: 0.82) : Color(red: 0.65, green: 0.78, blue: 0.95), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .accessibilityLabel("\(step.title(language: language)), \(formattedStepDate(step.registeredDate, language: language))")
    }
}

private struct HomeActionCard: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var colors: [Color]
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 22) {
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .bold))
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 9) {
                    Text(title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.92)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 142)
            .padding(.horizontal, 28)
            .background(
                LinearGradient(colors: disabled ? [.gray.opacity(0.5), .gray.opacity(0.65)] : colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: colors.last?.opacity(disabled ? 0 : 0.24) ?? .clear, radius: 12, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .disabled(disabled)
    }
}

private struct TodayProgressCard: View {
    var language: AppLanguage
    var progress: TodayStepProgress
    var action: () -> Void

    private var canReviewRemaining: Bool {
        progress.hasTestActivity && progress.remainingCount > 0
    }

    private var statusTitle: String {
        if progress.totalWords == 0 {
            return language.text(japanese: "単語がありません", english: "No words")
        }
        if progress.isComplete && progress.hasPerfectRun {
            return language.text(japanese: "ぜんぶできた", english: "Fully Done")
        }
        if progress.isComplete {
            return language.text(japanese: "きょうはできた", english: "Done Today")
        }
        if progress.hasTestActivity {
            return language.text(japanese: "あと\(progress.remainingCount)こ", english: "\(progress.remainingCount) left")
        }
        return language.text(japanese: "まずはテスト", english: "Start Test")
    }

    private var statusMessage: String {
        if progress.totalWords == 0 {
            return language.text(japanese: "親メニューで単語を入れてください", english: "Add words in the parent menu")
        }
        if progress.isComplete && progress.hasPerfectRun {
            return language.text(japanese: "全部通しでできました", english: "Full set completed")
        }
        if progress.isComplete {
            return language.text(japanese: "しあげテストに進めます", english: "Ready for the final test")
        }
        if progress.hasTestActivity {
            return language.text(japanese: "残りだけやればOK", english: "Only the remaining words")
        }
        return language.text(japanese: "全部を一回やってみよう", english: "Try all words once")
    }

    var body: some View {
        VStack(spacing: 14) {
            BearMascot()
                .frame(width: 96, height: 96)

            VStack(spacing: 6) {
                Text(language.text(japanese: "きょうできた", english: "Today"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.12))

                Text(progress.totalWords == 0 ? "0/0" : "\(progress.clearedCount)/\(progress.totalWords)")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(progress.isComplete ? Color(red: 0.18, green: 0.58, blue: 0.20) : Color(red: 0.13, green: 0.35, blue: 0.76))

                Text(statusTitle)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(progress.isComplete && progress.hasPerfectRun ? Color(red: 0.78, green: 0.42, blue: 0.06) : Color(red: 0.12, green: 0.22, blue: 0.38))

                Text(statusMessage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label(language.text(japanese: "残りをれんしゅう", english: "Practice Left"), systemImage: "book.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderedProminent)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .tapFeedback()
            .tint(Color(red: 0.52, green: 0.35, blue: 0.76))
            .disabled(!canReviewRemaining)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 258)
        .background((progress.isComplete ? Color(red: 0.92, green: 1.0, blue: 0.84) : Color(red: 1.0, green: 0.95, blue: 0.84)).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.95, green: 0.70, blue: 0.36).opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

private struct HomeStatsRow: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    var body: some View {
        let progress = model.todayStepProgress

        HStack(spacing: 12) {
            HomeStatChip(
                title: language.text(japanese: "ステップ", english: "Step"),
                value: model.selectedWordStep.map { "\($0.number)" } ?? "-",
                systemImage: "rectangle.stack.fill"
            )
            HomeStatChip(
                title: language.text(japanese: "できた", english: "Done"),
                value: "\(progress.clearedCount)/\(progress.totalWords)",
                systemImage: "target"
            )
            HomeStatChip(
                title: language.text(japanese: "単語", english: "Words"),
                value: "\(model.activeWords.count)",
                systemImage: "list.bullet"
            )
            HomeStatChip(
                title: language.text(japanese: "残り", english: "Left"),
                value: "\(progress.remainingCount)",
                systemImage: "arrow.counterclockwise"
            )
        }
        .frame(maxWidth: 760)
    }
}

private struct HomeStatChip: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.16, green: 0.38, blue: 0.76))
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }
}

enum HomeRewardCharacterCategory: String, CaseIterable, Identifiable {
    case starter
    case animal
    case sea
    case people
    case vehicle
    case building
    case landmark
    case japan
    case food
    case sports
    case instruments
    case insect
    case dinosaur
    case space
    case cosme
    case fantasy

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .starter:
            return language.text(japanese: "きほん", english: "Starter")
        case .animal:
            return language.text(japanese: "どうぶつ", english: "Animals")
        case .sea:
            return language.text(japanese: "うみのいきもの", english: "Sea Life")
        case .people:
            return language.text(japanese: "ひと", english: "People")
        case .vehicle:
            return language.text(japanese: "のりもの", english: "Vehicles")
        case .building:
            return language.text(japanese: "たてもの", english: "Buildings")
        case .landmark:
            return language.text(japanese: "せかいのたてもの", english: "Landmarks")
        case .japan:
            return language.text(japanese: "にほんのめいしょ", english: "Japan")
        case .food:
            return language.text(japanese: "たべもの", english: "Food")
        case .sports:
            return language.text(japanese: "スポーツ", english: "Sports")
        case .instruments:
            return language.text(japanese: "がっき", english: "Instruments")
        case .insect:
            return language.text(japanese: "むし", english: "Insects")
        case .dinosaur:
            return language.text(japanese: "きょうりゅう", english: "Dinosaurs")
        case .space:
            return language.text(japanese: "うちゅう", english: "Space")
        case .cosme:
            return language.text(japanese: "コスメ", english: "Cosmetics")
        case .fantasy:
            return language.text(japanese: "ファンタジー", english: "Fantasy")
        }
    }
}

enum HomeRewardCharacterStyle {
    case bear
    case cat
    case dog
    case rabbit
    case panda
    case penguin
    case lion
    case fox
    case koala
    case sheep
    case elephant
    case giraffe
    case owl
    case turtle
    case whale
    case car
    case train
    case rocket
    case plane
    case bus
    case ship
    case helicopter
    case bicycle
    case tractor
    case balloon
    case monkey
    case pig
    case personShort
    case personLong
    case personCurly
    case personBun
    case personBuzz
    case personPonytail
    case personTwintails
    case personBob
    case personAfro
    case personSpiky
    case personBraids
    case personWavy
    case robot
    case ghost
    case star
    case unicorn
    case dragon
    case excavator
    case crane
    case dumpTruck
    case house
    case school
    case castle
    case tower
    case lipstick
    case perfume
    case compact
    case nailPolish
    case octopus
    case crab
    case fish
    case dolphin
    case shark
    case jellyfish
    case starfish
    case strawberry
    case cake
    case iceCream
    case donut
    case riceBall
    case sushi
    case hamburger
    case soccerBall
    case baseball
    case basketball
    case tennisBall
    case trophy
    case eiffel
    case tokyoTower
    case liberty
    case pyramid
    case pisa
    case bigBen
    case tajMahal
    case fuji
    case torii
    case moai
    case windmill
    case colosseum
    case greatWall
    case operaHouse
    case stonehenge
    case christRedeemer
    case sagrada
    case goldenGate
    case towerBridge
    case ferrisWheel
    case kinkaku
    case sphinx
    case angkor
    case matterhorn
    case libertyBell
    case whiteHouse
    case notreDame
    case burjKhalifa
    case archTriomphe
    case skytree
    case japaneseCastle
    case pagoda
    case daibutsu
    case gasshou
    case stBasil
    case parthenon
    case machuPicchu
    case mosque
    case montStMichel
    case capitol
    case petra
    case kiyomizu
    case tokyoStation
    case templeHall
    case duomo
    case euroCastle
    case mayanPyramid
    case skyscraper
    case starFort
    case guitar
    case piano
    case drum
    case trumpet
    case violin
    case butterfly
    case beetle
    case ladybug
    case bee
    case ant
    case trex
    case triceratops
    case stegosaurus
    case brachiosaurus
    case pteranodon
    case astronaut
    case ufo
    case saturn
    case moon
    case alien
    case alienBlob
    case alienTriclops
    case alienSquid
    case alienWorm
    case alienMushroom
    case alienBugeye
    case alienCrystal
    case alienHover
    case velociraptor
    case ankylosaurus
    case spinosaurus
    case parasaurolophus
    case plesiosaurus
    case dinoEgg
    case mouse
    case cow
    case horse
    case wolf
    case kangaroo
    case bat
    case goat
    case otter
    case orca
    case seahorse
    case shrimp
    case duck
    case bird
    case flamingo
    case parrot
    case swan
    case snail
    case dragonfly
    case banana
    case taiyaki
    case cookie
    /// 画像ベースの「なかま」。SwiftUI 描画ではなく Assets の WebP(Data Set) を表示する。
    /// 画像は character.id から `nakama_<id>` という NSDataAsset 名で引く。
    case imageAsset
}

struct HomeRewardCharacter: Identifiable {
    var id: String
    var category: HomeRewardCharacterCategory
    var japaneseName: String
    var englishName: String
    var price: Int
    var style: HomeRewardCharacterStyle
    var primary: Color
    var secondary: Color
    var accent: Color

    var isFree: Bool {
        price == 0
    }

    func name(language: AppLanguage) -> String {
        language.text(japanese: japaneseName, english: englishName)
    }

    static func character(id: String) -> HomeRewardCharacter {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    // MARK: - CHARACTER CATALOG (generated from scripts/characters.csv)
    // Do not edit the catalog/defaultUnlockedIDs/defaultID below by hand.
    // Run: python3 scripts/generate_characters.py
    // CATALOG-GENERATED-BEGIN
    static let defaultID = "bear"

    static let defaultUnlockedIDs: Set<String> = ["bear", "cat", "dog", "rabbit", "panda", "penguin", "fox", "owl"]

    static let catalog: [HomeRewardCharacter] = [
        HomeRewardCharacter(
            id: "bear",
            category: .starter,
            japaneseName: "くま",
            englishName: "Bear",
            price: 0,
            style: .bear,
            primary: Color(red: 0.8706, green: 0.5490, blue: 0.2196),
            secondary: Color(red: 0.9686, green: 0.7686, blue: 0.4392),
            accent: Color(red: 0.4902, green: 0.2980, blue: 0.1608)
        ),
        HomeRewardCharacter(
            id: "cat",
            category: .starter,
            japaneseName: "ねこ",
            englishName: "Cat",
            price: 0,
            style: .cat,
            primary: Color(red: 0.5804, green: 0.6392, blue: 0.7804),
            secondary: Color(red: 0.9216, green: 0.8706, blue: 0.7608),
            accent: Color(red: 0.3216, green: 0.3412, blue: 0.4588)
        ),
        HomeRewardCharacter(
            id: "dog",
            category: .starter,
            japaneseName: "いぬ",
            englishName: "Dog",
            price: 0,
            style: .dog,
            primary: Color(red: 0.7608, green: 0.5294, blue: 0.2980),
            secondary: Color(red: 0.9804, green: 0.7804, blue: 0.4784),
            accent: Color(red: 0.4392, green: 0.2784, blue: 0.1608)
        ),
        HomeRewardCharacter(
            id: "rabbit",
            category: .animal,
            japaneseName: "うさぎ",
            englishName: "Rabbit",
            price: 0,
            style: .rabbit,
            primary: Color(red: 0.9490, green: 0.8000, blue: 0.9020),
            secondary: Color(red: 1.0000, green: 0.9412, blue: 0.9804),
            accent: Color(red: 0.7490, green: 0.3804, blue: 0.6196)
        ),
        HomeRewardCharacter(
            id: "panda",
            category: .animal,
            japaneseName: "パンダ",
            englishName: "Panda",
            price: 0,
            style: .panda,
            primary: Color(red: 0.1686, green: 0.1882, blue: 0.2314),
            secondary: Color(red: 0.9608, green: 0.9608, blue: 0.9216),
            accent: Color(red: 0.3490, green: 0.6196, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "penguin",
            category: .animal,
            japaneseName: "ペンギン",
            englishName: "Penguin",
            price: 0,
            style: .penguin,
            primary: Color(red: 0.1804, green: 0.3098, blue: 0.6196),
            secondary: Color(red: 0.9412, green: 0.9686, blue: 1.0000),
            accent: Color(red: 0.9608, green: 0.6196, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "lion",
            category: .animal,
            japaneseName: "ライオン",
            englishName: "Lion",
            price: 50,
            style: .lion,
            primary: Color(red: 0.9412, green: 0.5294, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.7804, blue: 0.2980),
            accent: Color(red: 0.5804, green: 0.2588, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "fox",
            category: .animal,
            japaneseName: "きつね",
            englishName: "Fox",
            price: 0,
            style: .fox,
            primary: Color(red: 0.9216, green: 0.4314, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6980),
            accent: Color(red: 0.4314, green: 0.1804, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "koala",
            category: .animal,
            japaneseName: "コアラ",
            englishName: "Koala",
            price: 40,
            style: .koala,
            primary: Color(red: 0.5608, green: 0.6118, blue: 0.6588),
            secondary: Color(red: 0.8784, green: 0.9020, blue: 0.9216),
            accent: Color(red: 0.2196, green: 0.2392, blue: 0.2784)
        ),
        HomeRewardCharacter(
            id: "hamster",
            category: .animal,
            japaneseName: "ハムスター",
            englishName: "Hamster",
            price: 40,
            style: .bear,
            primary: Color(red: 0.8588, green: 0.6392, blue: 0.3804),
            secondary: Color(red: 1.0000, green: 0.8588, blue: 0.6196),
            accent: Color(red: 0.5020, green: 0.2784, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "sheep",
            category: .animal,
            japaneseName: "ひつじ",
            englishName: "Sheep",
            price: 50,
            style: .sheep,
            primary: Color(red: 0.9608, green: 0.9608, blue: 0.9020),
            secondary: Color(red: 0.7216, green: 0.7608, blue: 0.8196),
            accent: Color(red: 0.3804, green: 0.4000, blue: 0.4588)
        ),
        HomeRewardCharacter(
            id: "elephant",
            category: .animal,
            japaneseName: "ぞう",
            englishName: "Elephant",
            price: 50,
            style: .elephant,
            primary: Color(red: 0.5490, green: 0.6314, blue: 0.7412),
            secondary: Color(red: 0.8196, green: 0.8784, blue: 0.9608),
            accent: Color(red: 0.2392, green: 0.3098, blue: 0.4392)
        ),
        HomeRewardCharacter(
            id: "giraffe",
            category: .animal,
            japaneseName: "キリン",
            englishName: "Giraffe",
            price: 50,
            style: .giraffe,
            primary: Color(red: 0.9412, green: 0.6784, blue: 0.2196),
            secondary: Color(red: 1.0000, green: 0.8588, blue: 0.4392),
            accent: Color(red: 0.5686, green: 0.3098, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "owl",
            category: .animal,
            japaneseName: "ふくろう",
            englishName: "Owl",
            price: 0,
            style: .owl,
            primary: Color(red: 0.6000, green: 0.3804, blue: 0.1804),
            secondary: Color(red: 0.9490, green: 0.7804, blue: 0.4784),
            accent: Color(red: 0.2784, green: 0.1686, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "turtle",
            category: .animal,
            japaneseName: "かめ",
            englishName: "Turtle",
            price: 50,
            style: .turtle,
            primary: Color(red: 0.2196, green: 0.5804, blue: 0.2980),
            secondary: Color(red: 0.7216, green: 0.8588, blue: 0.4196),
            accent: Color(red: 0.1216, green: 0.3608, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "whale",
            category: .animal,
            japaneseName: "くじら",
            englishName: "Whale",
            price: 60,
            style: .whale,
            primary: Color(red: 0.2196, green: 0.4784, blue: 0.8000),
            secondary: Color(red: 0.7804, green: 0.9216, blue: 1.0000),
            accent: Color(red: 0.1216, green: 0.2588, blue: 0.5216)
        ),
        HomeRewardCharacter(
            id: "frog",
            category: .animal,
            japaneseName: "かえる",
            englishName: "Frog",
            price: 40,
            style: .panda,
            primary: Color(red: 0.1490, green: 0.5608, blue: 0.2588),
            secondary: Color(red: 0.7608, green: 0.9412, blue: 0.5804),
            accent: Color(red: 0.0784, green: 0.3216, blue: 0.1412)
        ),
        HomeRewardCharacter(
            id: "tiger",
            category: .animal,
            japaneseName: "トラ",
            englishName: "Tiger",
            price: 60,
            style: .lion,
            primary: Color(red: 0.9608, green: 0.5020, blue: 0.1020),
            secondary: Color(red: 1.0000, green: 0.7608, blue: 0.2784),
            accent: Color(red: 0.2000, green: 0.1294, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "squirrel",
            category: .animal,
            japaneseName: "リス",
            englishName: "Squirrel",
            price: 50,
            style: .cat,
            primary: Color(red: 0.6588, green: 0.3804, blue: 0.1608),
            secondary: Color(red: 0.9412, green: 0.6784, blue: 0.3608),
            accent: Color(red: 0.3412, green: 0.1804, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "deer",
            category: .animal,
            japaneseName: "しか",
            englishName: "Deer",
            price: 60,
            style: .rabbit,
            primary: Color(red: 0.6706, green: 0.4196, blue: 0.2000),
            secondary: Color(red: 0.9608, green: 0.7608, blue: 0.4784),
            accent: Color(red: 0.3608, green: 0.2000, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "car",
            category: .vehicle,
            japaneseName: "くるま",
            englishName: "Car",
            price: 40,
            style: .car,
            primary: Color(red: 0.1804, green: 0.4588, blue: 0.8588),
            secondary: Color(red: 0.6588, green: 0.8588, blue: 1.0000),
            accent: Color(red: 0.0784, green: 0.1804, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "train",
            category: .vehicle,
            japaneseName: "でんしゃ",
            englishName: "Train",
            price: 50,
            style: .train,
            primary: Color(red: 0.2000, green: 0.6196, blue: 0.3804),
            secondary: Color(red: 0.8196, green: 0.9608, blue: 0.7412),
            accent: Color(red: 0.1020, green: 0.3216, blue: 0.2000)
        ),
        HomeRewardCharacter(
            id: "rocket",
            category: .vehicle,
            japaneseName: "ロケット",
            englishName: "Rocket",
            price: 60,
            style: .rocket,
            primary: Color(red: 0.7804, green: 0.2980, blue: 0.7216),
            secondary: Color(red: 0.9804, green: 0.9020, blue: 1.0000),
            accent: Color(red: 0.9608, green: 0.5490, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "plane",
            category: .vehicle,
            japaneseName: "ひこうき",
            englishName: "Plane",
            price: 60,
            style: .plane,
            primary: Color(red: 0.2784, green: 0.6196, blue: 0.9020),
            secondary: Color(red: 0.8588, green: 0.9608, blue: 1.0000),
            accent: Color(red: 0.1412, green: 0.3412, blue: 0.6980)
        ),
        HomeRewardCharacter(
            id: "bus",
            category: .vehicle,
            japaneseName: "バス",
            englishName: "Bus",
            price: 50,
            style: .bus,
            primary: Color(red: 0.9608, green: 0.6980, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.9216, blue: 0.5412),
            accent: Color(red: 0.5804, green: 0.3608, blue: 0.0588)
        ),
        HomeRewardCharacter(
            id: "truck",
            category: .vehicle,
            japaneseName: "トラック",
            englishName: "Truck",
            price: 50,
            style: .car,
            primary: Color(red: 0.2196, green: 0.5216, blue: 0.7216),
            secondary: Color(red: 0.7216, green: 0.9020, blue: 1.0000),
            accent: Color(red: 0.1020, green: 0.2510, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "ship",
            category: .vehicle,
            japaneseName: "ふね",
            englishName: "Ship",
            price: 60,
            style: .ship,
            primary: Color(red: 0.2000, green: 0.4196, blue: 0.7804),
            secondary: Color(red: 0.8392, green: 0.9412, blue: 1.0000),
            accent: Color(red: 0.8196, green: 0.3412, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "helicopter",
            category: .vehicle,
            japaneseName: "ヘリコプター",
            englishName: "Helicopter",
            price: 60,
            style: .helicopter,
            primary: Color(red: 0.8392, green: 0.2784, blue: 0.2784),
            secondary: Color(red: 1.0000, green: 0.8196, blue: 0.7412),
            accent: Color(red: 0.4784, green: 0.1216, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "bicycle",
            category: .vehicle,
            japaneseName: "じてんしゃ",
            englishName: "Bicycle",
            price: 50,
            style: .bicycle,
            primary: Color(red: 0.5216, green: 0.3412, blue: 0.8196),
            secondary: Color(red: 0.9216, green: 0.8588, blue: 1.0000),
            accent: Color(red: 0.2784, green: 0.1608, blue: 0.5412)
        ),
        HomeRewardCharacter(
            id: "tractor",
            category: .vehicle,
            japaneseName: "トラクター",
            englishName: "Tractor",
            price: 60,
            style: .tractor,
            primary: Color(red: 0.2196, green: 0.6196, blue: 0.2784),
            secondary: Color(red: 0.8784, green: 0.9608, blue: 0.6588),
            accent: Color(red: 0.1216, green: 0.3216, blue: 0.1608)
        ),
        HomeRewardCharacter(
            id: "balloon",
            category: .vehicle,
            japaneseName: "ききゅう",
            englishName: "Balloon",
            price: 60,
            style: .balloon,
            primary: Color(red: 0.8196, green: 0.3216, blue: 0.6588),
            secondary: Color(red: 1.0000, green: 0.8392, blue: 0.9412),
            accent: Color(red: 0.4392, green: 0.2000, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "submarine",
            category: .vehicle,
            japaneseName: "せんすいかん",
            englishName: "Submarine",
            price: 70,
            style: .ship,
            primary: Color(red: 0.8784, green: 0.6196, blue: 0.0784),
            secondary: Color(red: 1.0000, green: 0.9020, blue: 0.4000),
            accent: Color(red: 0.5216, green: 0.3412, blue: 0.0510)
        ),
        HomeRewardCharacter(
            id: "firetruck",
            category: .vehicle,
            japaneseName: "しょうぼうしゃ",
            englishName: "Fire Truck",
            price: 70,
            style: .bus,
            primary: Color(red: 0.8588, green: 0.1608, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.7804, blue: 0.6980),
            accent: Color(red: 0.4784, green: 0.0588, blue: 0.0392)
        ),
        HomeRewardCharacter(
            id: "scooter",
            category: .vehicle,
            japaneseName: "スクーター",
            englishName: "Scooter",
            price: 60,
            style: .bicycle,
            primary: Color(red: 0.1804, green: 0.6196, blue: 0.6980),
            secondary: Color(red: 0.8000, green: 0.9608, blue: 1.0000),
            accent: Color(red: 0.0784, green: 0.3412, blue: 0.4000)
        ),
        HomeRewardCharacter(
            id: "monkey",
            category: .animal,
            japaneseName: "さる",
            englishName: "Monkey",
            price: 50,
            style: .monkey,
            primary: Color(red: 0.6196, green: 0.4196, blue: 0.2353),
            secondary: Color(red: 0.9490, green: 0.8235, blue: 0.6510),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "pig",
            category: .animal,
            japaneseName: "ぶた",
            englishName: "Pig",
            price: 40,
            style: .pig,
            primary: Color(red: 0.9490, green: 0.6510, blue: 0.7373),
            secondary: Color(red: 1.0000, green: 0.8392, blue: 0.8784),
            accent: Color(red: 0.7686, green: 0.4196, blue: 0.5216)
        ),
        HomeRewardCharacter(
            id: "kid_haru",
            category: .people,
            japaneseName: "ハル",
            englishName: "Haru",
            price: 40,
            style: .personShort,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.4314, green: 0.7569, blue: 0.8941),
            accent: Color(red: 0.1216, green: 0.1059, blue: 0.0902)
        ),
        HomeRewardCharacter(
            id: "kid_sora",
            category: .people,
            japaneseName: "ソラ",
            englishName: "Sora",
            price: 40,
            style: .personLong,
            primary: Color(red: 0.8471, green: 0.6078, blue: 0.4235),
            secondary: Color(red: 0.9490, green: 0.6510, blue: 0.7608),
            accent: Color(red: 0.2314, green: 0.1647, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "kid_niko",
            category: .people,
            japaneseName: "ニコ",
            englishName: "Niko",
            price: 50,
            style: .personCurly,
            primary: Color(red: 0.4196, green: 0.2588, blue: 0.1490),
            secondary: Color(red: 0.9608, green: 0.8157, blue: 0.2980),
            accent: Color(red: 0.0824, green: 0.0667, blue: 0.0510)
        ),
        HomeRewardCharacter(
            id: "kid_mei",
            category: .people,
            japaneseName: "メイ",
            englishName: "Mei",
            price: 50,
            style: .personBun,
            primary: Color(red: 0.7765, green: 0.5412, blue: 0.3686),
            secondary: Color(red: 0.5608, green: 0.8196, blue: 0.4784),
            accent: Color(red: 0.1255, green: 0.0863, blue: 0.0588)
        ),
        HomeRewardCharacter(
            id: "kid_leo",
            category: .people,
            japaneseName: "レオ",
            englishName: "Leo",
            price: 40,
            style: .personBuzz,
            primary: Color(red: 0.9686, green: 0.8431, blue: 0.7098),
            secondary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            accent: Color(red: 0.4196, green: 0.2667, blue: 0.1373)
        ),
        HomeRewardCharacter(
            id: "kid_aya",
            category: .people,
            japaneseName: "アヤ",
            englishName: "Aya",
            price: 50,
            style: .personPonytail,
            primary: Color(red: 0.8784, green: 0.6588, blue: 0.4706),
            secondary: Color(red: 0.7255, green: 0.5490, blue: 0.8784),
            accent: Color(red: 0.1020, green: 0.0863, blue: 0.1333)
        ),
        HomeRewardCharacter(
            id: "kid_ken",
            category: .people,
            japaneseName: "ケン",
            englishName: "Ken",
            price: 50,
            style: .personShort,
            primary: Color(red: 0.3608, green: 0.2275, blue: 0.1294),
            secondary: Color(red: 0.2980, green: 0.6510, blue: 0.4196),
            accent: Color(red: 0.0706, green: 0.0549, blue: 0.0392)
        ),
        HomeRewardCharacter(
            id: "kid_luna",
            category: .people,
            japaneseName: "ルナ",
            englishName: "Luna",
            price: 50,
            style: .personLong,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.8784, green: 0.4157, blue: 0.6588),
            accent: Color(red: 0.8784, green: 0.7216, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "kid_jin",
            category: .people,
            japaneseName: "ジン",
            englishName: "Jin",
            price: 50,
            style: .personBuzz,
            primary: Color(red: 0.7098, green: 0.4784, blue: 0.3137),
            secondary: Color(red: 0.2275, green: 0.4314, blue: 0.6471),
            accent: Color(red: 0.0784, green: 0.0627, blue: 0.0471)
        ),
        HomeRewardCharacter(
            id: "kid_mio",
            category: .people,
            japaneseName: "ミオ",
            englishName: "Mio",
            price: 60,
            style: .personCurly,
            primary: Color(red: 0.8314, green: 0.6039, blue: 0.4157),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.7098, green: 0.2824, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "kid_nao",
            category: .people,
            japaneseName: "ナオ",
            englishName: "Nao",
            price: 60,
            style: .personBun,
            primary: Color(red: 0.9490, green: 0.7961, blue: 0.6588),
            secondary: Color(red: 0.4000, green: 0.7608, blue: 0.7608),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "kid_riku",
            category: .people,
            japaneseName: "リク",
            englishName: "Riku",
            price: 60,
            style: .personPonytail,
            primary: Color(red: 0.4000, green: 0.2588, blue: 0.1647),
            secondary: Color(red: 0.8784, green: 0.5412, blue: 0.2353),
            accent: Color(red: 0.8784, green: 0.4157, blue: 0.6588)
        ),
        HomeRewardCharacter(
            id: "kid_yui",
            category: .people,
            japaneseName: "ユイ",
            englishName: "Yui",
            price: 40,
            style: .personTwintails,
            primary: Color(red: 0.9686, green: 0.8431, blue: 0.7098),
            secondary: Color(red: 0.9490, green: 0.6510, blue: 0.7608),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_rin",
            category: .people,
            japaneseName: "リン",
            englishName: "Rin",
            price: 50,
            style: .personTwintails,
            primary: Color(red: 0.8471, green: 0.6078, blue: 0.4235),
            secondary: Color(red: 0.4000, green: 0.7608, blue: 0.7608),
            accent: Color(red: 0.2902, green: 0.1843, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "kid_emma",
            category: .people,
            japaneseName: "エマ",
            englishName: "Emma",
            price: 50,
            style: .personBob,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.8784, green: 0.7216, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "kid_hana",
            category: .people,
            japaneseName: "ハナ",
            englishName: "Hana",
            price: 40,
            style: .personBob,
            primary: Color(red: 0.7765, green: 0.5412, blue: 0.3686),
            secondary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            accent: Color(red: 0.0824, green: 0.0667, blue: 0.0510)
        ),
        HomeRewardCharacter(
            id: "kid_max",
            category: .people,
            japaneseName: "マックス",
            englishName: "Max",
            price: 60,
            style: .personAfro,
            primary: Color(red: 0.5412, green: 0.3529, blue: 0.2196),
            secondary: Color(red: 0.8784, green: 0.4667, blue: 0.2353),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_zoe",
            category: .people,
            japaneseName: "ゾーイ",
            englishName: "Zoe",
            price: 60,
            style: .personAfro,
            primary: Color(red: 0.6471, green: 0.4157, blue: 0.2431),
            secondary: Color(red: 0.2275, green: 0.6196, blue: 0.6196),
            accent: Color(red: 0.1647, green: 0.1059, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_taku",
            category: .people,
            japaneseName: "タク",
            englishName: "Taku",
            price: 40,
            style: .personSpiky,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.2275, green: 0.4314, blue: 0.6471),
            accent: Color(red: 0.0824, green: 0.0667, blue: 0.0510)
        ),
        HomeRewardCharacter(
            id: "kid_kai",
            category: .people,
            japaneseName: "カイ",
            englishName: "Kai",
            price: 50,
            style: .personSpiky,
            primary: Color(red: 0.8471, green: 0.6078, blue: 0.4235),
            secondary: Color(red: 0.2980, green: 0.6510, blue: 0.4196),
            accent: Color(red: 0.2902, green: 0.1843, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "kid_sara",
            category: .people,
            japaneseName: "サラ",
            englishName: "Sara",
            price: 60,
            style: .personBraids,
            primary: Color(red: 0.5412, green: 0.3529, blue: 0.2196),
            secondary: Color(red: 0.5451, green: 0.3608, blue: 0.7804),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_noa",
            category: .people,
            japaneseName: "ノア",
            englishName: "Noa",
            price: 50,
            style: .personBraids,
            primary: Color(red: 0.7765, green: 0.5412, blue: 0.3686),
            secondary: Color(red: 0.8784, green: 0.4157, blue: 0.6588),
            accent: Color(red: 0.1647, green: 0.1059, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_lily",
            category: .people,
            japaneseName: "リリー",
            englishName: "Lily",
            price: 50,
            style: .personWavy,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.7255, green: 0.5490, blue: 0.8784),
            accent: Color(red: 0.5451, green: 0.2275, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "kid_yuna",
            category: .people,
            japaneseName: "ユナ",
            englishName: "Yuna",
            price: 50,
            style: .personWavy,
            primary: Color(red: 0.8784, green: 0.6588, blue: 0.4706),
            secondary: Color(red: 0.9412, green: 0.5412, blue: 0.4235),
            accent: Color(red: 0.2902, green: 0.1843, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "kid_ren",
            category: .people,
            japaneseName: "レン",
            englishName: "Ren",
            price: 50,
            style: .personShort,
            primary: Color(red: 0.8471, green: 0.6078, blue: 0.4235),
            secondary: Color(red: 0.1647, green: 0.2902, blue: 0.4784),
            accent: Color(red: 0.2275, green: 0.4314, blue: 0.6471)
        ),
        HomeRewardCharacter(
            id: "kid_aoi",
            category: .people,
            japaneseName: "アオイ",
            englishName: "Aoi",
            price: 50,
            style: .personLong,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.4000, green: 0.7608, blue: 0.7608),
            accent: Color(red: 0.5451, green: 0.3608, blue: 0.7804)
        ),
        HomeRewardCharacter(
            id: "kid_sho",
            category: .people,
            japaneseName: "ショウ",
            englishName: "Sho",
            price: 40,
            style: .personBuzz,
            primary: Color(red: 0.5412, green: 0.3529, blue: 0.2196),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "kid_momo",
            category: .people,
            japaneseName: "モモ",
            englishName: "Momo",
            price: 50,
            style: .personPonytail,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.9490, green: 0.6510, blue: 0.7608),
            accent: Color(red: 0.8784, green: 0.4157, blue: 0.6588)
        ),
        HomeRewardCharacter(
            id: "kid_gen",
            category: .people,
            japaneseName: "ゲン",
            englishName: "Gen",
            price: 50,
            style: .personCurly,
            primary: Color(red: 0.8471, green: 0.6078, blue: 0.4235),
            secondary: Color(red: 0.2980, green: 0.6510, blue: 0.4196),
            accent: Color(red: 0.7529, green: 0.2235, blue: 0.1686)
        ),
        HomeRewardCharacter(
            id: "kid_eri",
            category: .people,
            japaneseName: "エリ",
            englishName: "Eri",
            price: 60,
            style: .personBun,
            primary: Color(red: 0.9686, green: 0.8431, blue: 0.7098),
            secondary: Color(red: 0.2275, green: 0.6196, blue: 0.6196),
            accent: Color(red: 0.7216, green: 0.7373, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "robot",
            category: .fantasy,
            japaneseName: "ロボット",
            englishName: "Robot",
            price: 60,
            style: .robot,
            primary: Color(red: 0.5490, green: 0.5961, blue: 0.6588),
            secondary: Color(red: 0.8392, green: 0.8784, blue: 0.9216),
            accent: Color(red: 0.8784, green: 0.3373, blue: 0.2314)
        ),
        HomeRewardCharacter(
            id: "ghost",
            category: .fantasy,
            japaneseName: "おばけ",
            englishName: "Ghost",
            price: 50,
            style: .ghost,
            primary: Color(red: 0.9294, green: 0.9294, blue: 0.9608),
            secondary: Color(red: 0.7882, green: 0.7882, blue: 0.8784),
            accent: Color(red: 0.2902, green: 0.2902, blue: 0.4000)
        ),
        HomeRewardCharacter(
            id: "star",
            category: .fantasy,
            japaneseName: "おほしさま",
            englishName: "Star",
            price: 50,
            style: .star,
            primary: Color(red: 0.9608, green: 0.7843, blue: 0.2588),
            secondary: Color(red: 1.0000, green: 0.9098, blue: 0.6196),
            accent: Color(red: 0.8784, green: 0.5804, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "unicorn",
            category: .fantasy,
            japaneseName: "ユニコーン",
            englishName: "Unicorn",
            price: 70,
            style: .unicorn,
            primary: Color(red: 0.9569, green: 0.8627, blue: 0.9373),
            secondary: Color(red: 0.7882, green: 0.6510, blue: 0.8784),
            accent: Color(red: 0.9490, green: 0.6510, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "dragon",
            category: .fantasy,
            japaneseName: "ドラゴン",
            englishName: "Dragon",
            price: 70,
            style: .dragon,
            primary: Color(red: 0.2980, green: 0.6510, blue: 0.4196),
            secondary: Color(red: 0.7216, green: 0.9020, blue: 0.6196),
            accent: Color(red: 0.8784, green: 0.3373, blue: 0.2314)
        ),
        HomeRewardCharacter(
            id: "police",
            category: .vehicle,
            japaneseName: "パトカー",
            englishName: "Police Car",
            price: 50,
            style: .car,
            primary: Color(red: 0.1686, green: 0.2000, blue: 0.2510),
            secondary: Color(red: 0.9294, green: 0.9373, blue: 0.9490),
            accent: Color(red: 0.2275, green: 0.4314, blue: 0.6471)
        ),
        HomeRewardCharacter(
            id: "ambulance",
            category: .vehicle,
            japaneseName: "きゅうきゅうしゃ",
            englishName: "Ambulance",
            price: 60,
            style: .bus,
            primary: Color(red: 0.9490, green: 0.9569, blue: 0.9686),
            secondary: Color(red: 1.0000, green: 0.8392, blue: 0.8196),
            accent: Color(red: 0.8588, green: 0.1608, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "excavator",
            category: .vehicle,
            japaneseName: "ショベルカー",
            englishName: "Excavator",
            price: 60,
            style: .excavator,
            primary: Color(red: 0.9490, green: 0.6902, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.5412),
            accent: Color(red: 0.2275, green: 0.2667, blue: 0.3255)
        ),
        HomeRewardCharacter(
            id: "crane",
            category: .vehicle,
            japaneseName: "クレーンしゃ",
            englishName: "Crane Truck",
            price: 70,
            style: .crane,
            primary: Color(red: 0.8784, green: 0.5333, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6980),
            accent: Color(red: 0.2275, green: 0.2667, blue: 0.3255)
        ),
        HomeRewardCharacter(
            id: "dumptruck",
            category: .vehicle,
            japaneseName: "ダンプカー",
            englishName: "Dump Truck",
            price: 60,
            style: .dumpTruck,
            primary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6510),
            accent: Color(red: 0.2275, green: 0.2667, blue: 0.3255)
        ),
        HomeRewardCharacter(
            id: "mixer",
            category: .vehicle,
            japaneseName: "ミキサーしゃ",
            englishName: "Mixer Truck",
            price: 60,
            style: .dumpTruck,
            primary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            secondary: Color(red: 0.8118, green: 0.8784, blue: 0.9608),
            accent: Color(red: 0.1804, green: 0.2275, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "garbage",
            category: .vehicle,
            japaneseName: "ごみしゅうしゅうしゃ",
            englishName: "Garbage Truck",
            price: 60,
            style: .dumpTruck,
            primary: Color(red: 0.3098, green: 0.6275, blue: 0.4196),
            secondary: Color(red: 0.8039, green: 0.9216, blue: 0.8392),
            accent: Color(red: 0.1804, green: 0.2275, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "house",
            category: .building,
            japaneseName: "おうち",
            englishName: "House",
            price: 40,
            style: .house,
            primary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            secondary: Color(red: 1.0000, green: 0.9059, blue: 0.7608),
            accent: Color(red: 0.4784, green: 0.2902, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "school",
            category: .building,
            japaneseName: "がっこう",
            englishName: "School",
            price: 50,
            style: .school,
            primary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.9373, blue: 0.7608),
            accent: Color(red: 0.6196, green: 0.3529, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "shop",
            category: .building,
            japaneseName: "おみせ",
            englishName: "Shop",
            price: 50,
            style: .house,
            primary: Color(red: 0.3098, green: 0.6275, blue: 0.4196),
            secondary: Color(red: 0.9098, green: 0.9608, blue: 0.8392),
            accent: Color(red: 0.1804, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "castle",
            category: .building,
            japaneseName: "おしろ",
            englishName: "Castle",
            price: 70,
            style: .castle,
            primary: Color(red: 0.6039, green: 0.6510, blue: 0.7608),
            secondary: Color(red: 0.9294, green: 0.9373, blue: 0.9686),
            accent: Color(red: 0.7804, green: 0.2784, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "tower",
            category: .building,
            japaneseName: "タワー",
            englishName: "Tower",
            price: 60,
            style: .tower,
            primary: Color(red: 0.8784, green: 0.5333, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6980),
            accent: Color(red: 0.3569, green: 0.5255, blue: 0.7804)
        ),
        HomeRewardCharacter(
            id: "lipstick",
            category: .cosme,
            japaneseName: "くちべに",
            englishName: "Lipstick",
            price: 50,
            style: .lipstick,
            primary: Color(red: 0.7608, green: 0.2902, blue: 0.5412),
            secondary: Color(red: 0.2275, green: 0.2000, blue: 0.2510),
            accent: Color(red: 0.8784, green: 0.3373, blue: 0.2314)
        ),
        HomeRewardCharacter(
            id: "perfume",
            category: .cosme,
            japaneseName: "こうすい",
            englishName: "Perfume",
            price: 60,
            style: .perfume,
            primary: Color(red: 0.8784, green: 0.6510, blue: 0.7608),
            secondary: Color(red: 0.9490, green: 0.8784, blue: 0.9216),
            accent: Color(red: 0.7608, green: 0.2902, blue: 0.5412)
        ),
        HomeRewardCharacter(
            id: "compact",
            category: .cosme,
            japaneseName: "コンパクト",
            englishName: "Compact",
            price: 50,
            style: .compact,
            primary: Color(red: 0.8196, green: 0.4784, blue: 0.6510),
            secondary: Color(red: 0.9686, green: 0.8784, blue: 0.9333),
            accent: Color(red: 0.7608, green: 0.2902, blue: 0.5412)
        ),
        HomeRewardCharacter(
            id: "nailpolish",
            category: .cosme,
            japaneseName: "マニキュア",
            englishName: "Nail Polish",
            price: 50,
            style: .nailPolish,
            primary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            secondary: Color(red: 0.2275, green: 0.2000, blue: 0.2510),
            accent: Color(red: 0.9490, green: 0.6510, blue: 0.7373)
        ),
        HomeRewardCharacter(
            id: "octopus",
            category: .sea,
            japaneseName: "たこ",
            englishName: "Octopus",
            price: 50,
            style: .octopus,
            primary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            secondary: Color(red: 1.0000, green: 0.7608, blue: 0.6980),
            accent: Color(red: 0.4784, green: 0.1647, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "crab",
            category: .sea,
            japaneseName: "かに",
            englishName: "Crab",
            price: 50,
            style: .crab,
            primary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            secondary: Color(red: 1.0000, green: 0.7216, blue: 0.6510),
            accent: Color(red: 0.4784, green: 0.1216, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "fish",
            category: .sea,
            japaneseName: "さかな",
            englishName: "Fish",
            price: 40,
            style: .fish,
            primary: Color(red: 0.2275, green: 0.6196, blue: 0.8196),
            secondary: Color(red: 0.7412, green: 0.9216, blue: 1.0000),
            accent: Color(red: 0.1216, green: 0.3529, blue: 0.4784)
        ),
        HomeRewardCharacter(
            id: "dolphin",
            category: .sea,
            japaneseName: "いるか",
            englishName: "Dolphin",
            price: 60,
            style: .dolphin,
            primary: Color(red: 0.3569, green: 0.5608, blue: 0.7804),
            secondary: Color(red: 0.8627, green: 0.9216, blue: 1.0000),
            accent: Color(red: 0.1804, green: 0.2902, blue: 0.4314)
        ),
        HomeRewardCharacter(
            id: "shark",
            category: .sea,
            japaneseName: "さめ",
            englishName: "Shark",
            price: 60,
            style: .shark,
            primary: Color(red: 0.5608, green: 0.6275, blue: 0.6980),
            secondary: Color(red: 0.8784, green: 0.9098, blue: 0.9412),
            accent: Color(red: 0.2275, green: 0.2745, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "jellyfish",
            category: .sea,
            japaneseName: "くらげ",
            englishName: "Jellyfish",
            price: 60,
            style: .jellyfish,
            primary: Color(red: 0.8196, green: 0.4784, blue: 0.7608),
            secondary: Color(red: 0.9490, green: 0.8392, blue: 0.9412),
            accent: Color(red: 0.4784, green: 0.2275, blue: 0.4314)
        ),
        HomeRewardCharacter(
            id: "starfish",
            category: .sea,
            japaneseName: "ひとで",
            englishName: "Starfish",
            price: 50,
            style: .starfish,
            primary: Color(red: 0.9490, green: 0.6000, blue: 0.2902),
            secondary: Color(red: 1.0000, green: 0.8392, blue: 0.6510),
            accent: Color(red: 0.6196, green: 0.3529, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "strawberry",
            category: .food,
            japaneseName: "いちご",
            englishName: "Strawberry",
            price: 40,
            style: .strawberry,
            primary: Color(red: 0.8784, green: 0.1961, blue: 0.1804),
            secondary: Color(red: 0.3098, green: 0.6275, blue: 0.4196),
            accent: Color(red: 0.4784, green: 0.0706, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "cake",
            category: .food,
            japaneseName: "ケーキ",
            englishName: "Cake",
            price: 50,
            style: .cake,
            primary: Color(red: 0.9490, green: 0.6510, blue: 0.7608),
            secondary: Color(red: 1.0000, green: 0.9098, blue: 0.8392),
            accent: Color(red: 0.8196, green: 0.2902, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "icecream",
            category: .food,
            japaneseName: "アイス",
            englishName: "Ice Cream",
            price: 50,
            style: .iceCream,
            primary: Color(red: 0.9490, green: 0.7137, blue: 0.8392),
            secondary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            accent: Color(red: 0.7608, green: 0.2902, blue: 0.5412)
        ),
        HomeRewardCharacter(
            id: "donut",
            category: .food,
            japaneseName: "ドーナツ",
            englishName: "Donut",
            price: 50,
            style: .donut,
            primary: Color(red: 0.7608, green: 0.4706, blue: 0.2902),
            secondary: Color(red: 0.9686, green: 0.6902, blue: 0.7608),
            accent: Color(red: 0.8784, green: 0.2627, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "riceball",
            category: .food,
            japaneseName: "おにぎり",
            englishName: "Rice Ball",
            price: 40,
            style: .riceBall,
            primary: Color(red: 0.9686, green: 0.9569, blue: 0.9255),
            secondary: Color(red: 0.2275, green: 0.2471, blue: 0.2745),
            accent: Color(red: 0.8784, green: 0.5333, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "sushi",
            category: .food,
            japaneseName: "すし",
            englishName: "Sushi",
            price: 60,
            style: .sushi,
            primary: Color(red: 0.8784, green: 0.3961, blue: 0.2353),
            secondary: Color(red: 0.9686, green: 0.9490, blue: 0.9098),
            accent: Color(red: 0.8196, green: 0.2902, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "burger",
            category: .food,
            japaneseName: "ハンバーガー",
            englishName: "Hamburger",
            price: 60,
            style: .hamburger,
            primary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            secondary: Color(red: 0.4784, green: 0.6902, blue: 0.3098),
            accent: Color(red: 0.6196, green: 0.3529, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "soccer",
            category: .sports,
            japaneseName: "サッカー",
            englishName: "Soccer Ball",
            price: 40,
            style: .soccerBall,
            primary: Color(red: 0.9294, green: 0.9373, blue: 0.9490),
            secondary: Color(red: 0.9294, green: 0.9373, blue: 0.9490),
            accent: Color(red: 0.1686, green: 0.2000, blue: 0.2510)
        ),
        HomeRewardCharacter(
            id: "baseball",
            category: .sports,
            japaneseName: "やきゅう",
            englishName: "Baseball",
            price: 50,
            style: .baseball,
            primary: Color(red: 0.9490, green: 0.6902, blue: 0.1216),
            secondary: Color(red: 0.9686, green: 0.9569, blue: 0.9255),
            accent: Color(red: 0.8588, green: 0.1608, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "basketball",
            category: .sports,
            japaneseName: "バスケ",
            englishName: "Basketball",
            price: 50,
            style: .basketball,
            primary: Color(red: 0.8784, green: 0.4667, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8392, blue: 0.6980),
            accent: Color(red: 0.3529, green: 0.1804, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "tennis",
            category: .sports,
            japaneseName: "テニス",
            englishName: "Tennis",
            price: 50,
            style: .tennisBall,
            primary: Color(red: 0.7608, green: 0.8784, blue: 0.2902),
            secondary: Color(red: 0.9176, green: 0.9686, blue: 0.7608),
            accent: Color(red: 1.0000, green: 1.0000, blue: 1.0000)
        ),
        HomeRewardCharacter(
            id: "trophy",
            category: .sports,
            japaneseName: "トロフィー",
            englishName: "Trophy",
            price: 70,
            style: .trophy,
            primary: Color(red: 0.9490, green: 0.7529, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.9098, blue: 0.6196),
            accent: Color(red: 0.6196, green: 0.4196, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "eiffel",
            category: .landmark,
            japaneseName: "エッフェルとう",
            englishName: "Eiffel Tower",
            price: 60,
            style: .eiffel,
            primary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            secondary: Color(red: 0.4196, green: 0.3216, blue: 0.1882),
            accent: Color(red: 0.2275, green: 0.1804, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "tokyotower",
            category: .japan,
            japaneseName: "とうきょうタワー",
            englishName: "Tokyo Tower",
            price: 50,
            style: .tokyoTower,
            primary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.4784, green: 0.1216, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "liberty",
            category: .landmark,
            japaneseName: "じゆうのめがみ",
            englishName: "Statue of Liberty",
            price: 70,
            style: .liberty,
            primary: Color(red: 0.3569, green: 0.6588, blue: 0.5490),
            secondary: Color(red: 0.7804, green: 0.8784, blue: 0.8392),
            accent: Color(red: 0.8784, green: 0.6471, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "pyramid",
            category: .landmark,
            japaneseName: "ピラミッド",
            englishName: "Pyramid",
            price: 50,
            style: .pyramid,
            primary: Color(red: 0.8784, green: 0.7059, blue: 0.3608),
            secondary: Color(red: 0.9490, green: 0.8471, blue: 0.6196),
            accent: Color(red: 0.7804, green: 0.4784, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "pisa",
            category: .landmark,
            japaneseName: "ピサのしゃとう",
            englishName: "Tower of Pisa",
            price: 60,
            style: .pisa,
            primary: Color(red: 0.9294, green: 0.9020, blue: 0.8392),
            secondary: Color(red: 0.9686, green: 0.9490, blue: 0.9098),
            accent: Color(red: 0.6196, green: 0.5412, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "bigben",
            category: .landmark,
            japaneseName: "ビッグベン",
            englishName: "Big Ben",
            price: 60,
            style: .bigBen,
            primary: Color(red: 0.7804, green: 0.6392, blue: 0.4196),
            secondary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            accent: Color(red: 0.2275, green: 0.1804, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "tajmahal",
            category: .landmark,
            japaneseName: "タージマハル",
            englishName: "Taj Mahal",
            price: 70,
            style: .tajMahal,
            primary: Color(red: 0.9490, green: 0.9294, blue: 0.9020),
            secondary: Color(red: 0.8392, green: 0.8118, blue: 0.7608),
            accent: Color(red: 0.6196, green: 0.5412, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "fuji",
            category: .japan,
            japaneseName: "ふじさん",
            englishName: "Mt. Fuji",
            price: 50,
            style: .fuji,
            primary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            secondary: Color(red: 0.4784, green: 0.6902, blue: 0.3098),
            accent: Color(red: 0.1804, green: 0.2902, blue: 0.4314)
        ),
        HomeRewardCharacter(
            id: "torii",
            category: .japan,
            japaneseName: "とりい",
            englishName: "Torii Gate",
            price: 50,
            style: .torii,
            primary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.4784, green: 0.1216, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "moai",
            category: .landmark,
            japaneseName: "モアイ",
            englishName: "Moai",
            price: 60,
            style: .moai,
            primary: Color(red: 0.5490, green: 0.5490, blue: 0.5490),
            secondary: Color(red: 0.4196, green: 0.4196, blue: 0.4196),
            accent: Color(red: 0.2275, green: 0.2275, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "windmill",
            category: .landmark,
            japaneseName: "ふうしゃ",
            englishName: "Windmill",
            price: 50,
            style: .windmill,
            primary: Color(red: 0.7804, green: 0.4706, blue: 0.2902),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.4784, green: 0.2275, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "colosseum",
            category: .landmark,
            japaneseName: "コロッセオ",
            englishName: "Colosseum",
            price: 60,
            style: .colosseum,
            primary: Color(red: 0.8392, green: 0.7216, blue: 0.5490),
            secondary: Color(red: 0.9490, green: 0.9020, blue: 0.8118),
            accent: Color(red: 0.6196, green: 0.4824, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "greatwall",
            category: .landmark,
            japaneseName: "ばんりのちょうじょう",
            englishName: "Great Wall",
            price: 60,
            style: .greatWall,
            primary: Color(red: 0.7098, green: 0.6431, blue: 0.5490),
            secondary: Color(red: 0.4784, green: 0.6902, blue: 0.3098),
            accent: Color(red: 0.4196, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "operahouse",
            category: .landmark,
            japaneseName: "オペラハウス",
            englishName: "Opera House",
            price: 60,
            style: .operaHouse,
            primary: Color(red: 0.9686, green: 0.9686, blue: 0.9686),
            secondary: Color(red: 0.5608, green: 0.7490, blue: 0.8392),
            accent: Color(red: 0.6039, green: 0.6510, blue: 0.6980)
        ),
        HomeRewardCharacter(
            id: "stonehenge",
            category: .landmark,
            japaneseName: "ストーンヘンジ",
            englishName: "Stonehenge",
            price: 50,
            style: .stonehenge,
            primary: Color(red: 0.6196, green: 0.5922, blue: 0.5490),
            secondary: Color(red: 0.4784, green: 0.6902, blue: 0.3098),
            accent: Color(red: 0.4196, green: 0.3882, blue: 0.3451)
        ),
        HomeRewardCharacter(
            id: "christ",
            category: .landmark,
            japaneseName: "キリストぞう",
            englishName: "Christ the Redeemer",
            price: 70,
            style: .christRedeemer,
            primary: Color(red: 0.7804, green: 0.8000, blue: 0.8235),
            secondary: Color(red: 0.5608, green: 0.7490, blue: 0.8392),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "sagrada",
            category: .landmark,
            japaneseName: "サグラダファミリア",
            englishName: "Sagrada Familia",
            price: 70,
            style: .sagrada,
            primary: Color(red: 0.7804, green: 0.6392, blue: 0.4196),
            secondary: Color(red: 0.8784, green: 0.7882, blue: 0.6196),
            accent: Color(red: 0.5412, green: 0.4196, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "goldengate",
            category: .landmark,
            japaneseName: "きんもんきょう",
            englishName: "Golden Gate",
            price: 60,
            style: .goldenGate,
            primary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            secondary: Color(red: 0.6039, green: 0.7216, blue: 0.7804),
            accent: Color(red: 0.4784, green: 0.1647, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "towerbridge",
            category: .landmark,
            japaneseName: "タワーブリッジ",
            englishName: "Tower Bridge",
            price: 60,
            style: .towerBridge,
            primary: Color(red: 0.6039, green: 0.6510, blue: 0.6980),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.2902, green: 0.4824, blue: 0.6588)
        ),
        HomeRewardCharacter(
            id: "ferriswheel",
            category: .landmark,
            japaneseName: "かんらんしゃ",
            englishName: "Ferris Wheel",
            price: 50,
            style: .ferrisWheel,
            primary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            secondary: Color(red: 0.9490, green: 0.7529, blue: 0.2353),
            accent: Color(red: 0.2275, green: 0.2745, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "kinkaku",
            category: .japan,
            japaneseName: "きんかくじ",
            englishName: "Golden Pavilion",
            price: 60,
            style: .kinkaku,
            primary: Color(red: 0.8784, green: 0.7059, blue: 0.2353),
            secondary: Color(red: 0.7804, green: 0.6039, blue: 0.2353),
            accent: Color(red: 0.4784, green: 0.3529, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "sphinx",
            category: .landmark,
            japaneseName: "スフィンクス",
            englishName: "Sphinx",
            price: 60,
            style: .sphinx,
            primary: Color(red: 0.8784, green: 0.7059, blue: 0.3608),
            secondary: Color(red: 0.9490, green: 0.8471, blue: 0.6196),
            accent: Color(red: 0.6196, green: 0.4196, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "angkor",
            category: .landmark,
            japaneseName: "アンコールワット",
            englishName: "Angkor Wat",
            price: 70,
            style: .angkor,
            primary: Color(red: 0.6196, green: 0.5412, blue: 0.4196),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.4196, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "matterhorn",
            category: .landmark,
            japaneseName: "マッターホルン",
            englishName: "Matterhorn",
            price: 50,
            style: .matterhorn,
            primary: Color(red: 0.4784, green: 0.5412, blue: 0.6196),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.2902, green: 0.3529, blue: 0.4314)
        ),
        HomeRewardCharacter(
            id: "libertybell",
            category: .landmark,
            japaneseName: "じゆうのかね",
            englishName: "Liberty Bell",
            price: 60,
            style: .libertyBell,
            primary: Color(red: 0.7098, green: 0.5373, blue: 0.2902),
            secondary: Color(red: 0.5412, green: 0.4196, blue: 0.2275),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "whitehouse",
            category: .landmark,
            japaneseName: "ホワイトハウス",
            englishName: "White House",
            price: 60,
            style: .whiteHouse,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.8627, green: 0.8627, blue: 0.8627),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "notredame",
            category: .landmark,
            japaneseName: "ノートルダム",
            englishName: "Notre-Dame",
            price: 70,
            style: .notreDame,
            primary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            secondary: Color(red: 0.6588, green: 0.6039, blue: 0.4941),
            accent: Color(red: 0.4196, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "burj",
            category: .landmark,
            japaneseName: "ブルジュハリファ",
            englishName: "Burj Khalifa",
            price: 70,
            style: .burjKhalifa,
            primary: Color(red: 0.6039, green: 0.7216, blue: 0.7804),
            secondary: Color(red: 0.8392, green: 0.9176, blue: 0.9490),
            accent: Color(red: 0.3569, green: 0.4784, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "arc",
            category: .landmark,
            japaneseName: "がいせんもん",
            englishName: "Arc de Triomphe",
            price: 60,
            style: .archTriomphe,
            primary: Color(red: 0.8392, green: 0.7804, blue: 0.6588),
            secondary: Color(red: 0.9294, green: 0.9020, blue: 0.8392),
            accent: Color(red: 0.6196, green: 0.5412, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "skytree",
            category: .japan,
            japaneseName: "スカイツリー",
            englishName: "Tokyo Skytree",
            price: 60,
            style: .skytree,
            primary: Color(red: 0.5608, green: 0.6510, blue: 0.7804),
            secondary: Color(red: 0.8392, green: 0.8784, blue: 0.9216),
            accent: Color(red: 0.3569, green: 0.4196, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "himeji",
            category: .japan,
            japaneseName: "ひめじじょう",
            englishName: "Himeji Castle",
            price: 70,
            style: .japaneseCastle,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.2275, green: 0.2745, blue: 0.3373),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "osaka",
            category: .japan,
            japaneseName: "おおさかじょう",
            englishName: "Osaka Castle",
            price: 70,
            style: .japaneseCastle,
            primary: Color(red: 0.9098, green: 0.8941, blue: 0.8392),
            secondary: Color(red: 0.1804, green: 0.3529, blue: 0.2902),
            accent: Color(red: 0.7804, green: 0.6392, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "pagoda",
            category: .japan,
            japaneseName: "ごじゅうのとう",
            englishName: "Five-Story Pagoda",
            price: 60,
            style: .pagoda,
            primary: Color(red: 0.7098, green: 0.2824, blue: 0.1647),
            secondary: Color(red: 0.2902, green: 0.2275, blue: 0.1804),
            accent: Color(red: 0.8784, green: 0.7529, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "daibutsu",
            category: .japan,
            japaneseName: "だいぶつ",
            englishName: "Great Buddha",
            price: 70,
            style: .daibutsu,
            primary: Color(red: 0.4196, green: 0.5490, blue: 0.4784),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.2275, green: 0.2902, blue: 0.2588)
        ),
        HomeRewardCharacter(
            id: "gasshou",
            category: .japan,
            japaneseName: "しらかわごう",
            englishName: "Gassho House",
            price: 60,
            style: .gasshou,
            primary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.3608, green: 0.2627, blue: 0.1608)
        ),
        HomeRewardCharacter(
            id: "stbasil",
            category: .landmark,
            japaneseName: "せいワシリイだいせいどう",
            englishName: "St. Basil's",
            price: 70,
            style: .stBasil,
            primary: Color(red: 0.9098, green: 0.8784, blue: 0.8157),
            secondary: Color(red: 0.7804, green: 0.8000, blue: 0.8392),
            accent: Color(red: 0.6196, green: 0.5412, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "parthenon",
            category: .landmark,
            japaneseName: "パルテノンしんでん",
            englishName: "Parthenon",
            price: 70,
            style: .parthenon,
            primary: Color(red: 0.9294, green: 0.9020, blue: 0.8392),
            secondary: Color(red: 0.8392, green: 0.8118, blue: 0.7608),
            accent: Color(red: 0.6196, green: 0.5412, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "machupicchu",
            category: .landmark,
            japaneseName: "マチュピチュ",
            englishName: "Machu Picchu",
            price: 70,
            style: .machuPicchu,
            primary: Color(red: 0.3098, green: 0.6196, blue: 0.3529),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.5412, green: 0.6510, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "mosque",
            category: .landmark,
            japaneseName: "モスク",
            englishName: "Mosque",
            price: 60,
            style: .mosque,
            primary: Color(red: 0.8784, green: 0.8392, blue: 0.7608),
            secondary: Color(red: 0.9490, green: 0.9176, blue: 0.8392),
            accent: Color(red: 0.7804, green: 0.6392, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "montsaintmichel",
            category: .landmark,
            japaneseName: "モンサンミッシェル",
            englishName: "Mont-St-Michel",
            price: 70,
            style: .montStMichel,
            primary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            secondary: Color(red: 0.8784, green: 0.8392, blue: 0.7608),
            accent: Color(red: 0.6039, green: 0.6510, blue: 0.6980)
        ),
        HomeRewardCharacter(
            id: "capitol",
            category: .landmark,
            japaneseName: "こっかいぎじどう",
            englishName: "Capitol",
            price: 60,
            style: .capitol,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.8627, green: 0.8627, blue: 0.8627),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "petra",
            category: .landmark,
            japaneseName: "ペトラ",
            englishName: "Petra",
            price: 70,
            style: .petra,
            primary: Color(red: 0.8392, green: 0.6039, blue: 0.4196),
            secondary: Color(red: 0.8784, green: 0.7216, blue: 0.5804),
            accent: Color(red: 0.5412, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "ginkaku",
            category: .japan,
            japaneseName: "ぎんかくじ",
            englishName: "Silver Pavilion",
            price: 60,
            style: .kinkaku,
            primary: Color(red: 0.6039, green: 0.6275, blue: 0.6510),
            secondary: Color(red: 0.4784, green: 0.5020, blue: 0.5373),
            accent: Color(red: 0.2902, green: 0.3098, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "nagoya",
            category: .japan,
            japaneseName: "なごやじょう",
            englishName: "Nagoya Castle",
            price: 70,
            style: .japaneseCastle,
            primary: Color(red: 0.9098, green: 0.8941, blue: 0.8392),
            secondary: Color(red: 0.2275, green: 0.2745, blue: 0.3373),
            accent: Color(red: 0.7804, green: 0.6392, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "itsukushima",
            category: .japan,
            japaneseName: "いつくしまじんじゃ",
            englishName: "Itsukushima",
            price: 60,
            style: .torii,
            primary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            secondary: Color(red: 0.5608, green: 0.7490, blue: 0.8392),
            accent: Color(red: 0.4784, green: 0.1216, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "kiyomizu",
            category: .japan,
            japaneseName: "きよみずでら",
            englishName: "Kiyomizu-dera",
            price: 60,
            style: .kiyomizu,
            primary: Color(red: 0.8784, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.6196, green: 0.3529, blue: 0.2275),
            accent: Color(red: 0.5412, green: 0.4196, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "tokyostation",
            category: .japan,
            japaneseName: "とうきょうえき",
            englishName: "Tokyo Station",
            price: 60,
            style: .tokyoStation,
            primary: Color(red: 0.6275, green: 0.3216, blue: 0.1765),
            secondary: Color(red: 0.4784, green: 0.5490, blue: 0.5412),
            accent: Color(red: 0.8784, green: 0.8392, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "todaiji",
            category: .japan,
            japaneseName: "とうだいじ",
            englishName: "Todai-ji",
            price: 70,
            style: .templeHall,
            primary: Color(red: 0.6196, green: 0.3529, blue: 0.2275),
            secondary: Color(red: 0.3529, green: 0.4196, blue: 0.3529),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "duomo",
            category: .landmark,
            japaneseName: "ドゥオモ",
            englishName: "Duomo",
            price: 70,
            style: .duomo,
            primary: Color(red: 0.9294, green: 0.9020, blue: 0.8392),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.7608, green: 0.3333, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "neuschwanstein",
            category: .landmark,
            japaneseName: "ノイシュバンシュタイン",
            englishName: "Neuschwanstein",
            price: 70,
            style: .euroCastle,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.7804, green: 0.8392, blue: 0.8784),
            accent: Color(red: 0.3569, green: 0.4784, blue: 0.6196)
        ),
        HomeRewardCharacter(
            id: "mayan",
            category: .landmark,
            japaneseName: "マヤピラミッド",
            englishName: "Mayan Pyramid",
            price: 60,
            style: .mayanPyramid,
            primary: Color(red: 0.6588, green: 0.6039, blue: 0.4941),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.4196, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "gateway",
            category: .landmark,
            japaneseName: "インドもん",
            englishName: "Gateway of India",
            price: 60,
            style: .archTriomphe,
            primary: Color(red: 0.7804, green: 0.6392, blue: 0.4196),
            secondary: Color(red: 0.8784, green: 0.7882, blue: 0.6196),
            accent: Color(red: 0.5412, green: 0.4196, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "harukas",
            category: .japan,
            japaneseName: "あべのハルカス",
            englishName: "Abeno Harukas",
            price: 60,
            style: .skyscraper,
            primary: Color(red: 0.6039, green: 0.7216, blue: 0.7804),
            secondary: Color(red: 0.7804, green: 0.8627, blue: 0.9098),
            accent: Color(red: 0.3569, green: 0.4784, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "goryokaku",
            category: .japan,
            japaneseName: "ごりょうかく",
            englishName: "Goryokaku",
            price: 60,
            style: .starFort,
            primary: Color(red: 0.3725, green: 0.6275, blue: 0.4196),
            secondary: Color(red: 0.5412, green: 0.7804, blue: 0.4784),
            accent: Color(red: 0.2275, green: 0.4196, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "okayama",
            category: .japan,
            japaneseName: "おかやまじょう",
            englishName: "Okayama Castle",
            price: 70,
            style: .japaneseCastle,
            primary: Color(red: 0.2275, green: 0.2471, blue: 0.2745),
            secondary: Color(red: 0.1216, green: 0.1373, blue: 0.1608),
            accent: Color(red: 0.7804, green: 0.6392, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "tsutenkaku",
            category: .japan,
            japaneseName: "つうてんかく",
            englishName: "Tsutenkaku",
            price: 50,
            style: .tower,
            primary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6510),
            accent: Color(red: 0.7608, green: 0.3333, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "guitar",
            category: .instruments,
            japaneseName: "ギター",
            englishName: "Guitar",
            price: 50,
            style: .guitar,
            primary: Color(red: 0.7608, green: 0.4706, blue: 0.2902),
            secondary: Color(red: 0.9490, green: 0.8392, blue: 0.6510),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "piano",
            category: .instruments,
            japaneseName: "ピアノ",
            englishName: "Piano",
            price: 60,
            style: .piano,
            primary: Color(red: 0.1686, green: 0.1686, blue: 0.1882),
            secondary: Color(red: 0.7804, green: 0.6392, blue: 0.4196),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "drum",
            category: .instruments,
            japaneseName: "たいこ",
            englishName: "Drum",
            price: 50,
            style: .drum,
            primary: Color(red: 0.8196, green: 0.2902, blue: 0.1804),
            secondary: Color(red: 0.9490, green: 0.9098, blue: 0.8392),
            accent: Color(red: 0.4784, green: 0.1647, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "trumpet",
            category: .instruments,
            japaneseName: "トランペット",
            englishName: "Trumpet",
            price: 60,
            style: .trumpet,
            primary: Color(red: 0.8784, green: 0.7059, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.9098, blue: 0.6196),
            accent: Color(red: 0.6196, green: 0.4196, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "violin",
            category: .instruments,
            japaneseName: "バイオリン",
            englishName: "Violin",
            price: 60,
            style: .violin,
            primary: Color(red: 0.6196, green: 0.3529, blue: 0.1804),
            secondary: Color(red: 0.8784, green: 0.7882, blue: 0.6196),
            accent: Color(red: 0.2275, green: 0.1647, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "butterfly",
            category: .insect,
            japaneseName: "ちょうちょ",
            englishName: "Butterfly",
            price: 50,
            style: .butterfly,
            primary: Color(red: 0.8784, green: 0.4157, blue: 0.6588),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.4784, green: 0.1647, blue: 0.3529)
        ),
        HomeRewardCharacter(
            id: "beetle",
            category: .insect,
            japaneseName: "かぶとむし",
            englishName: "Beetle",
            price: 50,
            style: .beetle,
            primary: Color(red: 0.3608, green: 0.2275, blue: 0.1020),
            secondary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            accent: Color(red: 0.1647, green: 0.1020, blue: 0.0392)
        ),
        HomeRewardCharacter(
            id: "ladybug",
            category: .insect,
            japaneseName: "てんとうむし",
            englishName: "Ladybug",
            price: 40,
            style: .ladybug,
            primary: Color(red: 0.8784, green: 0.1961, blue: 0.1804),
            secondary: Color(red: 0.2275, green: 0.1647, blue: 0.1647),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "bee",
            category: .insect,
            japaneseName: "はち",
            englishName: "Bee",
            price: 50,
            style: .bee,
            primary: Color(red: 0.9490, green: 0.7529, blue: 0.2353),
            secondary: Color(red: 0.2275, green: 0.1882, blue: 0.1490),
            accent: Color(red: 0.1647, green: 0.1255, blue: 0.0941)
        ),
        HomeRewardCharacter(
            id: "ant",
            category: .insect,
            japaneseName: "あり",
            englishName: "Ant",
            price: 40,
            style: .ant,
            primary: Color(red: 0.4784, green: 0.2627, blue: 0.1608),
            secondary: Color(red: 0.6196, green: 0.3529, blue: 0.2275),
            accent: Color(red: 0.2275, green: 0.1255, blue: 0.0941)
        ),
        HomeRewardCharacter(
            id: "trex",
            category: .dinosaur,
            japaneseName: "ティラノサウルス",
            englishName: "T-Rex",
            price: 60,
            style: .trex,
            primary: Color(red: 0.3725, green: 0.6275, blue: 0.4196),
            secondary: Color(red: 0.5412, green: 0.7804, blue: 0.4784),
            accent: Color(red: 0.2275, green: 0.4196, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "triceratops",
            category: .dinosaur,
            japaneseName: "トリケラトプス",
            englishName: "Triceratops",
            price: 60,
            style: .triceratops,
            primary: Color(red: 0.4784, green: 0.6275, blue: 0.7804),
            secondary: Color(red: 0.7804, green: 0.8627, blue: 0.9098),
            accent: Color(red: 0.2275, green: 0.3529, blue: 0.4784)
        ),
        HomeRewardCharacter(
            id: "stegosaurus",
            category: .dinosaur,
            japaneseName: "ステゴサウルス",
            englishName: "Stegosaurus",
            price: 60,
            style: .stegosaurus,
            primary: Color(red: 0.6196, green: 0.4824, blue: 0.7804),
            secondary: Color(red: 0.7804, green: 0.6510, blue: 0.8784),
            accent: Color(red: 0.3529, green: 0.2275, blue: 0.4784)
        ),
        HomeRewardCharacter(
            id: "brachiosaurus",
            category: .dinosaur,
            japaneseName: "ブラキオサウルス",
            englishName: "Brachiosaurus",
            price: 60,
            style: .brachiosaurus,
            primary: Color(red: 0.3725, green: 0.6275, blue: 0.6275),
            secondary: Color(red: 0.5412, green: 0.7804, blue: 0.7804),
            accent: Color(red: 0.2275, green: 0.4196, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "pteranodon",
            category: .dinosaur,
            japaneseName: "プテラノドン",
            englishName: "Pteranodon",
            price: 60,
            style: .pteranodon,
            primary: Color(red: 0.8784, green: 0.5333, blue: 0.2353),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.6196, green: 0.3529, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "astronaut",
            category: .space,
            japaneseName: "うちゅうひこうし",
            englishName: "Astronaut",
            price: 60,
            style: .astronaut,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            accent: Color(red: 0.2275, green: 0.2745, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "ufo",
            category: .space,
            japaneseName: "ユーフォー",
            englishName: "UFO",
            price: 50,
            style: .ufo,
            primary: Color(red: 0.5608, green: 0.6275, blue: 0.6980),
            secondary: Color(red: 0.6039, green: 0.8784, blue: 0.7804),
            accent: Color(red: 0.2275, green: 0.2745, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "saturn",
            category: .space,
            japaneseName: "どせい",
            englishName: "Saturn",
            price: 60,
            style: .saturn,
            primary: Color(red: 0.8784, green: 0.7059, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.9098, blue: 0.6196),
            accent: Color(red: 0.7804, green: 0.6039, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "moon",
            category: .space,
            japaneseName: "つき",
            englishName: "Moon",
            price: 40,
            style: .moon,
            primary: Color(red: 0.8784, green: 0.8784, blue: 0.9098),
            secondary: Color(red: 0.7804, green: 0.7804, blue: 0.8157),
            accent: Color(red: 0.6039, green: 0.6275, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "alien",
            category: .space,
            japaneseName: "うちゅうじん",
            englishName: "Alien",
            price: 50,
            style: .alien,
            primary: Color(red: 0.4784, green: 0.7804, blue: 0.4784),
            secondary: Color(red: 0.3725, green: 0.6275, blue: 0.4196),
            accent: Color(red: 0.1647, green: 0.2902, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "spacerocket",
            category: .space,
            japaneseName: "ロケット",
            englishName: "Rocket",
            price: 50,
            style: .rocket,
            primary: Color(red: 0.7804, green: 0.2980, blue: 0.7216),
            secondary: Color(red: 0.9804, green: 0.9020, blue: 1.0000),
            accent: Color(red: 0.9608, green: 0.5490, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "velociraptor",
            category: .dinosaur,
            japaneseName: "ヴェロキラプトル",
            englishName: "Velociraptor",
            price: 60,
            style: .velociraptor,
            primary: Color(red: 0.7804, green: 0.4784, blue: 0.2353),
            secondary: Color(red: 0.8784, green: 0.6588, blue: 0.4196),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "ankylosaurus",
            category: .dinosaur,
            japaneseName: "アンキロサウルス",
            englishName: "Ankylosaurus",
            price: 60,
            style: .ankylosaurus,
            primary: Color(red: 0.4784, green: 0.5490, blue: 0.3529),
            secondary: Color(red: 0.6510, green: 0.7216, blue: 0.4784),
            accent: Color(red: 0.2902, green: 0.3529, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "spinosaurus",
            category: .dinosaur,
            japaneseName: "スピノサウルス",
            englishName: "Spinosaurus",
            price: 70,
            style: .spinosaurus,
            primary: Color(red: 0.3529, green: 0.4784, blue: 0.6275),
            secondary: Color(red: 0.7804, green: 0.4784, blue: 0.2902),
            accent: Color(red: 0.1647, green: 0.2902, blue: 0.4157)
        ),
        HomeRewardCharacter(
            id: "parasaurolophus",
            category: .dinosaur,
            japaneseName: "パラサウロロフス",
            englishName: "Parasaurolophus",
            price: 60,
            style: .parasaurolophus,
            primary: Color(red: 0.3725, green: 0.6275, blue: 0.6275),
            secondary: Color(red: 0.7804, green: 0.4784, blue: 0.2902),
            accent: Color(red: 0.2275, green: 0.4196, blue: 0.4196)
        ),
        HomeRewardCharacter(
            id: "plesiosaurus",
            category: .dinosaur,
            japaneseName: "くびながりゅう",
            englishName: "Plesiosaurus",
            price: 60,
            style: .plesiosaurus,
            primary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            secondary: Color(red: 0.7804, green: 0.8784, blue: 1.0000),
            accent: Color(red: 0.1804, green: 0.2902, blue: 0.4314)
        ),
        HomeRewardCharacter(
            id: "dinoegg",
            category: .dinosaur,
            japaneseName: "きょうりゅうのたまご",
            englishName: "Dino Egg",
            price: 40,
            style: .dinoEgg,
            primary: Color(red: 0.9490, green: 0.9098, blue: 0.8392),
            secondary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            accent: Color(red: 0.7804, green: 0.4784, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "alpaca",
            category: .animal,
            japaneseName: "アルパカ",
            englishName: "Alpaca",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9059, green: 0.8392, blue: 0.7451),
            secondary: Color(red: 0.9843, green: 0.9529, blue: 0.9020),
            accent: Color(red: 0.6039, green: 0.4824, blue: 0.3412)
        ),
        HomeRewardCharacter(
            id: "hippo",
            category: .animal,
            japaneseName: "かば",
            englishName: "Hippo",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7098, green: 0.5451, blue: 0.7529),
            secondary: Color(red: 0.9098, green: 0.8392, blue: 0.9412),
            accent: Color(red: 0.4314, green: 0.2980, blue: 0.4902)
        ),
        HomeRewardCharacter(
            id: "hedgehog",
            category: .animal,
            japaneseName: "はりねずみ",
            englishName: "Hedgehog",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7255, green: 0.5412, blue: 0.3686),
            secondary: Color(red: 0.9529, green: 0.8863, blue: 0.7961),
            accent: Color(red: 0.3686, green: 0.2745, blue: 0.1882)
        ),
        HomeRewardCharacter(
            id: "sloth",
            category: .animal,
            japaneseName: "なまけもの",
            englishName: "Sloth",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7216, green: 0.6627, blue: 0.5490),
            secondary: Color(red: 0.9294, green: 0.8980, blue: 0.8275),
            accent: Color(red: 0.4196, green: 0.3569, blue: 0.2706)
        ),
        HomeRewardCharacter(
            id: "chick",
            category: .animal,
            japaneseName: "ひよこ",
            englishName: "Chick",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9686, green: 0.8392, blue: 0.3529),
            secondary: Color(red: 1.0000, green: 0.9412, blue: 0.7216),
            accent: Color(red: 0.8980, green: 0.6039, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "tanuki",
            category: .animal,
            japaneseName: "たぬき",
            englishName: "Tanuki",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.6078, green: 0.4824, blue: 0.3529),
            secondary: Color(red: 0.9294, green: 0.8784, blue: 0.8078),
            accent: Color(red: 0.2902, green: 0.2275, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "seal",
            category: .sea,
            japaneseName: "あざらし",
            englishName: "Seal",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.6863, green: 0.7647, blue: 0.8392),
            secondary: Color(red: 0.9176, green: 0.9490, blue: 0.9725),
            accent: Color(red: 0.2980, green: 0.3843, blue: 0.4588)
        ),
        HomeRewardCharacter(
            id: "pufferfish",
            category: .sea,
            japaneseName: "ふぐ",
            englishName: "Pufferfish",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.6627, green: 0.8118, blue: 0.5569),
            secondary: Color(red: 0.9176, green: 0.9647, blue: 0.8745),
            accent: Color(red: 0.3686, green: 0.4784, blue: 0.2706)
        ),
        HomeRewardCharacter(
            id: "apple",
            category: .food,
            japaneseName: "りんご",
            englishName: "Apple",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.8784, green: 0.3216, blue: 0.2941),
            secondary: Color(red: 0.9647, green: 0.7176, blue: 0.6902),
            accent: Color(red: 0.3059, green: 0.4784, blue: 0.2078)
        ),
        HomeRewardCharacter(
            id: "watermelon",
            category: .food,
            japaneseName: "すいか",
            englishName: "Watermelon",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.3647, green: 0.6824, blue: 0.3569),
            secondary: Color(red: 0.8863, green: 0.3608, blue: 0.4157),
            accent: Color(red: 0.1804, green: 0.4196, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "pudding",
            category: .food,
            japaneseName: "プリン",
            englishName: "Pudding",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.7804, blue: 0.4000),
            secondary: Color(red: 0.9843, green: 0.9098, blue: 0.7216),
            accent: Color(red: 0.5412, green: 0.3529, blue: 0.1686)
        ),
        HomeRewardCharacter(
            id: "ya_hina",
            category: .people,
            japaneseName: "ヒナ",
            englishName: "Hina",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.6235, green: 0.7843, blue: 0.9098),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "ya_marcus",
            category: .people,
            japaneseName: "マーカス",
            englishName: "Marcus",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.4784, green: 0.2902, blue: 0.1804),
            secondary: Color(red: 0.8784, green: 0.4667, blue: 0.2353),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0314)
        ),
        HomeRewardCharacter(
            id: "ya_emily",
            category: .people,
            japaneseName: "エミリー",
            englishName: "Emily",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.5608, green: 0.7490, blue: 0.4784),
            accent: Color(red: 0.8784, green: 0.7216, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "ya_diego",
            category: .people,
            japaneseName: "ディエゴ",
            englishName: "Diego",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7843, green: 0.5373, blue: 0.3608),
            secondary: Color(red: 0.2275, green: 0.2471, blue: 0.2745),
            accent: Color(red: 0.2902, green: 0.1843, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "ya_aisha",
            category: .people,
            japaneseName: "アイシャ",
            englishName: "Aisha",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7098, green: 0.5098, blue: 0.3529),
            secondary: Color(red: 0.1804, green: 0.5490, blue: 0.5490),
            accent: Color(red: 0.1804, green: 0.5490, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "ya_jamal",
            category: .people,
            japaneseName: "ジャマル",
            englishName: "Jamal",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.4314, green: 0.2627, blue: 0.1490),
            secondary: Color(red: 0.8784, green: 0.6902, blue: 0.2510),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0314)
        ),
        HomeRewardCharacter(
            id: "ya_zara",
            category: .people,
            japaneseName: "ザラ",
            englishName: "Zara",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.4784, green: 0.2902, blue: 0.1804),
            secondary: Color(red: 0.8784, green: 0.4392, blue: 0.3529),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0314)
        ),
        HomeRewardCharacter(
            id: "ya_yuki",
            category: .people,
            japaneseName: "ユキ",
            englishName: "Yuki",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.9490, green: 0.8235, blue: 0.2980),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "ya_haruto",
            category: .people,
            japaneseName: "ハルト",
            englishName: "Haruto",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9098, green: 0.7529, blue: 0.6275),
            secondary: Color(red: 0.1647, green: 0.2275, blue: 0.3608),
            accent: Color(red: 0.2275, green: 0.1569, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "ya_sofia",
            category: .people,
            japaneseName: "ソフィア",
            englishName: "Sofia",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7843, green: 0.5373, blue: 0.3608),
            secondary: Color(red: 0.7608, green: 0.3333, blue: 0.1804),
            accent: Color(red: 0.2275, green: 0.1569, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "ya_mateo",
            category: .people,
            japaneseName: "マテオ",
            englishName: "Mateo",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7843, green: 0.5373, blue: 0.3608),
            secondary: Color(red: 0.3098, green: 0.6275, blue: 0.4196),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "ya_liam",
            category: .people,
            japaneseName: "リアム",
            englishName: "Liam",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9686, green: 0.8431, blue: 0.7098),
            secondary: Color(red: 0.6039, green: 0.7843, blue: 0.9098),
            accent: Color(red: 0.6196, green: 0.4824, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "ya_chloe",
            category: .people,
            japaneseName: "クロエ",
            englishName: "Chloe",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9882, green: 0.8784, blue: 0.7608),
            secondary: Color(red: 0.2275, green: 0.2471, blue: 0.2745),
            accent: Color(red: 0.7804, green: 0.8000, blue: 0.8235)
        ),
        HomeRewardCharacter(
            id: "ya_priya",
            category: .people,
            japaneseName: "プリヤ",
            englishName: "Priya",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7098, green: 0.5098, blue: 0.3529),
            secondary: Color(red: 0.1804, green: 0.6196, blue: 0.4196),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0314)
        ),
        HomeRewardCharacter(
            id: "ya_arjun",
            category: .people,
            japaneseName: "アルジュン",
            englishName: "Arjun",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7098, green: 0.5098, blue: 0.3529),
            secondary: Color(red: 0.4784, green: 0.1647, blue: 0.1804),
            accent: Color(red: 0.1020, green: 0.0706, blue: 0.0314)
        ),
        HomeRewardCharacter(
            id: "ya_amir",
            category: .people,
            japaneseName: "アミール",
            englishName: "Amir",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7608, green: 0.6039, blue: 0.4196),
            secondary: Color(red: 0.4196, green: 0.4784, blue: 0.2275),
            accent: Color(red: 0.1647, green: 0.1176, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "ya_layla",
            category: .people,
            japaneseName: "ライラ",
            englishName: "Layla",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.7608, green: 0.6039, blue: 0.4196),
            secondary: Color(red: 0.1804, green: 0.5490, blue: 0.5490),
            accent: Color(red: 0.2275, green: 0.1569, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "ya_taro",
            category: .people,
            japaneseName: "タロウ",
            englishName: "Taro",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9098, green: 0.7529, blue: 0.6275),
            secondary: Color(red: 0.8196, green: 0.2902, blue: 0.1804),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "ya_sakura",
            category: .people,
            japaneseName: "サクラ",
            englishName: "Sakura",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.7882, blue: 0.6510),
            secondary: Color(red: 0.9686, green: 0.9490, blue: 0.9098),
            accent: Color(red: 0.1020, green: 0.0784, blue: 0.0627)
        ),
        HomeRewardCharacter(
            id: "ya_leon",
            category: .people,
            japaneseName: "レオン",
            englishName: "Leon",
            price: 40,
            style: .imageAsset,
            primary: Color(red: 0.9686, green: 0.8627, blue: 0.7608),
            secondary: Color(red: 0.2275, green: 0.4196, blue: 0.2902),
            accent: Color(red: 0.7843, green: 0.3529, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "alien_blob",
            category: .space,
            japaneseName: "ブロブ",
            englishName: "Blob",
            price: 50,
            style: .alienBlob,
            primary: Color(red: 0.4196, green: 0.7961, blue: 0.4667),
            secondary: Color(red: 0.7490, green: 0.9412, blue: 0.6510),
            accent: Color(red: 0.1804, green: 0.3529, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "alien_mitsume",
            category: .space,
            japaneseName: "ミツメ",
            englishName: "Mitsume",
            price: 50,
            style: .alienTriclops,
            primary: Color(red: 0.7255, green: 0.5490, blue: 0.8784),
            secondary: Color(red: 0.4784, green: 0.3529, blue: 0.6902),
            accent: Color(red: 0.1020, green: 0.1020, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "alien_ikar",
            category: .space,
            japaneseName: "イカル",
            englishName: "Ikar",
            price: 50,
            style: .alienSquid,
            primary: Color(red: 0.3569, green: 0.7843, blue: 0.8392),
            secondary: Color(red: 0.7804, green: 0.4784, blue: 0.8392),
            accent: Color(red: 0.1373, green: 0.1922, blue: 0.3098)
        ),
        HomeRewardCharacter(
            id: "alien_nyoro",
            category: .space,
            japaneseName: "ニョロ",
            englishName: "Nyoro",
            price: 50,
            style: .alienWorm,
            primary: Color(red: 0.4784, green: 0.7804, blue: 0.4784),
            secondary: Color(red: 0.7608, green: 0.9412, blue: 0.6510),
            accent: Color(red: 0.1804, green: 0.3529, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "alien_kino",
            category: .space,
            japaneseName: "キノ",
            englishName: "Kino",
            price: 50,
            style: .alienMushroom,
            primary: Color(red: 0.8784, green: 0.3373, blue: 0.2314),
            secondary: Color(red: 0.9490, green: 0.8706, blue: 0.7608),
            accent: Color(red: 1.0000, green: 0.9490, blue: 0.8784)
        ),
        HomeRewardCharacter(
            id: "alien_medama",
            category: .space,
            japaneseName: "メダマ",
            englishName: "Medama",
            price: 50,
            style: .alienBugeye,
            primary: Color(red: 0.4196, green: 0.7961, blue: 0.6902),
            secondary: Color(red: 0.2902, green: 0.6196, blue: 0.5255),
            accent: Color(red: 0.8784, green: 0.6471, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "alien_kirari",
            category: .space,
            japaneseName: "キラリ",
            englishName: "Kirari",
            price: 50,
            style: .alienCrystal,
            primary: Color(red: 0.5490, green: 0.6196, blue: 0.8784),
            secondary: Color(red: 0.7804, green: 0.8235, blue: 0.9686),
            accent: Color(red: 0.9490, green: 0.8235, blue: 0.2980)
        ),
        HomeRewardCharacter(
            id: "alien_hova",
            category: .space,
            japaneseName: "ホバ",
            englishName: "Hova",
            price: 50,
            style: .alienHover,
            primary: Color(red: 0.6039, green: 0.6510, blue: 0.6980),
            secondary: Color(red: 0.5608, green: 0.8392, blue: 0.8784),
            accent: Color(red: 0.3569, green: 0.8784, blue: 0.7804)
        ),
        HomeRewardCharacter(
            id: "et_nova",
            category: .space,
            japaneseName: "ノヴァ",
            englishName: "Nova",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.7255, green: 0.5490, blue: 0.8784),
            secondary: Color(red: 0.7804, green: 0.7804, blue: 0.8392),
            accent: Color(red: 0.1373, green: 0.1922, blue: 0.3098)
        ),
        HomeRewardCharacter(
            id: "et_zorp",
            category: .space,
            japaneseName: "ゾープ",
            englishName: "Zorp",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.5451, green: 0.8392, blue: 0.2902),
            secondary: Color(red: 0.7804, green: 0.9412, blue: 0.6275),
            accent: Color(red: 0.1804, green: 0.3529, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "et_korr",
            category: .space,
            japaneseName: "コール",
            englishName: "Korr",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.8784, green: 0.5333, blue: 0.2353),
            secondary: Color(red: 0.9490, green: 0.7569, blue: 0.3059),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "vox_robo",
            category: .fantasy,
            japaneseName: "ボクセルロボ",
            englishName: "Voxel Robo",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.2471, green: 0.7216, blue: 0.6902),
            secondary: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
            accent: Color(red: 0.9490, green: 0.7529, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "vox_neko",
            category: .animal,
            japaneseName: "キューブネコ",
            englishName: "Cube Cat",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.8784, green: 0.5333, blue: 0.2353),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6980),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "vox_knight",
            category: .fantasy,
            japaneseName: "ブロックきし",
            englishName: "Block Knight",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.6039, green: 0.6510, blue: 0.7608),
            secondary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            accent: Color(red: 0.7804, green: 0.8000, blue: 0.8235)
        ),
        HomeRewardCharacter(
            id: "vox_dragon",
            category: .fantasy,
            japaneseName: "ブロックりゅう",
            englishName: "Block Dragon",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.3725, green: 0.6275, blue: 0.4196),
            secondary: Color(red: 0.9490, green: 0.8235, blue: 0.2980),
            accent: Color(red: 0.2275, green: 0.4196, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "vox_inu",
            category: .animal,
            japaneseName: "ボクセルいぬ",
            englishName: "Voxel Dog",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.7608, green: 0.5294, blue: 0.2980),
            secondary: Color(red: 0.9804, green: 0.8784, blue: 0.7608),
            accent: Color(red: 0.3608, green: 0.2275, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "vox_panda",
            category: .animal,
            japaneseName: "ボクセルパンダ",
            englishName: "Voxel Panda",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.1686, green: 0.1882, blue: 0.2314),
            secondary: Color(red: 0.9608, green: 0.9608, blue: 0.9216),
            accent: Color(red: 0.3490, green: 0.6196, blue: 0.3608)
        ),
        HomeRewardCharacter(
            id: "vox_usagi",
            category: .animal,
            japaneseName: "ボクセルうさぎ",
            englishName: "Voxel Rabbit",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.9176, blue: 0.9412),
            secondary: Color(red: 1.0000, green: 0.9412, blue: 0.9804),
            accent: Color(red: 0.8784, green: 0.6510, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "vox_penguin",
            category: .animal,
            japaneseName: "ボクセルペンギン",
            englishName: "Voxel Penguin",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.1804, green: 0.2275, blue: 0.3373),
            secondary: Color(red: 0.9412, green: 0.9686, blue: 1.0000),
            accent: Color(red: 0.9608, green: 0.6196, blue: 0.1216)
        ),
        HomeRewardCharacter(
            id: "vox_kitsune",
            category: .animal,
            japaneseName: "ボクセルきつね",
            englishName: "Voxel Fox",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9216, green: 0.4314, blue: 0.1216),
            secondary: Color(red: 1.0000, green: 0.8784, blue: 0.6980),
            accent: Color(red: 0.4314, green: 0.1804, blue: 0.0784)
        ),
        HomeRewardCharacter(
            id: "vox_kuma",
            category: .animal,
            japaneseName: "ボクセルくま",
            englishName: "Voxel Bear",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.5412, green: 0.3529, blue: 0.2196),
            secondary: Color(red: 0.7804, green: 0.6392, blue: 0.4196),
            accent: Color(red: 0.2902, green: 0.1843, blue: 0.1020)
        ),
        HomeRewardCharacter(
            id: "vox_car",
            category: .vehicle,
            japaneseName: "ボクセルカー",
            englishName: "Voxel Car",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            secondary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            accent: Color(red: 0.1686, green: 0.2000, blue: 0.2510)
        ),
        HomeRewardCharacter(
            id: "vox_train",
            category: .vehicle,
            japaneseName: "ボクセルきかんしゃ",
            englishName: "Voxel Train",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.1804, green: 0.4784, blue: 0.2275),
            secondary: Color(red: 0.1686, green: 0.1686, blue: 0.1882),
            accent: Color(red: 0.8196, green: 0.2902, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "vox_rocket",
            category: .vehicle,
            japaneseName: "ボクセルロケット",
            englishName: "Voxel Rocket",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.8784, green: 0.2627, blue: 0.1804),
            accent: Color(red: 0.3569, green: 0.5255, blue: 0.7804)
        ),
        HomeRewardCharacter(
            id: "vox_ship",
            category: .vehicle,
            japaneseName: "ボクセルふね",
            englishName: "Voxel Ship",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.2275, green: 0.4196, blue: 0.7804),
            secondary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            accent: Color(red: 0.8784, green: 0.6471, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "vox_wizard",
            category: .fantasy,
            japaneseName: "ボクセルまほうつかい",
            englishName: "Voxel Wizard",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.4784, green: 0.2902, blue: 0.6902),
            secondary: Color(red: 0.8784, green: 0.6471, blue: 0.2353),
            accent: Color(red: 0.9490, green: 0.8784, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "vox_ninja",
            category: .fantasy,
            japaneseName: "ボクセルにんじゃ",
            englishName: "Voxel Ninja",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.1647, green: 0.2275, blue: 0.3608),
            secondary: Color(red: 0.1020, green: 0.1333, blue: 0.2196),
            accent: Color(red: 0.8784, green: 0.7882, blue: 0.6510)
        ),
        HomeRewardCharacter(
            id: "vox_astro",
            category: .space,
            japaneseName: "ボクセルうちゅうひこうし",
            englishName: "Voxel Astronaut",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9490, green: 0.9490, blue: 0.9490),
            secondary: Color(red: 0.3569, green: 0.5255, blue: 0.7804),
            accent: Color(red: 0.2275, green: 0.2745, blue: 0.3373)
        ),
        HomeRewardCharacter(
            id: "vox_ghost",
            category: .fantasy,
            japaneseName: "ボクセルおばけ",
            englishName: "Voxel Ghost",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9294, green: 0.9294, blue: 0.9608),
            secondary: Color(red: 0.7882, green: 0.7882, blue: 0.8784),
            accent: Color(red: 0.8784, green: 0.6471, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "vox_apple",
            category: .food,
            japaneseName: "ボクセルりんご",
            englishName: "Voxel Apple",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.8784, green: 0.1961, blue: 0.1804),
            secondary: Color(red: 0.3098, green: 0.6275, blue: 0.4196),
            accent: Color(red: 0.4784, green: 0.0706, blue: 0.0706)
        ),
        HomeRewardCharacter(
            id: "vox_cake",
            category: .food,
            japaneseName: "ボクセルケーキ",
            englishName: "Voxel Cake",
            price: 50,
            style: .imageAsset,
            primary: Color(red: 0.9686, green: 0.9490, blue: 0.9098),
            secondary: Color(red: 0.8784, green: 0.1961, blue: 0.1804),
            accent: Color(red: 0.9490, green: 0.6510, blue: 0.7608)
        ),
        HomeRewardCharacter(
            id: "mouse",
            category: .animal,
            japaneseName: "ねずみ",
            englishName: "Mouse",
            price: 40,
            style: .mouse,
            primary: Color(red: 0.7216, green: 0.7373, blue: 0.7686),
            secondary: Color(red: 0.9255, green: 0.9333, blue: 0.9490),
            accent: Color(red: 0.9098, green: 0.6078, blue: 0.6902)
        ),
        HomeRewardCharacter(
            id: "cow",
            category: .animal,
            japaneseName: "うし",
            englishName: "Cow",
            price: 50,
            style: .cow,
            primary: Color(red: 0.9490, green: 0.9412, blue: 0.9216),
            secondary: Color(red: 0.9569, green: 0.7137, blue: 0.6510),
            accent: Color(red: 0.2902, green: 0.2510, blue: 0.2196)
        ),
        HomeRewardCharacter(
            id: "horse",
            category: .animal,
            japaneseName: "うま",
            englishName: "Horse",
            price: 50,
            style: .horse,
            primary: Color(red: 0.7843, green: 0.5686, blue: 0.3686),
            secondary: Color(red: 0.9020, green: 0.7647, blue: 0.6039),
            accent: Color(red: 0.3569, green: 0.2275, blue: 0.1333)
        ),
        HomeRewardCharacter(
            id: "wolf",
            category: .animal,
            japaneseName: "オオカミ",
            englishName: "Wolf",
            price: 50,
            style: .wolf,
            primary: Color(red: 0.5490, green: 0.5922, blue: 0.6510),
            secondary: Color(red: 0.8431, green: 0.8627, blue: 0.8902),
            accent: Color(red: 0.2275, green: 0.2471, blue: 0.2902)
        ),
        HomeRewardCharacter(
            id: "kangaroo",
            category: .animal,
            japaneseName: "かんがるー",
            englishName: "Kangaroo",
            price: 50,
            style: .kangaroo,
            primary: Color(red: 0.7882, green: 0.5412, blue: 0.3686),
            secondary: Color(red: 0.9098, green: 0.7882, blue: 0.6588),
            accent: Color(red: 0.3569, green: 0.2275, blue: 0.1333)
        ),
        HomeRewardCharacter(
            id: "bat",
            category: .animal,
            japaneseName: "こうもり",
            englishName: "Bat",
            price: 40,
            style: .bat,
            primary: Color(red: 0.4196, green: 0.3686, blue: 0.4824),
            secondary: Color(red: 0.5804, green: 0.5255, blue: 0.6588),
            accent: Color(red: 0.9490, green: 0.8235, blue: 0.2980)
        ),
        HomeRewardCharacter(
            id: "goat",
            category: .animal,
            japaneseName: "やぎ",
            englishName: "Goat",
            price: 40,
            style: .goat,
            primary: Color(red: 0.9294, green: 0.9137, blue: 0.8863),
            secondary: Color(red: 0.8235, green: 0.7804, blue: 0.7059),
            accent: Color(red: 0.5412, green: 0.4784, blue: 0.3529)
        ),
        HomeRewardCharacter(
            id: "otter",
            category: .sea,
            japaneseName: "らっこ",
            englishName: "Otter",
            price: 50,
            style: .otter,
            primary: Color(red: 0.5412, green: 0.4157, blue: 0.3098),
            secondary: Color(red: 0.8510, green: 0.7647, blue: 0.6588),
            accent: Color(red: 0.2902, green: 0.2000, blue: 0.1412)
        ),
        HomeRewardCharacter(
            id: "orca",
            category: .sea,
            japaneseName: "しゃち",
            englishName: "Orca",
            price: 60,
            style: .orca,
            primary: Color(red: 0.1686, green: 0.1843, blue: 0.2118),
            secondary: Color(red: 0.9490, green: 0.9569, blue: 0.9686),
            accent: Color(red: 1.0000, green: 1.0000, blue: 1.0000)
        ),
        HomeRewardCharacter(
            id: "seahorse",
            category: .sea,
            japaneseName: "たつのおとしご",
            englishName: "Seahorse",
            price: 50,
            style: .seahorse,
            primary: Color(red: 0.9490, green: 0.6627, blue: 0.2353),
            secondary: Color(red: 0.9686, green: 0.7765, blue: 0.4196),
            accent: Color(red: 0.7882, green: 0.4549, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "shrimp",
            category: .sea,
            japaneseName: "えび",
            englishName: "Shrimp",
            price: 40,
            style: .shrimp,
            primary: Color(red: 0.9412, green: 0.5412, blue: 0.4196),
            secondary: Color(red: 0.9686, green: 0.7608, blue: 0.6588),
            accent: Color(red: 0.7882, green: 0.3294, blue: 0.1804)
        ),
        HomeRewardCharacter(
            id: "duck",
            category: .animal,
            japaneseName: "あひる",
            englishName: "Duck",
            price: 40,
            style: .duck,
            primary: Color(red: 0.9569, green: 0.8235, blue: 0.2980),
            secondary: Color(red: 0.9843, green: 0.9098, blue: 0.6039),
            accent: Color(red: 0.9490, green: 0.5686, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "bird",
            category: .animal,
            japaneseName: "とり",
            englishName: "Bird",
            price: 40,
            style: .bird,
            primary: Color(red: 0.4353, green: 0.7176, blue: 0.9098),
            secondary: Color(red: 0.8627, green: 0.9333, blue: 0.9843),
            accent: Color(red: 0.9490, green: 0.6627, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "flamingo",
            category: .animal,
            japaneseName: "フラミンゴ",
            englishName: "Flamingo",
            price: 60,
            style: .flamingo,
            primary: Color(red: 0.9490, green: 0.6000, blue: 0.7216),
            secondary: Color(red: 0.9686, green: 0.7608, blue: 0.8314),
            accent: Color(red: 0.1686, green: 0.1843, blue: 0.2118)
        ),
        HomeRewardCharacter(
            id: "parrot",
            category: .animal,
            japaneseName: "インコ",
            englishName: "Parrot",
            price: 50,
            style: .parrot,
            primary: Color(red: 0.2471, green: 0.6824, blue: 0.4196),
            secondary: Color(red: 0.9490, green: 0.8235, blue: 0.2980),
            accent: Color(red: 0.8784, green: 0.3255, blue: 0.2314)
        ),
        HomeRewardCharacter(
            id: "swan",
            category: .animal,
            japaneseName: "はくちょう",
            englishName: "Swan",
            price: 50,
            style: .swan,
            primary: Color(red: 0.9569, green: 0.9569, blue: 0.9490),
            secondary: Color(red: 0.8902, green: 0.9020, blue: 0.9255),
            accent: Color(red: 0.8784, green: 0.5137, blue: 0.2353)
        ),
        HomeRewardCharacter(
            id: "snail",
            category: .insect,
            japaneseName: "かたつむり",
            englishName: "Snail",
            price: 40,
            style: .snail,
            primary: Color(red: 0.7882, green: 0.6039, blue: 0.4196),
            secondary: Color(red: 0.9098, green: 0.8235, blue: 0.6902),
            accent: Color(red: 0.5412, green: 0.3529, blue: 0.2196)
        ),
        HomeRewardCharacter(
            id: "dragonfly",
            category: .insect,
            japaneseName: "とんぼ",
            englishName: "Dragonfly",
            price: 40,
            style: .dragonfly,
            primary: Color(red: 0.2471, green: 0.6588, blue: 0.7608),
            secondary: Color(red: 0.7490, green: 0.9020, blue: 0.9412),
            accent: Color(red: 0.1804, green: 0.4196, blue: 0.5490)
        ),
        HomeRewardCharacter(
            id: "banana",
            category: .food,
            japaneseName: "バナナ",
            englishName: "Banana",
            price: 40,
            style: .banana,
            primary: Color(red: 0.9569, green: 0.8235, blue: 0.2980),
            secondary: Color(red: 0.9843, green: 0.9098, blue: 0.6039),
            accent: Color(red: 0.5412, green: 0.4157, blue: 0.2275)
        ),
        HomeRewardCharacter(
            id: "taiyaki",
            category: .food,
            japaneseName: "たいやき",
            englishName: "Taiyaki",
            price: 50,
            style: .taiyaki,
            primary: Color(red: 0.8510, green: 0.6039, blue: 0.2980),
            secondary: Color(red: 0.9098, green: 0.7686, blue: 0.5412),
            accent: Color(red: 0.5412, green: 0.3529, blue: 0.1647)
        ),
        HomeRewardCharacter(
            id: "cookie",
            category: .food,
            japaneseName: "クッキー",
            englishName: "Cookie",
            price: 40,
            style: .cookie,
            primary: Color(red: 0.8510, green: 0.6588, blue: 0.4196),
            secondary: Color(red: 0.9098, green: 0.7882, blue: 0.6039),
            accent: Color(red: 0.4196, green: 0.2902, blue: 0.1647)
        )
    ]
    // CATALOG-GENERATED-END
}

private enum RewardPickerTab: Hashable {
    case buddy
    case background
}

private struct CharacterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    @State private var tab: RewardPickerTab = .buddy
    // 下にスクロールしてインラインのタブが画面外へ出たら、モーダル上部に固定タブを出す。
    @State private var showStickyTab = false

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 122), spacing: 8)
    ]

    private let backgroundColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    private var headerTitle: String {
        switch tab {
        case .buddy:
            return language.text(japanese: "なかまをえらぼう", english: "Choose a Buddy")
        case .background:
            return language.text(japanese: "はいけいをえらぼう", english: "Choose a Background")
        }
    }

    private var headerSubtitle: String {
        switch tab {
        case .buddy:
            return language.text(japanese: "れんしゅうでコインをためて、なかまをふやせます。", english: "Practice to earn coins and unlock buddies.")
        case .background:
            return language.text(japanese: "コインをつかって、はいけいをかえられます。", english: "Spend coins to change the background.")
        }
    }

    // なかま/はいけい 切り替え。インラインと固定バーの両方で使い回す。
    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text(language.text(japanese: "なかま", english: "Buddies")).tag(RewardPickerTab.buddy)
            Text(language.text(japanese: "はいけい", english: "Backgrounds")).tag(RewardPickerTab.background)
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = sheetContentWidth(in: geometry, maxWidth: 820, horizontalPadding: 28)

                ZStack {
                    SheetHomeBackground(themeID: model.selectedBackgroundID)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(headerTitle)
                                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                                    Text(headerSubtitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                // どんな背景画像・端末でもタイトルが読めるよう、白い角丸パネルで隔離する。
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(
                                    .white.opacity(0.86),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)

                                Spacer()

                                HomeCoinBadge(coins: model.rewardCoins, language: language)
                            }

                            tabPicker
                                // インラインタブの下端位置を測り、上に抜けたら固定バーへ切り替える。
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: StickyTabOffsetKey.self,
                                            value: proxy.frame(in: .named("rewardPickerScroll")).maxY
                                        )
                                    }
                                )

                            switch tab {
                            case .buddy:
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                    ForEach(HomeRewardCharacter.catalog) { character in
                                        CharacterPickerCard(
                                            character: character,
                                            isSelected: model.selectedCharacterID == character.id,
                                            isUnlocked: model.unlockedCharacterIDs.contains(character.id),
                                            coinBalance: model.rewardCoins,
                                            language: language
                                        ) {
                                            if model.unlockedCharacterIDs.contains(character.id) {
                                                model.selectCharacter(id: character.id)
                                            } else {
                                                model.unlockCharacter(id: character.id, cost: character.price)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.bottom, 28)
                            case .background:
                                LazyVGrid(columns: backgroundColumns, alignment: .leading, spacing: 12) {
                                    ForEach(HomeBackgroundTheme.catalog) { theme in
                                        BackgroundPickerCard(
                                            theme: theme,
                                            isSelected: model.selectedBackgroundID == theme.id,
                                            isUnlocked: model.unlockedBackgroundIDs.contains(theme.id),
                                            coinBalance: model.rewardCoins,
                                            language: language
                                        ) {
                                            if model.unlockedBackgroundIDs.contains(theme.id) {
                                                model.selectBackground(id: theme.id)
                                            } else {
                                                model.unlockBackground(id: theme.id, cost: theme.price)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.bottom, 28)
                            }
                        }
                        .frame(maxWidth: contentWidth, minHeight: geometry.size.height, alignment: .top)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .background(Color.white.opacity(0.001))
                        .contentShape(Rectangle())
                    }
                    .scrollIndicators(.visible)
                    .scrollBounceBasedOnSizeCompat()
                    .coordinateSpace(name: "rewardPickerScroll")
                    .onPreferenceChange(StickyTabOffsetKey.self) { maxY in
                        // インラインタブの下端がスクロール領域の上端より上に抜けたら固定表示。
                        let shouldShow = maxY < 6
                        if shouldShow != showStickyTab {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showStickyTab = shouldShow
                            }
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if showStickyTab {
                        VStack(spacing: 0) {
                            // インラインヘッダーが流れて消えても、固定バーでコイン残高を見せ続ける。
                            // インラインと同じく右側に置いて位置を揃える。
                            HStack(spacing: 10) {
                                tabPicker
                                HomeCoinBadge(coins: model.rewardCoins, language: language)
                            }
                            .frame(maxWidth: contentWidth)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            Divider()
                        }
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                }
            }
        }
    }
}

/// インラインのタブバーの下端位置（スクロール座標系）を親へ伝えるためのキー。
private struct StickyTabOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private extension View {
    /// 名前ラベルに白い縁取り(ハロー)を重ねる。濃い背景画像の上や、
    /// キャラ/サムネイルの色が文字色(濃紺)と同系色のときでも名前が読めるようにする。
    func legibleLabelHalo() -> some View {
        self
            .shadow(color: .white.opacity(0.95), radius: 1.2)
            .shadow(color: .white.opacity(0.95), radius: 1.2)
            .shadow(color: .white.opacity(0.8), radius: 2.5)
    }
}

private struct CharacterPickerCard: View {
    var character: HomeRewardCharacter
    var isSelected: Bool
    var isUnlocked: Bool
    var coinBalance: Int
    var language: AppLanguage
    var action: () -> Void

    private var canUnlock: Bool {
        isUnlocked || coinBalance >= character.price
    }

    private var borderColor: Color {
        if isSelected {
            return Color(red: 0.20, green: 0.62, blue: 0.26)
        }
        if isUnlocked || canUnlock {
            return Color(red: 0.66, green: 0.78, blue: 0.95)
        }
        return Color(red: 0.78, green: 0.80, blue: 0.86)
    }

    var body: some View {
        VStack(spacing: 6) {
            RewardCharacterAvatar(character: character)
                .frame(width: 58, height: 58)
                // 未購入(未所有)はキャラ本体だけ少し薄くして「まだ持っていない」を伝える。
                // 文字には掛けない。
                .opacity(isUnlocked ? 1 : 0.5)

            Text(character.name(language: language))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .legibleLabelHalo()

            statePill
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.white.opacity(canUnlock ? 0.95 : 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected ? 2.5 : 1.2)
        )
        .shadow(color: .black.opacity(canUnlock ? 0.05 : 0.02), radius: 6, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            guard canUnlock else {
                return
            }
            action()
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(canUnlock ? .isButton : .isStaticText)
    }

    @ViewBuilder
    private var statePill: some View {
        if isSelected {
            Label(language.text(japanese: "いっしょ", english: "Active"), systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 7)
                .background(Color(red: 0.20, green: 0.62, blue: 0.26))
                .clipShape(Capsule())
        } else if isUnlocked {
            Label(language.text(japanese: "えらぶ", english: "Choose"), systemImage: "hand.tap.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color(red: 0.13, green: 0.35, blue: 0.76))
                .padding(.vertical, 4)
                .padding(.horizontal, 7)
                .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                SmallCoinIcon()
                    .frame(width: 14, height: 14)
                Text("\(character.price)")
                    .font(.caption2.monospacedDigit().weight(.heavy))
                if !canUnlock {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.heavy))
                }
            }
            .foregroundStyle(canUnlock ? Color(red: 0.62, green: 0.36, blue: 0.04) : Color(red: 0.48, green: 0.50, blue: 0.56))
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(canUnlock ? Color(red: 1.0, green: 0.94, blue: 0.76) : Color(red: 0.91, green: 0.92, blue: 0.95))
            .clipShape(Capsule())
        }
    }

    private var accessibilityText: String {
        if isSelected {
            return language.text(japanese: "\(character.name(language: language))、選択中", english: "\(character.name(language: language)), active")
        }
        if isUnlocked {
            return language.text(japanese: "\(character.name(language: language))、選べます", english: "\(character.name(language: language)), unlocked")
        }
        return language.text(japanese: "\(character.name(language: language))、\(character.price)コイン", english: "\(character.name(language: language)), \(character.price) coins")
    }
}

private struct BackgroundPickerCard: View {
    var theme: HomeBackgroundTheme
    var isSelected: Bool
    var isUnlocked: Bool
    var coinBalance: Int
    var language: AppLanguage
    var action: () -> Void

    private var canUnlock: Bool {
        isUnlocked || coinBalance >= theme.price
    }

    private var borderColor: Color {
        if isSelected {
            return Color(red: 0.20, green: 0.62, blue: 0.26)
        }
        if isUnlocked || canUnlock {
            return Color(red: 0.66, green: 0.78, blue: 0.95)
        }
        return Color(red: 0.78, green: 0.80, blue: 0.86)
    }

    var body: some View {
        VStack(spacing: 8) {
            HomeBackgroundThumbnail(theme: theme)
                .frame(height: 84)
                // 未購入(未所有)はサムネイルだけ少し薄くする。文字には掛けない。
                .opacity(isUnlocked ? 1 : 0.5)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white, Color(red: 0.20, green: 0.62, blue: 0.26))
                            .padding(6)
                    } else if !isUnlocked && !canUnlock {
                        Image(systemName: "lock.fill")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.32), in: Circle())
                            .padding(6)
                    }
                }

            Text(theme.name(language: language))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .legibleLabelHalo()

            statePill
        }
        .padding(8)
        .background(.white.opacity(canUnlock ? 0.95 : 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isSelected ? 2.5 : 1.2)
        )
        .shadow(color: .black.opacity(canUnlock ? 0.05 : 0.02), radius: 6, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard canUnlock else {
                return
            }
            action()
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(canUnlock ? .isButton : .isStaticText)
    }

    @ViewBuilder
    private var statePill: some View {
        if isSelected {
            Label(language.text(japanese: "つかってる", english: "Active"), systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 7)
                .background(Color(red: 0.20, green: 0.62, blue: 0.26))
                .clipShape(Capsule())
        } else if isUnlocked {
            Label(language.text(japanese: "えらぶ", english: "Choose"), systemImage: "hand.tap.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color(red: 0.13, green: 0.35, blue: 0.76))
                .padding(.vertical, 4)
                .padding(.horizontal, 7)
                .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                SmallCoinIcon()
                    .frame(width: 14, height: 14)
                Text("\(theme.price)")
                    .font(.caption2.monospacedDigit().weight(.heavy))
                if !canUnlock {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.heavy))
                }
            }
            .foregroundStyle(canUnlock ? Color(red: 0.62, green: 0.36, blue: 0.04) : Color(red: 0.48, green: 0.50, blue: 0.56))
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(canUnlock ? Color(red: 1.0, green: 0.94, blue: 0.76) : Color(red: 0.91, green: 0.92, blue: 0.95))
            .clipShape(Capsule())
        }
    }

    private var accessibilityText: String {
        if isSelected {
            return language.text(japanese: "\(theme.name(language: language))、つかっています", english: "\(theme.name(language: language)), active")
        }
        if isUnlocked {
            return language.text(japanese: "\(theme.name(language: language))、えらべます", english: "\(theme.name(language: language)), unlocked")
        }
        return language.text(japanese: "\(theme.name(language: language))、\(theme.price)コイン", english: "\(theme.name(language: language)), \(theme.price) coins")
    }
}

private struct HomeCoinBadge: View {
    var coins: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 7) {
            SmallCoinIcon()
                .frame(width: 25, height: 25)
            Text("\(max(coins, 0))")
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(Color(red: 0.52, green: 0.30, blue: 0.04))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .layoutPriority(1)
        .padding(.vertical, 7)
        .padding(.horizontal, 11)
        .background(Color(red: 1.0, green: 0.94, blue: 0.76).opacity(0.96))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(red: 0.95, green: 0.70, blue: 0.28), lineWidth: 1)
        )
        .accessibilityLabel(language.text(japanese: "\(coins)コイン", english: "\(coins) coins"))
    }
}

private struct HomeLearnedWordMilestone: View {
    var count: Int
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(language.text(japanese: "これまで", english: "Learned"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))

            Text("\(max(count, 0))")
                .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(red: 0.14, green: 0.36, blue: 0.78))

            Text(language.text(japanese: "こ できた", english: "words"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.20, green: 0.58, blue: 0.24))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        // 背景の絵の上でも読めるよう、文字はクッキリ塗りのまま
        // 後ろに白い角丸プレートを敷く（縁取りより濁らない）。
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(language.text(japanese: "これまで学習した単語 \(count)個", english: "\(count) learned words"))
    }
}

private struct SmallCoinIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.22),
                            Color(red: 0.94, green: 0.58, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.8), lineWidth: 2)
                .padding(3)
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}

struct RewardCharacterAvatar: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            character.secondary.opacity(0.46),
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch character.style {
            case .bear:
                BearCharacterFace(character: character)
            case .cat:
                CatCharacterFace(character: character)
            case .dog:
                DogCharacterFace(character: character)
            case .rabbit:
                RabbitCharacterFace(character: character)
            case .panda:
                PandaCharacterFace(character: character)
            case .penguin:
                PenguinCharacterFace(character: character)
            case .lion:
                LionCharacterFace(character: character)
            case .fox:
                FoxCharacterFace(character: character)
            case .koala:
                KoalaCharacterFace(character: character)
            case .sheep:
                SheepCharacterFace(character: character)
            case .elephant:
                ElephantCharacterFace(character: character)
            case .giraffe:
                GiraffeCharacterFace(character: character)
            case .owl:
                OwlCharacterFace(character: character)
            case .turtle:
                TurtleCharacterView(character: character)
            case .whale:
                WhaleCharacterView(character: character)
            case .car:
                CarCharacterView(character: character)
            case .train:
                TrainCharacterView(character: character)
            case .rocket:
                RocketCharacterView(character: character)
            case .plane:
                PlaneCharacterView(character: character)
            case .bus:
                BusCharacterView(character: character)
            case .ship:
                ShipCharacterView(character: character)
            case .helicopter:
                HelicopterCharacterView(character: character)
            case .bicycle:
                BicycleCharacterView(character: character)
            case .tractor:
                TractorCharacterView(character: character)
            case .balloon:
                BalloonCharacterView(character: character)
            case .monkey:
                MonkeyCharacterFace(character: character)
            case .pig:
                PigCharacterFace(character: character)
            case .personShort:
                PersonCharacterFace(character: character, hair: .short)
            case .personLong:
                PersonCharacterFace(character: character, hair: .long)
            case .personCurly:
                PersonCharacterFace(character: character, hair: .curly)
            case .personBun:
                PersonCharacterFace(character: character, hair: .bun)
            case .personBuzz:
                PersonCharacterFace(character: character, hair: .buzz)
            case .personPonytail:
                PersonCharacterFace(character: character, hair: .ponytail)
            case .personTwintails:
                PersonCharacterFace(character: character, hair: .twintails)
            case .personBob:
                PersonCharacterFace(character: character, hair: .bob)
            case .personAfro:
                PersonCharacterFace(character: character, hair: .afro)
            case .personSpiky:
                PersonCharacterFace(character: character, hair: .spiky)
            case .personBraids:
                PersonCharacterFace(character: character, hair: .braids)
            case .personWavy:
                PersonCharacterFace(character: character, hair: .wavy)
            case .robot:
                RobotCharacterFace(character: character)
            case .ghost:
                GhostCharacterFace(character: character)
            case .star:
                StarCharacterFace(character: character)
            case .unicorn:
                UnicornCharacterFace(character: character)
            case .dragon:
                DragonCharacterFace(character: character)
            case .excavator:
                ExcavatorCharacterView(character: character)
            case .crane:
                CraneCharacterView(character: character)
            case .dumpTruck:
                DumpTruckCharacterView(character: character)
            case .house:
                HouseCharacterView(character: character)
            case .school:
                SchoolCharacterView(character: character)
            case .castle:
                CastleCharacterView(character: character)
            case .tower:
                TowerCharacterView(character: character)
            case .lipstick:
                LipstickCharacterView(character: character)
            case .perfume:
                PerfumeCharacterView(character: character)
            case .compact:
                CompactCharacterView(character: character)
            case .nailPolish:
                NailPolishCharacterView(character: character)
            case .octopus:
                OctopusCharacterFace(character: character)
            case .crab:
                CrabCharacterFace(character: character)
            case .fish:
                FishCharacterFace(character: character)
            case .dolphin:
                DolphinCharacterFace(character: character)
            case .shark:
                SharkCharacterFace(character: character)
            case .jellyfish:
                JellyfishCharacterFace(character: character)
            case .starfish:
                StarfishCharacterFace(character: character)
            case .strawberry:
                StrawberryCharacterFace(character: character)
            case .cake:
                CakeCharacterFace(character: character)
            case .iceCream:
                IceCreamCharacterFace(character: character)
            case .donut:
                DonutCharacterFace(character: character)
            case .riceBall:
                RiceBallCharacterFace(character: character)
            case .sushi:
                SushiCharacterFace(character: character)
            case .hamburger:
                HamburgerCharacterFace(character: character)
            case .soccerBall:
                SoccerBallCharacterView(character: character)
            case .baseball:
                BaseballCharacterView(character: character)
            case .basketball:
                BasketballCharacterView(character: character)
            case .tennisBall:
                TennisBallCharacterView(character: character)
            case .trophy:
                TrophyCharacterView(character: character)
            case .eiffel:
                EiffelCharacterView(character: character)
            case .tokyoTower:
                TokyoTowerCharacterView(character: character)
            case .liberty:
                LibertyCharacterView(character: character)
            case .pyramid:
                PyramidCharacterView(character: character)
            case .pisa:
                PisaCharacterView(character: character)
            case .bigBen:
                BigBenCharacterView(character: character)
            case .tajMahal:
                TajMahalCharacterView(character: character)
            case .fuji:
                FujiCharacterView(character: character)
            case .torii:
                ToriiCharacterView(character: character)
            case .moai:
                MoaiCharacterView(character: character)
            case .windmill:
                WindmillCharacterView(character: character)
            case .colosseum:
                ColosseumCharacterView(character: character)
            case .greatWall:
                GreatWallCharacterView(character: character)
            case .operaHouse:
                OperaHouseCharacterView(character: character)
            case .stonehenge:
                StonehengeCharacterView(character: character)
            case .christRedeemer:
                ChristRedeemerCharacterView(character: character)
            case .sagrada:
                SagradaCharacterView(character: character)
            case .goldenGate:
                GoldenGateCharacterView(character: character)
            case .towerBridge:
                TowerBridgeCharacterView(character: character)
            case .ferrisWheel:
                FerrisWheelCharacterView(character: character)
            case .kinkaku:
                KinkakuCharacterView(character: character)
            case .sphinx:
                SphinxCharacterView(character: character)
            case .angkor:
                AngkorCharacterView(character: character)
            case .matterhorn:
                MatterhornCharacterView(character: character)
            case .libertyBell:
                LibertyBellCharacterView(character: character)
            case .whiteHouse:
                WhiteHouseCharacterView(character: character)
            case .notreDame:
                NotreDameCharacterView(character: character)
            case .burjKhalifa:
                BurjKhalifaCharacterView(character: character)
            case .archTriomphe:
                ArchTriompheCharacterView(character: character)
            case .skytree:
                SkytreeCharacterView(character: character)
            case .japaneseCastle:
                JapaneseCastleCharacterView(character: character)
            case .pagoda:
                PagodaCharacterView(character: character)
            case .daibutsu:
                DaibutsuCharacterView(character: character)
            case .gasshou:
                GasshouCharacterView(character: character)
            case .stBasil:
                StBasilCharacterView(character: character)
            case .parthenon:
                ParthenonCharacterView(character: character)
            case .machuPicchu:
                MachuPicchuCharacterView(character: character)
            case .mosque:
                MosqueCharacterView(character: character)
            case .montStMichel:
                MontStMichelCharacterView(character: character)
            case .capitol:
                CapitolCharacterView(character: character)
            case .petra:
                PetraCharacterView(character: character)
            case .kiyomizu:
                KiyomizuCharacterView(character: character)
            case .tokyoStation:
                TokyoStationCharacterView(character: character)
            case .templeHall:
                TempleHallCharacterView(character: character)
            case .duomo:
                DuomoCharacterView(character: character)
            case .euroCastle:
                EuroCastleCharacterView(character: character)
            case .mayanPyramid:
                MayanPyramidCharacterView(character: character)
            case .skyscraper:
                SkyscraperCharacterView(character: character)
            case .starFort:
                StarFortCharacterView(character: character)
            case .guitar:
                GuitarCharacterView(character: character)
            case .piano:
                PianoCharacterView(character: character)
            case .drum:
                DrumCharacterView(character: character)
            case .trumpet:
                TrumpetCharacterView(character: character)
            case .violin:
                ViolinCharacterView(character: character)
            case .butterfly:
                ButterflyCharacterFace(character: character)
            case .beetle:
                BeetleCharacterFace(character: character)
            case .ladybug:
                LadybugCharacterFace(character: character)
            case .bee:
                BeeCharacterFace(character: character)
            case .ant:
                AntCharacterFace(character: character)
            case .trex:
                TrexCharacterFace(character: character)
            case .triceratops:
                TriceratopsCharacterFace(character: character)
            case .stegosaurus:
                StegosaurusCharacterFace(character: character)
            case .brachiosaurus:
                BrachiosaurusCharacterFace(character: character)
            case .pteranodon:
                PteranodonCharacterFace(character: character)
            case .astronaut:
                AstronautCharacterFace(character: character)
            case .ufo:
                UfoCharacterView(character: character)
            case .saturn:
                SaturnCharacterFace(character: character)
            case .moon:
                MoonCharacterFace(character: character)
            case .alien:
                AlienCharacterFace(character: character)
            case .alienBlob:
                AlienBlobCharacterFace(character: character)
            case .alienTriclops:
                AlienTriclopsCharacterFace(character: character)
            case .alienSquid:
                AlienSquidCharacterFace(character: character)
            case .alienWorm:
                AlienWormCharacterFace(character: character)
            case .alienMushroom:
                AlienMushroomCharacterFace(character: character)
            case .alienBugeye:
                AlienBugeyeCharacterFace(character: character)
            case .alienCrystal:
                AlienCrystalCharacterFace(character: character)
            case .alienHover:
                AlienHoverCharacterFace(character: character)
            case .velociraptor:
                VelociraptorCharacterFace(character: character)
            case .ankylosaurus:
                AnkylosaurusCharacterFace(character: character)
            case .spinosaurus:
                SpinosaurusCharacterFace(character: character)
            case .parasaurolophus:
                ParasaurolophusCharacterFace(character: character)
            case .plesiosaurus:
                PlesiosaurusCharacterFace(character: character)
            case .dinoEgg:
                DinoEggCharacterView(character: character)
            case .mouse:
                MouseCharacterFace(character: character)
            case .cow:
                CowCharacterFace(character: character)
            case .horse:
                HorseCharacterFace(character: character)
            case .wolf:
                WolfCharacterFace(character: character)
            case .kangaroo:
                KangarooCharacterFace(character: character)
            case .bat:
                BatCharacterFace(character: character)
            case .goat:
                GoatCharacterFace(character: character)
            case .otter:
                OtterCharacterFace(character: character)
            case .orca:
                OrcaCharacterFace(character: character)
            case .seahorse:
                SeahorseCharacterFace(character: character)
            case .shrimp:
                ShrimpCharacterFace(character: character)
            case .duck:
                DuckCharacterFace(character: character)
            case .bird:
                BirdCharacterFace(character: character)
            case .flamingo:
                FlamingoCharacterFace(character: character)
            case .parrot:
                ParrotCharacterFace(character: character)
            case .swan:
                SwanCharacterFace(character: character)
            case .snail:
                SnailCharacterFace(character: character)
            case .dragonfly:
                DragonflyCharacterFace(character: character)
            case .banana:
                BananaCharacterFace(character: character)
            case .taiyaki:
                TaiyakiCharacterFace(character: character)
            case .cookie:
                CookieCharacterFace(character: character)
            case .imageAsset:
                NakamaImageView(character: character)
            }
        }
        .padding(4)
    }
}

/// 画像ベースの「なかま」を表示する。Assets.xcassets の Data Set `nakama_<id>`(WebP) を
/// NSDataAsset で読み、正方形枠に **aspect-fit＋中央** で収める(縦長キャラもはみ出さない)。
/// 画像が見つからない/壊れている時はフォールバックの絵文字を出す。
@MainActor
private struct NakamaImageView: View {
    var character: HomeRewardCharacter

    /// デコード済み画像を id ごとにキャッシュ（多数表示時の毎回デコードを避ける）。
    private static let cache = NSCache<NSString, UIImage>()

    private var uiImage: UIImage? {
        let key = "nakama_\(character.id)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        guard let data = NSDataAsset(name: key as String)?.data,
              let img = UIImage(data: data) else { return nil }
        Self.cache.setObject(img, forKey: key)
        return img
    }

    /// 既存の SwiftUI 描画キャラ(BearCharacterFace 等)は約100ptの固定サイズで描かれ、
    /// avatar 枠(例 58pt)を超えてカードいっぱいに見える。画像なかまも同じ見た目にするため、
    /// 枠に縮める scaledToFit ではなく **固定サイズで描いて他キャラとサイズを揃える**。
    private static let renderSize: CGFloat = 96

    var body: some View {
        if let img = uiImage {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()            // 縦長でもアスペクト維持(scaledToFill にしない=はみ出さない)
                .frame(width: Self.renderSize, height: Self.renderSize)
        } else {
            Text("🐾")
                .font(.system(size: 44))
        }
    }
}

private struct BearCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 70, height: 70).offset(y: 6)
            Circle().fill(character.primary).frame(width: 25, height: 25).offset(x: -26, y: -24)
            Circle().fill(character.primary).frame(width: 25, height: 25).offset(x: 26, y: -24)
            Circle().fill(character.secondary).frame(width: 38, height: 32).offset(y: 18)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(.black.opacity(0.78)).frame(width: 8, height: 7).offset(y: 14)
        }
    }
}

private struct CatCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle()
                .fill(character.primary)
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-18))
                .offset(x: -26, y: -28)
            Triangle()
                .fill(character.primary)
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(18))
                .offset(x: 26, y: -28)
            Circle().fill(character.primary).frame(width: 72, height: 72).offset(y: 5)
            Circle().fill(character.secondary).frame(width: 36, height: 28).offset(y: 18)
            CharacterEyes(color: character.accent)
            Circle().fill(character.accent).frame(width: 7, height: 6).offset(y: 12)
            WhiskerLines(color: character.accent.opacity(0.78))
        }
    }
}

private struct DogCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(character.accent)
                .frame(width: 25, height: 46)
                .rotationEffect(.degrees(14))
                .offset(x: -33, y: -8)
            RoundedRectangle(cornerRadius: 15)
                .fill(character.accent)
                .frame(width: 25, height: 46)
                .rotationEffect(.degrees(-14))
                .offset(x: 33, y: -8)
            Circle().fill(character.primary).frame(width: 74, height: 74).offset(y: 5)
            Circle().fill(character.secondary).frame(width: 42, height: 34).offset(y: 18)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(.black.opacity(0.80)).frame(width: 9, height: 8).offset(y: 13)
        }
    }
}

private struct RabbitCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 22, height: 54).rotationEffect(.degrees(-10)).offset(x: -16, y: -36)
            Capsule().fill(character.primary).frame(width: 22, height: 54).rotationEffect(.degrees(10)).offset(x: 16, y: -36)
            Capsule().fill(character.secondary).frame(width: 10, height: 36).rotationEffect(.degrees(-10)).offset(x: -16, y: -35)
            Capsule().fill(character.secondary).frame(width: 10, height: 36).rotationEffect(.degrees(10)).offset(x: 16, y: -35)
            Circle().fill(character.primary).frame(width: 72, height: 72).offset(y: 10)
            CharacterEyes(color: character.accent)
            Circle().fill(character.accent).frame(width: 7, height: 6).offset(y: 18)
        }
    }
}

private struct PandaCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 28, height: 28).offset(x: -27, y: -24)
            Circle().fill(character.primary).frame(width: 28, height: 28).offset(x: 27, y: -24)
            Circle().fill(character.secondary).frame(width: 76, height: 76).offset(y: 5)
            Circle().fill(character.primary).frame(width: 22, height: 26).offset(x: -16, y: 1)
            Circle().fill(character.primary).frame(width: 22, height: 26).offset(x: 16, y: 1)
            CharacterEyes(color: .white)
            Circle().fill(character.primary).frame(width: 8, height: 7).offset(y: 16)
        }
    }
}

private struct PenguinCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 74, height: 88).offset(y: 8)
            Capsule().fill(character.secondary).frame(width: 45, height: 56).offset(y: 16)
            CharacterEyes(color: .white)
            Triangle().fill(character.accent).frame(width: 18, height: 14).rotationEffect(.degrees(180)).offset(y: 12)
            Circle().fill(character.accent).frame(width: 12, height: 9).offset(x: -16, y: 45)
            Circle().fill(character.accent).frame(width: 12, height: 9).offset(x: 16, y: 45)
        }
    }
}

private struct LionCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<12) { index in
                Capsule()
                    .fill(character.primary)
                    .frame(width: 18, height: 34)
                    .offset(y: -36)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
            Circle().fill(character.primary).frame(width: 82, height: 82).offset(y: 4)
            Circle().fill(character.secondary).frame(width: 62, height: 62).offset(y: 5)
            CharacterEyes(color: character.accent)
            Circle().fill(character.accent).frame(width: 8, height: 7).offset(y: 14)
        }
    }
}

private struct FoxCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 32, height: 34).rotationEffect(.degrees(-18)).offset(x: -25, y: -30)
            Triangle().fill(character.primary).frame(width: 32, height: 34).rotationEffect(.degrees(18)).offset(x: 25, y: -30)
            Circle().fill(character.primary).frame(width: 74, height: 74).offset(y: 6)
            Triangle().fill(character.secondary).frame(width: 56, height: 42).rotationEffect(.degrees(180)).offset(y: 20)
            CharacterEyes(color: character.accent)
            Circle().fill(character.accent).frame(width: 8, height: 7).offset(y: 16)
        }
    }
}

private struct KoalaCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: -31, y: -18)
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: 31, y: -18)
            Circle().fill(character.secondary).frame(width: 20, height: 20).offset(x: -31, y: -18)
            Circle().fill(character.secondary).frame(width: 20, height: 20).offset(x: 31, y: -18)
            Circle().fill(character.primary).frame(width: 76, height: 76).offset(y: 7)
            CharacterEyes(color: .black.opacity(0.78))
            Capsule().fill(character.accent).frame(width: 16, height: 22).offset(y: 14)
        }
    }
}

private struct SheepCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<9) { index in
                Circle()
                    .fill(character.primary)
                    .frame(width: 29, height: 29)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index) * 40))
            }
            Circle().fill(character.primary).frame(width: 74, height: 68).offset(y: 6)
            Capsule().fill(character.secondary).frame(width: 40, height: 35).offset(y: 18)
            CharacterEyes(color: character.accent)
            Circle().fill(character.accent).frame(width: 7, height: 6).offset(y: 16)
        }
    }
}

private struct ElephantCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 44, height: 52).offset(x: -34, y: 2)
            Circle().fill(character.primary).frame(width: 44, height: 52).offset(x: 34, y: 2)
            Circle().fill(character.secondary.opacity(0.70)).frame(width: 28, height: 34).offset(x: -34, y: 4)
            Circle().fill(character.secondary.opacity(0.70)).frame(width: 28, height: 34).offset(x: 34, y: 4)
            Circle().fill(character.primary).frame(width: 76, height: 76).offset(y: 5)
            Capsule().fill(character.primary).frame(width: 18, height: 42).offset(y: 30)
            CharacterEyes(color: character.accent)
            Capsule().fill(character.accent.opacity(0.26)).frame(width: 10, height: 4).offset(y: 46)
        }
    }
}

private struct GiraffeCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(character.primary).frame(width: 36, height: 66).offset(y: 24)
            Circle().fill(character.primary).frame(width: 66, height: 58).offset(y: -4)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: -13, y: -2)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 17, y: 11)
            Capsule().fill(character.primary).frame(width: 8, height: 24).offset(x: -16, y: -37)
            Capsule().fill(character.primary).frame(width: 8, height: 24).offset(x: 16, y: -37)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: -16, y: -49)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: 16, y: -49)
            CharacterEyes(color: character.accent)
            Capsule().fill(character.secondary).frame(width: 26, height: 17).offset(y: 16)
        }
    }
}

private struct OwlCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 76, height: 86).offset(y: 8)
            Circle().fill(character.secondary).frame(width: 30, height: 30).offset(x: -16, y: -5)
            Circle().fill(character.secondary).frame(width: 30, height: 30).offset(x: 16, y: -5)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: -16, y: -5)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: 16, y: -5)
            Triangle().fill(character.secondary).frame(width: 18, height: 14).rotationEffect(.degrees(180)).offset(y: 12)
            Circle().fill(character.secondary.opacity(0.50)).frame(width: 34, height: 42).offset(x: -28, y: 17)
            Circle().fill(character.secondary.opacity(0.50)).frame(width: 34, height: 42).offset(x: 28, y: 17)
        }
    }
}

private struct TurtleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 25, height: 25).offset(x: 43, y: -3)
            Capsule().fill(character.primary).frame(width: 18, height: 24).rotationEffect(.degrees(-28)).offset(x: -28, y: -24)
            Capsule().fill(character.primary).frame(width: 18, height: 24).rotationEffect(.degrees(28)).offset(x: -26, y: 28)
            Capsule().fill(character.primary).frame(width: 18, height: 24).rotationEffect(.degrees(28)).offset(x: 18, y: -28)
            Capsule().fill(character.primary).frame(width: 18, height: 24).rotationEffect(.degrees(-28)).offset(x: 18, y: 31)
            Ellipse().fill(character.secondary).frame(width: 70, height: 56).offset(x: -3, y: 5)
            Ellipse().stroke(character.accent.opacity(0.72), lineWidth: 4).frame(width: 54, height: 40).offset(x: -3, y: 5)
            Circle().fill(character.accent).frame(width: 5, height: 5).offset(x: 48, y: -8)
        }
    }
}

private struct WhaleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 82, height: 48).offset(x: -6, y: 6)
            Triangle().fill(character.primary).frame(width: 28, height: 24).rotationEffect(.degrees(90)).offset(x: 44, y: 1)
            Triangle().fill(character.primary).frame(width: 28, height: 24).rotationEffect(.degrees(140)).offset(x: 42, y: 15)
            Circle().fill(.white).frame(width: 7, height: 7).offset(x: -24, y: -2)
            Circle().fill(character.accent).frame(width: 4, height: 4).offset(x: -24, y: -2)
            Capsule().fill(character.secondary).frame(width: 34, height: 8).offset(x: -4, y: 19)
            Circle().fill(character.secondary).frame(width: 6, height: 6).offset(x: -8, y: -32)
            Circle().fill(character.secondary).frame(width: 5, height: 5).offset(x: 1, y: -39)
        }
    }
}

private struct CarCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(character.primary)
                .frame(width: 76, height: 35)
                .offset(y: 12)
            RoundedRectangle(cornerRadius: 12)
                .fill(character.primary.opacity(0.92))
                .frame(width: 48, height: 28)
                .offset(y: -5)
            RoundedRectangle(cornerRadius: 6)
                .fill(character.secondary)
                .frame(width: 32, height: 14)
                .offset(y: -6)
            Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: -24, y: 32)
            Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: 24, y: 32)
        }
    }
}

private struct TrainCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(character.primary)
                .frame(width: 72, height: 62)
                .offset(y: 7)
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4).fill(character.secondary)
                RoundedRectangle(cornerRadius: 4).fill(character.secondary)
            }
            .frame(width: 44, height: 18)
            .offset(y: -8)
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.82)).frame(width: 48, height: 5).offset(y: 17)
            Circle().fill(character.accent).frame(width: 13, height: 13).offset(x: -18, y: 39)
            Circle().fill(character.accent).frame(width: 13, height: 13).offset(x: 18, y: 39)
        }
    }
}

private struct RocketCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule()
                .fill(character.secondary)
                .frame(width: 38, height: 76)
                .offset(y: -4)
            Triangle()
                .fill(character.primary)
                .frame(width: 38, height: 30)
                .offset(y: -52)
            Circle().fill(character.primary.opacity(0.82)).frame(width: 18, height: 18).offset(y: -14)
            Triangle().fill(character.primary).frame(width: 22, height: 25).rotationEffect(.degrees(-28)).offset(x: -27, y: 26)
            Triangle().fill(character.primary).frame(width: 22, height: 25).rotationEffect(.degrees(28)).offset(x: 27, y: 26)
            Triangle().fill(character.accent).frame(width: 28, height: 30).rotationEffect(.degrees(180)).offset(y: 54)
        }
    }
}

private struct PlaneCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        Image(systemName: "airplane")
            .font(.system(size: 58, weight: .heavy))
            .foregroundStyle(character.primary)
            .rotationEffect(.degrees(-12))
            .shadow(color: character.accent.opacity(0.24), radius: 5, x: 0, y: 4)
    }
}

private struct BusCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(character.primary).frame(width: 78, height: 58).offset(y: 4)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(character.secondary)
                RoundedRectangle(cornerRadius: 4).fill(character.secondary)
                RoundedRectangle(cornerRadius: 4).fill(character.secondary)
            }
            .frame(width: 54, height: 18)
            .offset(y: -6)
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.85)).frame(width: 48, height: 5).offset(y: 17)
            Circle().fill(character.accent).frame(width: 14, height: 14).offset(x: -24, y: 35)
            Circle().fill(character.accent).frame(width: 14, height: 14).offset(x: 24, y: 35)
        }
    }
}

private struct ShipCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(character.secondary).frame(width: 42, height: 24).offset(y: -18)
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.86)).frame(width: 20, height: 9).offset(y: -20)
            Trapezoid().fill(character.primary).frame(width: 82, height: 34).offset(y: 12)
            Capsule().fill(character.accent).frame(width: 58, height: 6).offset(y: 23)
            Circle().fill(character.secondary).frame(width: 8, height: 8).offset(x: -22, y: 9)
            Circle().fill(character.secondary).frame(width: 8, height: 8).offset(x: 0, y: 9)
            Circle().fill(character.secondary).frame(width: 8, height: 8).offset(x: 22, y: 9)
        }
    }
}

private struct HelicopterCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 76, height: 6).offset(y: -44)
            Capsule().fill(character.accent).frame(width: 6, height: 22).offset(y: -32)
            Capsule().fill(character.primary).frame(width: 68, height: 36).offset(y: 2)
            Circle().fill(character.secondary).frame(width: 22, height: 22).offset(x: -12, y: 1)
            Capsule().fill(character.primary).frame(width: 42, height: 10).rotationEffect(.degrees(-8)).offset(x: 48, y: -1)
            Capsule().fill(character.accent).frame(width: 55, height: 6).offset(y: 31)
            Capsule().fill(character.accent).frame(width: 8, height: 17).offset(x: -20, y: 24)
            Capsule().fill(character.accent).frame(width: 8, height: 17).offset(x: 20, y: 24)
        }
    }
}

private struct BicycleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().stroke(character.accent, lineWidth: 5).frame(width: 30, height: 30).offset(x: -28, y: 26)
            Circle().stroke(character.accent, lineWidth: 5).frame(width: 30, height: 30).offset(x: 28, y: 26)
            Capsule().fill(character.primary).frame(width: 44, height: 6).rotationEffect(.degrees(-24)).offset(x: -8, y: 9)
            Capsule().fill(character.primary).frame(width: 44, height: 6).rotationEffect(.degrees(24)).offset(x: 8, y: 9)
            Capsule().fill(character.primary).frame(width: 34, height: 6).offset(y: 11)
            Capsule().fill(character.primary).frame(width: 20, height: 6).rotationEffect(.degrees(80)).offset(x: 14, y: -8)
            Capsule().fill(character.accent).frame(width: 24, height: 6).offset(x: 23, y: -18)
            Capsule().fill(character.accent).frame(width: 20, height: 6).offset(x: -8, y: -10)
        }
    }
}

private struct TractorCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(character.primary).frame(width: 45, height: 36).offset(x: 5, y: 5)
            RoundedRectangle(cornerRadius: 7).fill(character.secondary).frame(width: 26, height: 28).offset(x: 20, y: -20)
            RoundedRectangle(cornerRadius: 5).fill(character.primary).frame(width: 30, height: 22).offset(x: -28, y: 14)
            Circle().fill(character.accent).frame(width: 31, height: 31).offset(x: 22, y: 32)
            Circle().fill(character.secondary).frame(width: 16, height: 16).offset(x: 22, y: 32)
            Circle().fill(character.accent).frame(width: 20, height: 20).offset(x: -28, y: 34)
            Circle().fill(character.secondary).frame(width: 10, height: 10).offset(x: -28, y: 34)
        }
    }
}

private struct BalloonCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 62, height: 62).offset(y: -22)
            Capsule().fill(character.secondary.opacity(0.78)).frame(width: 12, height: 55).offset(y: -22)
            Capsule().fill(character.secondary.opacity(0.56)).frame(width: 5, height: 58).offset(x: -18, y: -21)
            Capsule().fill(character.secondary.opacity(0.56)).frame(width: 5, height: 58).offset(x: 18, y: -21)
            Capsule().fill(character.accent.opacity(0.70)).frame(width: 3, height: 30).rotationEffect(.degrees(-16)).offset(x: -8, y: 26)
            Capsule().fill(character.accent.opacity(0.70)).frame(width: 3, height: 30).rotationEffect(.degrees(16)).offset(x: 8, y: 26)
            RoundedRectangle(cornerRadius: 4).fill(character.accent).frame(width: 28, height: 18).offset(y: 44)
        }
    }
}

// MARK: - People characters (skin = primary, shirt = secondary, hair = accent)

private enum PersonHair {
    case short
    case long
    case curly
    case bun
    case buzz
    case ponytail
    case twintails
    case bob
    case afro
    case spiky
    case braids
    case wavy
}

private struct PersonCharacterFace: View {
    var character: HomeRewardCharacter
    var hair: PersonHair

    private var cheek: Color {
        Color(red: 0.95, green: 0.55, blue: 0.58)
    }

    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 82, height: 48).offset(y: 52)
            RoundedRectangle(cornerRadius: 8).fill(character.primary).frame(width: 18, height: 16).offset(y: 33)

            hairBack

            Circle().fill(character.primary).frame(width: 62, height: 66).offset(y: 2)
            Circle().fill(character.primary).frame(width: 13, height: 15).offset(x: -31, y: 6)
            Circle().fill(character.primary).frame(width: 13, height: 15).offset(x: 31, y: 6)

            hairFront

            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(cheek.opacity(0.30)).frame(width: 11, height: 9).offset(x: -19, y: 13)
            Circle().fill(cheek.opacity(0.30)).frame(width: 11, height: 9).offset(x: 19, y: 13)
            SmileArc()
                .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 20, height: 11)
                .offset(y: 15)
        }
    }

    @ViewBuilder private var hairBack: some View {
        switch hair {
        case .long:
            RoundedRectangle(cornerRadius: 26).fill(character.accent).frame(width: 72, height: 88).offset(y: 8)
        case .ponytail:
            Capsule().fill(character.accent).frame(width: 20, height: 48).rotationEffect(.degrees(18)).offset(x: 35, y: 8)
        case .bun:
            Circle().fill(character.accent).frame(width: 26, height: 26).offset(y: -34)
        case .twintails:
            Capsule().fill(character.accent).frame(width: 18, height: 46).rotationEffect(.degrees(-22)).offset(x: -34, y: 10)
            Capsule().fill(character.accent).frame(width: 18, height: 46).rotationEffect(.degrees(22)).offset(x: 34, y: 10)
        case .bob:
            RoundedRectangle(cornerRadius: 22).fill(character.accent).frame(width: 76, height: 70).offset(y: 2)
        case .afro:
            Circle().fill(character.accent).frame(width: 86, height: 82).offset(y: -4)
        case .braids:
            ForEach(0..<3) { index in
                Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: -33, y: CGFloat(index) * 13 + 6)
            }
            ForEach(0..<3) { index in
                Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: 33, y: CGFloat(index) * 13 + 6)
            }
        case .wavy:
            RoundedRectangle(cornerRadius: 30).fill(character.accent).frame(width: 72, height: 84).offset(y: 10)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(x: -29, y: 44)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(x: 29, y: 44)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var hairFront: some View {
        switch hair {
        case .buzz:
            Circle().fill(character.accent).frame(width: 60, height: 60).offset(y: -8)
                .mask(Rectangle().frame(width: 64, height: 24).offset(y: -22))
        case .short:
            Circle().fill(character.accent).frame(width: 66, height: 64).offset(y: -10)
                .mask(Rectangle().frame(width: 70, height: 34).offset(y: -18))
        case .curly:
            ForEach(0..<6) { index in
                Circle().fill(character.accent).frame(width: 24, height: 24)
                    .offset(y: -30)
                    .rotationEffect(.degrees(Double(index) * 28 - 70))
            }
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(y: -32)
        case .spiky:
            // 髪の土台キャップ → そこからトゲを生やす（坊主に浮かないよう接続）
            Circle().fill(character.accent).frame(width: 66, height: 62).offset(y: -12)
                .mask(Rectangle().frame(width: 70, height: 28).offset(y: -22))
            ForEach(0..<5) { index in
                Triangle().fill(character.accent).frame(width: 16, height: 22)
                    .offset(x: CGFloat(index - 2) * 14, y: -34)
            }
        default:
            // long, ponytail, bun, twintails, bob, afro, braids, wavy: 共通の前髪
            Circle().fill(character.accent).frame(width: 64, height: 58).offset(y: -12)
                .mask(Rectangle().frame(width: 70, height: 30).offset(y: -20))
        }
    }
}

// MARK: - New animal faces

private struct MonkeyCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: -32, y: -6)
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: 32, y: -6)
            Circle().fill(character.secondary).frame(width: 18, height: 18).offset(x: -32, y: -6)
            Circle().fill(character.secondary).frame(width: 18, height: 18).offset(x: 32, y: -6)
            Circle().fill(character.primary).frame(width: 74, height: 72).offset(y: 4)
            Circle().fill(character.secondary).frame(width: 54, height: 46).offset(y: 12)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent.opacity(0.6)).frame(width: 6, height: 5).offset(x: -7, y: 16)
            Circle().fill(character.accent.opacity(0.6)).frame(width: 6, height: 5).offset(x: 7, y: 16)
            Capsule().fill(.black.opacity(0.45)).frame(width: 12, height: 4).offset(y: 22)
        }
    }
}

private struct PigCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 22, height: 20).rotationEffect(.degrees(-12)).offset(x: -24, y: -28)
            Triangle().fill(character.primary).frame(width: 22, height: 20).rotationEffect(.degrees(12)).offset(x: 24, y: -28)
            Circle().fill(character.primary).frame(width: 78, height: 70).offset(y: 6)
            Ellipse().fill(character.secondary).frame(width: 32, height: 24).offset(y: 16)
            Circle().fill(character.accent).frame(width: 7, height: 9).offset(x: -7, y: 16)
            Circle().fill(character.accent).frame(width: 7, height: 9).offset(x: 7, y: 16)
            CharacterEyes(color: .black.opacity(0.78))
        }
    }
}

// MARK: - Fantasy faces

private struct RobotCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.accent).frame(width: 4, height: 14).offset(y: -34)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(y: -42)
            Capsule().fill(character.accent).frame(width: 8, height: 22).offset(x: -38, y: 4)
            Capsule().fill(character.accent).frame(width: 8, height: 22).offset(x: 38, y: 4)
            RoundedRectangle(cornerRadius: 18).fill(character.primary).frame(width: 74, height: 70).offset(y: 4)
            RoundedRectangle(cornerRadius: 12).fill(character.secondary).frame(width: 56, height: 40).offset(y: 0)
            Circle().fill(character.accent).frame(width: 13, height: 13).offset(x: -14, y: -4)
            Circle().fill(character.accent).frame(width: 13, height: 13).offset(x: 14, y: -4)
            RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.45)).frame(width: 26, height: 5).offset(y: 16)
        }
    }
}

private struct GhostCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            GhostShape().fill(character.primary).frame(width: 66, height: 84).offset(y: 4)
            Ellipse().fill(character.accent).frame(width: 12, height: 17).offset(x: -13, y: -8)
            Ellipse().fill(character.accent).frame(width: 12, height: 17).offset(x: 13, y: -8)
            Ellipse().fill(character.accent).frame(width: 11, height: 13).offset(y: 12)
            Circle().fill(character.secondary.opacity(0.7)).frame(width: 10, height: 8).offset(x: -22, y: 4)
            Circle().fill(character.secondary.opacity(0.7)).frame(width: 10, height: 8).offset(x: 22, y: 4)
        }
    }
}

private struct StarCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            StarShape().fill(character.primary).frame(width: 94, height: 94).offset(y: 2)
            StarShape().fill(character.secondary).frame(width: 54, height: 54).offset(y: 2)
            CharacterEyes(color: character.accent)
            SmileArc()
                .stroke(character.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 10)
                .offset(y: 14)
        }
    }
}

private struct UnicornCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.accent).frame(width: 14, height: 26).offset(y: -34)
            Triangle().fill(character.primary).frame(width: 16, height: 22).offset(x: -22, y: -28)
            Triangle().fill(character.primary).frame(width: 16, height: 22).offset(x: 22, y: -28)
            Capsule().fill(character.secondary).frame(width: 26, height: 56).rotationEffect(.degrees(-16)).offset(x: -30, y: 2)
            Circle().fill(character.primary).frame(width: 72, height: 74).offset(y: 6)
            Ellipse().fill(character.secondary.opacity(0.5)).frame(width: 40, height: 30).offset(y: 20)
            Capsule().fill(character.secondary).frame(width: 18, height: 24).rotationEffect(.degrees(20)).offset(x: 8, y: -20)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(.black.opacity(0.4)).frame(width: 5, height: 5).offset(x: -6, y: 22)
            Circle().fill(.black.opacity(0.4)).frame(width: 5, height: 5).offset(x: 6, y: 22)
        }
    }
}

private struct DragonCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 14, height: 20).rotationEffect(.degrees(-20)).offset(x: -18, y: -30)
            Triangle().fill(character.secondary).frame(width: 14, height: 20).rotationEffect(.degrees(20)).offset(x: 18, y: -30)
            Triangle().fill(character.accent).frame(width: 12, height: 13).offset(y: -28)
            Circle().fill(character.primary).frame(width: 78, height: 72).offset(y: 4)
            Ellipse().fill(character.primary).frame(width: 46, height: 34).offset(y: 18)
            Circle().fill(.black.opacity(0.5)).frame(width: 6, height: 6).offset(x: -9, y: 22)
            Circle().fill(.black.opacity(0.5)).frame(width: 6, height: 6).offset(x: 9, y: 22)
            CharacterEyes(color: .black.opacity(0.78))
        }
    }
}

// MARK: - Working vehicles (はたらく車)

private struct ExcavatorCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(character.accent).frame(width: 70, height: 18).offset(y: 30)
            Circle().fill(.black.opacity(0.4)).frame(width: 13, height: 13).offset(x: -22, y: 30)
            Circle().fill(.black.opacity(0.4)).frame(width: 13, height: 13).offset(x: 22, y: 30)
            RoundedRectangle(cornerRadius: 8).fill(character.primary).frame(width: 40, height: 34).offset(x: -12, y: 6)
            RoundedRectangle(cornerRadius: 4).fill(character.secondary).frame(width: 18, height: 14).offset(x: -18, y: 0)
            Capsule().fill(character.primary).frame(width: 10, height: 42).rotationEffect(.degrees(40)).offset(x: 18, y: -2)
            Triangle().fill(character.accent).frame(width: 22, height: 18).rotationEffect(.degrees(205)).offset(x: 34, y: 22)
        }
    }
}

private struct CraneCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(character.primary).frame(width: 66, height: 26).offset(y: 24)
            Circle().fill(.black.opacity(0.4)).frame(width: 14, height: 14).offset(x: -20, y: 35)
            Circle().fill(.black.opacity(0.4)).frame(width: 14, height: 14).offset(x: 20, y: 35)
            RoundedRectangle(cornerRadius: 6).fill(character.secondary).frame(width: 22, height: 20).offset(x: -22, y: 8)
            Capsule().fill(character.accent).frame(width: 8, height: 72).rotationEffect(.degrees(-42)).offset(x: 6, y: -8)
            Rectangle().fill(.black.opacity(0.4)).frame(width: 2, height: 18).offset(x: 34, y: -16)
            Circle().fill(character.primary).frame(width: 9, height: 9).offset(x: 34, y: -6)
        }
    }
}

private struct DumpTruckCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.secondary).frame(width: 48, height: 32).offset(x: 9, y: -2)
            RoundedRectangle(cornerRadius: 6).fill(character.primary).frame(width: 26, height: 30).offset(x: -28, y: 4)
            RoundedRectangle(cornerRadius: 3).fill(character.secondary).frame(width: 14, height: 12).offset(x: -28, y: -2)
            RoundedRectangle(cornerRadius: 4).fill(character.accent).frame(width: 82, height: 12).offset(y: 20)
            Circle().fill(.black.opacity(0.45)).frame(width: 16, height: 16).offset(x: -24, y: 30)
            Circle().fill(.black.opacity(0.45)).frame(width: 16, height: 16).offset(x: 14, y: 30)
            Circle().fill(.black.opacity(0.45)).frame(width: 16, height: 16).offset(x: 30, y: 30)
        }
    }
}

// MARK: - Buildings (たてもの)

private struct HouseCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(character.secondary).frame(width: 64, height: 50).offset(y: 18)
            Triangle().fill(character.primary).frame(width: 84, height: 40).offset(y: -16)
            RoundedRectangle(cornerRadius: 3).fill(character.accent.opacity(0.55)).frame(width: 15, height: 15).offset(x: -16, y: 12)
            RoundedRectangle(cornerRadius: 3).fill(character.accent.opacity(0.55)).frame(width: 15, height: 15).offset(x: 16, y: 12)
            RoundedRectangle(cornerRadius: 4).fill(character.accent).frame(width: 18, height: 26).offset(y: 30)
        }
    }
}

private struct SchoolCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(character.secondary).frame(width: 80, height: 50).offset(y: 20)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 84, height: 12).offset(y: -6)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 22, height: 24).offset(y: -20)
            Circle().fill(.white).frame(width: 12, height: 12).offset(y: -20)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.55)).frame(width: 12, height: 14)
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.55)).frame(width: 12, height: 14)
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.55)).frame(width: 12, height: 14)
            }
            .offset(y: 16)
            RoundedRectangle(cornerRadius: 3).fill(character.accent).frame(width: 16, height: 22).offset(y: 34)
        }
    }
}

private struct CastleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 18, height: 64).offset(x: -34, y: 6)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 18, height: 64).offset(x: 34, y: 6)
            RoundedRectangle(cornerRadius: 4).fill(character.secondary).frame(width: 66, height: 46).offset(y: 20)
            HStack(spacing: 6) {
                Rectangle().fill(character.primary).frame(width: 9, height: 11)
                Rectangle().fill(character.primary).frame(width: 9, height: 11)
                Rectangle().fill(character.primary).frame(width: 9, height: 11)
            }
            .offset(y: -6)
            Triangle().fill(character.accent).frame(width: 12, height: 11).rotationEffect(.degrees(90)).offset(x: -28, y: -30)
            Triangle().fill(character.accent).frame(width: 12, height: 11).rotationEffect(.degrees(90)).offset(x: 40, y: -30)
            RoundedRectangle(cornerRadius: 9).fill(character.accent).frame(width: 22, height: 30).offset(y: 28)
        }
    }
}

private struct TowerCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 46, height: 28).offset(y: -42)
            RoundedRectangle(cornerRadius: 8).fill(character.primary).frame(width: 34, height: 82).offset(y: 8)
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.55))
                    .frame(width: 14, height: 9)
                    .offset(y: CGFloat(-18 + index * 16))
            }
            RoundedRectangle(cornerRadius: 4).fill(character.secondary).frame(width: 48, height: 12).offset(y: 44)
        }
    }
}

// MARK: - Cosmetics (コスメ)

private struct LipstickCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(character.secondary).frame(width: 32, height: 44).offset(y: 22)
            Rectangle().fill(character.primary).frame(width: 32, height: 7).offset(y: -1)
            RoundedRectangle(cornerRadius: 9).fill(character.accent).frame(width: 22, height: 38).rotationEffect(.degrees(8)).offset(y: -24)
        }
    }
}

private struct PerfumeCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(character.secondary).frame(width: 46, height: 48).offset(y: 18)
            Circle().fill(character.accent.opacity(0.5)).frame(width: 20, height: 20).offset(y: 20)
            Rectangle().fill(character.secondary).frame(width: 16, height: 12).offset(y: -8)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 20, height: 16).offset(y: -20)
            Circle().fill(character.accent).frame(width: 15, height: 15).offset(x: 22, y: -16)
        }
    }
}

private struct CompactCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 16, height: 9).offset(y: -30)
            Circle().fill(character.primary).frame(width: 64, height: 64).offset(y: 6)
            Circle().fill(character.secondary).frame(width: 46, height: 46).offset(y: 6)
            Circle().fill(character.accent.opacity(0.45)).frame(width: 30, height: 30).offset(y: 6)
            Circle().fill(.white.opacity(0.85)).frame(width: 18, height: 18).offset(x: 14, y: 16)
        }
    }
}

private struct NailPolishCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(character.accent).frame(width: 38, height: 40).offset(y: 22)
            RoundedRectangle(cornerRadius: 3).fill(character.accent.opacity(0.85)).frame(width: 30, height: 8).offset(y: 0)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 18, height: 34).offset(y: -22)
            Capsule().fill(.white.opacity(0.45)).frame(width: 6, height: 16).offset(x: -10, y: 24)
        }
    }
}

// MARK: - Cute face overlay (eyes + smile) for sea/food buddies

private struct CuteFace: View {
    var eyeColor: Color = .black.opacity(0.78)
    var mouthColor: Color = .black.opacity(0.5)
    var eyeY: CGFloat = -4
    var mouthY: CGFloat = 9
    var spacing: CGFloat = 20

    var body: some View {
        ZStack {
            HStack(spacing: spacing) {
                Circle().fill(eyeColor).frame(width: 7, height: 7)
                Circle().fill(eyeColor).frame(width: 7, height: 7)
            }
            .offset(y: eyeY)
            SmileArc()
                .stroke(mouthColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 8)
                .offset(y: mouthY)
        }
    }
}

// MARK: - Sea life (うみのいきもの)

private struct OctopusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Capsule().fill(character.primary)
                    .frame(width: 14, height: 28)
                    .offset(x: CGFloat(-28 + index * 14), y: 30)
            }
            Circle().fill(character.primary).frame(width: 64, height: 60).offset(y: -6)
            Circle().fill(character.secondary.opacity(0.5)).frame(width: 12, height: 8).offset(x: -16, y: 2)
            Circle().fill(character.secondary.opacity(0.5)).frame(width: 12, height: 8).offset(x: 16, y: 2)
            CuteFace(eyeY: -12, mouthY: 2)
        }
    }
}

private struct CrabCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 22, height: 22).offset(x: -36, y: 0)
            Capsule().fill(character.primary).frame(width: 22, height: 22).offset(x: 36, y: 0)
            ForEach(0..<3) { index in
                Capsule().fill(character.primary).frame(width: 5, height: 16)
                    .rotationEffect(.degrees(-30)).offset(x: -30, y: CGFloat(12 + index * 8))
                Capsule().fill(character.primary).frame(width: 5, height: 16)
                    .rotationEffect(.degrees(30)).offset(x: 30, y: CGFloat(12 + index * 8))
            }
            Capsule().fill(character.primary).frame(width: 64, height: 40).offset(y: 8)
            Capsule().fill(character.primary).frame(width: 4, height: 14).offset(x: -10, y: -18)
            Capsule().fill(character.primary).frame(width: 4, height: 14).offset(x: 10, y: -18)
            Circle().fill(.white).frame(width: 12, height: 12).offset(x: -10, y: -24)
            Circle().fill(.white).frame(width: 12, height: 12).offset(x: 10, y: -24)
            Circle().fill(.black.opacity(0.78)).frame(width: 6, height: 6).offset(x: -10, y: -24)
            Circle().fill(.black.opacity(0.78)).frame(width: 6, height: 6).offset(x: 10, y: -24)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 8).offset(y: 10)
        }
    }
}

private struct FishCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 30, height: 32).rotationEffect(.degrees(-90)).offset(x: 32, y: 0)
            Ellipse().fill(character.primary).frame(width: 62, height: 48).offset(x: -6, y: 0)
            Triangle().fill(character.secondary).frame(width: 22, height: 14).offset(x: -6, y: -22)
            Circle().fill(.white).frame(width: 15, height: 15).offset(x: -18, y: -4)
            Circle().fill(.black.opacity(0.78)).frame(width: 7, height: 7).offset(x: -18, y: -4)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12, height: 7).offset(x: -10, y: 12)
        }
    }
}

private struct DolphinCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 26, height: 22).rotationEffect(.degrees(-90)).offset(x: 36, y: 4)
            Triangle().fill(character.primary).frame(width: 20, height: 22).rotationEffect(.degrees(20)).offset(x: 6, y: -22)
            Ellipse().fill(character.primary).frame(width: 68, height: 44).rotationEffect(.degrees(-8)).offset(y: 2)
            Capsule().fill(character.primary).frame(width: 24, height: 14).rotationEffect(.degrees(-22)).offset(x: -30, y: -4)
            Ellipse().fill(character.secondary).frame(width: 40, height: 18).offset(x: -6, y: 12)
            Circle().fill(.black.opacity(0.78)).frame(width: 7, height: 7).offset(x: -16, y: -4)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12, height: 7).offset(x: -22, y: 4)
        }
    }
}

private struct SharkCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 26, height: 24).rotationEffect(.degrees(-90)).offset(x: 38, y: -2)
            Triangle().fill(character.primary).frame(width: 24, height: 26).offset(x: 2, y: -24)
            Ellipse().fill(character.primary).frame(width: 72, height: 46).offset(y: 2)
            Ellipse().fill(character.secondary).frame(width: 52, height: 18).offset(y: 14)
            Capsule().fill(.white).frame(width: 26, height: 7).offset(x: -10, y: 12)
            Circle().fill(.black.opacity(0.78)).frame(width: 7, height: 7).offset(x: -18, y: -4)
            Circle().fill(.black.opacity(0.78)).frame(width: 7, height: 7).offset(x: 0, y: -4)
        }
    }
}

private struct JellyfishCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Capsule().fill(character.secondary)
                    .frame(width: 6, height: 30)
                    .offset(x: CGFloat(-20 + index * 10), y: 28)
            }
            Ellipse().fill(character.primary).frame(width: 62, height: 52).offset(y: -6)
            CuteFace(eyeY: -10, mouthY: 4)
        }
    }
}

private struct StarfishCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            StarShape().fill(character.primary).frame(width: 90, height: 90).offset(y: 2)
            Circle().fill(character.secondary).frame(width: 7, height: 7).offset(x: -14, y: 14)
            Circle().fill(character.secondary).frame(width: 7, height: 7).offset(x: 14, y: 14)
            Circle().fill(character.secondary).frame(width: 7, height: 7).offset(y: -16)
            CuteFace(eyeColor: character.accent, mouthColor: character.accent, eyeY: -2, mouthY: 12)
        }
    }
}

// MARK: - Food (たべもの)

private struct StrawberryCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 54, height: 40).rotationEffect(.degrees(180)).offset(y: 24)
            Circle().fill(character.primary).frame(width: 58, height: 52).offset(y: 0)
            Triangle().fill(character.secondary).frame(width: 16, height: 12).offset(x: -11, y: -24)
            Triangle().fill(character.secondary).frame(width: 16, height: 13).offset(y: -28)
            Triangle().fill(character.secondary).frame(width: 16, height: 12).offset(x: 11, y: -24)
            CuteFace(eyeColor: .white.opacity(0.92), mouthColor: .white.opacity(0.85), eyeY: 0, mouthY: 12)
        }
    }
}

private struct CakeCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(character.secondary).frame(width: 64, height: 36).offset(y: 18)
            RoundedRectangle(cornerRadius: 10).fill(character.primary).frame(width: 66, height: 20).offset(y: 2)
            Circle().fill(character.accent).frame(width: 14, height: 14).offset(y: -16)
            CuteFace(eyeY: 14, mouthY: 26)
        }
    }
}

private struct IceCreamCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 34, height: 46).rotationEffect(.degrees(180)).offset(y: 24)
            Circle().fill(character.primary).frame(width: 42, height: 42).offset(y: -4)
            Circle().fill(character.accent.opacity(0.85)).frame(width: 30, height: 30).offset(y: -22)
            CuteFace(eyeY: -6, mouthY: 6)
        }
    }
}

private struct DonutCharacterFace: View {
    var character: HomeRewardCharacter

    private var hole: Color { Color(red: 0.98, green: 0.96, blue: 0.92) }

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 72, height: 72).offset(y: 2)
            Circle().fill(character.secondary).frame(width: 72, height: 40).offset(y: -8)
                .mask(Circle().frame(width: 72, height: 72).offset(y: 2))
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -14, y: -12)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 16, y: -6)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 0, y: -18)
            Circle().fill(hole).frame(width: 26, height: 26).offset(y: 4)
            CuteFace(eyeY: 0, mouthY: 18)
        }
    }
}

private struct RiceBallCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(character.primary).frame(width: 70, height: 64).offset(y: 2)
            RoundedRectangle(cornerRadius: 3).fill(character.secondary).frame(width: 42, height: 24).offset(y: 24)
            CuteFace(eyeColor: character.secondary, mouthColor: character.secondary, eyeY: -4, mouthY: 8)
        }
    }
}

private struct SushiCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(character.secondary).frame(width: 60, height: 30).offset(y: 16)
            RoundedRectangle(cornerRadius: 13).fill(character.primary).frame(width: 62, height: 28).offset(y: -6)
            RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.4)).frame(width: 62, height: 4).offset(y: -10)
            CuteFace(eyeColor: .white.opacity(0.92), mouthColor: .white.opacity(0.85), eyeY: -8, mouthY: 2)
        }
    }
}

private struct HamburgerCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(character.primary).frame(width: 64, height: 18).offset(y: 22)
            RoundedRectangle(cornerRadius: 5).fill(character.accent).frame(width: 64, height: 12).offset(y: 8)
            RoundedRectangle(cornerRadius: 6).fill(character.secondary).frame(width: 70, height: 10).offset(y: -1)
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 20)
                .fill(character.primary).frame(width: 66, height: 30).offset(y: -18)
            Circle().fill(.white.opacity(0.7)).frame(width: 5, height: 5).offset(x: -12, y: -22)
            Circle().fill(.white.opacity(0.7)).frame(width: 5, height: 5).offset(x: 6, y: -26)
            Circle().fill(.white.opacity(0.7)).frame(width: 5, height: 5).offset(x: 18, y: -20)
            CuteFace(eyeY: -16, mouthY: -6)
        }
    }
}

// MARK: - Sports equipment (スポーツ)

private struct SoccerBallCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.secondary).frame(width: 76, height: 76).offset(y: 2)
            Circle().stroke(character.accent.opacity(0.3), lineWidth: 2).frame(width: 76, height: 76).offset(y: 2)
            Pentagon().fill(character.accent).frame(width: 22, height: 22).offset(y: 2)
            ForEach(0..<5) { index in
                Pentagon().fill(character.accent)
                    .frame(width: 13, height: 13)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
        }
    }
}

private struct BaseballCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.secondary).frame(width: 74, height: 74).offset(y: 2)
            Circle().stroke(character.primary.opacity(0.25), lineWidth: 2).frame(width: 74, height: 74).offset(y: 2)
            Capsule().fill(character.accent).frame(width: 4, height: 42).rotationEffect(.degrees(18)).offset(x: -22, y: 2)
            Capsule().fill(character.accent).frame(width: 4, height: 42).rotationEffect(.degrees(-18)).offset(x: 22, y: 2)
        }
    }
}

private struct BasketballCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 74, height: 74).offset(y: 2)
            Rectangle().fill(character.accent).frame(width: 74, height: 2.5).offset(y: 2)
            Rectangle().fill(character.accent).frame(width: 2.5, height: 74).offset(y: 2)
            Circle().stroke(character.accent, lineWidth: 2.5).frame(width: 100, height: 74).offset(x: -52, y: 2)
            Circle().stroke(character.accent, lineWidth: 2.5).frame(width: 100, height: 74).offset(x: 52, y: 2)
            Circle().stroke(character.accent.opacity(0.5), lineWidth: 2).frame(width: 74, height: 74).offset(y: 2)
        }
        .mask(Circle().frame(width: 74, height: 74).offset(y: 2))
    }
}

private struct TennisBallCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 72, height: 72).offset(y: 2)
            Circle().stroke(character.accent, lineWidth: 3).frame(width: 96, height: 72).offset(x: -46, y: 2)
            Circle().stroke(character.accent, lineWidth: 3).frame(width: 96, height: 72).offset(x: 46, y: 2)
        }
        .mask(Circle().frame(width: 72, height: 72).offset(y: 2))
    }
}

private struct TrophyCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().stroke(character.primary, lineWidth: 6).frame(width: 26, height: 30).offset(x: -27, y: -8)
            Circle().stroke(character.primary, lineWidth: 6).frame(width: 26, height: 30).offset(x: 27, y: -8)
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 6)
                .fill(character.primary).frame(width: 50, height: 46).offset(y: -8)
            Rectangle().fill(character.primary).frame(width: 10, height: 16).offset(y: 18)
            RoundedRectangle(cornerRadius: 3).fill(character.accent).frame(width: 38, height: 12).offset(y: 30)
            StarShape().fill(character.secondary).frame(width: 20, height: 20).offset(y: -10)
        }
    }
}

private struct Pentagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<5 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / 5
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - World landmarks (せかいのたてもの)

private struct EiffelCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            EiffelShape().fill(character.primary).frame(width: 78, height: 92).offset(y: 4)
            Rectangle().fill(character.secondary).frame(width: 44, height: 5).offset(y: 6)
            Rectangle().fill(character.secondary).frame(width: 26, height: 4).offset(y: -16)
            Rectangle().fill(character.accent).frame(width: 3, height: 14).offset(y: -46)
        }
    }
}

private struct TokyoTowerCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 7, height: 86).rotationEffect(.degrees(9)).offset(x: -11, y: 6)
            Capsule().fill(character.primary).frame(width: 7, height: 86).rotationEffect(.degrees(-9)).offset(x: 11, y: 6)
            ForEach(0..<4) { index in
                Rectangle().fill(character.primary)
                    .frame(width: CGFloat(40 - index * 7), height: 4)
                    .offset(y: CGFloat(24 - index * 16))
            }
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 30, height: 10).offset(y: 2)
            Rectangle().fill(character.accent).frame(width: 4, height: 20).offset(y: -46)
        }
    }
}

private struct LibertyCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.primary).frame(width: 42, height: 58).offset(y: 22)
            Capsule().fill(character.primary).frame(width: 7, height: 28).rotationEffect(.degrees(22)).offset(x: 17, y: -14)
            Circle().fill(character.accent).frame(width: 13, height: 13).offset(x: 24, y: -32)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 14, height: 11).offset(x: -15, y: 0)
            Circle().fill(character.primary).frame(width: 18, height: 18).offset(y: -16)
            ForEach(0..<5) { index in
                Triangle().fill(character.primary)
                    .frame(width: 5, height: 12)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index - 2) * 17))
            }
        }
    }
}

private struct PyramidCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.accent).frame(width: 20, height: 20).offset(x: 28, y: -30)
            Triangle().fill(character.primary).frame(width: 94, height: 70).offset(y: 14)
            Triangle().fill(character.secondary.opacity(0.45)).frame(width: 47, height: 70).offset(x: -23, y: 14)
            Rectangle().fill(character.accent.opacity(0.5)).frame(width: 96, height: 5).offset(y: 48)
        }
    }
}

private struct PisaCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(character.primary).frame(width: 28, height: 84)
            ForEach(0..<5) { index in
                Rectangle().fill(character.accent.opacity(0.35))
                    .frame(width: 28, height: 2)
                    .offset(y: CGFloat(-28 + index * 14))
            }
            Circle().fill(character.secondary).frame(width: 28, height: 16).offset(y: -40)
        }
        .rotationEffect(.degrees(12))
        .offset(x: 4, y: 2)
    }
}

private struct BigBenCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.accent).frame(width: 36, height: 26).offset(y: -38)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 34, height: 80).offset(y: 8)
            Circle().fill(.white).frame(width: 18, height: 18).offset(y: -10)
            Rectangle().fill(character.accent).frame(width: 2, height: 7).offset(y: -12)
            Rectangle().fill(character.accent).frame(width: 6, height: 2).offset(x: 2, y: -10)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 42, height: 10).offset(y: 44)
        }
    }
}

private struct TajMahalCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 7, height: 58).offset(x: -34, y: 10)
            Capsule().fill(character.secondary).frame(width: 7, height: 58).offset(x: 34, y: 10)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 74, height: 32).offset(y: 24)
            Circle().fill(character.primary).frame(width: 16, height: 16).offset(x: -24, y: 4)
            Circle().fill(character.primary).frame(width: 16, height: 16).offset(x: 24, y: 4)
            Circle().fill(character.primary).frame(width: 36, height: 36).offset(y: -4)
            Triangle().fill(character.primary).frame(width: 14, height: 16).offset(y: -26)
            Rectangle().fill(character.accent.opacity(0.55)).frame(width: 12, height: 18).offset(y: 30)
        }
    }
}

private struct FujiCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.accent.opacity(0.8)).frame(width: 20, height: 20).offset(x: 30, y: -26)
            Triangle().fill(character.primary).frame(width: 98, height: 66).offset(y: 16)
            Triangle().fill(.white).frame(width: 40, height: 26).offset(y: -8)
            Rectangle().fill(character.secondary).frame(width: 98, height: 6).offset(y: 47)
        }
    }
}

private struct ToriiCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.primary).frame(width: 11, height: 72).offset(x: -22, y: 8)
            Rectangle().fill(character.primary).frame(width: 11, height: 72).offset(x: 22, y: 8)
            Rectangle().fill(character.accent).frame(width: 78, height: 6).offset(y: -34)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 72, height: 11).offset(y: -26)
            Rectangle().fill(character.primary).frame(width: 58, height: 8).offset(y: -10)
        }
    }
}

private struct MoaiCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 20)
                .fill(character.primary).frame(width: 52, height: 80).offset(y: 6)
            Rectangle().fill(character.accent.opacity(0.28)).frame(width: 52, height: 9).offset(y: -16)
            Rectangle().fill(character.accent.opacity(0.5)).frame(width: 13, height: 8).offset(x: -10, y: -6)
            Rectangle().fill(character.accent.opacity(0.5)).frame(width: 13, height: 8).offset(x: 10, y: -6)
            RoundedRectangle(cornerRadius: 3).fill(character.secondary.opacity(0.6)).frame(width: 12, height: 24).offset(y: 8)
        }
    }
}

private struct WindmillCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.primary).frame(width: 48, height: 60).offset(y: 20)
            Triangle().fill(character.accent).frame(width: 32, height: 18).offset(y: -12)
            RoundedRectangle(cornerRadius: 4).fill(character.accent).frame(width: 12, height: 18).offset(y: 34)
            Capsule().fill(character.secondary).frame(width: 8, height: 72).rotationEffect(.degrees(45)).offset(y: -8)
            Capsule().fill(character.secondary).frame(width: 8, height: 72).rotationEffect(.degrees(-45)).offset(y: -8)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(y: -8)
        }
    }
}

private struct ColosseumCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 88, height: 62).offset(y: 8)
            Ellipse().fill(character.secondary).frame(width: 54, height: 34).offset(y: 16)
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.5))
                    .frame(width: 7, height: 12)
                    .offset(x: CGFloat(-32 + index * 13), y: -8)
            }
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.4))
                    .frame(width: 7, height: 10)
                    .offset(x: CGFloat(-32 + index * 13), y: 8)
            }
            Rectangle().fill(character.primary).frame(width: 88, height: 8).offset(y: 32)
        }
        .mask(
            ZStack {
                Ellipse().frame(width: 88, height: 62).offset(y: 8)
                Rectangle().frame(width: 88, height: 32).offset(y: 22)
            }
        )
    }
}

// MARK: - World landmarks (batch 2)

private struct GreatWallCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 60, height: 48).offset(x: -28, y: 34)
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 70, height: 52).offset(x: 30, y: 36)
            Capsule().fill(character.primary).frame(width: 96, height: 20).rotationEffect(.degrees(-9)).offset(y: 6)
            ForEach(0..<7) { index in
                Rectangle().fill(character.primary)
                    .frame(width: 8, height: 9)
                    .rotationEffect(.degrees(-9))
                    .offset(x: CGFloat(-40 + index * 13), y: CGFloat(-3 + index))
            }
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 18, height: 30).offset(x: -30, y: -2)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 18, height: 26).offset(x: 26, y: 8)
            Rectangle().fill(character.accent.opacity(0.5)).frame(width: 8, height: 12).offset(x: -30, y: 2)
        }
    }
}

private struct OperaHouseCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary).frame(width: 90, height: 22).offset(y: 30)
            SailShape().fill(character.primary).frame(width: 30, height: 40).offset(x: -22, y: 8)
            SailShape().fill(character.primary).frame(width: 36, height: 52).offset(x: -6, y: 2)
            SailShape().fill(character.primary).frame(width: 30, height: 44).scaleEffect(x: -1, y: 1).offset(x: 16, y: 6)
            SailShape().fill(character.primary).frame(width: 22, height: 34).scaleEffect(x: -1, y: 1).offset(x: 30, y: 12)
            Rectangle().fill(character.accent.opacity(0.3)).frame(width: 84, height: 3).offset(y: 22)
        }
    }
}

private struct StonehengeCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.secondary.opacity(0.6)).frame(width: 98, height: 8).offset(y: 38)
            Group {
                Rectangle().fill(character.primary).frame(width: 12, height: 44).offset(x: -30, y: 14)
                Rectangle().fill(character.primary).frame(width: 12, height: 44).offset(x: -12, y: 14)
                RoundedRectangle(cornerRadius: 2).fill(character.accent).frame(width: 32, height: 11).offset(x: -21, y: -10)
            }
            Group {
                Rectangle().fill(character.primary).frame(width: 13, height: 56).offset(x: 14, y: 8)
                Rectangle().fill(character.primary).frame(width: 13, height: 56).offset(x: 34, y: 8)
                RoundedRectangle(cornerRadius: 2).fill(character.accent).frame(width: 36, height: 12).offset(x: 24, y: -22)
            }
            Rectangle().fill(character.primary).frame(width: 9, height: 30).offset(x: 2, y: 22)
        }
    }
}

private struct ChristRedeemerCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.accent.opacity(0.6)).frame(width: 30, height: 16).offset(y: 38)
            Trapezoid().fill(character.primary).frame(width: 34, height: 50).offset(y: 18)
            Capsule().fill(character.primary).frame(width: 76, height: 11).offset(y: -8)
            Circle().fill(character.primary).frame(width: 16, height: 16).offset(y: -22)
        }
    }
}

private struct SagradaCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 70, height: 30).offset(y: 26)
            SpireShape().fill(character.primary).frame(width: 16, height: 64).offset(x: -28, y: 2)
            SpireShape().fill(character.primary).frame(width: 18, height: 78).offset(x: -12, y: -6)
            SpireShape().fill(character.secondary).frame(width: 20, height: 90).offset(y: -12)
            SpireShape().fill(character.primary).frame(width: 18, height: 78).offset(x: 12, y: -6)
            SpireShape().fill(character.primary).frame(width: 16, height: 64).offset(x: 28, y: 2)
            ForEach(0..<5) { index in
                Circle().fill(character.accent.opacity(0.5)).frame(width: 5, height: 5)
                    .offset(x: CGFloat(-28 + index * 14), y: CGFloat([6, -2, -8, -2, 6][index]))
            }
        }
    }
}

private struct GoldenGateCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.6)).frame(width: 98, height: 18).offset(y: 36)
            Rectangle().fill(character.primary).frame(width: 96, height: 6).offset(y: 14)
            Rectangle().fill(character.primary).frame(width: 9, height: 70).offset(x: -28, y: -2)
            Rectangle().fill(character.primary).frame(width: 9, height: 70).offset(x: 28, y: -2)
            Triangle().fill(.clear).overlay(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 6)); p.addQuadCurve(to: CGPoint(x: 56, y: 6), control: CGPoint(x: 28, y: 40))
                }.stroke(character.primary, lineWidth: 3)
            ).frame(width: 56, height: 40).offset(y: -16)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 6)); p.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 15, y: 30))
            }.stroke(character.primary, lineWidth: 3).frame(width: 30, height: 30).offset(x: -42, y: -8)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 6)); p.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 15, y: 30))
            }.stroke(character.primary, lineWidth: 3).frame(width: 30, height: 30).offset(x: 42, y: -8)
        }
    }
}

private struct TowerBridgeCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.6)).frame(width: 96, height: 16).offset(y: 36)
            Rectangle().fill(character.accent).frame(width: 96, height: 6).offset(y: 22)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0)); p.addQuadCurve(to: CGPoint(x: 44, y: 0), control: CGPoint(x: 22, y: 22))
            }.stroke(character.accent, lineWidth: 3).frame(width: 44, height: 20).offset(y: 2)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 22, height: 60).offset(x: -22, y: 4)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 22, height: 60).offset(x: 22, y: 4)
            Triangle().fill(character.accent).frame(width: 22, height: 16).offset(x: -22, y: -32)
            Triangle().fill(character.accent).frame(width: 22, height: 16).offset(x: 22, y: -32)
            Rectangle().fill(character.secondary).frame(width: 22, height: 9).offset(x: -22, y: -6)
            Rectangle().fill(character.secondary).frame(width: 22, height: 9).offset(x: 22, y: -6)
        }
    }
}

private struct FerrisWheelCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.accent).frame(width: 7, height: 54).rotationEffect(.degrees(18)).offset(x: -10, y: 22)
            Rectangle().fill(character.accent).frame(width: 7, height: 54).rotationEffect(.degrees(-18)).offset(x: 10, y: 22)
            Circle().stroke(character.primary, lineWidth: 4).frame(width: 76, height: 76).offset(y: -4)
            ForEach(0..<8) { index in
                Rectangle().fill(character.primary).frame(width: 2.5, height: 72)
                    .rotationEffect(.degrees(Double(index) * 22.5)).offset(y: -4)
            }
            ForEach(0..<8) { index in
                Circle().fill(character.secondary).frame(width: 11, height: 11)
                    .offset(y: -42).rotationEffect(.degrees(Double(index) * 45)).offset(y: 0)
            }
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(y: -4)
        }
    }
}

private struct KinkakuCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.accent).frame(width: 26, height: 16).offset(y: -34)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(y: -42)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 30, height: 22).offset(y: -18)
            Trapezoid().fill(character.secondary).frame(width: 50, height: 14).offset(y: -24).rotationEffect(.degrees(180))
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 44, height: 22).offset(y: 0)
            Trapezoid().fill(character.secondary).frame(width: 64, height: 16).offset(y: -6).rotationEffect(.degrees(180))
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 58, height: 24).offset(y: 22)
            Trapezoid().fill(character.secondary).frame(width: 74, height: 16).offset(y: 14).rotationEffect(.degrees(180))
            Rectangle().fill(character.accent.opacity(0.5)).frame(width: 58, height: 4).offset(y: 34)
        }
    }
}

private struct SphinxCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.secondary.opacity(0.7)).frame(width: 60, height: 50).offset(x: 18, y: -4)
            Capsule().fill(character.primary).frame(width: 78, height: 30).offset(x: -2, y: 24)
            Triangle().fill(character.primary).frame(width: 22, height: 22).rotationEffect(.degrees(-90)).offset(x: -42, y: 22)
            RoundedRectangle(cornerRadius: 6).fill(character.primary).frame(width: 30, height: 34).offset(x: -22, y: -2)
            Trapezoid().fill(character.accent.opacity(0.55)).frame(width: 36, height: 26).offset(x: -22, y: -8)
            Circle().fill(character.accent.opacity(0.7)).frame(width: 5, height: 5).offset(x: -28, y: 0)
        }
    }
}

private struct AngkorCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 84, height: 22).offset(y: 28)
            CornSpireShape().fill(character.secondary).frame(width: 22, height: 56).offset(x: -34, y: 4)
            CornSpireShape().fill(character.secondary).frame(width: 22, height: 56).offset(x: 34, y: 4)
            CornSpireShape().fill(character.primary).frame(width: 26, height: 70).offset(x: -18, y: -4)
            CornSpireShape().fill(character.primary).frame(width: 26, height: 70).offset(x: 18, y: -4)
            CornSpireShape().fill(character.secondary).frame(width: 30, height: 86).offset(y: -12)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 84, height: 4).offset(y: 38)
        }
    }
}

private struct MatterhornCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            PeakShape().fill(character.primary).frame(width: 92, height: 84).offset(y: 8)
            PeakShape().fill(character.accent.opacity(0.35)).frame(width: 46, height: 84).offset(x: 23, y: 8)
            PeakShape().fill(character.secondary).frame(width: 38, height: 32).offset(x: 5, y: -22)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 94, height: 5).offset(y: 46)
        }
    }
}

private struct SailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SpireShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let neck = rect.maxY - rect.width * 0.7
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: neck))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: neck))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CornSpireShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shoulder = rect.maxY - rect.height * 0.40
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: shoulder), control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.24, y: rect.minY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - World landmarks (batch 3)

private struct LibertyBellCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(character.accent).frame(width: 14, height: 8).offset(y: -34)
            BellShape().fill(character.primary).frame(width: 62, height: 60).offset(y: 6)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 66, height: 8).offset(y: 32)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(y: 40)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 5, y: 9))
                p.addLine(to: CGPoint(x: -3, y: 18))
                p.addLine(to: CGPoint(x: 4, y: 27))
            }.stroke(character.accent.opacity(0.6), lineWidth: 2.5).frame(width: 12, height: 27).offset(x: 6, y: 10)
        }
    }
}

private struct WhiteHouseCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 84, height: 40).offset(y: 22)
            ForEach(0..<6) { index in
                Rectangle().fill(character.secondary).frame(width: 6, height: 32)
                    .offset(x: CGFloat(-30 + index * 12), y: 24)
            }
            Rectangle().fill(character.primary).frame(width: 86, height: 8).offset(y: 4)
            Triangle().fill(character.primary).frame(width: 46, height: 16).offset(y: -8)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 20, height: 14).offset(y: -22)
            Circle().fill(character.primary).frame(width: 14, height: 14).offset(y: -28)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 88, height: 4).offset(y: 42)
        }
    }
}

private struct NotreDameCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 24, height: 74).offset(x: -24, y: 6)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 24, height: 74).offset(x: 24, y: 6)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 34, height: 56).offset(y: 16)
            Circle().fill(character.secondary).frame(width: 18, height: 18).offset(y: 4)
            Circle().fill(character.primary).frame(width: 8, height: 8).offset(y: 4)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.5)).frame(width: 8, height: 12).offset(x: -24, y: -4)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.5)).frame(width: 8, height: 12).offset(x: 24, y: -4)
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(character.accent).frame(width: 14, height: 22).offset(y: 32)
        }
    }
}

private struct BurjKhalifaCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            BurjShape().fill(character.primary).frame(width: 46, height: 96).offset(y: 2)
            BurjShape().fill(character.secondary.opacity(0.5)).frame(width: 23, height: 96).offset(x: 11, y: 2)
            Rectangle().fill(character.accent).frame(width: 3, height: 22).offset(y: -48)
            ForEach(0..<5) { index in
                Rectangle().fill(character.accent.opacity(0.3)).frame(width: 30, height: 1.5)
                    .offset(y: CGFloat(-20 + index * 14))
            }
        }
    }
}

private struct ArchTriompheCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 70, height: 70).offset(y: 6)
            UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13).fill(character.secondary).frame(width: 26, height: 46).offset(y: 18)
            Rectangle().fill(character.accent.opacity(0.45)).frame(width: 74, height: 9).offset(y: -22)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.3)).frame(width: 12, height: 14).offset(x: -24, y: -2)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.3)).frame(width: 12, height: 14).offset(x: 24, y: -2)
        }
    }
}

// MARK: - Japan landmarks (にほんのめいしょ)

private struct SkytreeCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 6, height: 42).rotationEffect(.degrees(13)).offset(x: -9, y: 24)
            Capsule().fill(character.primary).frame(width: 6, height: 42).rotationEffect(.degrees(-13)).offset(x: 9, y: 24)
            Rectangle().fill(character.primary).frame(width: 9, height: 90).offset(y: 0)
            Ellipse().fill(character.secondary).frame(width: 24, height: 11).offset(y: -6)
            Ellipse().fill(character.secondary).frame(width: 17, height: 9).offset(y: -26)
            Rectangle().fill(character.accent).frame(width: 3, height: 18).offset(y: -52)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(y: -62)
        }
    }
}

private struct JapaneseCastleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.accent.opacity(0.45)).frame(width: 72, height: 24).offset(y: 30)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 52, height: 18).offset(y: 18)
            RoofShape().fill(character.secondary).frame(width: 66, height: 15).offset(y: 9)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 38, height: 16).offset(y: -2)
            RoofShape().fill(character.secondary).frame(width: 50, height: 13).offset(y: -8)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 24, height: 14).offset(y: -18)
            RoofShape().fill(character.secondary).frame(width: 34, height: 11).offset(y: -23)
            Rectangle().fill(character.accent).frame(width: 4, height: 7).offset(y: -31)
        }
    }
}

private struct PagodaCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.accent).frame(width: 4, height: 26).offset(y: -34)
            ForEach(0..<5) { index in
                let y = CGFloat(26 - index * 14)
                let bodyW = CGFloat(34 - index * 4)
                let roofW = CGFloat(48 - index * 7)
                RoundedRectangle(cornerRadius: 2).fill(character.primary)
                    .frame(width: bodyW, height: 11).offset(y: y)
                RoofShape().fill(character.secondary)
                    .frame(width: roofW, height: 10).offset(y: y - 8)
            }
        }
    }
}

private struct DaibutsuCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Trapezoid().fill(character.primary).frame(width: 66, height: 42).offset(y: 26)
            Capsule().fill(character.secondary.opacity(0.45)).frame(width: 30, height: 10).offset(y: 18)
            Circle().fill(character.primary).frame(width: 32, height: 38).offset(y: -8)
            Circle().fill(character.primary).frame(width: 12, height: 12).offset(y: -26)
            Circle().fill(character.accent.opacity(0.5)).frame(width: 5, height: 4).offset(x: -6, y: -10)
            Circle().fill(character.accent.opacity(0.5)).frame(width: 5, height: 4).offset(x: 6, y: -10)
            Capsule().fill(character.accent.opacity(0.4)).frame(width: 10, height: 3).offset(y: -2)
        }
    }
}

private struct GasshouCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 44, height: 18).offset(y: 32)
            Triangle().fill(character.primary).frame(width: 78, height: 76).offset(y: 6)
            Rectangle().fill(character.accent.opacity(0.35)).frame(width: 2, height: 70).offset(y: 6)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.5)).frame(width: 12, height: 9).offset(x: -10, y: 30)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.5)).frame(width: 12, height: 9).offset(x: 10, y: 30)
            RoundedRectangle(cornerRadius: 2).fill(character.accent.opacity(0.4)).frame(width: 12, height: 8).offset(y: 8)
        }
    }
}

private struct BellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - w * 0.10, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w * 0.10, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX + w * 0.18, y: rect.minY + h * 0.55)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - w * 0.10, y: rect.minY),
            control: CGPoint(x: rect.midX - w * 0.18, y: rect.minY + h * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

private struct RoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.30, y: rect.minY),
            control: CGPoint(x: rect.minX + w * 0.10, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.30, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - w * 0.10, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct BurjShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addLine(to: CGPoint(x: cx + w * 0.16, y: rect.minY + h * 0.30))
        path.addLine(to: CGPoint(x: cx + w * 0.26, y: rect.minY + h * 0.30))
        path.addLine(to: CGPoint(x: cx + w * 0.40, y: rect.minY + h * 0.66))
        path.addLine(to: CGPoint(x: cx + w * 0.50, y: rect.minY + h * 0.66))
        path.addLine(to: CGPoint(x: cx + w * 0.50, y: rect.maxY))
        path.addLine(to: CGPoint(x: cx - w * 0.50, y: rect.maxY))
        path.addLine(to: CGPoint(x: cx - w * 0.50, y: rect.minY + h * 0.66))
        path.addLine(to: CGPoint(x: cx - w * 0.40, y: rect.minY + h * 0.66))
        path.addLine(to: CGPoint(x: cx - w * 0.26, y: rect.minY + h * 0.30))
        path.addLine(to: CGPoint(x: cx - w * 0.16, y: rect.minY + h * 0.30))
        path.closeSubpath()
        return path
    }
}

// MARK: - World & Japan landmarks (batch 4)

private struct StBasilCharacterView: View {
    var character: HomeRewardCharacter
    private let domeRed = Color(red: 0.85, green: 0.27, blue: 0.22)
    private let domeBlue = Color(red: 0.22, green: 0.46, blue: 0.76)
    private let domeGreen = Color(red: 0.27, green: 0.62, blue: 0.42)
    private let domeGold = Color(red: 0.92, green: 0.72, blue: 0.22)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 72, height: 30).offset(y: 26)
            Rectangle().fill(character.secondary).frame(width: 13, height: 30).offset(x: -25, y: 14)
            OnionDomeShape().fill(domeRed).frame(width: 22, height: 26).offset(x: -25, y: -6)
            Rectangle().fill(character.secondary).frame(width: 13, height: 30).offset(x: 25, y: 14)
            OnionDomeShape().fill(domeBlue).frame(width: 22, height: 26).offset(x: 25, y: -6)
            OnionDomeShape().fill(domeGreen).frame(width: 15, height: 19).offset(x: -13, y: 8)
            OnionDomeShape().fill(domeGold).frame(width: 15, height: 19).offset(x: 13, y: 8)
            Rectangle().fill(character.secondary).frame(width: 18, height: 40).offset(y: 6)
            Triangle().fill(character.accent).frame(width: 22, height: 20).offset(y: -16)
            OnionDomeShape().fill(domeGold).frame(width: 12, height: 16).offset(y: -32)
        }
    }
}

private struct ParthenonCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 84, height: 24).offset(y: -26)
            Rectangle().fill(character.primary).frame(width: 86, height: 10).offset(y: -11)
            ForEach(0..<6) { index in
                Rectangle().fill(character.secondary).frame(width: 8, height: 40)
                    .offset(x: CGFloat(-35 + index * 14), y: 14)
            }
            Rectangle().fill(character.primary).frame(width: 92, height: 8).offset(y: 36)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 96, height: 5).offset(y: 42)
        }
    }
}

private struct MachuPicchuCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.accent.opacity(0.55)).frame(width: 52, height: 64).offset(x: 20, y: -6)
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.primary)
                    .frame(width: CGFloat(72 - index * 13), height: 12)
                    .offset(y: CGFloat(32 - index * 12))
            }
            Rectangle().fill(character.secondary).frame(width: 8, height: 11).offset(x: -10, y: -4)
            Rectangle().fill(character.secondary).frame(width: 8, height: 9).offset(x: 4, y: -6)
            Rectangle().fill(character.secondary).frame(width: 7, height: 8).offset(x: -20, y: 8)
        }
    }
}

private struct MosqueCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 8, height: 66).offset(x: -34, y: 6)
            Capsule().fill(character.secondary).frame(width: 8, height: 66).offset(x: 34, y: 6)
            Circle().fill(character.primary).frame(width: 11, height: 11).offset(x: -34, y: -28)
            Circle().fill(character.primary).frame(width: 11, height: 11).offset(x: 34, y: -28)
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 66, height: 30).offset(y: 24)
            Circle().fill(character.primary).frame(width: 46, height: 46).offset(y: 2)
            Image(systemName: "moon.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(character.accent)
                .offset(y: -28)
            RoundedRectangle(cornerRadius: 6).fill(character.accent.opacity(0.5)).frame(width: 16, height: 22).offset(y: 28)
        }
    }
}

private struct MontStMichelCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.accent.opacity(0.4)).frame(width: 84, height: 18).offset(y: 36)
            Triangle().fill(character.primary).frame(width: 70, height: 66).offset(y: 10)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 42, height: 14).offset(y: 24)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 26, height: 12).offset(y: 8)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 15, height: 12).offset(y: -6)
            Triangle().fill(character.primary).frame(width: 10, height: 22).offset(y: -24)
            Circle().fill(character.accent).frame(width: 5, height: 5).offset(y: -36)
        }
    }
}

private struct CapitolCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 90, height: 28).offset(y: 26)
            ForEach(0..<7) { index in
                Rectangle().fill(character.secondary).frame(width: 5, height: 22)
                    .offset(x: CGFloat(-30 + index * 10), y: 26)
            }
            Triangle().fill(character.primary).frame(width: 32, height: 12).offset(y: 10)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 34, height: 18).offset(y: 6)
            Circle().fill(character.primary).frame(width: 38, height: 38).offset(y: -10)
            Rectangle().fill(character.accent).frame(width: 3, height: 12).offset(y: -32)
            Circle().fill(character.accent).frame(width: 5, height: 5).offset(y: -38)
        }
    }
}

private struct PetraCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(character.accent.opacity(0.3)).frame(width: 80, height: 90).offset(y: 4)
            Triangle().fill(character.primary).frame(width: 18, height: 11).offset(x: -22, y: -20)
            Triangle().fill(character.primary).frame(width: 18, height: 11).offset(x: 22, y: -20)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 22, height: 26).offset(y: -16)
            Triangle().fill(character.secondary).frame(width: 22, height: 9).offset(y: -30)
            Rectangle().fill(character.primary).frame(width: 64, height: 8).offset(y: 4)
            ForEach(0..<4) { index in
                Rectangle().fill(character.primary).frame(width: 7, height: 32)
                    .offset(x: CGFloat(-21 + index * 14), y: 24)
            }
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(character.accent).frame(width: 13, height: 26).offset(y: 26)
        }
    }
}

private struct KiyomizuCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                Rectangle().fill(character.accent).frame(width: 5, height: 34)
                    .offset(x: CGFloat(-24 + index * 16), y: 28)
            }
            Rectangle().fill(character.accent.opacity(0.7)).frame(width: 72, height: 3).offset(y: 20)
            Rectangle().fill(character.accent.opacity(0.7)).frame(width: 72, height: 3).offset(y: 34)
            Rectangle().fill(character.primary).frame(width: 76, height: 8).offset(y: 9)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 50, height: 16).offset(y: -3)
            RoofShape().fill(character.secondary).frame(width: 68, height: 16).offset(y: -14)
        }
    }
}

private struct TokyoStationCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 88, height: 36).offset(y: 18)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 30, height: 18).offset(y: 0)
            Circle().fill(character.secondary).frame(width: 24, height: 24).offset(x: -32, y: -2)
            Circle().fill(character.secondary).frame(width: 24, height: 24).offset(x: 32, y: -2)
            Triangle().fill(character.secondary).frame(width: 11, height: 9).offset(x: -32, y: -16)
            Triangle().fill(character.secondary).frame(width: 11, height: 9).offset(x: 32, y: -16)
            Rectangle().fill(character.accent.opacity(0.6)).frame(width: 88, height: 2).offset(y: 10)
            Rectangle().fill(character.accent.opacity(0.6)).frame(width: 88, height: 2).offset(y: 26)
            ForEach(0..<5) { index in
                Rectangle().fill(character.accent.opacity(0.5)).frame(width: 6, height: 8)
                    .offset(x: CGFloat(-24 + index * 12), y: 18)
            }
        }
    }
}

private struct TempleHallCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 92, height: 8).offset(y: 35)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 72, height: 26).offset(y: 18)
            ForEach(0..<5) { index in
                Rectangle().fill(character.accent).frame(width: 5, height: 24)
                    .offset(x: CGFloat(-28 + index * 14), y: 18)
            }
            RoofShape().fill(character.secondary).frame(width: 96, height: 28).offset(y: -8)
            RoofShape().fill(character.secondary).frame(width: 60, height: 16).offset(y: -26)
            Capsule().fill(domeGold).frame(width: 5, height: 12).offset(x: -16, y: -20)
            Capsule().fill(domeGold).frame(width: 5, height: 12).offset(x: 16, y: -20)
        }
    }

    private var domeGold: Color { Color(red: 0.86, green: 0.68, blue: 0.20) }
}

private struct OnionDomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX - w * 0.12, y: rect.minY + h * 0.45),
            control2: CGPoint(x: rect.midX - w * 0.10, y: rect.minY + h * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.midX + w * 0.10, y: rect.minY + h * 0.08),
            control2: CGPoint(x: rect.maxX + w * 0.12, y: rect.minY + h * 0.45)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Landmarks (batch 5)

private struct DuomoCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 78, height: 30).offset(y: 26)
            RoundedRectangle(cornerRadius: 3).fill(character.secondary).frame(width: 16, height: 60).offset(x: -32, y: 8)
            Triangle().fill(character.accent).frame(width: 18, height: 14).offset(x: -32, y: -26)
            Circle().fill(character.accent).frame(width: 50, height: 50).offset(y: 2)
                .mask(Rectangle().frame(width: 54, height: 30).offset(y: -10))
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 44, height: 16).offset(y: 14)
            Triangle().fill(character.secondary).frame(width: 12, height: 14).offset(y: -26)
            Circle().fill(character.secondary).frame(width: 7, height: 7).offset(y: -34)
        }
    }
}

private struct EuroCastleCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 20, height: 70).offset(x: -28, y: 4)
            Triangle().fill(character.accent).frame(width: 26, height: 22).offset(x: -28, y: -34)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 16, height: 56).offset(x: 26, y: 12)
            Triangle().fill(character.accent).frame(width: 22, height: 18).offset(x: 26, y: -22)
            RoundedRectangle(cornerRadius: 3).fill(character.primary).frame(width: 40, height: 48).offset(y: 16)
            Triangle().fill(character.accent).frame(width: 30, height: 22).offset(y: -10)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary.opacity(0.6)).frame(width: 9, height: 14).offset(x: -8, y: 14)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary.opacity(0.6)).frame(width: 9, height: 14).offset(x: 8, y: 14)
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(character.accent).frame(width: 12, height: 18).offset(y: 30)
        }
    }
}

private struct MayanPyramidCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.primary)
                    .frame(width: CGFloat(86 - index * 18), height: 14)
                    .offset(y: CGFloat(28 - index * 14))
            }
            Rectangle().fill(character.secondary).frame(width: 14, height: 56).offset(y: 0)
            RoundedRectangle(cornerRadius: 2).fill(character.primary).frame(width: 22, height: 12).offset(y: -28)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 90, height: 5).offset(y: 38)
        }
    }
}

private struct SkyscraperCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 4).fill(character.primary).frame(width: 26, height: 92).offset(x: -10, y: 2)
            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 8).fill(character.secondary).frame(width: 20, height: 70).offset(x: 14, y: 13)
            ForEach(0..<6) { index in
                Rectangle().fill(character.accent.opacity(0.3)).frame(width: 22, height: 2)
                    .offset(x: -10, y: CGFloat(-30 + index * 13))
            }
            Rectangle().fill(character.accent).frame(width: 2.5, height: 16).offset(x: -10, y: -52)
        }
    }
}

private struct StarFortCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            StarShape(points: 5).fill(character.secondary.opacity(0.6)).frame(width: 96, height: 96).offset(y: 2)
            StarShape(points: 5).fill(character.primary).frame(width: 74, height: 74).offset(y: 2)
            StarShape(points: 5).fill(character.accent.opacity(0.35)).frame(width: 40, height: 40).offset(y: 2)
        }
    }
}

// MARK: - Instruments (がっき)

private struct GuitarCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.accent).frame(width: 9, height: 64).rotationEffect(.degrees(32)).offset(x: 18, y: -20)
            RoundedRectangle(cornerRadius: 3).fill(character.secondary).frame(width: 16, height: 12).rotationEffect(.degrees(32)).offset(x: 32, y: -42)
            Circle().fill(character.primary).frame(width: 42, height: 42).offset(x: -12, y: 22)
            Circle().fill(character.primary).frame(width: 52, height: 52).offset(x: -18, y: 30)
            Circle().fill(character.accent.opacity(0.7)).frame(width: 18, height: 18).offset(x: -16, y: 26)
            Circle().fill(character.secondary).frame(width: 9, height: 9).offset(x: -16, y: 26)
        }
    }
}

private struct PianoCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(character.primary).frame(width: 80, height: 34).offset(y: -8)
            RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 72, height: 22).offset(y: 18)
            ForEach(0..<7) { index in
                Rectangle().fill(character.accent).frame(width: 1.5, height: 22).offset(x: CGFloat(-30 + index * 10), y: 18)
            }
            ForEach(0..<6) { index in
                Rectangle().fill(.black).frame(width: 5, height: 13).offset(x: CGFloat(-25 + index * 10), y: 13)
            }
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 80, height: 6).offset(y: 3)
        }
    }
}

private struct DrumCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 5, height: 56).rotationEffect(.degrees(34)).offset(x: -2, y: -22)
            Capsule().fill(character.accent).frame(width: 5, height: 56).rotationEffect(.degrees(-34)).offset(x: 2, y: -22)
            RoundedRectangle(cornerRadius: 6).fill(character.primary).frame(width: 72, height: 40).offset(y: 14)
            Ellipse().fill(character.secondary).frame(width: 72, height: 22).offset(y: -4)
            Path { p in
                for i in 0..<6 {
                    let x = -30 + i * 12
                    p.move(to: CGPoint(x: CGFloat(x), y: 4))
                    p.addLine(to: CGPoint(x: CGFloat(x + 6), y: 30))
                }
            }.stroke(character.accent, lineWidth: 2).frame(width: 72, height: 34).offset(y: 14)
        }
    }
}

private struct TrumpetCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 56, height: 12).offset(x: -8, y: -8)
            TrumpetBellShape().fill(character.primary).frame(width: 34, height: 44).offset(x: 22, y: 8)
            Capsule().fill(character.primary).frame(width: 12, height: 30).offset(x: -30, y: 6)
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 2).fill(character.accent).frame(width: 6, height: 16)
                    .offset(x: CGFloat(-14 + index * 12), y: -16)
            }
            Capsule().fill(character.secondary).frame(width: 8, height: 8).offset(x: -36, y: 6)
        }
    }
}

private struct ViolinCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(character.accent).frame(width: 9, height: 56).rotationEffect(.degrees(-28)).offset(x: 18, y: -22)
            Circle().fill(character.secondary).frame(width: 14, height: 14).offset(x: 30, y: -42)
            ViolinBodyShape().fill(character.primary).frame(width: 44, height: 64).rotationEffect(.degrees(-28)).offset(x: -8, y: 16)
            Rectangle().fill(character.accent).frame(width: 4, height: 40).rotationEffect(.degrees(-28)).offset(x: -8, y: 14)
        }
    }
}

private struct TrumpetBellShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.14))
        path.closeSubpath()
        return path
    }
}

private struct ViolinBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: w, height: h * 0.5))
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY + h * 0.45, width: w, height: h * 0.55))
        path.addRect(CGRect(x: rect.minX + w * 0.30, y: rect.minY + h * 0.30, width: w * 0.40, height: h * 0.40))
        return path
    }
}

// MARK: - Insects (むし)

private struct ButterflyCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 36, height: 36).offset(x: -22, y: -16)
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: -20, y: 18)
            Circle().fill(character.primary).frame(width: 36, height: 36).offset(x: 22, y: -16)
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: 20, y: 18)
            Circle().fill(character.secondary.opacity(0.7)).frame(width: 14, height: 14).offset(x: -22, y: -16)
            Circle().fill(character.secondary.opacity(0.7)).frame(width: 14, height: 14).offset(x: 22, y: -16)
            Capsule().fill(character.accent).frame(width: 9, height: 50).offset(y: 0)
            Capsule().fill(character.accent).frame(width: 2, height: 12).rotationEffect(.degrees(20)).offset(x: 5, y: -30)
            Capsule().fill(character.accent).frame(width: 2, height: 12).rotationEffect(.degrees(-20)).offset(x: -5, y: -30)
            CharacterEyes(color: .white).offset(y: -22)
        }
    }
}

private struct BeetleCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Capsule().fill(character.accent).frame(width: 4, height: 18).rotationEffect(.degrees(-40)).offset(x: -30, y: CGFloat(-4 + index * 14))
                Capsule().fill(character.accent).frame(width: 4, height: 18).rotationEffect(.degrees(40)).offset(x: 30, y: CGFloat(-4 + index * 14))
            }
            Triangle().fill(character.accent).frame(width: 10, height: 26).offset(y: -34)
            Ellipse().fill(character.primary).frame(width: 56, height: 70).offset(y: 6)
            Rectangle().fill(character.accent.opacity(0.4)).frame(width: 2, height: 56).offset(y: 12)
            Circle().fill(character.secondary.opacity(0.6)).frame(width: 18, height: 18).offset(y: -10)
            CharacterEyes(color: .black.opacity(0.78)).offset(y: -14)
        }
    }
}

private struct LadybugCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.accent).frame(width: 28, height: 24).offset(y: -22)
            CharacterEyes(color: .white).offset(y: -24)
            Circle().fill(character.primary).frame(width: 70, height: 64).offset(y: 8)
            Rectangle().fill(character.accent).frame(width: 2.5, height: 64).offset(y: 8)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -16, y: 0)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 16, y: 0)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: -14, y: 20)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: 14, y: 20)
        }
    }
}

private struct BeeCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 30, height: 22).offset(x: -18, y: -10)
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 30, height: 22).offset(x: 18, y: -10)
            Ellipse().fill(character.primary).frame(width: 58, height: 52).offset(y: 8)
            Rectangle().fill(character.accent).frame(width: 58, height: 7).offset(y: 0)
            Rectangle().fill(character.accent).frame(width: 50, height: 7).offset(y: 16)
            Triangle().fill(character.accent).frame(width: 14, height: 12).rotationEffect(.degrees(180)).offset(y: 34)
            CharacterEyes(color: .black.opacity(0.78)).offset(y: -8)
        }
    }
}

private struct AntCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Capsule().fill(character.accent).frame(width: 3, height: 18).rotationEffect(.degrees(-35)).offset(x: -14, y: CGFloat(2 + index * 9))
                Capsule().fill(character.accent).frame(width: 3, height: 18).rotationEffect(.degrees(35)).offset(x: 14, y: CGFloat(2 + index * 9))
            }
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: 24, y: 14)
            Circle().fill(character.primary).frame(width: 24, height: 24).offset(y: 6)
            Circle().fill(character.primary).frame(width: 28, height: 28).offset(x: -24, y: -4)
            Capsule().fill(character.accent).frame(width: 2, height: 12).rotationEffect(.degrees(25)).offset(x: -30, y: -20)
            Capsule().fill(character.accent).frame(width: 2, height: 12).rotationEffect(.degrees(-25)).offset(x: -36, y: -18)
            CharacterEyes(color: .white).offset(x: -24, y: -6)
        }
    }
}

// MARK: - Dinosaurs (きょうりゅう)

private struct TrexCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 22, height: 50).rotationEffect(.degrees(40)).offset(x: 30, y: 18)
            Capsule().fill(character.primary).frame(width: 24, height: 40).rotationEffect(.degrees(-20)).offset(x: -8, y: 22)
            Circle().fill(character.primary).frame(width: 46, height: 44).offset(x: -14, y: -8)
            RoundedRectangle(cornerRadius: 6).fill(character.primary).frame(width: 30, height: 22).offset(x: -30, y: 2)
            Path { p in
                for i in 0..<4 { p.move(to: CGPoint(x: CGFloat(i*7), y: 0)); p.addLine(to: CGPoint(x: CGFloat(i*7+3), y: 6)); p.addLine(to: CGPoint(x: CGFloat(i*7+6), y: 0)) }
            }.fill(.white).frame(width: 24, height: 6).offset(x: -34, y: 10)
            Capsule().fill(character.secondary).frame(width: 8, height: 16).rotationEffect(.degrees(20)).offset(x: 0, y: 14)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -20, y: -12)
        }
    }
}

private struct TriceratopsCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.secondary).frame(width: 64, height: 58).offset(x: 6, y: -8)
            ForEach(0..<7) { index in
                Triangle().fill(character.accent.opacity(0.6)).frame(width: 8, height: 10)
                    .offset(y: -32).rotationEffect(.degrees(Double(index - 3) * 22))
                    .offset(x: 6, y: 0)
            }
            Circle().fill(character.primary).frame(width: 50, height: 46).offset(x: -8, y: 8)
            Capsule().fill(character.primary).frame(width: 22, height: 18).offset(x: -28, y: 16)
            Triangle().fill(character.secondary).frame(width: 7, height: 16).offset(x: -8, y: -10)
            Triangle().fill(character.secondary).frame(width: 5, height: 11).offset(x: -32, y: 6)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -10, y: 6)
        }
    }
}

private struct StegosaurusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Triangle().fill(character.secondary)
                    .frame(width: 18, height: 20)
                    .offset(x: CGFloat(-24 + index * 12), y: CGFloat(-22 + abs(index - 2) * 4))
            }
            Ellipse().fill(character.primary).frame(width: 78, height: 40).offset(y: 6)
            Circle().fill(character.primary).frame(width: 26, height: 24).offset(x: -34, y: 6)
            Capsule().fill(character.primary).frame(width: 30, height: 9).rotationEffect(.degrees(-18)).offset(x: 36, y: 0)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -34, y: 4)
        }
    }
}

private struct BrachiosaurusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 64, height: 38).offset(y: 18)
            Capsule().fill(character.primary).frame(width: 18, height: 64).rotationEffect(.degrees(-16)).offset(x: -16, y: -14)
            Circle().fill(character.primary).frame(width: 26, height: 24).offset(x: -26, y: -38)
            Capsule().fill(character.primary).frame(width: 26, height: 10).rotationEffect(.degrees(14)).offset(x: 32, y: 16)
            Circle().fill(character.secondary.opacity(0.5)).frame(width: 12, height: 12).offset(x: 6, y: 16)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -28, y: -40)
        }
    }
}

private struct PteranodonCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 52, height: 30).rotationEffect(.degrees(-58)).offset(x: -22, y: 2)
            Triangle().fill(character.primary).frame(width: 52, height: 30).rotationEffect(.degrees(58)).offset(x: 22, y: 2)
            Capsule().fill(character.primary).frame(width: 16, height: 34).offset(y: 10)
            Circle().fill(character.primary).frame(width: 22, height: 20).offset(y: -16)
            Triangle().fill(character.secondary).frame(width: 26, height: 10).rotationEffect(.degrees(-90)).offset(x: -14, y: -20)
            Triangle().fill(character.accent).frame(width: 22, height: 9).rotationEffect(.degrees(90)).offset(x: 14, y: -12)
            CharacterEyes(color: .black.opacity(0.8)).offset(y: -16)
        }
    }
}

// MARK: - Space (うちゅう)

private struct AstronautCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(character.primary).frame(width: 54, height: 56).offset(y: 24)
            Capsule().fill(character.primary).frame(width: 16, height: 30).rotationEffect(.degrees(28)).offset(x: -30, y: 22)
            Capsule().fill(character.primary).frame(width: 16, height: 30).rotationEffect(.degrees(-28)).offset(x: 30, y: 22)
            Circle().fill(character.primary).frame(width: 60, height: 60).offset(y: -10)
            Circle().fill(character.accent).frame(width: 44, height: 44).offset(y: -10)
            Capsule().fill(.white.opacity(0.45)).frame(width: 9, height: 18).rotationEffect(.degrees(28)).offset(x: -8, y: -16)
            RoundedRectangle(cornerRadius: 2).fill(character.secondary).frame(width: 14, height: 8).offset(y: 24)
        }
    }
}

private struct UfoCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Triangle().fill(character.accent.opacity(0.25)).frame(width: 50, height: 36).rotationEffect(.degrees(180)).offset(y: 34)
            Circle().fill(character.secondary).frame(width: 40, height: 40).offset(y: -8)
                .mask(Rectangle().frame(width: 44, height: 24).offset(y: -10))
            Ellipse().fill(character.primary).frame(width: 88, height: 30).offset(y: 6)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: -24, y: 8)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(y: 10)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 24, y: 8)
            Capsule().fill(.white.opacity(0.5)).frame(width: 12, height: 7).offset(x: -6, y: -14)
        }
    }
}

private struct SaturnCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.accent.opacity(0.7)).frame(width: 104, height: 30).rotationEffect(.degrees(-18))
            Circle().fill(character.primary).frame(width: 60, height: 60)
            Ellipse().fill(character.secondary.opacity(0.4)).frame(width: 40, height: 12).rotationEffect(.degrees(-12)).offset(y: -10)
            CuteFace(eyeY: -2, mouthY: 12)
        }
    }
}

private struct MoonCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 76, height: 76).offset(y: 2)
            Circle().fill(character.accent.opacity(0.35)).frame(width: 16, height: 16).offset(x: -16, y: -12)
            Circle().fill(character.accent.opacity(0.35)).frame(width: 11, height: 11).offset(x: 18, y: 10)
            Circle().fill(character.accent.opacity(0.35)).frame(width: 8, height: 8).offset(x: 6, y: 22)
            CuteFace(eyeColor: character.accent.opacity(0.7), mouthColor: character.accent.opacity(0.7), eyeY: -2, mouthY: 12)
        }
    }
}

private struct AlienCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 3, height: 16).rotationEffect(.degrees(20)).offset(x: -10, y: -38)
            Capsule().fill(character.primary).frame(width: 3, height: 16).rotationEffect(.degrees(-20)).offset(x: 10, y: -38)
            Circle().fill(character.primary).frame(width: 12, height: 12).offset(x: -14, y: -44)
            Circle().fill(character.primary).frame(width: 12, height: 12).offset(x: 14, y: -44)
            Capsule().fill(character.primary).frame(width: 40, height: 30).offset(y: 26)
            Ellipse().fill(character.primary).frame(width: 60, height: 66).offset(y: -6)
            Ellipse().fill(character.accent).frame(width: 18, height: 24).rotationEffect(.degrees(20)).offset(x: -13, y: -6)
            Ellipse().fill(character.accent).frame(width: 18, height: 24).rotationEffect(.degrees(-20)).offset(x: 13, y: -6)
            SmileArc().stroke(character.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 16, height: 7).offset(y: 14)
        }
    }
}

// MARK: - Aliens (batch 2: モードS 宇宙人)

private struct AlienBlobCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 14, height: 12).offset(x: -16, y: 40)
            Capsule().fill(character.primary).frame(width: 14, height: 12).offset(x: 16, y: 40)
            Capsule().fill(character.primary).frame(width: 4, height: 16).offset(y: -38)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(y: -46)
            Ellipse().fill(character.primary).frame(width: 80, height: 74).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 46, height: 40).offset(y: 22)
            Circle().fill(.white).frame(width: 44, height: 44).offset(y: -4)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(y: -3)
            Circle().fill(.black).frame(width: 12, height: 12).offset(y: -3)
            Circle().fill(.white).frame(width: 5, height: 5).offset(x: 5, y: -7)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 24)
        }
    }
}

private struct AlienTriclopsCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 10, height: 26).rotationEffect(.degrees(22)).offset(x: -32, y: 20)
            Capsule().fill(character.primary).frame(width: 10, height: 26).rotationEffect(.degrees(-22)).offset(x: 32, y: 20)
            Capsule().fill(character.secondary).frame(width: 46, height: 42).offset(y: 32)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(18)).offset(x: -12, y: -38)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(-18)).offset(x: 12, y: -38)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: -15, y: -44)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 15, y: -44)
            Circle().fill(character.primary).frame(width: 68, height: 60).offset(y: -6)
            ForEach(-1...1, id: \.self) { i in
                Circle().fill(.white).frame(width: 17, height: 19).offset(x: CGFloat(i) * 19, y: -8)
                Circle().fill(.black).frame(width: 8, height: 8).offset(x: CGFloat(i) * 19, y: -6)
            }
            SmileArc().stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 16, height: 7).offset(y: 12)
        }
    }
}

private struct AlienSquidCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(i % 2 == 0 ? character.primary : character.secondary)
                    .frame(width: 9, height: 30)
                    .rotationEffect(.degrees(Double(i - 2) * 9))
                    .offset(x: CGFloat(i - 2) * 14, y: 34)
            }
            Ellipse().fill(character.primary).frame(width: 84, height: 70).offset(y: -6)
            Ellipse().fill(character.secondary).frame(width: 84, height: 26).offset(y: 16)
                .mask(Ellipse().frame(width: 84, height: 70).offset(y: -6))
            Circle().fill(.white).frame(width: 20, height: 22).offset(x: -15, y: -8)
            Circle().fill(.white).frame(width: 20, height: 22).offset(x: 15, y: -8)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: -14, y: -6)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 16, y: -6)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 8)
        }
    }
}

private struct AlienWormCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: 14, y: 40)
            Circle().fill(character.secondary).frame(width: 11, height: 11).offset(x: 14, y: 40)
            Circle().fill(character.primary).frame(width: 36, height: 36).offset(x: -8, y: 26)
            Circle().fill(character.secondary).frame(width: 13, height: 13).offset(x: -8, y: 26)
            Circle().fill(character.primary).frame(width: 40, height: 40).offset(x: 10, y: 8)
            Circle().fill(character.secondary).frame(width: 14, height: 14).offset(x: 10, y: 8)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(20)).offset(x: -8, y: -30)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(-20)).offset(x: 8, y: -30)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: -11, y: -36)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 11, y: -36)
            Circle().fill(character.primary).frame(width: 50, height: 48).offset(x: -8, y: -14)
            Circle().fill(.white).frame(width: 13, height: 14).offset(x: -16, y: -16)
            Circle().fill(.white).frame(width: 13, height: 14).offset(x: 0, y: -16)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: -16, y: -15)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: 0, y: -15)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 13, height: 6).offset(x: -8, y: -3)
        }
    }
}

private struct AlienMushroomCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 46, height: 54).offset(y: 24)
            Ellipse().fill(character.primary).frame(width: 92, height: 60).offset(y: -18)
            Circle().fill(character.accent).frame(width: 14, height: 14).offset(x: -24, y: -22)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 6, y: -30)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 26, y: -16)
            Circle().fill(.white).frame(width: 15, height: 16).offset(x: -11, y: 18)
            Circle().fill(.white).frame(width: 15, height: 16).offset(x: 11, y: 18)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: -11, y: 19)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: 11, y: 19)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 14, height: 6).offset(y: 32)
        }
    }
}

private struct AlienBugeyeCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 9, height: 24).rotationEffect(.degrees(24)).offset(x: -28, y: 20)
            Capsule().fill(character.primary).frame(width: 9, height: 24).rotationEffect(.degrees(-24)).offset(x: 28, y: 20)
            Capsule().fill(character.secondary).frame(width: 46, height: 44).offset(y: 30)
            Circle().fill(character.primary).frame(width: 48, height: 44).offset(y: -2)
            Capsule().fill(character.primary).frame(width: 6, height: 22).offset(x: -14, y: -28)
            Capsule().fill(character.primary).frame(width: 6, height: 22).offset(x: 14, y: -28)
            Circle().fill(.white).frame(width: 26, height: 26).offset(x: -14, y: -40)
            Circle().fill(.white).frame(width: 26, height: 26).offset(x: 14, y: -40)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -12, y: -39)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 16, y: -39)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: -12, y: -39)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: 16, y: -39)
            SmileArc().stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 16, height: 7).offset(y: 6)
        }
    }
}

private struct AlienCrystalCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(character.secondary).frame(width: 26, height: 26).rotationEffect(.degrees(45)).offset(x: -34, y: 28)
            RoundedRectangle(cornerRadius: 10).fill(character.secondary).frame(width: 22, height: 22).rotationEffect(.degrees(45)).offset(x: 34, y: 30)
            RoundedRectangle(cornerRadius: 16).fill(character.primary).frame(width: 74, height: 74).rotationEffect(.degrees(45)).offset(y: -2)
            Capsule().fill(character.secondary.opacity(0.6)).frame(width: 3, height: 30).rotationEffect(.degrees(45)).offset(x: -10, y: -2)
            Capsule().fill(character.secondary.opacity(0.6)).frame(width: 3, height: 30).rotationEffect(.degrees(-45)).offset(x: 10, y: -2)
            Circle().fill(.white).frame(width: 14, height: 15).offset(x: -11, y: -4)
            Circle().fill(.white).frame(width: 14, height: 15).offset(x: 11, y: -4)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: -11, y: -3)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: 11, y: -3)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 14, height: 6).offset(y: 12)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: 22, y: -26)
        }
    }
}

private struct AlienHoverCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.5)).frame(width: 54, height: 16).offset(y: 42)
            Capsule().fill(character.primary).frame(width: 3, height: 14).offset(y: -42)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(y: -50)
            Circle().fill(character.primary).frame(width: 74, height: 70).offset(y: -2)
            Ellipse().fill(character.secondary).frame(width: 70, height: 18).offset(y: 24)
                .mask(Circle().frame(width: 74, height: 70).offset(y: -2))
            Capsule().fill(.black.opacity(0.82)).frame(width: 58, height: 24).offset(y: -4)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -12, y: -4)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 12, y: -4)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: -14, y: -6)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: 10, y: -6)
        }
    }
}

// MARK: - Dinosaurs (batch 2)

private struct VelociraptorCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 40, height: 11).rotationEffect(.degrees(16)).offset(x: 30, y: 4)
            Ellipse().fill(character.primary).frame(width: 38, height: 30).offset(x: 4, y: 2)
            Capsule().fill(character.primary).frame(width: 11, height: 28).offset(x: 10, y: 24)
            Capsule().fill(character.primary).frame(width: 11, height: 24).offset(x: -2, y: 24)
            Triangle().fill(character.accent).frame(width: 9, height: 6).rotationEffect(.degrees(-90)).offset(x: -12, y: 36)
            Capsule().fill(character.secondary).frame(width: 8, height: 16).rotationEffect(.degrees(40)).offset(x: -6, y: 10)
            Capsule().fill(character.primary).frame(width: 13, height: 26).rotationEffect(.degrees(-34)).offset(x: -16, y: -10)
            Circle().fill(character.primary).frame(width: 22, height: 20).offset(x: -28, y: -18)
            Capsule().fill(character.primary).frame(width: 18, height: 10).rotationEffect(.degrees(-10)).offset(x: -38, y: -14)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -28, y: -20)
        }
    }
}

private struct AnkylosaurusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 30, height: 12).rotationEffect(.degrees(-8)).offset(x: 34, y: 2)
            Circle().fill(character.accent).frame(width: 20, height: 20).offset(x: 44, y: 0)
            Ellipse().fill(character.primary).frame(width: 76, height: 46).offset(y: 8)
            ForEach(0..<5) { index in
                Triangle().fill(character.secondary)
                    .frame(width: 13, height: 12)
                    .offset(x: CGFloat(-24 + index * 11), y: CGFloat(-16 + abs(index - 2) * 2))
            }
            Circle().fill(character.primary).frame(width: 26, height: 22).offset(x: -34, y: 12)
            Triangle().fill(character.secondary).frame(width: 8, height: 7).offset(x: -40, y: 4)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -34, y: 10)
        }
    }
}

private struct SpinosaurusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            SailShape().fill(character.secondary).frame(width: 60, height: 46).scaleEffect(x: -1, y: 1).offset(x: 6, y: -8)
            ForEach(0..<4) { index in
                Rectangle().fill(character.accent.opacity(0.4)).frame(width: 2, height: CGFloat(20 + index * 4))
                    .offset(x: CGFloat(-8 + index * 12), y: -14)
            }
            Capsule().fill(character.primary).frame(width: 40, height: 12).rotationEffect(.degrees(18)).offset(x: 30, y: 18)
            Ellipse().fill(character.primary).frame(width: 40, height: 30).offset(x: 0, y: 14)
            Capsule().fill(character.primary).frame(width: 12, height: 24).offset(x: 6, y: 30)
            Capsule().fill(character.primary).frame(width: 14, height: 22).rotationEffect(.degrees(-26)).offset(x: -18, y: 0)
            Circle().fill(character.primary).frame(width: 20, height: 18).offset(x: -28, y: -8)
            Capsule().fill(character.primary).frame(width: 22, height: 9).rotationEffect(.degrees(-8)).offset(x: -40, y: -4)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -28, y: -10)
        }
    }
}

private struct ParasaurolophusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 40, height: 11).rotationEffect(.degrees(20)).offset(x: 30, y: 8)
            Ellipse().fill(character.primary).frame(width: 38, height: 32).offset(x: 6, y: 6)
            Capsule().fill(character.primary).frame(width: 12, height: 26).offset(x: 8, y: 28)
            Capsule().fill(character.primary).frame(width: 12, height: 24).offset(x: -4, y: 28)
            Capsule().fill(character.primary).frame(width: 15, height: 30).rotationEffect(.degrees(-34)).offset(x: -16, y: -4)
            Circle().fill(character.primary).frame(width: 22, height: 20).offset(x: -28, y: -16)
            Capsule().fill(character.primary).frame(width: 16, height: 9).rotationEffect(.degrees(-16)).offset(x: -38, y: -14)
            Capsule().fill(character.accent).frame(width: 9, height: 40).rotationEffect(.degrees(36)).offset(x: -14, y: -28)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: -28, y: -18)
        }
    }
}

private struct PlesiosaurusCharacterFace: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 64, height: 30).offset(y: 18)
            Triangle().fill(character.primary).frame(width: 22, height: 14).rotationEffect(.degrees(-50)).offset(x: -22, y: 26)
            Triangle().fill(character.primary).frame(width: 22, height: 14).rotationEffect(.degrees(50)).offset(x: 20, y: 26)
            Capsule().fill(character.primary).frame(width: 16, height: 60).rotationEffect(.degrees(-18)).offset(x: 14, y: -10)
            Circle().fill(character.primary).frame(width: 22, height: 20).offset(x: 24, y: -34)
            Capsule().fill(character.primary).frame(width: 14, height: 9).offset(x: 33, y: -34)
            Ellipse().fill(character.secondary.opacity(0.5)).frame(width: 40, height: 10).offset(y: 28)
            CharacterEyes(color: .black.opacity(0.8)).offset(x: 24, y: -36)
        }
    }
}

// MARK: - New companions (batch: animals / sea / birds / bugs / food)

private struct MouseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 38, height: 38).offset(x: -28, y: -24)
            Circle().fill(character.primary).frame(width: 38, height: 38).offset(x: 28, y: -24)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: -28, y: -24)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: 28, y: -24)
            Circle().fill(character.primary).frame(width: 70, height: 70).offset(y: 8)
            Circle().fill(character.secondary).frame(width: 34, height: 26).offset(y: 20)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 9, height: 7).offset(y: 16)
            WhiskerLines(color: character.secondary.opacity(0.9))
        }
    }
}

private struct CowCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 12, height: 18).rotationEffect(.degrees(-24)).offset(x: -20, y: -40)
            Capsule().fill(character.accent).frame(width: 12, height: 18).rotationEffect(.degrees(24)).offset(x: 20, y: -40)
            Ellipse().fill(character.primary).frame(width: 32, height: 22).offset(x: -36, y: -16)
            Ellipse().fill(character.primary).frame(width: 32, height: 22).offset(x: 36, y: -16)
            Circle().fill(character.primary).frame(width: 76, height: 72).offset(y: 6)
            Circle().fill(character.accent).frame(width: 26, height: 22).offset(x: -22, y: -10)
            Ellipse().fill(character.secondary).frame(width: 46, height: 34).offset(y: 22)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 7, height: 7).offset(x: -9, y: 22)
            Circle().fill(character.accent).frame(width: 7, height: 7).offset(x: 9, y: 22)
        }
    }
}

private struct HorseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 20, height: 26).rotationEffect(.degrees(-10)).offset(x: -20, y: -38)
            Triangle().fill(character.primary).frame(width: 20, height: 26).rotationEffect(.degrees(10)).offset(x: 20, y: -38)
            Capsule().fill(character.accent).frame(width: 16, height: 30).offset(y: -28)
            Ellipse().fill(character.primary).frame(width: 56, height: 80).offset(y: 6)
            Capsule().fill(character.accent).frame(width: 12, height: 16).offset(y: -30)
            Ellipse().fill(character.secondary).frame(width: 40, height: 38).offset(y: 30)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -8, y: 34)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 8, y: 34)
        }
    }
}

private struct WolfCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 30, height: 36).rotationEffect(.degrees(-14)).offset(x: -26, y: -32)
            Triangle().fill(character.primary).frame(width: 30, height: 36).rotationEffect(.degrees(14)).offset(x: 26, y: -32)
            Circle().fill(character.primary).frame(width: 76, height: 74).offset(y: 6)
            Triangle().fill(character.secondary).frame(width: 26, height: 24).rotationEffect(.degrees(-20)).offset(x: -28, y: 10)
            Triangle().fill(character.secondary).frame(width: 26, height: 24).rotationEffect(.degrees(20)).offset(x: 28, y: 10)
            Circle().fill(character.secondary).frame(width: 40, height: 40).offset(y: 18)
            Triangle().fill(character.primary).frame(width: 26, height: 22).rotationEffect(.degrees(180)).offset(y: 10)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 9, height: 8).offset(y: 16)
        }
    }
}

private struct KangarooCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 18, height: 44).rotationEffect(.degrees(-12)).offset(x: -22, y: -34)
            Capsule().fill(character.primary).frame(width: 18, height: 44).rotationEffect(.degrees(12)).offset(x: 22, y: -34)
            Capsule().fill(character.accent).frame(width: 9, height: 28).rotationEffect(.degrees(-12)).offset(x: -22, y: -32)
            Capsule().fill(character.accent).frame(width: 9, height: 28).rotationEffect(.degrees(12)).offset(x: 22, y: -32)
            Ellipse().fill(character.primary).frame(width: 60, height: 72).offset(y: 6)
            Ellipse().fill(character.secondary).frame(width: 34, height: 40).offset(y: 24)
            CharacterEyes(color: .black.opacity(0.78))
            Triangle().fill(character.accent).frame(width: 12, height: 9).rotationEffect(.degrees(180)).offset(y: 18)
        }
    }
}

private struct BatCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 46, height: 40).rotationEffect(.degrees(-90)).offset(x: -38, y: 0)
            Triangle().fill(character.primary).frame(width: 46, height: 40).rotationEffect(.degrees(90)).offset(x: 38, y: 0)
            Triangle().fill(character.primary).frame(width: 22, height: 24).offset(x: -16, y: -32)
            Triangle().fill(character.primary).frame(width: 22, height: 24).offset(x: 16, y: -32)
            Circle().fill(character.secondary).frame(width: 60, height: 56).offset(y: 4)
            CharacterEyes(color: character.accent)
            Triangle().fill(.white).frame(width: 7, height: 8).rotationEffect(.degrees(180)).offset(x: -7, y: 16)
            Triangle().fill(.white).frame(width: 7, height: 8).rotationEffect(.degrees(180)).offset(x: 7, y: 16)
        }
    }
}

private struct GoatCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 12, height: 30).rotationEffect(.degrees(-30)).offset(x: -18, y: -40)
            Capsule().fill(character.accent).frame(width: 12, height: 30).rotationEffect(.degrees(30)).offset(x: 18, y: -40)
            Ellipse().fill(character.secondary).frame(width: 30, height: 18).rotationEffect(.degrees(-20)).offset(x: -34, y: -8)
            Ellipse().fill(character.secondary).frame(width: 30, height: 18).rotationEffect(.degrees(20)).offset(x: 34, y: -8)
            Ellipse().fill(character.primary).frame(width: 62, height: 70).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 36, height: 34).offset(y: 22)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -8, y: 22)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 8, y: 22)
            Capsule().fill(character.secondary).frame(width: 13, height: 15).offset(y: 42)
        }
    }
}

private struct OtterCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 22, height: 22).offset(x: -28, y: -22)
            Circle().fill(character.primary).frame(width: 22, height: 22).offset(x: 28, y: -22)
            Circle().fill(character.primary).frame(width: 72, height: 70).offset(y: 8)
            Circle().fill(character.secondary).frame(width: 30, height: 28).offset(x: -13, y: 18)
            Circle().fill(character.secondary).frame(width: 30, height: 28).offset(x: 13, y: 18)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 12, height: 9).offset(y: 12)
            WhiskerLines(color: character.accent.opacity(0.6))
        }
    }
}

private struct OrcaCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 22, height: 26).offset(x: 2, y: -30)
            Triangle().fill(character.primary).frame(width: 26, height: 22).rotationEffect(.degrees(-90)).offset(x: 38, y: -2)
            Ellipse().fill(character.primary).frame(width: 74, height: 50).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 44, height: 22).offset(y: 18)
            Ellipse().fill(character.secondary).frame(width: 14, height: 10).offset(x: -16, y: -8)
            Circle().fill(.black.opacity(0.85)).frame(width: 7, height: 7).offset(x: -16, y: -8)
            Circle().fill(.black.opacity(0.85)).frame(width: 7, height: 7).offset(x: 4, y: -6)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: -8, y: 8)
        }
    }
}

private struct SeahorseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 12, height: 10).offset(x: -2, y: -42)
            Triangle().fill(character.secondary).frame(width: 12, height: 10).offset(x: 8, y: -40)
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: -2, y: -28)
            Capsule().fill(character.secondary).frame(width: 16, height: 14).rotationEffect(.degrees(-30)).offset(x: -18, y: -30)
            Capsule().fill(character.primary).frame(width: 30, height: 50).offset(x: 2, y: 4)
            ForEach(0..<3) { i in
                Triangle().fill(character.secondary).frame(width: 12, height: 10).rotationEffect(.degrees(-90)).offset(x: 20, y: CGFloat(-8 + i * 16))
            }
            Circle().fill(character.primary).frame(width: 24, height: 24).offset(x: -8, y: 34)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 2, y: -30)
            Circle().fill(.white).frame(width: 3, height: 3).offset(x: 4, y: -32)
        }
    }
}

private struct ShrimpCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Rectangle().fill(character.accent).frame(width: 2, height: 30).rotationEffect(.degrees(20)).offset(x: -34, y: -22)
            Rectangle().fill(character.accent).frame(width: 2, height: 38).rotationEffect(.degrees(34)).offset(x: -32, y: -16)
            Triangle().fill(character.secondary).frame(width: 26, height: 30).rotationEffect(.degrees(140)).offset(x: 34, y: 18)
            ForEach(0..<5) { i in
                Circle().fill(character.primary)
                    .frame(width: CGFloat(38 - i * 4), height: CGFloat(38 - i * 4))
                    .offset(x: CGFloat(-22 + i * 13), y: CGFloat(i * i) * 1.1 - 2)
            }
            Circle().fill(.black.opacity(0.82)).frame(width: 8, height: 8).offset(x: -22, y: -8)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 10, height: 5).offset(x: -20, y: 6)
        }
    }
}

private struct DuckCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 16, height: 20).rotationEffect(.degrees(20)).offset(x: 16, y: -36)
            Circle().fill(character.primary).frame(width: 72, height: 70).offset(y: 2)
            Ellipse().fill(character.secondary).frame(width: 40, height: 26).offset(y: 24)
            CharacterEyes(color: .black.opacity(0.82))
            Ellipse().fill(character.accent).frame(width: 40, height: 18).offset(y: 16)
            Ellipse().fill(character.accent.opacity(0.6)).frame(width: 40, height: 7).offset(y: 21)
        }
    }
}

private struct BirdCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            // しっぽ
            Capsule().fill(character.primary).frame(width: 13, height: 24)
                .rotationEffect(.degrees(-34)).offset(x: -33, y: 20)
            // からだ
            Circle().fill(character.primary).frame(width: 66, height: 66).offset(y: 4)
            // おなか
            Ellipse().fill(character.secondary).frame(width: 36, height: 42).offset(y: 14)
            // つばさ
            Ellipse().fill(character.secondary.opacity(0.8)).frame(width: 24, height: 32)
                .rotationEffect(.degrees(16)).offset(x: 21, y: 8)
            // あたまの羽
            Capsule().fill(character.primary).frame(width: 7, height: 15)
                .rotationEffect(.degrees(-16)).offset(x: -3, y: -36)
            // め
            CharacterEyes(color: .black.opacity(0.82)).offset(y: -6)
            // くちばし
            Triangle().fill(character.accent).frame(width: 15, height: 12)
                .rotationEffect(.degrees(180)).offset(y: 4)
        }
    }
}

private struct FlamingoCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 58, height: 44).offset(y: 22)
            Ellipse().fill(character.secondary).frame(width: 30, height: 24).offset(x: 8, y: 28)
            Capsule().fill(character.primary).frame(width: 18, height: 56).rotationEffect(.degrees(20)).offset(x: -14, y: -18)
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: -24, y: -38)
            Triangle().fill(character.accent).frame(width: 20, height: 14).rotationEffect(.degrees(-110)).offset(x: -38, y: -34)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -26, y: -42)
        }
    }
}

private struct ParrotCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 18, height: 24).rotationEffect(.degrees(-18)).offset(x: -6, y: -36)
            Circle().fill(character.primary).frame(width: 70, height: 70).offset(y: 2)
            Ellipse().fill(character.secondary).frame(width: 30, height: 44).offset(x: 24, y: 14)
            Circle().fill(character.accent.opacity(0.55)).frame(width: 18, height: 18).offset(x: -22, y: 8)
            CharacterEyes(color: .black.opacity(0.82))
            Circle().fill(character.accent).frame(width: 22, height: 18).offset(y: 16)
            Triangle().fill(character.accent).frame(width: 16, height: 16).rotationEffect(.degrees(180)).offset(y: 24)
        }
    }
}

private struct SwanCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 66, height: 46).offset(y: 22)
            Ellipse().fill(character.secondary).frame(width: 36, height: 30).offset(x: 14, y: 22)
            Capsule().fill(character.primary).frame(width: 16, height: 54).rotationEffect(.degrees(-18)).offset(x: -12, y: -16)
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: -22, y: -38)
            Triangle().fill(character.accent).frame(width: 18, height: 12).rotationEffect(.degrees(-110)).offset(x: -36, y: -36)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -24, y: -42)
        }
    }
}

private struct SnailCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 76, height: 28).offset(x: -4, y: 26)
            Circle().fill(character.secondary).frame(width: 34, height: 34).offset(x: -34, y: 14)
            Rectangle().fill(character.secondary).frame(width: 3, height: 18).offset(x: -42, y: -2)
            Rectangle().fill(character.secondary).frame(width: 3, height: 18).offset(x: -34, y: -4)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -42, y: -12)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -34, y: -14)
            Circle().fill(character.primary).frame(width: 64, height: 64).offset(x: 12, y: 0)
            Circle().fill(character.secondary).frame(width: 42, height: 42).offset(x: 12, y: 0)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: 12, y: 0)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: -36, y: 16)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 9, height: 4).offset(x: -34, y: 24)
        }
    }
}

private struct DragonflyCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 40, height: 16).rotationEffect(.degrees(20)).offset(x: -24, y: -14)
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 40, height: 16).rotationEffect(.degrees(-20)).offset(x: 24, y: -14)
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 34, height: 14).rotationEffect(.degrees(-18)).offset(x: -22, y: 4)
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 34, height: 14).rotationEffect(.degrees(18)).offset(x: 22, y: 4)
            Capsule().fill(character.primary).frame(width: 13, height: 66).offset(y: 10)
            Circle().fill(character.primary).frame(width: 30, height: 28).offset(y: -28)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -8, y: -30)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 8, y: -30)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: -6, y: -32)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: 10, y: -32)
        }
    }
}

private struct BananaCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 10, height: 16).rotationEffect(.degrees(-40)).offset(x: -34, y: -18)
            Capsule().fill(character.primary).frame(width: 84, height: 34).rotationEffect(.degrees(-22)).offset(y: 6)
            Capsule().fill(character.secondary).frame(width: 60, height: 14).rotationEffect(.degrees(-22)).offset(x: 4, y: 0)
            Circle().fill(character.accent.opacity(0.8)).frame(width: 9, height: 9).offset(x: 34, y: 20)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: -6, y: 2)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: 12, y: -4)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: 4, y: 6)
        }
    }
}

private struct TaiyakiCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 30, height: 30).rotationEffect(.degrees(-90)).offset(x: 36, y: 0)
            Ellipse().fill(character.primary).frame(width: 76, height: 54).offset(x: -4, y: 2)
            ForEach(0..<3) { i in
                Triangle().fill(character.secondary).frame(width: 12, height: 9).offset(x: CGFloat(-14 + i * 12), y: -26)
            }
            Ellipse().fill(character.secondary).frame(width: 50, height: 28).offset(x: -8, y: 8)
            Circle().fill(.white).frame(width: 14, height: 14).offset(x: -22, y: -6)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -22, y: -6)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: -10, y: 8)
        }
    }
}

private struct CookieCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 78, height: 78).offset(y: 4)
            Circle().fill(character.secondary).frame(width: 60, height: 60).offset(y: 4)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: -22, y: -14)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 20, y: -18)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 26, y: 16)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: -26, y: 20)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 0, y: 28)
            CharacterEyes(color: .black.opacity(0.8))
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 16)
        }
    }
}

private struct DinoEggCharacterView: View {
    var character: HomeRewardCharacter

    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 56, height: 70).offset(y: 0)
            Circle().fill(character.accent.opacity(0.4)).frame(width: 12, height: 12).offset(x: -10, y: -12)
            Circle().fill(character.accent.opacity(0.4)).frame(width: 9, height: 9).offset(x: 12, y: 8)
            Circle().fill(character.accent.opacity(0.4)).frame(width: 7, height: 7).offset(x: -6, y: 18)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 7, y: 7)); p.addLine(to: CGPoint(x: 1, y: 13)); p.addLine(to: CGPoint(x: 8, y: 20))
            }.stroke(character.secondary, lineWidth: 2.5).frame(width: 14, height: 20).offset(x: 2, y: -2)
            Capsule().fill(character.accent.opacity(0.7)).frame(width: 60, height: 14).offset(y: 34)
            Capsule().fill(character.secondary.opacity(0.7)).frame(width: 70, height: 10).offset(y: 40)
        }
    }
}

private struct EiffelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: cx + w * 0.10, y: rect.maxY - h * 0.32)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.20, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: cx + w * 0.07, y: rect.maxY - h * 0.34),
            control: CGPoint(x: cx + w * 0.15, y: rect.maxY - h * 0.20)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - w * 0.07, y: rect.maxY - h * 0.34),
            control: CGPoint(x: cx, y: rect.maxY - h * 0.24)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.20, y: rect.maxY),
            control: CGPoint(x: cx - w * 0.15, y: rect.maxY - h * 0.20)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control: CGPoint(x: cx - w * 0.10, y: rect.maxY - h * 0.32)
        )
        path.closeSubpath()
        return path
    }
}

private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return path
    }
}

private struct StarShape: Shape {
    var points: Int = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.46
        let total = points * 2
        for index in 0..<total {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let domeHeight = rect.height * 0.45
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + domeHeight))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + domeHeight),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        let waves = 4
        let step = rect.width / CGFloat(waves)
        var x = rect.maxX
        var dip = true
        for _ in 0..<waves {
            let nextX = x - step
            path.addQuadCurve(
                to: CGPoint(x: nextX, y: rect.maxY),
                control: CGPoint(x: x - step / 2, y: rect.maxY + (dip ? 10 : -8))
            )
            x = nextX
            dip.toggle()
        }
        path.closeSubpath()
        return path
    }
}

private struct CharacterEyes: View {
    var color: Color

    var body: some View {
        HStack(spacing: 24) {
            Circle().fill(color).frame(width: 7, height: 7)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .offset(y: 2)
    }
}

private struct WhiskerLines: View {
    var color: Color

    var body: some View {
        ZStack {
            Rectangle().fill(color).frame(width: 16, height: 2).offset(x: -30, y: 14)
            Rectangle().fill(color).frame(width: 16, height: 2).rotationEffect(.degrees(10)).offset(x: -30, y: 8)
            Rectangle().fill(color).frame(width: 16, height: 2).offset(x: 30, y: 14)
            Rectangle().fill(color).frame(width: 16, height: 2).rotationEffect(.degrees(-10)).offset(x: 30, y: 8)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HomeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.13, green: 0.35, blue: 0.76))
            .background(.white.opacity(configuration.isPressed ? 0.65 : 0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.54, green: 0.70, blue: 0.94).opacity(0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BearMascot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 82, height: 82)
                .offset(y: 10)

            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 28, height: 28)
                .offset(x: -30, y: -25)
            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 28, height: 28)
                .offset(x: 30, y: -25)

            Circle()
                .fill(Color(red: 0.97, green: 0.77, blue: 0.44))
                .frame(width: 46, height: 38)
                .offset(y: 18)

            Circle()
                .fill(.black.opacity(0.75))
                .frame(width: 7, height: 7)
                .offset(x: -16, y: 2)
            Circle()
                .fill(.black.opacity(0.75))
                .frame(width: 7, height: 7)
                .offset(x: 16, y: 2)
            Circle()
                .fill(.black.opacity(0.78))
                .frame(width: 9, height: 7)
                .offset(y: 14)
        }
    }
}

// MARK: - Background themes (coin-unlockable)

enum HomeBackgroundScene {
    case meadow
    case sunset
    case night
    case beach
    case snow
    case space
}

struct HomeBackgroundTheme: Identifiable {
    var id: String
    var japaneseName: String
    var englishName: String
    var price: Int
    /// Non-nil → rendered from a bundled image asset (an imageset in Assets.xcassets).
    /// Nil → rendered procedurally from `scene` + the color fields below.
    var imageName: String? = nil
    var scene: HomeBackgroundScene = .meadow
    var skyTop: Color = .clear
    var skyBottom: Color = .clear
    var groundPrimary: Color = .clear
    var groundSecondary: Color = .clear
    var accent: Color = .clear

    var isImage: Bool { imageName != nil }

    var isFree: Bool {
        price == 0
    }

    func name(language: AppLanguage) -> String {
        language.text(japanese: japaneseName, english: englishName)
    }

    static func theme(id: String) -> HomeBackgroundTheme {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    static let defaultID = "meadow"

    // オンボーディングで選べるよう、スターターとして数個を無料解放（残りはコインで解放）。
    static let defaultUnlockedIDs: Set<String> = ["meadow", "sunset", "forest", "park", "rainbow", "sakura", "candyland"]

    static let catalog: [HomeBackgroundTheme] = proceduralThemes + imageThemes

    /// Hand-drawn (SwiftUI) themes — color/scene data lives here, not in the CSV.
    static let proceduralThemes: [HomeBackgroundTheme] = [
        HomeBackgroundTheme(
            id: "meadow",
            japaneseName: "ひるのまち",
            englishName: "Meadow",
            price: 0,
            scene: .meadow,
            skyTop: Color(red: 0.90, green: 0.97, blue: 1.0),
            skyBottom: Color(red: 0.98, green: 0.99, blue: 1.0),
            groundPrimary: Color(red: 0.73, green: 0.88, blue: 0.54),
            groundSecondary: Color(red: 0.52, green: 0.80, blue: 0.73),
            accent: Color(red: 1.0, green: 0.90, blue: 0.35)
        ),
        HomeBackgroundTheme(
            id: "sunset",
            japaneseName: "ゆうやけ",
            englishName: "Sunset",
            price: 80,
            scene: .sunset,
            skyTop: Color(red: 1.0, green: 0.66, blue: 0.42),
            skyBottom: Color(red: 1.0, green: 0.88, blue: 0.78),
            groundPrimary: Color(red: 0.74, green: 0.45, blue: 0.40),
            groundSecondary: Color(red: 0.56, green: 0.36, blue: 0.42),
            accent: Color(red: 1.0, green: 0.80, blue: 0.34)
        ),
        HomeBackgroundTheme(
            id: "night",
            japaneseName: "よぞら",
            englishName: "Starry Night",
            price: 80,
            scene: .night,
            skyTop: Color(red: 0.07, green: 0.10, blue: 0.27),
            skyBottom: Color(red: 0.18, green: 0.22, blue: 0.44),
            groundPrimary: Color(red: 0.11, green: 0.17, blue: 0.31),
            groundSecondary: Color(red: 0.06, green: 0.10, blue: 0.22),
            accent: Color(red: 0.97, green: 0.96, blue: 0.86)
        ),
        HomeBackgroundTheme(
            id: "beach",
            japaneseName: "うみべ",
            englishName: "Beach",
            price: 120,
            scene: .beach,
            skyTop: Color(red: 0.53, green: 0.81, blue: 0.98),
            skyBottom: Color(red: 0.82, green: 0.94, blue: 1.0),
            groundPrimary: Color(red: 0.97, green: 0.89, blue: 0.66),
            groundSecondary: Color(red: 0.20, green: 0.62, blue: 0.80),
            accent: Color(red: 1.0, green: 0.90, blue: 0.42)
        ),
        HomeBackgroundTheme(
            id: "snow",
            japaneseName: "ゆきやま",
            englishName: "Snowland",
            price: 120,
            scene: .snow,
            skyTop: Color(red: 0.76, green: 0.86, blue: 0.96),
            skyBottom: Color(red: 0.95, green: 0.98, blue: 1.0),
            groundPrimary: Color(red: 0.98, green: 0.99, blue: 1.0),
            groundSecondary: Color(red: 0.81, green: 0.89, blue: 0.97),
            accent: Color(red: 0.66, green: 0.83, blue: 1.0)
        ),
        HomeBackgroundTheme(
            id: "space",
            japaneseName: "うちゅう",
            englishName: "Outer Space",
            price: 160,
            scene: .space,
            skyTop: Color(red: 0.04, green: 0.03, blue: 0.16),
            skyBottom: Color(red: 0.17, green: 0.10, blue: 0.35),
            groundPrimary: Color(red: 0.56, green: 0.41, blue: 0.86),
            groundSecondary: Color(red: 0.40, green: 0.28, blue: 0.66),
            accent: Color(red: 1.0, green: 0.82, blue: 0.45)
        )
    ]

    // BG-CATALOG-GENERATED-BEGIN
    // Image-backed themes. Source of truth: scripts/backgrounds.csv
    // Regenerate with: python3 scripts/generate_backgrounds.py
    static let imageThemes: [HomeBackgroundTheme] = [
        HomeBackgroundTheme(id: "forest", japaneseName: "もり", englishName: "Forest", price: 0, imageName: "bg_forest"),
        HomeBackgroundTheme(id: "flowerfield", japaneseName: "おはなばたけ", englishName: "Flower Field", price: 100, imageName: "bg_flowerfield"),
        HomeBackgroundTheme(id: "park", japaneseName: "こうえん", englishName: "Park", price: 0, imageName: "bg_park"),
        HomeBackgroundTheme(id: "town", japaneseName: "まち", englishName: "Town", price: 100, imageName: "bg_town"),
        HomeBackgroundTheme(id: "sakura", japaneseName: "さくら", englishName: "Cherry Blossoms", price: 0, imageName: "bg_sakura"),
        HomeBackgroundTheme(id: "autumn", japaneseName: "こうよう", englishName: "Autumn Leaves", price: 120, imageName: "bg_autumn"),
        HomeBackgroundTheme(id: "underwater", japaneseName: "うみのなか", englishName: "Under the Sea", price: 140, imageName: "bg_underwater"),
        HomeBackgroundTheme(id: "rainbow", japaneseName: "にじ", englishName: "Rainbow", price: 0, imageName: "bg_rainbow"),
        HomeBackgroundTheme(id: "candyland", japaneseName: "おかしのくに", englishName: "Candy Land", price: 0, imageName: "bg_candyland"),
        HomeBackgroundTheme(id: "castle", japaneseName: "おしろ", englishName: "Castle", price: 160, imageName: "bg_castle"),
        HomeBackgroundTheme(id: "farm", japaneseName: "ぼくじょう", englishName: "Farm", price: 100, imageName: "bg_farm"),
        HomeBackgroundTheme(id: "aquarium", japaneseName: "すいぞくかん", englishName: "Aquarium", price: 120, imageName: "bg_aquarium"),
        HomeBackgroundTheme(id: "amusement", japaneseName: "ゆうえんち", englishName: "Amusement Park", price: 140, imageName: "bg_amusement"),
        HomeBackgroundTheme(id: "boutique", japaneseName: "ブティック", englishName: "Boutique", price: 200, imageName: "bg_boutique"),
        HomeBackgroundTheme(id: "sneakers", japaneseName: "スニーカーショップ", englishName: "Sneaker Shop", price: 180, imageName: "bg_sneakers"),
        HomeBackgroundTheme(id: "carshowroom", japaneseName: "カーショールーム", englishName: "Car Showroom", price: 280, imageName: "bg_carshowroom"),
        HomeBackgroundTheme(id: "racetrack", japaneseName: "サーキット", englishName: "Race Track", price: 220, imageName: "bg_racetrack"),
        HomeBackgroundTheme(id: "concert", japaneseName: "コンサート", englishName: "Concert", price: 240, imageName: "bg_concert"),
        HomeBackgroundTheme(id: "studio", japaneseName: "スタジオ", englishName: "Studio", price: 200, imageName: "bg_studio"),
        HomeBackgroundTheme(id: "stadium", japaneseName: "スタジアム", englishName: "Stadium", price: 240, imageName: "bg_stadium"),
        HomeBackgroundTheme(id: "gamingroom", japaneseName: "ゲーミングルーム", englishName: "Gaming Room", price: 220, imageName: "bg_gamingroom"),
        HomeBackgroundTheme(id: "shibuya", japaneseName: "しぶや", englishName: "Shibuya", price: 260, imageName: "bg_shibuya"),
        HomeBackgroundTheme(id: "paris", japaneseName: "パリ", englishName: "Paris", price: 240, imageName: "bg_paris"),
        HomeBackgroundTheme(id: "newyork", japaneseName: "ニューヨーク", englishName: "New York", price: 260, imageName: "bg_newyork"),
        HomeBackgroundTheme(id: "london", japaneseName: "ロンドン", englishName: "London", price: 240, imageName: "bg_london"),
        HomeBackgroundTheme(id: "basketball", japaneseName: "バスケアリーナ", englishName: "Basketball Arena", price: 220, imageName: "bg_basketball"),
        HomeBackgroundTheme(id: "airport", japaneseName: "くうこうラウンジ", englishName: "Airport Lounge", price: 220, imageName: "bg_airport"),
        HomeBackgroundTheme(id: "shibuyaday", japaneseName: "しぶや(ひる)", englishName: "Shibuya Day", price: 240, imageName: "bg_shibuyaday"),
        HomeBackgroundTheme(id: "spaceship", japaneseName: "うちゅうせんのなか", englishName: "Spaceship", price: 200, imageName: "bg_spaceship"),
        HomeBackgroundTheme(id: "earthspace", japaneseName: "うちゅうのちきゅう", englishName: "Earth from Space", price: 180, imageName: "bg_earthspace"),
        HomeBackgroundTheme(id: "cakeshop", japaneseName: "ケーキやさん", englishName: "Cake Shop", price: 160, imageName: "bg_cakeshop"),
        HomeBackgroundTheme(id: "bakery", japaneseName: "パンやさん", englishName: "Bakery", price: 150, imageName: "bg_bakery"),
        HomeBackgroundTheme(id: "flowershop", japaneseName: "おはなやさん", englishName: "Flower Shop", price: 150, imageName: "bg_flowershop"),
        HomeBackgroundTheme(id: "police", japaneseName: "こうばん", englishName: "Police Box", price: 160, imageName: "bg_police"),
        HomeBackgroundTheme(id: "firestation", japaneseName: "しょうぼうしょ", englishName: "Fire Station", price: 170, imageName: "bg_firestation"),
        HomeBackgroundTheme(id: "dinomuseum", japaneseName: "きょうりゅうはくぶつかん", englishName: "Dinosaur Museum", price: 190, imageName: "bg_dinomuseum"),
        HomeBackgroundTheme(id: "trainstation", japaneseName: "えきのホーム", englishName: "Train Station", price: 170, imageName: "bg_trainstation"),
        HomeBackgroundTheme(id: "toyshop", japaneseName: "おもちゃやさん", englishName: "Toy Shop", price: 160, imageName: "bg_toyshop"),
        HomeBackgroundTheme(id: "soccerfield", japaneseName: "サッカーピッチ", englishName: "Soccer Pitch", price: 240, imageName: "bg_soccerfield"),
        HomeBackgroundTheme(id: "blockworld", japaneseName: "ブロックのせかい", englishName: "Block World", price: 200, imageName: "bg_blockworld"),
        HomeBackgroundTheme(id: "sciencelab", japaneseName: "かがくラボ", englishName: "Science Lab", price: 190, imageName: "bg_sciencelab"),
        HomeBackgroundTheme(id: "planetarium", japaneseName: "プラネタリウム", englishName: "Planetarium", price: 240, imageName: "bg_planetarium"),
        HomeBackgroundTheme(id: "ninjavillage", japaneseName: "にんじゃのさと", englishName: "Ninja Village", price: 190, imageName: "bg_ninjavillage"),
        HomeBackgroundTheme(id: "robotlab", japaneseName: "ロボットこうぼう", englishName: "Robot Workshop", price: 230, imageName: "bg_robotlab"),
        HomeBackgroundTheme(id: "artatelier", japaneseName: "おえかきアトリエ", englishName: "Art Atelier", price: 180, imageName: "bg_artatelier"),
        HomeBackgroundTheme(id: "musicstudio", japaneseName: "おんがくスタジオ", englishName: "Music Studio", price: 240, imageName: "bg_musicstudio"),
        HomeBackgroundTheme(id: "neoncafe", japaneseName: "ネオンカフェ", englishName: "Neon Cafe", price: 260, imageName: "bg_neoncafe"),
        HomeBackgroundTheme(id: "arcade", japaneseName: "ゲームセンター", englishName: "Arcade", price: 260, imageName: "bg_arcade"),
        HomeBackgroundTheme(id: "beachresort", japaneseName: "ビーチリゾート", englishName: "Beach Resort", price: 260, imageName: "bg_beachresort"),
        HomeBackgroundTheme(id: "skilodge", japaneseName: "スキーじょう", englishName: "Ski Resort", price: 250, imageName: "bg_skilodge"),
        HomeBackgroundTheme(id: "summerfes", japaneseName: "なつまつり", englishName: "Summer Festival", price: 200, imageName: "bg_summerfes"),
        HomeBackgroundTheme(id: "fireworks", japaneseName: "はなびたいかい", englishName: "Fireworks", price: 240, imageName: "bg_fireworks"),
        HomeBackgroundTheme(id: "xmasmarket", japaneseName: "クリスマスマーケット", englishName: "Christmas Market", price: 240, imageName: "bg_xmasmarket"),
        HomeBackgroundTheme(id: "halloween", japaneseName: "ハロウィンのよる", englishName: "Halloween Night", price: 200, imageName: "bg_halloween"),
        HomeBackgroundTheme(id: "shrine", japaneseName: "おしょうがつ", englishName: "New Year Shrine", price: 190, imageName: "bg_shrine"),
        HomeBackgroundTheme(id: "voxelforest", japaneseName: "ボクセルのもり", englishName: "Voxel Forest", price: 200, imageName: "bg_voxelforest"),
        HomeBackgroundTheme(id: "voxeldesert", japaneseName: "ボクセルのさばく", englishName: "Voxel Desert", price: 200, imageName: "bg_voxeldesert"),
        HomeBackgroundTheme(id: "voxelocean", japaneseName: "ボクセルのうみ", englishName: "Voxel Ocean", price: 200, imageName: "bg_voxelocean"),
        HomeBackgroundTheme(id: "voxelsnow", japaneseName: "ボクセルのゆきはら", englishName: "Voxel Snowland", price: 200, imageName: "bg_voxelsnow"),
        HomeBackgroundTheme(id: "voxelvolcano", japaneseName: "ボクセルのかざん", englishName: "Voxel Volcano", price: 210, imageName: "bg_voxelvolcano"),
        HomeBackgroundTheme(id: "voxelsky", japaneseName: "ボクセルのそらじま", englishName: "Voxel Sky Islands", price: 210, imageName: "bg_voxelsky"),
        HomeBackgroundTheme(id: "voxelplains", japaneseName: "ボクセルのそうげん", englishName: "Voxel Plains", price: 200, imageName: "bg_voxelplains"),
        HomeBackgroundTheme(id: "voxelvillage", japaneseName: "ボクセルのむら", englishName: "Voxel Village", price: 210, imageName: "bg_voxelvillage"),
        HomeBackgroundTheme(id: "voxeljungle", japaneseName: "ボクセルのジャングル", englishName: "Voxel Jungle", price: 210, imageName: "bg_voxeljungle"),
        HomeBackgroundTheme(id: "voxelcave", japaneseName: "ボクセルのどうくつ", englishName: "Voxel Cave", price: 210, imageName: "bg_voxelcave"),
        HomeBackgroundTheme(id: "voxelmountain", japaneseName: "ボクセルのやま", englishName: "Voxel Mountain Trail", price: 210, imageName: "bg_voxelmountain"),
        HomeBackgroundTheme(id: "voxelwaterfall", japaneseName: "ボクセルのたき", englishName: "Voxel Waterfall", price: 210, imageName: "bg_voxelwaterfall"),
        HomeBackgroundTheme(id: "voxellava", japaneseName: "ボクセルのようがん", englishName: "Voxel Lava Field", price: 220, imageName: "bg_voxellava"),
        HomeBackgroundTheme(id: "voxelcanyon", japaneseName: "ボクセルのだいきょうこく", englishName: "Voxel Canyon", price: 215, imageName: "bg_voxelcanyon"),
        HomeBackgroundTheme(id: "voxelmesa", japaneseName: "ボクセルのあかいわ", englishName: "Voxel Mesa", price: 215, imageName: "bg_voxelmesa"),
        HomeBackgroundTheme(id: "voxelglacier", japaneseName: "ボクセルのひょうが", englishName: "Voxel Glacier", price: 215, imageName: "bg_voxelglacier"),
        HomeBackgroundTheme(id: "voxelmushroom", japaneseName: "ボクセルのキノコもり", englishName: "Voxel Mushroom Forest", price: 220, imageName: "bg_voxelmushroom"),
        HomeBackgroundTheme(id: "voxelstorm", japaneseName: "ボクセルのあらし", englishName: "Voxel Storm Cliffs", price: 220, imageName: "bg_voxelstorm"),
        HomeBackgroundTheme(id: "dinovalley", japaneseName: "きょうりゅうのたに", englishName: "Dinosaur Valley", price: 200, imageName: "bg_dinovalley"),
        HomeBackgroundTheme(id: "tanabata", japaneseName: "たなばた", englishName: "Tanabata Festival", price: 180, imageName: "bg_tanabata"),
        HomeBackgroundTheme(id: "koinobori", japaneseName: "こどものひ", englishName: "Children's Day", price: 180, imageName: "bg_koinobori"),
        HomeBackgroundTheme(id: "hinamatsuri", japaneseName: "ひなまつり", englishName: "Hinamatsuri", price: 180, imageName: "bg_hinamatsuri"),
        HomeBackgroundTheme(id: "construction", japaneseName: "こうじげんば", englishName: "Construction Site", price: 200, imageName: "bg_construction"),
        HomeBackgroundTheme(id: "harbor", japaneseName: "みなと", englishName: "Harbor", price: 200, imageName: "bg_harbor"),
        HomeBackgroundTheme(id: "deepsea", japaneseName: "しんかい", englishName: "Deep Sea", price: 200, imageName: "bg_deepsea"),
        HomeBackgroundTheme(id: "coralreef", japaneseName: "さんごしょう", englishName: "Coral Reef", price: 200, imageName: "bg_coralreef"),
        HomeBackgroundTheme(id: "dragonpeak", japaneseName: "ドラゴンのやま", englishName: "Dragon Peak", price: 220, imageName: "bg_dragonpeak"),
        HomeBackgroundTheme(id: "cloudcastle", japaneseName: "くものおしろ", englishName: "Cloud Castle", price: 220, imageName: "bg_cloudcastle"),
        HomeBackgroundTheme(id: "pyramids", japaneseName: "ピラミッド", englishName: "Pyramids of Egypt", price: 240, imageName: "bg_pyramids"),
        HomeBackgroundTheme(id: "greatwall", japaneseName: "ばんりのちょうじょう", englishName: "Great Wall", price: 240, imageName: "bg_greatwall"),
        HomeBackgroundTheme(id: "aurora", japaneseName: "オーロラ", englishName: "Aurora", price: 240, imageName: "bg_aurora"),
        HomeBackgroundTheme(id: "moonbase", japaneseName: "つきのきち", englishName: "Moon Base", price: 260, imageName: "bg_moonbase"),
        HomeBackgroundTheme(id: "savanna", japaneseName: "サバンナ", englishName: "Savanna", price: 240, imageName: "bg_savanna"),
        HomeBackgroundTheme(id: "nightsakura", japaneseName: "よざくら", englishName: "Night Sakura", price: 240, imageName: "bg_nightsakura"),
        HomeBackgroundTheme(id: "voxelcity", japaneseName: "ボクセルシティ", englishName: "Voxel City", price: 200, imageName: "bg_voxelcity"),
        HomeBackgroundTheme(id: "voxelfarm", japaneseName: "ボクセルぼくじょう", englishName: "Voxel Farm", price: 200, imageName: "bg_voxelfarm"),
        HomeBackgroundTheme(id: "voxelcastle", japaneseName: "ボクセルキャッスル", englishName: "Voxel Castle", price: 200, imageName: "bg_voxelcastle"),
        HomeBackgroundTheme(id: "voxelautumn", japaneseName: "ボクセルこうよう", englishName: "Voxel Autumn", price: 200, imageName: "bg_voxelautumn"),
        HomeBackgroundTheme(id: "ghosthouse", japaneseName: "おばけやしき", englishName: "Ghost House", price: 200, imageName: "bg_ghosthouse"),
        HomeBackgroundTheme(id: "beetleforest", japaneseName: "カブトムシのもり", englishName: "Beetle Forest", price: 180, imageName: "bg_beetleforest"),
        HomeBackgroundTheme(id: "butterflygarden", japaneseName: "ちょうのにわ", englishName: "Butterfly Garden", price: 180, imageName: "bg_butterflygarden"),
        HomeBackgroundTheme(id: "fireflynight", japaneseName: "ほたるのよる", englishName: "Firefly Night", price: 200, imageName: "bg_fireflynight"),
        HomeBackgroundTheme(id: "dragonflypond", japaneseName: "とんぼのいけ", englishName: "Dragonfly Pond", price: 180, imageName: "bg_dragonflypond"),
        HomeBackgroundTheme(id: "rainyhydrangea", japaneseName: "あめとあじさい", englishName: "Rainy Hydrangea", price: 180, imageName: "bg_rainyhydrangea"),
        HomeBackgroundTheme(id: "tsukimi", japaneseName: "おつきみ", englishName: "Moon Viewing", price: 200, imageName: "bg_tsukimi"),
        HomeBackgroundTheme(id: "setsubun", japaneseName: "せつぶん", englishName: "Setsubun", price: 180, imageName: "bg_setsubun"),
        HomeBackgroundTheme(id: "newyear", japaneseName: "おしょうがつ", englishName: "New Year", price: 200, imageName: "bg_newyear"),
        HomeBackgroundTheme(id: "easter", japaneseName: "イースター", englishName: "Easter", price: 180, imageName: "bg_easter"),
        HomeBackgroundTheme(id: "fairyforest", japaneseName: "ようせいのもり", englishName: "Fairy Forest", price: 220, imageName: "bg_fairyforest"),
        HomeBackgroundTheme(id: "crystalcave", japaneseName: "クリスタルのどうくつ", englishName: "Crystal Cave", price: 220, imageName: "bg_crystalcave"),
        HomeBackgroundTheme(id: "piratecove", japaneseName: "かいぞくのいりえ", englishName: "Pirate Cove", price: 200, imageName: "bg_piratecove"),
        HomeBackgroundTheme(id: "treehouse", japaneseName: "ツリーハウス", englishName: "Treehouse", price: 200, imageName: "bg_treehouse"),
        HomeBackgroundTheme(id: "hotairballoons", japaneseName: "ききゅうのそら", englishName: "Hot Air Balloons", price: 200, imageName: "bg_hotairballoons"),
        HomeBackgroundTheme(id: "bamboo", japaneseName: "たけやぶ", englishName: "Bamboo Grove", price: 180, imageName: "bg_bamboo"),
        HomeBackgroundTheme(id: "ricefield", japaneseName: "いなかのたんぼ", englishName: "Countryside Rice Field", price: 180, imageName: "bg_ricefield"),
        HomeBackgroundTheme(id: "icepalace", japaneseName: "こおりのきゅうでん", englishName: "Ice Palace", price: 240, imageName: "bg_icepalace"),
        HomeBackgroundTheme(id: "desertpalace", japaneseName: "まほうのさばく", englishName: "Desert Palace", price: 240, imageName: "bg_desertpalace"),
        HomeBackgroundTheme(id: "seakingdom", japaneseName: "うみのおうこく", englishName: "Sea Kingdom", price: 240, imageName: "bg_seakingdom"),
        HomeBackgroundTheme(id: "lionrock", japaneseName: "サンライズのいわ", englishName: "Sunrise Rock", price: 240, imageName: "bg_lionrock"),
        HomeBackgroundTheme(id: "toyroom", japaneseName: "おもちゃのへや", englishName: "Toy Room", price: 200, imageName: "bg_toyroom"),
        HomeBackgroundTheme(id: "tropicalisland", japaneseName: "みなみのしま", englishName: "Tropical Island", price: 220, imageName: "bg_tropicalisland"),
        HomeBackgroundTheme(id: "ballroom", japaneseName: "まほうのぶとうかい", englishName: "Magic Ballroom", price: 240, imageName: "bg_ballroom"),
        HomeBackgroundTheme(id: "junglevines", japaneseName: "みどりのジャングル", englishName: "Green Jungle", price: 220, imageName: "bg_junglevines"),
        HomeBackgroundTheme(id: "lanternnight", japaneseName: "そらとぶランタン", englishName: "Lantern Night", price: 240, imageName: "bg_lanternnight"),
        HomeBackgroundTheme(id: "library", japaneseName: "まほうのとしょかん", englishName: "Magic Library", price: 220, imageName: "bg_library"),
        HomeBackgroundTheme(id: "fairytalevillage", japaneseName: "おとぎのむら", englishName: "Fairytale Village", price: 220, imageName: "bg_fairytalevillage"),
        HomeBackgroundTheme(id: "skyship", japaneseName: "そらとぶふね", englishName: "Flying Ship", price: 240, imageName: "bg_skyship"),
        HomeBackgroundTheme(id: "wonderland", japaneseName: "ふしぎのにわ", englishName: "Wonderland Garden", price: 220, imageName: "bg_wonderland"),
        HomeBackgroundTheme(id: "flowertower", japaneseName: "はなのとう", englishName: "Flower Tower", price: 220, imageName: "bg_flowertower"),
        HomeBackgroundTheme(id: "buildsite", japaneseName: "こうじげんば", englishName: "Construction Site", price: 200, imageName: "bg_buildsite"),
        HomeBackgroundTheme(id: "rocketlaunch", japaneseName: "ロケットはっしゃ", englishName: "Rocket Launch", price: 240, imageName: "bg_rocketlaunch"),
        HomeBackgroundTheme(id: "bullettrain", japaneseName: "しんかんせん", englishName: "Bullet Train", price: 220, imageName: "bg_bullettrain"),
        HomeBackgroundTheme(id: "fireengine", japaneseName: "しょうぼうたい", englishName: "Fire Engine", price: 200, imageName: "bg_fireengine"),
        HomeBackgroundTheme(id: "portcranes", japaneseName: "みなとのクレーン", englishName: "Port Cranes", price: 200, imageName: "bg_portcranes"),
        HomeBackgroundTheme(id: "wildsavanna", japaneseName: "サバンナ", englishName: "Wild Savanna", price: 240, imageName: "bg_wildsavanna"),
        HomeBackgroundTheme(id: "polarnight", japaneseName: "きょくほくのうみ", englishName: "Arctic Night", price: 220, imageName: "bg_polarnight"),
        HomeBackgroundTheme(id: "rainforest", japaneseName: "ねったいうりん", englishName: "Rainforest", price: 220, imageName: "bg_rainforest"),
        HomeBackgroundTheme(id: "flamingolake", japaneseName: "フラミンゴのみずうみ", englishName: "Flamingo Lake", price: 200, imageName: "bg_flamingolake"),
        HomeBackgroundTheme(id: "dinoplains", japaneseName: "きょうりゅうのへいげん", englishName: "Dinosaur Plains", price: 240, imageName: "bg_dinoplains"),
        HomeBackgroundTheme(id: "volcanoera", japaneseName: "かざんじだい", englishName: "Volcano Era", price: 240, imageName: "bg_volcanoera"),
        HomeBackgroundTheme(id: "ancientsea", japaneseName: "おおむかしのうみ", englishName: "Ancient Sea", price: 220, imageName: "bg_ancientsea"),
        HomeBackgroundTheme(id: "iceagemammoth", japaneseName: "ひょうがき", englishName: "Ice Age", price: 220, imageName: "bg_iceagemammoth"),
        HomeBackgroundTheme(id: "pteranodonsky", japaneseName: "そらとぶよくりゅう", englishName: "Flying Reptiles", price: 240, imageName: "bg_pteranodonsky"),
        HomeBackgroundTheme(id: "voxelreef", japaneseName: "ボクセルのサンゴしょう", englishName: "Voxel Reef", price: 220, imageName: "bg_voxelreef"),
        HomeBackgroundTheme(id: "voxelpirate", japaneseName: "ボクセルのかいぞくせん", englishName: "Voxel Pirates", price: 220, imageName: "bg_voxelpirate"),
        HomeBackgroundTheme(id: "voxeldragon", japaneseName: "ボクセルのドラゴンのたに", englishName: "Voxel Dragon", price: 240, imageName: "bg_voxeldragon"),
        HomeBackgroundTheme(id: "voxelaurora", japaneseName: "ボクセルのオーロラ", englishName: "Voxel Aurora", price: 220, imageName: "bg_voxelaurora"),
        HomeBackgroundTheme(id: "hauntedcastle", japaneseName: "おばけのおしろ", englishName: "Haunted Castle", price: 240, imageName: "bg_hauntedcastle"),
        HomeBackgroundTheme(id: "spookygraveyard", japaneseName: "おばけのはかば", englishName: "Spooky Graveyard", price: 220, imageName: "bg_spookygraveyard"),
        HomeBackgroundTheme(id: "witchcottage", japaneseName: "まじょのいえ", englishName: "Witch Cottage", price: 220, imageName: "bg_witchcottage"),
        HomeBackgroundTheme(id: "monsterlab", japaneseName: "かいぶつラボ", englishName: "Monster Lab", price: 220, imageName: "bg_monsterlab"),
        HomeBackgroundTheme(id: "werewolfwoods", japaneseName: "まんげつのもり", englishName: "Full Moon Woods", price: 240, imageName: "bg_werewolfwoods"),
        HomeBackgroundTheme(id: "cursedtomb", japaneseName: "のろいのいせき", englishName: "Cursed Tomb", price: 240, imageName: "bg_cursedtomb"),
        HomeBackgroundTheme(id: "swampmonster", japaneseName: "ぬまのモンスター", englishName: "Swamp Monster", price: 200, imageName: "bg_swampmonster"),
        HomeBackgroundTheme(id: "foggyforest", japaneseName: "きりのもり", englishName: "Foggy Forest", price: 220, imageName: "bg_foggyforest"),
        HomeBackgroundTheme(id: "yokaiparade", japaneseName: "ひゃっきやこう", englishName: "Yokai Parade", price: 240, imageName: "bg_yokaiparade"),
        HomeBackgroundTheme(id: "kappapond", japaneseName: "かっぱのぬま", englishName: "Kappa Pond", price: 200, imageName: "bg_kappapond"),
        HomeBackgroundTheme(id: "hauntedshrine", japaneseName: "おばけじんじゃ", englishName: "Haunted Shrine", price: 240, imageName: "bg_hauntedshrine"),
        HomeBackgroundTheme(id: "oninoyama", japaneseName: "おにのやま", englishName: "Ogre Mountain", price: 220, imageName: "bg_oninoyama"),
        HomeBackgroundTheme(id: "lanternghosts", japaneseName: "ちょうちんおばけ", englishName: "Lantern Ghosts", price: 200, imageName: "bg_lanternghosts"),
        HomeBackgroundTheme(id: "fujizakura", japaneseName: "ふじとさくら", englishName: "Mt Fuji & Sakura", price: 260, imageName: "bg_fujizakura"),
        HomeBackgroundTheme(id: "kyotoautumn", japaneseName: "きょうとのもみじ", englishName: "Kyoto Autumn", price: 260, imageName: "bg_kyotoautumn"),
        HomeBackgroundTheme(id: "snowonsen", japaneseName: "ゆきみおんせん", englishName: "Snow Hot Spring", price: 260, imageName: "bg_snowonsen"),
        HomeBackgroundTheme(id: "terracedrice", japaneseName: "たなだのゆうぐれ", englishName: "Terraced Rice", price: 240, imageName: "bg_terracedrice"),
        HomeBackgroundTheme(id: "shirakawa", japaneseName: "ゆきのむら", englishName: "Snow Village", price: 260, imageName: "bg_shirakawa"),
        HomeBackgroundTheme(id: "galaxystation", japaneseName: "ぎんがステーション", englishName: "Galaxy Station", price: 260, imageName: "bg_galaxystation"),
        HomeBackgroundTheme(id: "marsbase", japaneseName: "かせいきち", englishName: "Mars Base", price: 260, imageName: "bg_marsbase"),
        HomeBackgroundTheme(id: "saturnview", japaneseName: "どせいのわ", englishName: "Saturn View", price: 260, imageName: "bg_saturnview"),
        HomeBackgroundTheme(id: "blackhole", japaneseName: "ブラックホール", englishName: "Black Hole", price: 260, imageName: "bg_blackhole"),
        HomeBackgroundTheme(id: "meteornight", japaneseName: "りゅうせいぐん", englishName: "Meteor Shower", price: 240, imageName: "bg_meteornight"),
        HomeBackgroundTheme(id: "cockpit", japaneseName: "コックピット", englishName: "Cockpit", price: 240, imageName: "bg_cockpit"),
        HomeBackgroundTheme(id: "hospital", japaneseName: "びょういん", englishName: "Hospital", price: 220, imageName: "bg_hospital"),
        HomeBackgroundTheme(id: "patisserie", japaneseName: "パティシエのちゅうぼう", englishName: "Patisserie", price: 220, imageName: "bg_patisserie"),
        HomeBackgroundTheme(id: "digsite", japaneseName: "はっくつげんば", englishName: "Dig Site", price: 220, imageName: "bg_digsite"),
        HomeBackgroundTheme(id: "vetclinic", japaneseName: "どうぶつびょういん", englishName: "Vet Clinic", price: 220, imageName: "bg_vetclinic"),
        HomeBackgroundTheme(id: "catcafe", japaneseName: "ねこカフェ", englishName: "Cat Cafe", price: 220, imageName: "bg_catcafe"),
        HomeBackgroundTheme(id: "pandabamboo", japaneseName: "パンダのたけやぶ", englishName: "Panda Grove", price: 220, imageName: "bg_pandabamboo"),
        HomeBackgroundTheme(id: "bunnyisland", japaneseName: "うさぎのしま", englishName: "Bunny Island", price: 220, imageName: "bg_bunnyisland"),
        HomeBackgroundTheme(id: "penguinbeach", japaneseName: "ペンギンビーチ", englishName: "Penguin Beach", price: 220, imageName: "bg_penguinbeach"),
        HomeBackgroundTheme(id: "puppyfarm", japaneseName: "こいぬのまきば", englishName: "Puppy Meadow", price: 220, imageName: "bg_puppyfarm"),
        HomeBackgroundTheme(id: "uyuni", japaneseName: "かがみのみずうみ", englishName: "Mirror Lake", price: 260, imageName: "bg_uyuni"),
        HomeBackgroundTheme(id: "grandcanyon", japaneseName: "おおきなたにがわ", englishName: "Grand Canyon", price: 260, imageName: "bg_grandcanyon"),
        HomeBackgroundTheme(id: "santorini", japaneseName: "あおいドームのまち", englishName: "Cliff Town", price: 260, imageName: "bg_santorini"),
        HomeBackgroundTheme(id: "maldives", japaneseName: "みずうえコテージ", englishName: "Overwater Villas", price: 260, imageName: "bg_maldives"),
        HomeBackgroundTheme(id: "mountainruins", japaneseName: "くものいせき", englishName: "Mountain Ruins", price: 260, imageName: "bg_mountainruins"),
        HomeBackgroundTheme(id: "bigfalls", japaneseName: "だいばくふ", englishName: "Great Falls", price: 260, imageName: "bg_bigfalls"),
        HomeBackgroundTheme(id: "wizardhall", japaneseName: "まほうのひろま", englishName: "Wizard Hall", price: 260, imageName: "bg_wizardhall"),
        HomeBackgroundTheme(id: "dragonhoard", japaneseName: "ドラゴンのたから", englishName: "Dragon Hoard", price: 260, imageName: "bg_dragonhoard"),
        HomeBackgroundTheme(id: "skykingdom", japaneseName: "てんくうのしろ", englishName: "Sky Kingdom", price: 260, imageName: "bg_skykingdom"),
        HomeBackgroundTheme(id: "rainbowpalace", japaneseName: "にじのきゅうでん", englishName: "Rainbow Palace", price: 240, imageName: "bg_rainbowpalace"),
        HomeBackgroundTheme(id: "elfspring", japaneseName: "エルフのいずみ", englishName: "Elf Spring", price: 240, imageName: "bg_elfspring"),
        HomeBackgroundTheme(id: "birthday", japaneseName: "たんじょうび", englishName: "Birthday", price: 220, imageName: "bg_birthday"),
        HomeBackgroundTheme(id: "trophystage", japaneseName: "ひょうしょうだい", englishName: "Award Stage", price: 220, imageName: "bg_trophystage"),
        HomeBackgroundTheme(id: "throne", japaneseName: "おうさまのま", englishName: "Throne Room", price: 260, imageName: "bg_throne"),
        HomeBackgroundTheme(id: "partyfireworks", japaneseName: "おいわいのはなび", englishName: "Party Fireworks", price: 240, imageName: "bg_partyfireworks"),
        HomeBackgroundTheme(id: "rewardroom", japaneseName: "ごほうびルーム", englishName: "Reward Room", price: 240, imageName: "bg_rewardroom"),
        HomeBackgroundTheme(id: "auroracoast", japaneseName: "オーロラのうみべ", englishName: "Aurora Coast", price: 260, imageName: "bg_auroracoast"),
        HomeBackgroundTheme(id: "starfallsea", japaneseName: "ほしふるうみ", englishName: "Starfall Sea", price: 260, imageName: "bg_starfallsea"),
        HomeBackgroundTheme(id: "milkywaylake", japaneseName: "てんのがわのみずうみ", englishName: "Milky Way Lake", price: 260, imageName: "bg_milkywaylake"),
        HomeBackgroundTheme(id: "auroramountain", japaneseName: "オーロラのゆきやま", englishName: "Aurora Peaks", price: 260, imageName: "bg_auroramountain"),
        HomeBackgroundTheme(id: "cometnight", japaneseName: "すいせいのよぞら", englishName: "Comet Night", price: 240, imageName: "bg_cometnight"),
        HomeBackgroundTheme(id: "glowingsea", japaneseName: "ひかるうみ", englishName: "Glowing Sea", price: 260, imageName: "bg_glowingsea"),
        HomeBackgroundTheme(id: "desertstars", japaneseName: "さばくのほしぞら", englishName: "Desert Stars", price: 240, imageName: "bg_desertstars"),
        HomeBackgroundTheme(id: "starrycape", japaneseName: "ほしぞらのみさき", englishName: "Starry Cape", price: 260, imageName: "bg_starrycape"),
        HomeBackgroundTheme(id: "cruiseship", japaneseName: "ごうかきゃくせん", englishName: "Cruise Ship", price: 260, imageName: "bg_cruiseship"),
        HomeBackgroundTheme(id: "airshow", japaneseName: "エアショー", englishName: "Air Show", price: 260, imageName: "bg_airshow"),
        HomeBackgroundTheme(id: "steamtrain", japaneseName: "じょうききかんしゃ", englishName: "Steam Train", price: 240, imageName: "bg_steamtrain"),
        HomeBackgroundTheme(id: "submarine", japaneseName: "しんかいたんさてい", englishName: "Deep-Sea Sub", price: 240, imageName: "bg_submarine"),
        HomeBackgroundTheme(id: "tallship", japaneseName: "だいこうかいのはんせん", englishName: "Tall Ship", price: 240, imageName: "bg_tallship"),
        HomeBackgroundTheme(id: "cablecar", japaneseName: "やまのロープウェイ", englishName: "Cable Car", price: 220, imageName: "bg_cablecar"),
        HomeBackgroundTheme(id: "aquariumtunnel", japaneseName: "すいぞくかんトンネル", englishName: "Aquarium Tunnel", price: 240, imageName: "bg_aquariumtunnel"),
        HomeBackgroundTheme(id: "whaleswim", japaneseName: "クジラとおよぐ", englishName: "Swim with Whale", price: 260, imageName: "bg_whaleswim"),
        HomeBackgroundTheme(id: "jellyfishtank", japaneseName: "クラゲのすいそう", englishName: "Jellyfish Tank", price: 240, imageName: "bg_jellyfishtank"),
        HomeBackgroundTheme(id: "dolphinshow", japaneseName: "イルカショー", englishName: "Dolphin Show", price: 220, imageName: "bg_dolphinshow"),
        HomeBackgroundTheme(id: "seaturtle", japaneseName: "ウミガメのうみ", englishName: "Sea Turtle", price: 200, imageName: "bg_seaturtle"),
        HomeBackgroundTheme(id: "mantaray", japaneseName: "マンタのうみ", englishName: "Manta Ray", price: 240, imageName: "bg_mantaray"),
        HomeBackgroundTheme(id: "skylanternfest", japaneseName: "スカイランタン", englishName: "Sky Lanterns", price: 260, imageName: "bg_skylanternfest"),
        HomeBackgroundTheme(id: "riocarnival", japaneseName: "カーニバル", englishName: "Carnival", price: 260, imageName: "bg_riocarnival"),
        HomeBackgroundTheme(id: "holifestival", japaneseName: "いろのまつり", englishName: "Color Festival", price: 240, imageName: "bg_holifestival"),
        HomeBackgroundTheme(id: "natsumatsuri", japaneseName: "なつまつり", englishName: "Summer Festival", price: 220, imageName: "bg_natsumatsuri"),
        HomeBackgroundTheme(id: "diwali", japaneseName: "ひかりのまつり", englishName: "Diwali Lights", price: 240, imageName: "bg_diwali"),
        HomeBackgroundTheme(id: "dragondance", japaneseName: "りゅうのまい", englishName: "Dragon Dance", price: 220, imageName: "bg_dragondance")
    ]
    // BG-CATALOG-GENERATED-END
}

struct HomeBackground: View {
    var themeID: String = HomeBackgroundTheme.defaultID
    var ignoresSafeArea: Bool = true

    private var theme: HomeBackgroundTheme {
        HomeBackgroundTheme.theme(id: themeID)
    }

    var body: some View {
        if let imageName = theme.imageName {
            // 利用可能領域いっぱいに敷き、はみ出しは clip する。
            // frame/clipped が無いと scaledToFill が本来サイズを主張し、シート等の
            // 「中身に合わせて縮む」コンテナ内でレイアウトを押し広げて崩す（きょうのたんご画面）。
            safeAreaBackground(
                Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            )
        } else {
            ZStack(alignment: .bottom) {
                safeAreaBackground(
                    LinearGradient(
                        colors: [theme.skyTop, theme.skyBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                HomeBackgroundScenery(theme: theme)
            }
        }
    }

    @ViewBuilder
    private func safeAreaBackground<Background: View>(_ background: Background) -> some View {
        if ignoresSafeArea {
            background.ignoresSafeArea()
        } else {
            background
        }
    }
}

private struct HomeBackgroundScenery: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        switch theme.scene {
        case .meadow:
            MeadowScene(theme: theme)
        case .sunset:
            SunsetScene(theme: theme)
        case .night:
            NightScene(theme: theme)
        case .beach:
            BeachScene(theme: theme)
        case .snow:
            SnowScene(theme: theme)
        case .space:
            SpaceScene(theme: theme)
        }
    }
}

private struct MeadowScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            DriftingCloud(width: 150, height: 62, opacity: 0.78,
                          baseX: -330, baseY: -560, period: 46, amplitude: 26)
            DriftingCloud(width: 120, height: 54, opacity: 0.68,
                          baseX: 320, baseY: -550, period: 58, amplitude: 20, phase: 0.5)

            Hills()
                .fill(theme.groundPrimary)
                .frame(height: 142)
                .ignoresSafeArea(edges: .bottom)

            Hills()
                .fill(theme.groundSecondary.opacity(0.75))
                .frame(height: 118)
                .offset(y: 12)
                .ignoresSafeArea(edges: .bottom)

            HStack {
                Tree().frame(width: 42, height: 70)
                Spacer()
                Tree().frame(width: 34, height: 58)
                Spacer()
                Tree().frame(width: 52, height: 88)
                Spacer()
                Tree().frame(width: 38, height: 66)
            }
            .padding(.horizontal, 58)
            .padding(.bottom, 36)
        }
    }
}

private struct SunsetScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            GlowingSun(color: theme.accent, size: 130, baseShadow: 40, offsetY: -300)

            DriftingCloud(width: 150, height: 60, opacity: 0.42,
                          baseX: -300, baseY: -480, period: 52, amplitude: 24)
            DriftingCloud(width: 120, height: 50, opacity: 0.34,
                          baseX: 320, baseY: -520, period: 64, amplitude: 18, phase: 0.5)

            Hills()
                .fill(theme.groundSecondary.opacity(0.85))
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
            Hills()
                .fill(theme.groundPrimary)
                .frame(height: 116)
                .offset(y: 14)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct NightScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            ScatteredStars(color: theme.accent, twinkles: true)

            CrescentMoonView(color: theme.accent)
                .frame(width: 78, height: 78)
                .shadow(color: theme.accent.opacity(0.5), radius: 18)
                .offset(x: 280, y: -520)

            Hills()
                .fill(theme.groundSecondary)
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
            Hills()
                .fill(theme.groundPrimary)
                .frame(height: 116)
                .offset(y: 14)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct BeachScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            GlowingSun(color: theme.accent, size: 96, baseShadow: 28, offsetX: -250, offsetY: -520)

            DriftingCloud(width: 140, height: 56, opacity: 0.78,
                          baseX: 300, baseY: -540, period: 50, amplitude: 22)

            Hills()
                .fill(theme.groundSecondary)
                .frame(height: 170)
                .ignoresSafeArea(edges: .bottom)
            Hills()
                .fill(theme.groundPrimary)
                .frame(height: 92)
                .offset(y: 16)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct SnowScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            ScatteredStars(color: .white.opacity(0.92), count: 16, asDots: true, twinkles: true)

            DriftingCloud(width: 150, height: 60, opacity: 0.86,
                          baseX: -300, baseY: -540, period: 56, amplitude: 22)

            Hills()
                .fill(theme.groundSecondary)
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
            Hills()
                .fill(theme.groundPrimary)
                .frame(height: 118)
                .offset(y: 14)
                .ignoresSafeArea(edges: .bottom)

            Snowman()
                .frame(width: 60, height: 96)
                .padding(.bottom, 34)

            // 手前を舞い落ちる雪（fallProgress＋driftOffset・Core）。
            FallingSnow()
        }
    }
}

private struct SpaceScene: View {
    var theme: HomeBackgroundTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            ScatteredStars(color: .white, count: 20, asDots: true, twinkles: true)

            // Ringed planet
            ZStack {
                Ellipse()
                    .stroke(theme.accent.opacity(0.8), lineWidth: 6)
                    .frame(width: 150, height: 54)
                    .rotationEffect(.degrees(-18))
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.groundPrimary, theme.groundSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
            }
            .offset(x: 250, y: -470)

            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 46, height: 46)
                .offset(x: -280, y: -540)
        }
    }
}

/// 横にゆっくり往復する雲。動きの量は `BackgroundMotion.driftOffset`（Core・テスト済）に委譲し、
/// View は時刻を渡して描くだけ。reduce-motion 時は静止（基準位置のまま）。
private struct DriftingCloud: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var width: CGFloat
    var height: CGFloat
    var opacity: Double
    var baseX: CGFloat
    var baseY: CGFloat
    var period: Double
    var amplitude: CGFloat
    var phase: Double = 0

    var body: some View {
        // 動きが遅い背景なので 20fps に間引く（120Hz 更新は無駄＝電力/発熱）。
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let dx = reduceMotion ? 0 : BackgroundMotion.driftOffset(
                time: context.date.timeIntervalSinceReferenceDate,
                period: period, amplitude: Double(amplitude), phase: phase)
            Cloud()
                .fill(.white.opacity(opacity))
                .frame(width: width, height: height)
                .offset(x: baseX + CGFloat(dx), y: baseY)
        }
    }
}

/// じんわり脈動する太陽。明るさ・グロー半径・わずかな拡縮を `BackgroundMotion.twinkle`（Core）で駆動。
/// reduce-motion 時は静止（常時最大）。
private struct GlowingSun: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color
    var size: CGFloat
    var baseShadow: CGFloat
    var offsetX: CGFloat = 0
    var offsetY: CGFloat
    var period: Double = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let pulse = reduceMotion ? 1 : BackgroundMotion.twinkle(
                time: context.date.timeIntervalSinceReferenceDate, seed: 0, period: period, floor: 0.7)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.55), radius: baseShadow * pulse)
                .scaleEffect(0.97 + 0.03 * pulse)
                .offset(x: offsetX, y: offsetY)
        }
    }
}

/// 手前を舞い落ちる雪。縦位置は `BackgroundMotion.fallProgress`、横揺れは `driftOffset`（ともに Core・テスト済）。
/// reduce-motion 時は `TimelineView` が時刻を止めるため静止スナップショットになる。
private struct FallingSnow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var count: Int = 14
    var color: Color = .white.opacity(0.92)

    // 雪片ごとの固定 x（幅の割合）・サイズ・落下周期（秒）。
    private static let flakes: [(x: CGFloat, s: CGFloat, period: Double)] = [
        (0.06, 7, 9.0), (0.15, 5, 11.5), (0.24, 8, 8.0), (0.33, 5, 12.5),
        (0.42, 6, 9.5), (0.50, 4, 13.0), (0.58, 7, 8.5), (0.67, 5, 11.0),
        (0.75, 8, 9.0), (0.83, 5, 12.0), (0.91, 6, 8.5), (0.20, 4, 14.0),
        (0.62, 6, 10.5), (0.88, 4, 13.5)
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(0..<min(count, Self.flakes.count), id: \.self) { i in
                        let flake = Self.flakes[i]
                        // reduce-motion 時は時刻を使わず seed 由来の固定位置に置く（揺れ無し）。
                        let y = reduceMotion
                            ? BackgroundMotion.fallProgress(time: 0, seed: i, period: 0)
                            : BackgroundMotion.fallProgress(time: time, seed: i, period: flake.period)
                        let sway = reduceMotion ? 0 : BackgroundMotion.driftOffset(
                            time: time, period: flake.period * 0.5, amplitude: 12, phase: Double(i) * 0.3)
                        Circle()
                            .fill(color)
                            .frame(width: flake.s, height: flake.s)
                            .position(x: flake.x * geo.size.width + CGFloat(sway),
                                      y: y * geo.size.height)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct Cloud: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.40, width: rect.width * 0.35, height: rect.height * 0.35))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.20, width: rect.width * 0.38, height: rect.height * 0.46))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.34, width: rect.width * 0.34, height: rect.height * 0.36))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.48, width: rect.width * 0.76, height: rect.height * 0.22), cornerSize: CGSize(width: 18, height: 18))
        return path
    }
}

private struct Hills: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 24))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + 10),
            control1: CGPoint(x: rect.width * 0.25, y: rect.midY - 36),
            control2: CGPoint(x: rect.width * 0.64, y: rect.midY + 72)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Tree: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.63, green: 0.45, blue: 0.24))
                .frame(width: 8, height: 36)

            Circle()
                .fill(Color(red: 0.31, green: 0.67, blue: 0.38))
                .frame(width: 34, height: 34)
                .offset(y: -24)
            Circle()
                .fill(Color(red: 0.43, green: 0.76, blue: 0.48))
                .frame(width: 24, height: 24)
                .offset(x: -10, y: -18)
        }
    }
}

private struct CrescentMoonView: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            Circle()
                .fill(color)
                .overlay(
                    Circle()
                        .fill(Color.black)
                        .frame(width: size * 0.86, height: size * 0.86)
                        .offset(x: size * 0.30)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()
        }
    }
}

/// Deterministic scatter of small stars/dots across the upper screen.
private struct ScatteredStars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color
    var count: Int = 12
    var asDots: Bool = false
    /// true なら星が個別の位相でゆっくり明滅する（明るさは `BackgroundMotion.twinkle`・Core）。
    var twinkles: Bool = false

    // Fixed pseudo-random positions (fraction of width/height) + size.
    private static let layout: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.08, 0.10, 6), (0.20, 0.22, 4), (0.33, 0.08, 7), (0.46, 0.18, 4),
        (0.58, 0.06, 6), (0.70, 0.20, 5), (0.84, 0.10, 7), (0.92, 0.26, 4),
        (0.12, 0.34, 5), (0.27, 0.40, 4), (0.40, 0.32, 6), (0.54, 0.42, 4),
        (0.66, 0.34, 5), (0.78, 0.44, 6), (0.88, 0.38, 4), (0.16, 0.50, 5),
        (0.36, 0.52, 4), (0.50, 0.48, 6), (0.62, 0.54, 4), (0.80, 0.52, 5)
    ]

    var body: some View {
        GeometryReader { geo in
            // twinkle が無効 or reduce-motion のときは一度きりの描画（無駄な再描画をしない）。
            // 有効時も瞬きは遅いので 20fps に間引く（電力/発熱）。
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !twinkles || reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(0..<min(count, Self.layout.count), id: \.self) { i in
                        let item = Self.layout[i]
                        let brightness = (twinkles && !reduceMotion)
                            ? BackgroundMotion.twinkle(time: time, seed: i, period: 3.6, floor: 0.45)
                            : 1
                        Group {
                            if asDots {
                                Circle().fill(color)
                            } else {
                                Star(points: 4).fill(color)
                            }
                        }
                        .frame(width: item.s, height: item.s)
                        .opacity(brightness)
                        .position(x: item.x * geo.size.width, y: item.y * geo.size.height)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct Star: Shape {
    var points: Int = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        let step = Double.pi / Double(points)
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * step - Double.pi / 2
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct Snowman: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(.white)
                .frame(width: 56, height: 56)
            Circle()
                .fill(.white)
                .frame(width: 40, height: 40)
                .offset(y: -44)
                .overlay(alignment: .top) {
                    HStack(spacing: 7) {
                        Circle().fill(.black.opacity(0.7)).frame(width: 4, height: 4)
                        Circle().fill(.black.opacity(0.7)).frame(width: 4, height: 4)
                    }
                    .offset(y: -32)
                }
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

/// Compact preview of a background theme for store cards.
struct HomeBackgroundThumbnail: View {
    var theme: HomeBackgroundTheme
    var cornerRadius: CGFloat = 10

    private var isDark: Bool {
        theme.scene == .night || theme.scene == .space
    }

    var body: some View {
        Group {
            if let imageName = theme.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                proceduralThumbnail
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        )
    }

    private var proceduralThumbnail: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [theme.skyTop, theme.skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    if isDark {
                        ForEach(thumbStars.indices, id: \.self) { i in
                            Circle()
                                .fill(.white.opacity(0.9))
                                .frame(width: 2.2, height: 2.2)
                                .position(
                                    x: thumbStars[i].0 * geo.size.width,
                                    y: thumbStars[i].1 * geo.size.height
                                )
                        }
                    }

                    accent
                        .position(
                            x: geo.size.width * (theme.scene == .night || theme.scene == .space ? 0.74 : 0.26),
                            y: geo.size.height * 0.3
                        )

                    ThumbnailHill()
                        .fill(theme.groundSecondary)
                        .frame(height: geo.size.height * 0.42)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    ThumbnailHill()
                        .fill(theme.groundPrimary)
                        .frame(height: geo.size.height * 0.30)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private var thumbStars: [(CGFloat, CGFloat)] {
        [(0.18, 0.18), (0.4, 0.1), (0.62, 0.22), (0.82, 0.14), (0.3, 0.34), (0.7, 0.4)]
    }

    @ViewBuilder
    private var accent: some View {
        switch theme.scene {
        case .night:
            CrescentMoonView(color: theme.accent).frame(width: 16, height: 16)
        case .space:
            Circle()
                .fill(LinearGradient(colors: [theme.groundPrimary, theme.groundSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
                .overlay(
                    Ellipse().stroke(theme.accent.opacity(0.85), lineWidth: 2)
                        .frame(width: 28, height: 10)
                        .rotationEffect(.degrees(-18))
                )
        default:
            Circle()
                .fill(theme.accent)
                .frame(width: 18, height: 18)
                .shadow(color: theme.accent.opacity(0.5), radius: 5)
        }
    }
}

private struct ThumbnailHill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 6))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + 2),
            control: CGPoint(x: rect.midX, y: rect.minY - 4)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HomeView()
        .environmentObject(AppModel())
        .environmentObject(SyncSession())
}

/// 連続ログイン報酬のポップアップ（7日スタンプカード＋もらえるコイン）。
private struct LoginRewardView: View {
    let streak: Int
    let coins: Int
    var language: AppLanguage
    let onClose: () -> Void

    /// 今週のスタンプ位置（1〜7）。7日を超えたら1に戻る。
    private var weekDay: Int { ((max(streak, 1) - 1) % 7) + 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 18) {
                Text("🎉 " + language.text(japanese: "ログインボーナス！", english: "Login Bonus!"))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))

                HStack(spacing: 10) {
                    coin.frame(width: 46, height: 46)
                    Text("＋\(coins)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.90, green: 0.60, blue: 0.10))
                }

                Text(language.text(japanese: "\(streak)にち れんぞく！", english: "\(streak)-day streak!"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { i in
                        ZStack {
                            Circle()
                                .fill(i <= weekDay
                                      ? Color(red: 1.0, green: 0.82, blue: 0.30)
                                      : Color.secondary.opacity(0.18))
                                .frame(width: 28, height: 28)
                            if i <= weekDay {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                Button(language.text(japanese: "やったー！", english: "Yay!"), action: onClose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(40)
        }
    }

    private var coin: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Color(red: 1.0, green: 0.86, blue: 0.35), Color(red: 0.96, green: 0.62, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color(red: 0.80, green: 0.50, blue: 0.08), lineWidth: 2)
            Image(systemName: "star.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}
