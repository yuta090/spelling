import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var iris = IrisController()
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingResults = false
    @State private var showingWordPreview = false
    @State private var showingCharacterPicker = false
    @State private var showingStepPicker = false
    @State private var showingPracticeRetryPicker = false
    @State private var selectedPracticeWordIDs = Set<UUID>()
    @State private var retryPracticeWordIDs = Set<UUID>()
    @State private var lastPracticeWordIDs = Set<UUID>()
    @State private var completedPracticeWordIDs = Set<UUID>()
    @State private var practiceResumeState: PracticeSessionResumeState?

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    private var selectedPracticeWords: [SpellingWord] {
        model.activeWords.filter { selectedPracticeWordIDs.contains($0.id) }
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
                HomeBackground()

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
                            startPractice: startPractice,
                            showWords: { showingWordPreview = true },
                            showStepPicker: { showingStepPicker = true },
                            showCharacters: { showingCharacterPicker = true },
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
            .navigationDestination(item: $activeMode) { mode in
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
            .fullScreenCover(isPresented: $showingParent) {
                ParentDashboardView()
                    .environmentObject(model)
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
        }
        .onChange(of: model.activeWords.map(\.id)) { _, _ in
            schedulePracticeSelectionSync()
        }
        .onChange(of: model.homeReviewWordIDs) { _, _ in
            schedulePracticeSelectionSync()
        }
        .onChange(of: model.focusedPracticeWordIDs) { _, _ in
            schedulePracticeSelectionSync()
        }
        .onChange(of: selectedPracticeWordIDs) { _, _ in
            clearCompletedPracticeRoundIfWordsChanged()
            clearPracticeResumeIfWordsChanged()
        }

            IrisTransitionOverlay(controller: iris)
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

    private var header: some View {
        HStack(spacing: 14) {
            Label(language.text(japanese: "ホーム", english: "Home"), systemImage: "house.fill")
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
                showingParent = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
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
    var startPractice: () -> Void
    var showWords: () -> Void
    var showStepPicker: () -> Void
    var showCharacters: () -> Void
    var startTest: () -> Void

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

private struct ChildStepPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(language.text(japanese: "ステップをえらぼう", english: "Choose a Step"))
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                        Text(language.text(japanese: "やりたい単語セットをタップしてね", english: "Tap the word set you want"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    if orderedSteps.isEmpty {
                        ContentUnavailableView(
                            language.text(japanese: "まだステップがありません", english: "No steps yet"),
                            systemImage: "book.closed.fill",
                            description: Text(language.text(japanese: "保護者メニューで単語を登録してください。", english: "Add words in the parent menu."))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(orderedSteps) { step in
                                    ChildStepPickerCard(
                                        step: step,
                                        progress: model.todayProgress(for: step),
                                        language: language,
                                        isSelected: step.id == model.selectedWordStepID
                                    ) {
                                        model.selectedWordStepID = step.id
                                        dismiss()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 24)
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
}

private struct ChildStepPickerCard: View {
    var step: WordStep
    var progress: TodayStepProgress
    var language: AppLanguage
    var isSelected: Bool
    var action: () -> Void

    private var statusText: String {
        if progress.totalWords == 0 {
            return language.text(japanese: "たんごなし", english: "No words")
        }
        if progress.isComplete {
            return language.text(japanese: "きょうはできた", english: "Done today")
        }
        if progress.hasTestActivity || progress.clearedCount > 0 {
            return language.text(japanese: "きょう \(progress.clearedCount)こできた", english: "\(progress.clearedCount) done today")
        }
        return language.text(japanese: "これから", english: "Ready")
    }

    private var cardTint: Color {
        isSelected ? Color(red: 0.16, green: 0.42, blue: 0.84) : Color(red: 0.48, green: 0.30, blue: 0.76)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(cardTint.opacity(isSelected ? 1 : 0.14))
                        .frame(width: 58, height: 58)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "rectangle.stack.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(isSelected ? .white : cardTint)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(step.title(language: language))
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(language.text(japanese: "\(step.words.count)こ", english: "\(step.words.count) words"))
                            .font(.headline.monospacedDigit().weight(.heavy))
                            .foregroundStyle(Color(red: 0.14, green: 0.35, blue: 0.76))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color(red: 0.90, green: 0.96, blue: 1.0))
                            .clipShape(Capsule())

                        Text(statusText)
                            .font(.headline.monospacedDigit().weight(.heavy))
                            .foregroundStyle(progress.isComplete ? Color(red: 0.20, green: 0.58, blue: 0.24) : Color(red: 0.50, green: 0.33, blue: 0.74))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.42, green: 0.54, blue: 0.72))
            }
            .padding(16)
            .background(isSelected ? Color(red: 0.91, green: 0.96, blue: 1.0) : .white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(red: 0.16, green: 0.42, blue: 0.84) : Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .accessibilityLabel("\(step.title(language: language))。\(step.words.count)。\(statusText)")
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
            ZStack {
                HomeBackground()

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
                        ContentUnavailableView(
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
                .frame(maxWidth: 760)
                .padding(28)
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

    private var canRegister: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()

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
        let count = model.addChildWords(from: rawText)
        guard count > 0 else {
            statusMessage = language.text(japanese: "あたらしい ことばが ないみたい。", english: "No new words to add.")
            return
        }
        onRegistered()
    }

    private func readImage(_ image: UIImage) {
        isReadingImage = true
        statusMessage = nil
        Task {
            do {
                let recognized = try await WordListImageTextRecognizer(language: model.settings.language)
                    .recognizeWords(in: image)
                await MainActor.run {
                    appendWords(recognized)
                    isReadingImage = false
                }
            } catch {
                await MainActor.run {
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
        .onChange(of: isExpanded) { _, expanded in
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
                        ContentUnavailableView(
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

    static let defaultUnlockedIDs: Set<String> = ["bear", "cat", "dog"]

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
            price: 3,
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
            price: 3,
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
            price: 4,
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
            price: 5,
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
            price: 4,
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
            price: 4,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 6,
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
            price: 4,
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
            price: 6,
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
            price: 5,
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
            price: 6,
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
            price: 4,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 5,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 7,
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
            price: 6,
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
            price: 5,
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
            price: 4,
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
            price: 4,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 6,
            style: .personPonytail,
            primary: Color(red: 0.4000, green: 0.2588, blue: 0.1647),
            secondary: Color(red: 0.8784, green: 0.5412, blue: 0.2353),
            accent: Color(red: 0.8784, green: 0.4157, blue: 0.6588)
        ),
        HomeRewardCharacter(
            id: "robot",
            category: .fantasy,
            japaneseName: "ロボット",
            englishName: "Robot",
            price: 6,
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
            price: 5,
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
            price: 5,
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
            price: 7,
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
            price: 7,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 6,
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
            price: 6,
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
            price: 6,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 7,
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
            price: 6,
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
            price: 5,
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
            price: 6,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 4,
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
            price: 6,
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
            price: 6,
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
            price: 6,
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
            price: 5,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 4,
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
            price: 6,
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
            price: 6,
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
            price: 4,
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
            price: 5,
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
            price: 5,
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
            price: 5,
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
            price: 7,
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
            price: 6,
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
            price: 5,
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
            price: 7,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 5,
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
            price: 5,
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
            price: 6,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 6,
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
            price: 5,
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
            price: 7,
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
            price: 7,
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
            price: 6,
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
            price: 6,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 5,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 7,
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
            price: 6,
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
            price: 6,
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
            price: 7,
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
            price: 7,
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
            price: 6,
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
            price: 7,
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
            price: 6,
            style: .gasshou,
            primary: Color(red: 0.6196, green: 0.4824, blue: 0.2902),
            secondary: Color(red: 0.7804, green: 0.7216, blue: 0.6196),
            accent: Color(red: 0.3608, green: 0.2627, blue: 0.1608)
        )
    ]
    // CATALOG-GENERATED-END
}

private struct CharacterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 122), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    HomeBackground()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(language.text(japanese: "なかまをえらぼう", english: "Choose a Buddy"))
                                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                                    Text(language.text(japanese: "れんしゅうでコインをためて、なかまをふやせます。", english: "Practice to earn coins and unlock buddies."))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HomeCoinBadge(coins: model.rewardCoins, language: language)
                            }

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
                        }
                        .frame(maxWidth: 820, minHeight: geometry.size.height, alignment: .top)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .background(Color.white.opacity(0.001))
                        .contentShape(Rectangle())
                    }
                    .scrollIndicators(.visible)
                    .scrollBounceBehavior(.basedOnSize)
                }
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
                .opacity(canUnlock ? 1 : 0.46)

            Text(character.name(language: language))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.56)

            statePill
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.white.opacity(canUnlock ? 0.92 : 0.64))
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
        }
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
        .frame(maxWidth: .infinity, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
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

private struct RewardCharacterAvatar: View {
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
            }
        }
        .padding(4)
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
        case .long, .ponytail, .bun:
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

private struct HomeBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.97, blue: 1.0),
                    Color(red: 0.98, green: 0.99, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Cloud()
                .fill(.white.opacity(0.78))
                .frame(width: 150, height: 62)
                .offset(x: -330, y: -560)
            Cloud()
                .fill(.white.opacity(0.68))
                .frame(width: 120, height: 54)
                .offset(x: 320, y: -550)

            Hills()
                .fill(Color(red: 0.73, green: 0.88, blue: 0.54))
                .frame(height: 142)
                .ignoresSafeArea(edges: .bottom)

            Hills()
                .fill(Color(red: 0.52, green: 0.80, blue: 0.73).opacity(0.75))
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

#Preview {
    HomeView()
        .environmentObject(AppModel())
}
