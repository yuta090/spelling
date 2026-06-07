import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
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

    var body: some View {
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
                            character: selectedCharacter,
                            startPractice: startPractice,
                            showWords: { showingWordPreview = true },
                            showStepPicker: { showingStepPicker = true },
                            showCharacters: { showingCharacterPicker = true },
                            startTest: { activeMode = .test }
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
            }
            .sheet(isPresented: $showingStepPicker) {
                ChildStepPickerSheet(language: language)
                    .environmentObject(model)
                    .presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            syncPracticeSelectionIfNeeded()
            applyFocusedPracticeSelectionIfNeeded()
        }
        .onChange(of: model.activeWords.map(\.id)) { _, _ in
            syncPracticeSelectionIfNeeded()
        }
        .onChange(of: model.homeReviewWordIDs) { _, _ in
            syncPracticeSelectionIfNeeded()
        }
        .onChange(of: model.focusedPracticeWordIDs) { _, _ in
            applyFocusedPracticeSelectionIfNeeded()
        }
        .onChange(of: selectedPracticeWordIDs) { _, _ in
            clearCompletedPracticeRoundIfWordsChanged()
            clearPracticeResumeIfWordsChanged()
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
        activeMode = .practice
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
        DispatchQueue.main.async {
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
            .tapFeedback()
            .accessibilityLabel(language.text(japanese: "結果", english: "Results"))

            Button {
                showingParent = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .tapFeedback()
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
                    .tapFeedback(scale: 0.94)
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
                    }
                    .buttonStyle(.plain)
                    .tapFeedback()
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

            if carryOverCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.headline.weight(.bold))
                    Text(language.text(japanese: "まえのステップから \(carryOverCount)こ", english: "\(carryOverCount) from the last step"))
                        .font(.headline.monospacedDigit().weight(.heavy))
                    Text(language.text(japanese: "テストにでる", english: "in the test"))
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color(red: 0.74, green: 0.34, blue: 0.06))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(red: 1.0, green: 0.94, blue: 0.84))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button(action: startPractice) {
                Label(
                    primaryButtonTitle,
                    systemImage: primaryButtonIcon
                )
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tapFeedback()
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
                    title: language.text(japanese: "テスト", english: "Test"),
                    systemImage: "checkmark.clipboard.fill",
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
            .tapFeedback()
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
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .accessibilityLabel("\(step.title(language: language))。\(step.words.count)。\(statusText)")
    }
}

private struct PracticeWordPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var words: [SpellingWord]
    var stepTitle: String
    var language: AppLanguage

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
                    }

                    if words.isEmpty {
                        ContentUnavailableView(
                            language.text(japanese: "たんごがありません", english: "No words"),
                            systemImage: "list.bullet",
                            description: Text(language.text(japanese: "保護者メニューで単語を入れてください。", english: "Add words in the parent menu."))
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(words) { word in
                                    PracticeWordPreviewChip(word: word)
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
        }
    }
}

private struct PracticeWordPreviewChip: View {
    var word: SpellingWord

    private var prompt: String {
        word.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.text)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

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
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1)
        )
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
                            }
                            .buttonStyle(.bordered)
                            .tapFeedback()

                            Button {
                                selectedIDs = []
                            } label: {
                                Label(language.text(japanese: "はずす", english: "Clear"), systemImage: "square")
                            }
                            .buttonStyle(.bordered)
                            .tapFeedback()

                            Spacer(minLength: 0)
                        }
                        .font(.headline.weight(.bold))

                        Button(action: onStart) {
                            Label(language.text(japanese: "これを れんしゅう", english: "Practice These"), systemImage: "pencil.line")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
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
            }
            .buttonStyle(.borderedProminent)
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
                    }
                    .buttonStyle(.bordered)
            .tapFeedback()

                    Button {
                        selectedIDs = []
                    } label: {
                        Label(language.text(japanese: "チェックをはずす", english: "Clear"), systemImage: "square")
                    }
                    .buttonStyle(.bordered)
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
        }
        .buttonStyle(.plain)
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
        }
        .buttonStyle(.plain)
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
        }
        .buttonStyle(.plain)
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
            }
            .buttonStyle(.borderedProminent)
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

private enum HomeRewardCharacterCategory: String, CaseIterable, Identifiable {
    case starter
    case animal
    case vehicle

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .starter:
            return language.text(japanese: "きほん", english: "Starter")
        case .animal:
            return language.text(japanese: "どうぶつ", english: "Animals")
        case .vehicle:
            return language.text(japanese: "のりもの", english: "Vehicles")
        }
    }
}

private enum HomeRewardCharacterStyle {
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
}

private struct HomeRewardCharacter: Identifiable {
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

