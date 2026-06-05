import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingResults = false
    @State private var showingWordPreview = false
    @State private var selectedPracticeWordIDs = Set<UUID>()
    @State private var lastPracticeWordIDs = Set<UUID>()

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    private var selectedPracticeWords: [SpellingWord] {
        model.activeWords.filter { selectedPracticeWordIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                HomeBackground()

                VStack(spacing: 20) {
                    header

                    Spacer(minLength: 22)

                    ChildMissionPanel(
                        stepTitle: model.selectedWordStep?.title(language: language) ?? language.text(japanese: "いまのステップ", english: "Current step"),
                        practiceCount: selectedPracticeWords.count,
                        progress: model.todayStepProgress,
                        language: language,
                        canPractice: !selectedPracticeWords.isEmpty,
                        canTest: !model.nextTestWords.isEmpty,
                        startPractice: { activeMode = .practice },
                        showWords: { showingWordPreview = true },
                        startTest: { activeMode = .test }
                    )
                    .frame(maxWidth: 760)

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 36)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .navigationDestination(item: $activeMode) { mode in
                SpellingSessionView(
                    mode: mode,
                    words: sessionWords(for: mode)
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            syncPracticeSelectionIfNeeded()
        }
        .onChange(of: model.activeWords.map(\.id)) { _, _ in
            syncPracticeSelectionIfNeeded()
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
        guard activeIDs != lastPracticeWordIDs else {
            selectedPracticeWordIDs = selectedPracticeWordIDs.intersection(activeIDs)
            return
        }

        selectedPracticeWordIDs = activeIDs
        lastPracticeWordIDs = activeIDs
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
            .accessibilityLabel(language.text(japanese: "結果", english: "Results"))

            Button {
                showingParent = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .accessibilityLabel(language.text(japanese: "保護者メニュー", english: "Parent menu"))
        }
    }
}

private struct ChildMissionPanel: View {
    var stepTitle: String
    var practiceCount: Int
    var progress: TodayStepProgress
    var language: AppLanguage
    var canPractice: Bool
    var canTest: Bool
    var startPractice: () -> Void
    var showWords: () -> Void
    var startTest: () -> Void

    private var missionText: String {
        if practiceCount == 0 {
            return language.text(japanese: "たんごがない", english: "No words")
        }
        return language.text(japanese: "\(practiceCount)こ れんしゅう", english: "\(practiceCount) words")
    }

    private var progressValue: Double {
        guard progress.totalWords > 0 else {
            return 0
        }
        return Double(progress.clearedCount) / Double(progress.totalWords)
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 22) {
                BearMascot()
                    .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    Text(language.text(japanese: "きょうのミッション", english: "Today"))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(stepTitle)
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(Color(red: 0.14, green: 0.35, blue: 0.76))
                        .lineLimit(1)

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
                    japanese: "今日のクリア \(progress.clearedCount) / \(progress.totalWords)",
                    english: "Today \(progress.clearedCount) of \(progress.totalWords)"
                ))

            Button(action: startPractice) {
                Label(language.text(japanese: "はじめる", english: "Start"), systemImage: "play.fill")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.16, green: 0.42, blue: 0.84))
            .disabled(!canPractice)

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
        .tint(tint)
        .disabled(disabled)
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

                    Button {
                        selectedIDs = []
                    } label: {
                        Label(language.text(japanese: "チェックをはずす", english: "Clear"), systemImage: "square")
                    }
                    .buttonStyle(.bordered)

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
            return language.text(japanese: "完全クリア", english: "Fully Cleared")
        }
        if progress.isComplete {
            return language.text(japanese: "今日クリア", english: "Cleared Today")
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
                Text(language.text(japanese: "今日のクリア", english: "Today"))
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
                title: language.text(japanese: "クリア", english: "Clear"),
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
