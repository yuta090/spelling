import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingResults = false
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

                    Spacer(minLength: 8)

                    ChildTaskBanner(
                        title: language.text(japanese: "きょうは なにをする？", english: "What will you do today?"),
                        message: language.text(japanese: "ステップをえらんで、れんしゅうかテストをおしてね。", english: "Choose a step, then pick practice or test."),
                        systemImage: "sparkles",
                        tint: Color(red: 0.12, green: 0.36, blue: 0.76)
                    )
                    .frame(maxWidth: 760)

                    StepSelectorPanel(language: language)
                        .environmentObject(model)
                        .frame(maxWidth: 760)

                    PracticeWordPickerPanel(
                        words: model.activeWords,
                        selectedIDs: $selectedPracticeWordIDs,
                        language: language
                    )
                    .frame(maxWidth: 760)

                    HStack(alignment: .center, spacing: 24) {
                        VStack(spacing: 18) {
                            HomeActionCard(
                                title: practiceButtonTitle,
                                subtitle: practiceButtonSubtitle,
                                systemImage: "pencil",
                                colors: [Color(red: 0.35, green: 0.64, blue: 0.96), Color(red: 0.10, green: 0.35, blue: 0.78)],
                                disabled: selectedPracticeWords.isEmpty
                            ) {
                                activeMode = .practice
                            }

                            HomeActionCard(
                                title: testButtonTitle,
                                subtitle: testButtonSubtitle,
                                systemImage: testButtonIcon,
                                colors: testButtonColors,
                                disabled: model.nextTestWords.isEmpty
                            ) {
                                activeMode = .test
                            }
                        }
                        .frame(maxWidth: 440)

                        TodayProgressCard(language: language, progress: model.todayStepProgress) {
                            activeMode = .review
                        }
                        .frame(width: 270)
                    }

                    HomeStatsRow(language: language)
                        .environmentObject(model)

                    Spacer(minLength: 64)
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            syncPracticeSelectionIfNeeded()
        }
        .onChange(of: model.activeWords.map(\.id)) { _, _ in
            syncPracticeSelectionIfNeeded()
        }
    }

    private var practiceButtonTitle: String {
        let count = selectedPracticeWords.count
        if count == 0 {
            return language.text(japanese: "たんごをえらんで", english: "Choose Words")
        }
        return language.text(japanese: "えらんだ\(count)こをれんしゅう", english: "Practice \(count) selected")
    }

    private var practiceButtonSubtitle: String {
        if selectedPracticeWords.isEmpty {
            return language.text(japanese: "チェックをつけてね", english: "Check words first")
        }
        return language.text(japanese: "チェックした単語だけやる", english: "Only checked words")
    }

    private var testButtonTitle: String {
        let progress = model.todayStepProgress
        if progress.isComplete {
            return progress.hasPerfectRun
                ? language.text(japanese: "もう一回通し", english: "Run Again")
                : language.text(japanese: "しあげテスト", english: "Final Test")
        }
        if progress.hasTestActivity {
            return language.text(japanese: "あと\(progress.remainingCount)こだけ", english: "\(progress.remainingCount) left")
        }
        return language.text(japanese: "テストする", english: "Take Test")
    }

    private var testButtonSubtitle: String {
        let progress = model.todayStepProgress
        if progress.isComplete {
            return progress.hasPerfectRun
                ? language.text(japanese: "完全クリア済み", english: "Fully cleared")
                : language.text(japanese: "全部通しでもう一回", english: "Try the full set")
        }
        if progress.hasTestActivity {
            return language.text(japanese: "残りだけチャレンジ", english: "Only the remaining words")
        }
        return language.text(japanese: "まずは全部やってみよう", english: "Start with the full set")
    }

    private var testButtonIcon: String {
        let progress = model.todayStepProgress
        if progress.isComplete {
            return progress.hasPerfectRun ? "checkmark.seal.fill" : "flag.checkered"
        }
        if progress.hasTestActivity {
            return "arrow.counterclockwise.circle.fill"
        }
        return "checkmark.clipboard.fill"
    }

    private var testButtonColors: [Color] {
        let progress = model.todayStepProgress
        if progress.isComplete {
            return [
                Color(red: 0.96, green: 0.66, blue: 0.14),
                Color(red: 0.78, green: 0.45, blue: 0.10)
            ]
        }
        if progress.hasTestActivity {
            return [
                Color(red: 0.38, green: 0.72, blue: 0.96),
                Color(red: 0.14, green: 0.42, blue: 0.78)
            ]
        }
        return [
            Color(red: 0.50, green: 0.78, blue: 0.34),
            Color(red: 0.18, green: 0.58, blue: 0.20)
        ]
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

private struct PracticeWordPickerPanel: View {
    var words: [SpellingWord]
    @Binding var selectedIDs: Set<UUID>
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
                    Label(language.text(japanese: "れんしゅうする単語をえらぼう", english: "Choose Practice Words"), systemImage: "checkmark.square.fill")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color(red: 0.49, green: 0.30, blue: 0.78))
                    Text(language.text(japanese: "チェックした単語だけ、まとめてれんしゅうします。", english: "Only checked words will be practiced together."))
                        .font(.subheadline.weight(.semibold))
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