    static let catalog: [HomeRewardCharacter] = [
        HomeRewardCharacter(
            id: "bear",
            category: .starter,
            japaneseName: "くま",
            englishName: "Bear",
            price: 0,
            style: .bear,
            primary: Color(red: 0.87, green: 0.55, blue: 0.22),
            secondary: Color(red: 0.97, green: 0.77, blue: 0.44),
            accent: Color(red: 0.49, green: 0.30, blue: 0.16)
        ),
        HomeRewardCharacter(
            id: "cat",
            category: .starter,
            japaneseName: "ねこ",
            englishName: "Cat",
            price: 0,
            style: .cat,
            primary: Color(red: 0.58, green: 0.64, blue: 0.78),
            secondary: Color(red: 0.92, green: 0.87, blue: 0.76),
            accent: Color(red: 0.32, green: 0.34, blue: 0.46)
        ),
        HomeRewardCharacter(
            id: "dog",
            category: .starter,
            japaneseName: "いぬ",
            englishName: "Dog",
            price: 0,
            style: .dog,
            primary: Color(red: 0.76, green: 0.53, blue: 0.30),
            secondary: Color(red: 0.98, green: 0.78, blue: 0.48),
            accent: Color(red: 0.44, green: 0.28, blue: 0.16)
        ),
        HomeRewardCharacter(
            id: "rabbit",
            category: .animal,
            japaneseName: "うさぎ",
            englishName: "Rabbit",
            price: 3,
            style: .rabbit,
            primary: Color(red: 0.95, green: 0.80, blue: 0.90),
            secondary: Color(red: 1.0, green: 0.94, blue: 0.98),
            accent: Color(red: 0.75, green: 0.38, blue: 0.62)
        ),
        HomeRewardCharacter(
            id: "panda",
            category: .animal,
            japaneseName: "パンダ",
            englishName: "Panda",
            price: 3,
            style: .panda,
            primary: Color(red: 0.17, green: 0.19, blue: 0.23),
            secondary: Color(red: 0.96, green: 0.96, blue: 0.92),
            accent: Color(red: 0.35, green: 0.62, blue: 0.36)
        ),
        HomeRewardCharacter(
            id: "penguin",
            category: .animal,
            japaneseName: "ペンギン",
            englishName: "Penguin",
            price: 4,
            style: .penguin,
            primary: Color(red: 0.18, green: 0.31, blue: 0.62),
            secondary: Color(red: 0.94, green: 0.97, blue: 1.0),
            accent: Color(red: 0.96, green: 0.62, blue: 0.12)
        ),
        HomeRewardCharacter(
            id: "lion",
            category: .animal,
            japaneseName: "ライオン",
            englishName: "Lion",
            price: 5,
            style: .lion,
            primary: Color(red: 0.94, green: 0.53, blue: 0.12),
            secondary: Color(red: 1.0, green: 0.78, blue: 0.30),
            accent: Color(red: 0.58, green: 0.26, blue: 0.08)
        ),
        HomeRewardCharacter(
            id: "fox",
            category: .animal,
            japaneseName: "きつね",
            englishName: "Fox",
            price: 4,
            style: .fox,
            primary: Color(red: 0.92, green: 0.43, blue: 0.12),
            secondary: Color(red: 1.0, green: 0.88, blue: 0.70),
            accent: Color(red: 0.43, green: 0.18, blue: 0.08)
        ),
        HomeRewardCharacter(
            id: "koala",
            category: .animal,
            japaneseName: "コアラ",
            englishName: "Koala",
            price: 4,
            style: .koala,
            primary: Color(red: 0.56, green: 0.61, blue: 0.66),
            secondary: Color(red: 0.88, green: 0.90, blue: 0.92),
            accent: Color(red: 0.22, green: 0.24, blue: 0.28)
        ),
        HomeRewardCharacter(
            id: "hamster",
            category: .animal,
            japaneseName: "ハムスター",
            englishName: "Hamster",
            price: 4,
            style: .bear,
            primary: Color(red: 0.86, green: 0.64, blue: 0.38),
            secondary: Color(red: 1.0, green: 0.86, blue: 0.62),
            accent: Color(red: 0.50, green: 0.28, blue: 0.12)
        ),
        HomeRewardCharacter(
            id: "sheep",
            category: .animal,
            japaneseName: "ひつじ",
            englishName: "Sheep",
            price: 5,
            style: .sheep,
            primary: Color(red: 0.96, green: 0.96, blue: 0.90),
            secondary: Color(red: 0.72, green: 0.76, blue: 0.82),
            accent: Color(red: 0.38, green: 0.40, blue: 0.46)
        ),
        HomeRewardCharacter(
            id: "elephant",
            category: .animal,
            japaneseName: "ぞう",
            englishName: "Elephant",
            price: 5,
            style: .elephant,
            primary: Color(red: 0.55, green: 0.63, blue: 0.74),
            secondary: Color(red: 0.82, green: 0.88, blue: 0.96),
            accent: Color(red: 0.24, green: 0.31, blue: 0.44)
        ),
        HomeRewardCharacter(
            id: "giraffe",
            category: .animal,
            japaneseName: "キリン",
            englishName: "Giraffe",
            price: 5,
            style: .giraffe,
            primary: Color(red: 0.94, green: 0.68, blue: 0.22),
            secondary: Color(red: 1.0, green: 0.86, blue: 0.44),
            accent: Color(red: 0.57, green: 0.31, blue: 0.08)
        ),
        HomeRewardCharacter(
            id: "owl",
            category: .animal,
            japaneseName: "ふくろう",
            englishName: "Owl",
            price: 5,
            style: .owl,
            primary: Color(red: 0.60, green: 0.38, blue: 0.18),
            secondary: Color(red: 0.95, green: 0.78, blue: 0.48),
            accent: Color(red: 0.28, green: 0.17, blue: 0.10)
        ),
        HomeRewardCharacter(
            id: "turtle",
            category: .animal,
            japaneseName: "かめ",
            englishName: "Turtle",
            price: 5,
            style: .turtle,
            primary: Color(red: 0.22, green: 0.58, blue: 0.30),
            secondary: Color(red: 0.72, green: 0.86, blue: 0.42),
            accent: Color(red: 0.12, green: 0.36, blue: 0.18)
        ),
        HomeRewardCharacter(
            id: "whale",
            category: .animal,
            japaneseName: "くじら",
            englishName: "Whale",
            price: 6,
            style: .whale,
            primary: Color(red: 0.22, green: 0.48, blue: 0.80),
            secondary: Color(red: 0.78, green: 0.92, blue: 1.0),
            accent: Color(red: 0.12, green: 0.26, blue: 0.52)
        ),
        HomeRewardCharacter(
            id: "frog",
            category: .animal,
            japaneseName: "かえる",
            englishName: "Frog",
            price: 4,
            style: .panda,
            primary: Color(red: 0.15, green: 0.56, blue: 0.26),
            secondary: Color(red: 0.76, green: 0.94, blue: 0.58),
            accent: Color(red: 0.08, green: 0.32, blue: 0.14)
        ),
        HomeRewardCharacter(
            id: "tiger",
            category: .animal,
            japaneseName: "トラ",
            englishName: "Tiger",
            price: 6,
            style: .lion,
            primary: Color(red: 0.96, green: 0.50, blue: 0.10),
            secondary: Color(red: 1.0, green: 0.76, blue: 0.28),
            accent: Color(red: 0.20, green: 0.13, blue: 0.08)
        ),
        HomeRewardCharacter(
            id: "squirrel",
            category: .animal,
            japaneseName: "リス",
            englishName: "Squirrel",
            price: 5,
            style: .cat,
            primary: Color(red: 0.66, green: 0.38, blue: 0.16),
            secondary: Color(red: 0.94, green: 0.68, blue: 0.36),
            accent: Color(red: 0.34, green: 0.18, blue: 0.08)
        ),
        HomeRewardCharacter(
            id: "deer",
            category: .animal,
            japaneseName: "しか",
            englishName: "Deer",
            price: 6,
            style: .rabbit,
            primary: Color(red: 0.67, green: 0.42, blue: 0.20),
            secondary: Color(red: 0.96, green: 0.76, blue: 0.48),
            accent: Color(red: 0.36, green: 0.20, blue: 0.10)
        ),
        HomeRewardCharacter(
            id: "car",
            category: .vehicle,
            japaneseName: "くるま",
            englishName: "Car",
            price: 4,
            style: .car,
            primary: Color(red: 0.18, green: 0.46, blue: 0.86),
            secondary: Color(red: 0.66, green: 0.86, blue: 1.0),
            accent: Color(red: 0.08, green: 0.18, blue: 0.36)
        ),
        HomeRewardCharacter(
            id: "train",
            category: .vehicle,
            japaneseName: "でんしゃ",
            englishName: "Train",
            price: 5,
            style: .train,
            primary: Color(red: 0.20, green: 0.62, blue: 0.38),
            secondary: Color(red: 0.82, green: 0.96, blue: 0.74),
            accent: Color(red: 0.10, green: 0.32, blue: 0.20)
        ),
        HomeRewardCharacter(
            id: "rocket",
            category: .vehicle,
            japaneseName: "ロケット",
            englishName: "Rocket",
            price: 6,
            style: .rocket,
            primary: Color(red: 0.78, green: 0.30, blue: 0.72),
            secondary: Color(red: 0.98, green: 0.90, blue: 1.0),
            accent: Color(red: 0.96, green: 0.55, blue: 0.10)
        ),
        HomeRewardCharacter(
            id: "plane",
            category: .vehicle,
            japaneseName: "ひこうき",
            englishName: "Plane",
            price: 6,
            style: .plane,
            primary: Color(red: 0.28, green: 0.62, blue: 0.90),
            secondary: Color(red: 0.86, green: 0.96, blue: 1.0),
            accent: Color(red: 0.14, green: 0.34, blue: 0.70)
        ),
        HomeRewardCharacter(
            id: "bus",
            category: .vehicle,
            japaneseName: "バス",
            englishName: "Bus",
            price: 5,
            style: .bus,
            primary: Color(red: 0.96, green: 0.70, blue: 0.12),
            secondary: Color(red: 1.0, green: 0.92, blue: 0.54),
            accent: Color(red: 0.58, green: 0.36, blue: 0.06)
        ),
        HomeRewardCharacter(
            id: "truck",
            category: .vehicle,
            japaneseName: "トラック",
            englishName: "Truck",
            price: 5,
            style: .car,
            primary: Color(red: 0.22, green: 0.52, blue: 0.72),
            secondary: Color(red: 0.72, green: 0.90, blue: 1.0),
            accent: Color(red: 0.10, green: 0.25, blue: 0.36)
        ),
        HomeRewardCharacter(
            id: "ship",
            category: .vehicle,
            japaneseName: "ふね",
            englishName: "Ship",
            price: 6,
            style: .ship,
            primary: Color(red: 0.20, green: 0.42, blue: 0.78),
            secondary: Color(red: 0.84, green: 0.94, blue: 1.0),
            accent: Color(red: 0.82, green: 0.34, blue: 0.18)
        ),
        HomeRewardCharacter(
            id: "helicopter",
            category: .vehicle,
            japaneseName: "ヘリコプター",
            englishName: "Helicopter",
            price: 6,
            style: .helicopter,
            primary: Color(red: 0.84, green: 0.28, blue: 0.28),
            secondary: Color(red: 1.0, green: 0.82, blue: 0.74),
            accent: Color(red: 0.48, green: 0.12, blue: 0.12)
        ),
        HomeRewardCharacter(
            id: "bicycle",
            category: .vehicle,
            japaneseName: "じてんしゃ",
            englishName: "Bicycle",
            price: 5,
            style: .bicycle,
            primary: Color(red: 0.52, green: 0.34, blue: 0.82),
            secondary: Color(red: 0.92, green: 0.86, blue: 1.0),
            accent: Color(red: 0.28, green: 0.16, blue: 0.54)
        ),
        HomeRewardCharacter(
            id: "tractor",
            category: .vehicle,
            japaneseName: "トラクター",
            englishName: "Tractor",
            price: 6,
            style: .tractor,
            primary: Color(red: 0.22, green: 0.62, blue: 0.28),
            secondary: Color(red: 0.88, green: 0.96, blue: 0.66),
            accent: Color(red: 0.12, green: 0.32, blue: 0.16)
        ),
        HomeRewardCharacter(
            id: "balloon",
            category: .vehicle,
            japaneseName: "ききゅう",
            englishName: "Balloon",
            price: 6,
            style: .balloon,
            primary: Color(red: 0.82, green: 0.32, blue: 0.66),
            secondary: Color(red: 1.0, green: 0.84, blue: 0.94),
            accent: Color(red: 0.44, green: 0.20, blue: 0.36)
        ),
        HomeRewardCharacter(
            id: "submarine",
            category: .vehicle,
            japaneseName: "せんすいかん",
            englishName: "Submarine",
            price: 7,
            style: .ship,
            primary: Color(red: 0.88, green: 0.62, blue: 0.08),
            secondary: Color(red: 1.0, green: 0.90, blue: 0.40),
            accent: Color(red: 0.52, green: 0.34, blue: 0.05)
        ),
        HomeRewardCharacter(
            id: "firetruck",
            category: .vehicle,
            japaneseName: "しょうぼうしゃ",
            englishName: "Fire Truck",
            price: 7,
            style: .bus,
            primary: Color(red: 0.86, green: 0.16, blue: 0.12),
            secondary: Color(red: 1.0, green: 0.78, blue: 0.70),
            accent: Color(red: 0.48, green: 0.06, blue: 0.04)
        ),
        HomeRewardCharacter(
            id: "scooter",
            category: .vehicle,
            japaneseName: "スクーター",
            englishName: "Scooter",
            price: 6,
            style: .bicycle,
            primary: Color(red: 0.18, green: 0.62, blue: 0.70),
            secondary: Color(red: 0.80, green: 0.96, blue: 1.0),
            accent: Color(red: 0.08, green: 0.34, blue: 0.40)
        )
    ]
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
            ZStack {
                HomeBackground()

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

                    ScrollView {
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
                    }
                }
                .frame(maxWidth: 820)
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
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .disabled(!canUnlock)
        .accessibilityLabel(accessibilityText)
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
