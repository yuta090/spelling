import PencilKit
import SwiftUI
import UIKit

private enum ParentPalette {
    static let primary = Color(red: 0.17, green: 0.45, blue: 0.24)
    static let primarySoft = Color(red: 0.91, green: 0.97, blue: 0.90)
    static let surface = Color.white.opacity(0.92)
    static let surfaceRaised = Color.white.opacity(0.86)
    static let surfaceTint = Color(red: 0.97, green: 0.99, blue: 0.97)
    static let ink = Color(red: 0.12, green: 0.22, blue: 0.34)
    static let neutral = Color(red: 0.42, green: 0.48, blue: 0.52)
    static let neutralSoft = Color(red: 0.94, green: 0.96, blue: 0.95)
    static let success = Color(red: 0.20, green: 0.62, blue: 0.24)
    static let successSoft = Color(red: 0.90, green: 0.97, blue: 0.88)
    static let warning = Color(red: 0.84, green: 0.45, blue: 0.10)
    static let warningSoft = Color(red: 1.0, green: 0.95, blue: 0.88)
    static let danger = Color(red: 0.76, green: 0.22, blue: 0.18)
}

struct ParentDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: ParentSection = .grading

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParentBackground()

                VStack(spacing: 18) {
                    header
                    ParentSectionSwitcher(selectedSection: $selectedSection, language: language)
                    ParentCurrentStepCard(language: language)

                    GeometryReader { proxy in
                        ScrollView {
                            selectedPanel(width: proxy.size.width)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .padding(.bottom, 8)
                        }
                    }
                    .animation(.easeInOut(duration: 0.16), value: selectedSection)
                    .frame(maxHeight: .infinity)

                    Text(language.text(
                        japanese: "※ データは端末内に保存されます。iCloud同期にはまだ対応していません。",
                        english: "Data is saved on this device. iCloud sync is not included yet."
                    ))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func selectedPanel(width: CGFloat) -> some View {
        switch selectedSection {
        case .grading:
            ParentGradingPanel(language: language)
        case .words:
            if width >= 900 {
                HStack(alignment: .top, spacing: 14) {
                    ParentWordStepPanel(language: language)
                        .frame(width: min(max(width * 0.34, 330), 430), alignment: .top)

                    ParentWordListPanel(language: language)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: 14) {
                    ParentWordStepPanel(language: language)
                    ParentWordListPanel(language: language)
                }
            }
        case .records:
            ParentRecordsWorkspace(language: language)
        case .settings:
            TestSettingsPanel(language: language)
                .frame(maxWidth: 820, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack {
            Label(language.text(japanese: "保護者メニュー", english: "Parent Menu"), systemImage: "person.2.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(ParentPalette.primary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    .font(.headline.weight(.bold))
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .tapFeedback()
            .foregroundStyle(ParentPalette.primary)
            .background(ParentPalette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ParentPalette.primary.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

private enum ParentSection: String, CaseIterable, Identifiable {
    case grading
    case words
    case records
    case settings

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .grading:
            return language.text(japanese: "採点", english: "Grade")
        case .words:
            return language.text(japanese: "単語登録", english: "Words")
        case .records:
            return language.text(japanese: "結果を見る", english: "Results")
        case .settings:
            return language.text(japanese: "設定", english: "Settings")
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .grading:
            return language.text(japanese: "大きく見てOK", english: "Review clearly")
        case .words:
            return language.text(japanese: "ステップを準備", english: "Prepare steps")
        case .records:
            return language.text(japanese: "学校テスト・アプリ", english: "School & app")
        case .settings:
            return language.text(japanese: "出題と音声", english: "Prompts & voice")
        }
    }

    var systemImage: String {
        switch self {
        case .grading:
            return "checkmark.seal.fill"
        case .words:
            return "text.book.closed.fill"
        case .records:
            return "chart.bar.xaxis"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    var tint: Color {
        ParentPalette.primary
    }
}

private struct ParentSectionSwitcher: View {
    @Binding var selectedSection: ParentSection
    var language: AppLanguage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                sectionButtons
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    sectionButtons
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sectionButtons: some View {
        ForEach(ParentSection.allCases) { section in
            ParentSectionButton(
                section: section,
                isSelected: section == selectedSection,
                language: language
            ) {
                selectedSection = section
            }
        }
    }
}

private struct ParentSectionButton: View {
    var section: ParentSection
    var isSelected: Bool
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.title3.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(isSelected ? .white.opacity(0.22) : ParentPalette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title(language: language))
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                    Text(section.subtitle(language: language))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(isSelected ? 0.92 : 0.72)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : ParentPalette.primary)
            .frame(width: 172, height: 64, alignment: .leading)
            .padding(.horizontal, 12)
            .background(isSelected ? ParentPalette.primary : ParentPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? ParentPalette.primary : ParentPalette.primary.opacity(0.16), lineWidth: isSelected ? 0 : 1)
            )
            .shadow(color: isSelected ? ParentPalette.primary.opacity(0.16) : .black.opacity(0.05), radius: isSelected ? 12 : 7, x: 0, y: 5)
        }
        .buttonStyle(.plain)
            .tapFeedback()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ParentCurrentStepCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingStepChooser = false
    var language: AppLanguage

    var body: some View {
        let step = model.selectedWordStep

        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 40, height: 40)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "今の単語集", english: "Current Word Set"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(step?.title(language: language) ?? language.text(japanese: "ステップなし", english: "No step"))
                    .font(.title3.monospacedDigit().weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
            }

            Spacer(minLength: 0)

            Text(language.text(
                japanese: "\(step?.words.count ?? 0) 単語",
                english: "\(step?.words.count ?? 0) words"
            ))
            .font(.headline.monospacedDigit().weight(.heavy))
            .foregroundStyle(ParentPalette.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(ParentPalette.primarySoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !model.wordSteps.isEmpty {
                Button {
                    showingStepChooser = true
                } label: {
                    Label(language.text(japanese: "切り替え", english: "Switch"), systemImage: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .tint(ParentPalette.primary)
            }
        }
        .padding(12)
        .background(ParentPalette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
        .sheet(isPresented: $showingStepChooser) {
            ParentStepChooserSheet(
                title: language.text(japanese: "ステップを選ぶ", english: "Choose Step"),
                language: language,
                selectedStepID: model.selectedWordStepID
            ) { step in
                model.selectedWordStepID = step.id
            }
            .environmentObject(model)
            .presentationDetents([.large])
        }
    }
}

private struct ParentStepChooserSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    var title: String
    var language: AppLanguage
    var selectedStepID: String
    var onSelect: (WordStep) -> Void

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    private var filteredSteps: [WordStep] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return orderedSteps
        }

        return orderedSteps.filter { step in
            stepMatchesQuery(step, query: query)
        }
    }

    private var groupedSections: [ParentStepChooserMonthSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSteps) { step in
            let components = calendar.dateComponents([.year, .month], from: step.registeredDate)
            return calendar.date(from: components) ?? calendar.startOfDay(for: step.registeredDate)
        }

        return grouped.keys.sorted(by: >).map { date in
            ParentStepChooserMonthSection(
                date: date,
                steps: (grouped[date] ?? []).sorted { $0.registeredDate > $1.registeredDate }
            )
        }
    }

    private var schoolResultStepIDs: Set<String> {
        Set(model.schoolTestResults.compactMap(\.stepID))
    }

    private var selectedStep: WordStep? {
        orderedSteps.first { $0.id == selectedStepID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ParentStepChooserHeader(
                    selectedStep: selectedStep,
                    totalCount: orderedSteps.count,
                    filteredCount: filteredSteps.count,
                    language: language
                )

                if groupedSections.isEmpty {
                    ContentUnavailableView(
                        language.text(japanese: "見つかりません", english: "No matching steps"),
                        systemImage: "magnifyingglass",
                        description: Text(language.text(japanese: "ステップ番号、日付、単語で検索できます。", english: "Search by step number, date, or word."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedSections) { section in
                            Section(monthTitle(section.date)) {
                                ForEach(section.steps) { step in
                                    ParentStepChooserRow(
                                        step: step,
                                        language: language,
                                        isSelected: step.id == selectedStepID,
                                        hasSchoolResult: schoolResultStepIDs.contains(step.id)
                                    ) {
                                        select(step)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ParentBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: language.text(japanese: "ステップ・日付・単語を検索", english: "Search step, date, or word")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    }
                    .tapFeedback()
                }
            }
        }
    }

    private func select(_ step: WordStep) {
        onSelect(step)
        dismiss()
    }

    private func stepMatchesQuery(_ step: WordStep, query: String) -> Bool {
        let parts = [
            step.title(language: language),
            "\(step.number)",
            formattedStepDate(step.registeredDate, language: language),
            step.words.map(\.text).joined(separator: " "),
            step.words.map(\.promptText).joined(separator: " ")
        ]

        return parts.contains { part in
            part.localizedCaseInsensitiveContains(query)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .japanese ? Locale(identifier: "ja_JP") : Locale(identifier: "en_US")
        formatter.dateFormat = language == .japanese ? "yyyy年M月" : "MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct ParentStepChooserMonthSection: Identifiable {
    var date: Date
    var steps: [WordStep]

    var id: TimeInterval {
        date.timeIntervalSinceReferenceDate
    }
}

private struct ParentStepChooserHeader: View {
    var selectedStep: WordStep?
    var totalCount: Int
    var filteredCount: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.title2.weight(.heavy))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 46, height: 46)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(language.text(japanese: "いま選んでいる単語集", english: "Selected Word Set"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(selectedStep?.title(language: language) ?? language.text(japanese: "未選択", english: "Not selected"))
                    .font(.title3.monospacedDigit().weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
            }

            Spacer()

            Text(language.text(
                japanese: "\(filteredCount) / \(totalCount) 件",
                english: "\(filteredCount) / \(totalCount)"
            ))
            .font(.headline.monospacedDigit().weight(.heavy))
            .foregroundStyle(ParentPalette.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(ParentPalette.primarySoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(.white.opacity(0.88))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct ParentStepChooserRow: View {
    var step: WordStep
    var language: AppLanguage
    var isSelected: Bool
    var hasSchoolResult: Bool
    var action: () -> Void

    private var wordPreview: String {
        let previewWords = step.words.prefix(5).map(\.text).joined(separator: " / ")
        guard step.words.count > 5 else {
            return previewWords
        }
        return "\(previewWords) ..."
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "rectangle.stack")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(isSelected ? ParentPalette.primary : ParentPalette.neutral)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? ParentPalette.primarySoft : ParentPalette.neutralSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(step.title(language: language))
                            .font(.headline.monospacedDigit().weight(.heavy))
                            .foregroundStyle(ParentPalette.ink)

                        if hasSchoolResult {
                            Label(language.text(japanese: "学校結果あり", english: "School result"), systemImage: "graduationcap.fill")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(ParentPalette.primary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 7)
                                .background(ParentPalette.primarySoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Text("\(formattedStepDate(step.registeredDate, language: language)) ・ \(step.words.count) \(language.text(japanese: "単語", english: "words"))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(wordPreview)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ParentPalette.ink)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .listRowBackground(isSelected ? ParentPalette.primarySoft : Color.white.opacity(0.92))
    }
}

private struct ParentRecordsWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAppRecords = false
    @State private var showingOtherSteps = false
    var language: AppLanguage

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    private var selectedStep: WordStep? {
        model.selectedWordStep ?? orderedSteps.first
    }

    private var otherSteps: [WordStep] {
        guard let selectedStep else {
            return orderedSteps
        }
        return orderedSteps.filter { $0.id != selectedStep.id }
    }

    var body: some View {
        VStack(spacing: 14) {
            ParentPanel(
                title: language.text(japanese: "ステップ別の結果", english: "Step Results"),
                systemImage: "rectangle.stack.fill",
                tint: ParentPalette.primary
            ) {
                if orderedSteps.isEmpty {
                    ContentUnavailableView(
                        language.text(japanese: "まだステップがありません", english: "No steps yet"),
                        systemImage: "rectangle.stack.fill",
                        description: Text(language.text(japanese: "単語を登録すると、日付ごとのステップを確認できます。", english: "Register words to view steps by date."))
                    )
                    .frame(minHeight: 240)
                } else if let selectedStep {
                    VStack(spacing: 12) {
                        ParentStepRecordCard(step: selectedStep, language: language)
                            .environmentObject(model)

                        if !otherSteps.isEmpty {
                            DisclosureGroup(isExpanded: $showingOtherSteps) {
                                VStack(spacing: 10) {
                                    ForEach(otherSteps) { step in
                                        ParentStepRecordCard(step: step, language: language)
                                            .environmentObject(model)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                ParentOtherStepRecordsHeader(
                                    count: otherSteps.count,
                                    language: language
                                )
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.86))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showingAppRecords) {
                VStack(spacing: 14) {
                    AnswerReviewPanel(language: language)
                    LearningHistoryPanel(language: language)
                    HandwritingListPanel(language: language)
                }
                .padding(.top, 8)
            } label: {
                ParentAppRecordDisclosureHeader(language: language)
            }
            .padding(14)
            .background(.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
    }
}

private struct ParentOtherStepRecordsHeader: View {
    var count: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 38, height: 38)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "ほかのステップを見る", english: "View Other Steps"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                Text(language.text(japanese: "必要なときだけ開きます。", english: "Open only when needed."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(count)")
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(ParentPalette.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ParentAppRecordDisclosureHeader: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3.weight(.bold))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 38, height: 38)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "練習・テストの履歴を見る", english: "View Practice & Test History"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                Text(language.text(
                    japanese: "アプリ内で書いた内容や判定履歴を確認します。",
                    english: "Review handwriting and app decisions when needed."
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(model.attempts.count + model.practiceSamples.count)")
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(ParentPalette.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ParentStepRecordCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSchoolEntry = false
    @State private var testDate = Date()
    @State private var missedSchoolWordIDs = Set<UUID>()
    @State private var selectedSchoolResultID: UUID?
    @State private var note = ""
    var step: WordStep
    var language: AppLanguage

    private var stepWordKeys: Set<String> {
        Set(step.words.map { normalize($0.text) })
    }

    private var stepAttempts: [SpellingAttempt] {
        model.attempts.filter { stepWordKeys.contains(normalize($0.word)) }
    }

    private var schoolResults: [SchoolTestResult] {
        model.schoolTestResults(for: step)
    }

    private var latestSchoolResult: SchoolTestResult? {
        schoolResults.first
    }

    private var selectedSchoolResult: SchoolTestResult? {
        guard !schoolResults.isEmpty else {
            return nil
        }
        if let selectedSchoolResultID,
           let result = schoolResults.first(where: { $0.id == selectedSchoolResultID }) {
            return result
        }
        return schoolResults.first
    }

    private var carryOverReviewWords: [SpellingWord] {
        model.carryOverReviewWords(for: step)
    }

    private var latestAttemptsByWord: [String: SpellingAttempt] {
        var latest: [String: SpellingAttempt] = [:]
        for attempt in stepAttempts.sorted(by: { $0.date < $1.date }) {
            latest[normalize(attempt.word)] = attempt
        }
        return latest
    }

    private var learnedCount: Int {
        step.words.filter { word in
            guard let attempt = latestAttemptsByWord[normalize(word.text)] else {
                return false
            }
            return attemptIsCleared(attempt)
        }
        .count
    }

    private var appTestSessionCount: Int {
        Set(stepAttempts.map(\.sessionID)).count
    }

    private var reviewWords: [SpellingWord] {
        model.unresolvedReviewWords(for: step)
    }

    private var reviewWordIDs: Set<UUID> {
        Set(reviewWords.map(\.id))
    }

    private var reviewWordsAreOnHome: Bool {
        !reviewWordIDs.isEmpty
            && model.selectedWordStepID == step.id
            && model.focusedPracticeWordIDs == reviewWordIDs
    }

    private var schoolScoreText: String {
        guard let latestSchoolResult else {
            return language.text(japanese: "未入力", english: "Not entered")
        }
        if latestSchoolResult.score == latestSchoolResult.total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        return language.text(japanese: "\(latestSchoolResult.score)問正解", english: "\(latestSchoolResult.score) correct")
    }

    private var schoolTestTotal: Int {
        step.words.count
    }

    private var missedSchoolWords: [SpellingWord] {
        step.words.filter { missedSchoolWordIDs.contains($0.id) }
    }

    private var schoolTestScore: Int {
        max(schoolTestTotal - missedSchoolWords.count, 0)
    }

    private var primaryAction: ParentStepRecordPrimaryAction {
        if step.words.isEmpty {
            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "状態", english: "Status"),
                title: language.text(japanese: "単語がありません", english: "No words"),
                message: language.text(japanese: "単語登録からこのステップに単語を入れます。", english: "Add words to this step from word registration."),
                buttonTitle: nil,
                systemImage: "minus.circle.fill",
                tint: ParentPalette.neutral,
                kind: .none
            )
        }

        if let latestSchoolResult, reviewWords.isEmpty && learnedCount == step.words.count && latestSchoolResult.score == latestSchoolResult.total {
            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "状態", english: "Status"),
                title: language.text(japanese: "このステップはOK", english: "This step looks good"),
                message: language.text(japanese: "アプリのテスト結果と学校テスト結果はそろっています。別の日の結果も追加できます。", english: "App test and school test results are complete. You can add another test date if needed."),
                buttonTitle: nil,
                systemImage: "checkmark.seal.fill",
                tint: ParentPalette.success,
                kind: .none
            )
        }

        if latestSchoolResult == nil {
            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "まずやること", english: "First Action"),
                title: language.text(japanese: "学校テスト結果を入れる", english: "Enter school test result"),
                message: language.text(japanese: "点数と間違えた単語を入れると、復習すべきか判断できます。", english: "Enter score and missed words to decide whether review is needed."),
                buttonTitle: language.text(japanese: "結果を入れる", english: "Enter Result"),
                systemImage: "graduationcap.fill",
                tint: ParentPalette.primary,
                kind: .enterSchoolTest
            )
        }

        if !reviewWords.isEmpty {
            if reviewWordsAreOnHome {
                return ParentStepRecordPrimaryAction(
                    eyebrow: language.text(japanese: "準備できました", english: "Ready"),
                    title: language.text(japanese: "復習をホームに出しました", english: "Review is on Home"),
                    message: language.text(japanese: "子供メニューに表示中です。", english: "Shown on the child Home screen."),
                    buttonTitle: nil,
                    systemImage: "checkmark.circle.fill",
                    tint: ParentPalette.success,
                    kind: .none,
                    infoTitle: language.text(japanese: "復習のしくみ", english: "How Review Works"),
                    infoMessage: language.text(
                        japanese: "学校テストやアプリで間違えた単語だけをホームに出して、まとめて練習できます。",
                        english: "Only words missed in school or app tests are sent to Home for focused review."
                    )
                )
            }

            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "まずやること", english: "First Action"),
                title: language.text(japanese: "復習する単語をホームに出す", english: "Send review words to Home"),
                message: language.text(japanese: "ホームの復習に追加します。", english: "Add these to Home review."),
                buttonTitle: language.text(japanese: "復習に出す", english: "Use for Review"),
                systemImage: "arrow.counterclockwise.circle.fill",
                tint: ParentPalette.warning,
                kind: .reviewWords,
                infoTitle: language.text(japanese: "復習のしくみ", english: "How Review Works"),
                infoMessage: language.text(
                    japanese: "学校テストやアプリで間違えた単語だけをホームに出して、まとめて練習できます。",
                    english: "Only words missed in school or app tests are sent to Home for focused review."
                )
            )
        }

        return ParentStepRecordPrimaryAction(
            eyebrow: language.text(japanese: "状態", english: "Status"),
            title: language.text(japanese: "このステップは確認済み", english: "This step is checked"),
            message: language.text(japanese: "学校テストがもう一度返ってきたら、別の日の結果も追加できます。", english: "Add another school test result if a retest comes back."),
            buttonTitle: nil,
            systemImage: "eye.fill",
            tint: ParentPalette.primary,
            kind: .none
        )
    }

    private var canSaveSchoolResult: Bool {
        schoolTestTotal > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title(language: language))
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Label(
                        language.text(
                            japanese: "単語登録日 \(formattedStepDate(step.registeredDate, language: language))",
                            english: "Words added \(formattedStepDate(step.registeredDate, language: language))"
                        ),
                        systemImage: "calendar"
                    )
                    .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if step.id == model.selectedWordStepID {
                    Label(language.text(japanese: "選択中", english: "Selected"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(ParentPalette.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background(ParentPalette.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        model.selectedWordStepID = step.id
                    } label: {
                        Label(language.text(japanese: "このステップを選ぶ", english: "Select Step"), systemImage: "cursorarrow.rays")
                    }
                    .buttonStyle(.bordered)
            .tapFeedback()
                    .font(.caption.weight(.bold))
                    .tint(ParentPalette.primary)
                }
            }

            ParentStepRecordPrimaryActionCard(
                action: primaryAction,
                language: language
            ) {
                performPrimaryAction(primaryAction)
            }

            HStack(spacing: 10) {
                ParentStepMetricPill(
                    title: language.text(japanese: "覚えた単語", english: "Learned"),
                    value: "\(learnedCount)/\(step.words.count)",
                    systemImage: "brain.head.profile",
                    tint: ParentPalette.primary
                )
                ParentStepMetricPill(
                    title: language.text(japanese: "アプリのテスト回数", english: "App Test Count"),
                    value: language.text(japanese: "\(appTestSessionCount)回", english: "\(appTestSessionCount) times"),
                    systemImage: "checklist.checked",
                    tint: ParentPalette.primary
                )
                ParentStepMetricPill(
                    title: language.text(japanese: "学校テスト", english: "School Test"),
                    value: schoolScoreText,
                    systemImage: "graduationcap.fill",
                    tint: ParentPalette.primary
                )
            }

            if !carryOverReviewWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text(japanese: "前ステップから自動で出る", english: "Auto-added from previous step"), systemImage: "arrow.forward.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ParentPalette.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(carryOverReviewWords) { word in
                                Text(word.text)
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(ParentPalette.primary)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(ParentPalette.primarySoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Text(language.text(
                        japanese: "このステップのテストに、復習として自動で混ざります。",
                        english: "These words are automatically included in this step's test."
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(ParentPalette.surfaceTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !reviewWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text(japanese: "ふりかえり候補", english: "Review Words"), systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ParentPalette.warning)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(reviewWords) { word in
                                Text(word.text)
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(ParentPalette.warning)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(ParentPalette.warningSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Text(language.text(
                        japanese: "この候補だけをホームに出せます。",
                        english: "These candidates can be sent to Home."
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            if !schoolResults.isEmpty {
                SchoolTestResultDatePicker(
                    results: schoolResults,
                    selectedID: $selectedSchoolResultID,
                    language: language
                )

                if let selectedSchoolResult {
                    SchoolTestResultCard(result: selectedSchoolResult, language: language)
                        .environmentObject(model)
                }
            }

            if showingSchoolEntry {
                schoolEntryForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if latestSchoolResult != nil {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        showingSchoolEntry = true
                    }
                } label: {
                    Label(language.text(japanese: "別の日の学校テストを追加", english: "Add Another School Test"), systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .tint(ParentPalette.primary)
            }

            Text(step.words.map(\.text).joined(separator: " / "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color.white.opacity(step.id == model.selectedWordStepID ? 0.96 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(step.id == model.selectedWordStepID ? 0.09 : 0.05), radius: step.id == model.selectedWordStepID ? 14 : 9, x: 0, y: 6)
        .onAppear {
            prepareSchoolDefaultsIfNeeded()
            selectDefaultSchoolResultIfNeeded()
        }
        .onChange(of: schoolResults.map(\.id)) { _, _ in
            selectDefaultSchoolResultIfNeeded()
        }
    }

    private var schoolEntryForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DatePicker(
                    language.text(japanese: "テスト日", english: "Date"),
                    selection: $testDate,
                    displayedComponents: .date
                )
                .font(.headline.weight(.bold))
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)

                ParentSchoolScorePreview(
                    score: schoolTestScore,
                    total: schoolTestTotal,
                    language: language
                )
            }

            ParentSchoolMissedWordPicker(
                words: step.words,
                selectedWordIDs: $missedSchoolWordIDs,
                language: language
            )

            VStack(alignment: .leading, spacing: 6) {
                Label(language.text(japanese: "メモ", english: "Note"), systemImage: "note.text")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.body)
                    .frame(height: 54)
                    .padding(8)
                    .background(Color.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ParentPalette.primary.opacity(0.14), lineWidth: 1)
                    )
            }

            HStack {
                Text(language.text(
                    japanese: "間違えた単語は、このステップのふりかえり候補に出ます。",
                    english: "Missed words appear as review candidates for this step."
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    saveSchoolResult()
                } label: {
                    Label(language.text(japanese: "保存", english: "Save"), systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
            .tapFeedback()
                .tint(ParentPalette.primary)
                .disabled(!canSaveSchoolResult)
            }
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performPrimaryAction(_ action: ParentStepRecordPrimaryAction) {
        switch action.kind {
        case .enterSchoolTest:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                showingSchoolEntry = true
            }
        case .reviewWords:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                model.selectedWordStepID = step.id
                model.focusedPracticeWordIDs = reviewWordIDs
            }
        case .none:
            break
        }
    }

    private func attemptIsCleared(_ attempt: SpellingAttempt) -> Bool {
        if attempt.parentReviewDecision == .approved {
            return true
        }
        if attempt.parentReviewDecision == .needsPractice {
            return false
        }
        return attempt.decision == .autoCorrect
    }

    private func prepareSchoolDefaultsIfNeeded() {
        let validIDs = Set(step.words.map(\.id))
        missedSchoolWordIDs = missedSchoolWordIDs.filter { validIDs.contains($0) }
    }

    private func selectDefaultSchoolResultIfNeeded() {
        let resultIDs = Set(schoolResults.map(\.id))
        if let selectedSchoolResultID, resultIDs.contains(selectedSchoolResultID) {
            return
        }
        selectedSchoolResultID = schoolResults.first?.id
    }

    private func saveSchoolResult() {
        let missedWordsText = missedSchoolWords.map(\.text).joined(separator: "\n")
        let result = SchoolTestResult(
            date: testDate,
            stepID: step.id,
            stepTitle: step.title(language: language),
            score: schoolTestScore,
            total: schoolTestTotal,
            missedWords: missedWordsText,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        model.addSchoolTestResult(result)
        selectedSchoolResultID = result.id
        testDate = Date()
        missedSchoolWordIDs.removeAll()
        note = ""
        prepareSchoolDefaultsIfNeeded()
        showingSchoolEntry = false
    }
}

private enum ParentStepRecordPrimaryActionKind {
    case enterSchoolTest
    case reviewWords
    case none
}

private struct ParentStepRecordPrimaryAction {
    var eyebrow: String
    var title: String
    var message: String
    var buttonTitle: String?
    var systemImage: String
    var tint: Color
    var kind: ParentStepRecordPrimaryActionKind
    var infoTitle: String? = nil
    var infoMessage: String? = nil
}

private struct ParentInfoButton: View {
    @State private var showingInfo = false
    var title: String
    var message: String
    var tint: Color

    var body: some View {
        Button {
            showingInfo = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .accessibilityLabel(title)
        .popover(isPresented: $showingInfo, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 310, alignment: .leading)
            .background(ParentPalette.surfaceRaised)
        }
    }
}

private struct ParentStepRecordPrimaryActionCard: View {
    var action: ParentStepRecordPrimaryAction
    var language: AppLanguage
    var perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.title3.weight(.heavy))
                .foregroundStyle(action.tint)
                .frame(width: 42, height: 42)
                .background(action.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.eyebrow)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(action.tint)
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .layoutPriority(1)

                    if let infoTitle = action.infoTitle, let infoMessage = action.infoMessage {
                        ParentInfoButton(
                            title: infoTitle,
                            message: infoMessage,
                            tint: action.tint
                        )
                    }
                }
                Text(action.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let buttonTitle = action.buttonTitle {
                Button(action: perform) {
                    Label(buttonTitle, systemImage: "arrow.right.circle.fill")
                        .font(.headline.weight(.heavy))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.borderedProminent)
                .tapFeedback()
                .tint(action.tint)
            }
        }
        .padding(14)
        .background(action.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: action.tint.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

private struct ParentSchoolScorePreview: View {
    var score: Int
    var total: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: score == total ? "checkmark.seal.fill" : "graduationcap.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(score == total ? ParentPalette.success : ParentPalette.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(japanese: "点数", english: "Score"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(score)/\(total)")
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.04), radius: 7, x: 0, y: 4)
    }
}

private struct ParentSchoolMissedWordPicker: View {
    var words: [SpellingWord]
    @Binding var selectedWordIDs: Set<UUID>
    var language: AppLanguage

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 145), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label(language.text(japanese: "間違えた単語を選ぶ", english: "Choose missed words"), systemImage: "text.badge.xmark")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.primary)

                ParentInfoButton(
                    title: language.text(japanese: "間違えた単語の選び方", english: "How to Choose Missed Words"),
                    message: language.text(
                        japanese: "最初はすべて正解として扱います。学校テストで間違えた単語だけタップしてください。選んだ単語は復習候補になります。",
                        english: "All words start as correct. Tap only the words missed on the school test. Selected words become review candidates."
                    ),
                    tint: ParentPalette.primary
                )

                Spacer()

                if !selectedWordIDs.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                            selectedWordIDs.removeAll()
                        }
                    } label: {
                        Label(language.text(japanese: "全問正解に戻す", english: "All correct"), systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.heavy))
                    }
                    .buttonStyle(.bordered)
                    .tapFeedback()
                    .tint(ParentPalette.success)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(words) { word in
                    ParentSchoolWordChoiceButton(
                        word: word,
                        isMissed: selectedWordIDs.contains(word.id),
                        language: language
                    ) {
                        toggle(word)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.04), radius: 7, x: 0, y: 4)
    }

    private func toggle(_ word: SpellingWord) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
            if selectedWordIDs.contains(word.id) {
                selectedWordIDs.remove(word.id)
            } else {
                selectedWordIDs.insert(word.id)
            }
        }
    }
}

private struct ParentSchoolWordChoiceButton: View {
    var word: SpellingWord
    var isMissed: Bool
    var language: AppLanguage
    var action: () -> Void

    private var tint: Color {
        isMissed ? ParentPalette.warning : ParentPalette.success
    }

    private var promptText: String {
        word.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isMissed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(word.text)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if !promptText.isEmpty {
                        Text(promptText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 10)
            .background(isMissed ? ParentPalette.warningSoft : ParentPalette.successSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isMissed ? tint.opacity(0.55) : .clear, lineWidth: isMissed ? 2 : 1)
            )
            .shadow(color: .black.opacity(isMissed ? 0.06 : 0.03), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .accessibilityLabel(
            isMissed
                ? language.text(japanese: "\(word.text) は間違い", english: "\(word.text) marked missed")
                : language.text(japanese: "\(word.text) は正解", english: "\(word.text) marked correct")
        )
    }
}

private struct ParentStepMetricPill: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.035), radius: 7, x: 0, y: 4)
    }
}

private struct SchoolTestResultPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var testDate = Date()
    @State private var selectedStepID = ""
    @State private var score = 0
    @State private var total = 0
    @State private var showingOptionalDetails = false
    @State private var showingStepChooser = false
    @State private var missedWords = ""
    @State private var note = ""
    var language: AppLanguage

    private var sortedResults: [SchoolTestResult] {
        model.schoolTestResults.sorted { $0.date > $1.date }
    }

    private var selectedStep: WordStep? {
        model.wordSteps.first { $0.id == selectedStepID }
    }

    private var canSave: Bool {
        total > 0 && score >= 0 && score <= total
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "学校テスト", english: "School Test"),
            systemImage: "graduationcap.fill",
            tint: ParentPalette.primary
        ) {
            Text(language.text(
                japanese: "学校で返ってきたスペリングテストの結果を、アプリの練習記録とは別に保存します。",
                english: "Save school spelling test results separately from app practice records."
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    DatePicker(
                        language.text(japanese: "テスト日", english: "Date"),
                        selection: $testDate,
                        displayedComponents: .date
                    )
                    .font(.headline.weight(.bold))
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !model.wordSteps.isEmpty {
                        Button {
                            showingStepChooser = true
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(language.text(japanese: "単語集", english: "Step"))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(selectedStep?.title(language: language) ?? language.text(japanese: "選ぶ", english: "Choose"))
                                        .font(.headline.monospacedDigit().weight(.heavy))
                                        .foregroundStyle(ParentPalette.ink)
                                }

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(ParentPalette.primary)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            .background(ParentPalette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .tapFeedback()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                HStack(spacing: 12) {
                    Stepper(value: $score, in: 0...max(total, 1)) {
                        SettingValueRow(
                            title: language.text(japanese: "正解", english: "Correct"),
                            value: "\(score)"
                        )
                    }

                    Stepper(value: $total, in: 1...50) {
                        SettingValueRow(
                            title: language.text(japanese: "満点", english: "Total"),
                            value: "\(total)"
                        )
                    }
                }

                DisclosureGroup(isExpanded: $showingOptionalDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(language.text(japanese: "間違えた単語", english: "Missed Words"), systemImage: "text.badge.xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $missedWords)
                                .font(.body.monospaced())
                                .frame(height: 70)
                                .padding(8)
                                .background(ParentPalette.surfaceTint)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ParentPalette.primary.opacity(0.14), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label(language.text(japanese: "メモ", english: "Note"), systemImage: "note.text")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $note)
                                .font(.body)
                                .frame(height: 64)
                                .padding(8)
                                .background(ParentPalette.surfaceTint)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ParentPalette.primary.opacity(0.14), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label(language.text(japanese: "間違えた単語・メモを追加", english: "Add missed words or note"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ParentPalette.primary)
                }

                HStack {
                    Spacer()

                    Button {
                        saveResult()
                    } label: {
                        Label(language.text(japanese: "学校テストを保存", english: "Save School Test"), systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
            .tapFeedback()
                    .tint(ParentPalette.primary)
                    .disabled(!canSave)
                }
            }
            .padding(12)
            .background(ParentPalette.surfaceTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ParentPalette.primary.opacity(0.14), lineWidth: 1)
            )

            Divider()

            HStack {
                SettingValueRow(
                    title: language.text(japanese: "保存済み", english: "Saved"),
                    value: "\(model.schoolTestResults.count)"
                )

                Spacer()
            }

            if sortedResults.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "まだ学校テスト結果がありません", english: "No school test results yet"),
                    systemImage: "graduationcap",
                    description: Text(language.text(japanese: "学校のテストが返ってきたら、ここに点数を入れます。", english: "Enter scores here when school tests come back."))
                )
                .frame(minHeight: 220)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(sortedResults) { result in
                            SchoolTestResultCard(result: result, language: language)
                                .environmentObject(model)
                        }
                    }
                }
                .frame(maxHeight: 520)
            }
        }
        .onAppear {
            prepareDefaultsIfNeeded()
        }
        .onChange(of: selectedStepID) { _, _ in
            if total <= 0 {
                applyDefaultTotal()
            }
        }
        .onChange(of: total) { _, newTotal in
            score = min(score, max(newTotal, 1))
        }
        .sheet(isPresented: $showingStepChooser) {
            ParentStepChooserSheet(
                title: language.text(japanese: "学校テストのステップを選ぶ", english: "Choose School Test Step"),
                language: language,
                selectedStepID: selectedStepID
            ) { step in
                selectedStepID = step.id
            }
            .environmentObject(model)
            .presentationDetents([.large])
        }
    }

    private func prepareDefaultsIfNeeded() {
        if selectedStepID.isEmpty {
            selectedStepID = model.selectedWordStep?.id ?? model.wordSteps.last?.id ?? ""
        }
        if total <= 0 {
            applyDefaultTotal()
        }
    }

    private func applyDefaultTotal() {
        let defaultTotal = max(selectedStep?.words.count ?? model.activeWords.count, 1)
        total = defaultTotal
        score = defaultTotal
    }

    private func saveResult() {
        let trimmedMissedWords = missedWords.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let stepTitle = selectedStep?.title(language: language)
            ?? language.text(japanese: "ステップ未設定", english: "No step")
        let result = SchoolTestResult(
            date: testDate,
            stepID: selectedStep?.id,
            stepTitle: stepTitle,
            score: score,
            total: total,
            missedWords: trimmedMissedWords,
            note: trimmedNote
        )
        model.addSchoolTestResult(result)
        testDate = Date()
        missedWords = ""
        note = ""
        applyDefaultTotal()
    }
}

private struct SchoolTestResultDatePicker: View {
    var results: [SchoolTestResult]
    @Binding var selectedID: UUID?
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(language.text(japanese: "学校テストの日付を選ぶ", english: "Choose School Test Date"), systemImage: "calendar")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(ParentPalette.primary)

                Spacer()

                if results.count > 1 {
                    Text(language.text(japanese: "\(results.count)日分", english: "\(results.count) dates"))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(ParentPalette.primary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(ParentPalette.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(results) { result in
                        SchoolTestResultDateButton(
                            result: result,
                            isSelected: result.id == selectedID || (selectedID == nil && result.id == results.first?.id),
                            language: language
                        ) {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                selectedID = result.id
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.035), radius: 7, x: 0, y: 4)
    }
}

private struct SchoolTestResultDateButton: View {
    var result: SchoolTestResult
    var isSelected: Bool
    var language: AppLanguage
    var action: () -> Void

    private var scoreText: String {
        if result.score == result.total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        return language.text(japanese: "\(result.score)問正解", english: "\(result.score) correct")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                Text(scoreText)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : ParentPalette.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(isSelected ? ParentPalette.primary : Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.035), radius: 7, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .tapFeedback()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SchoolTestResultCard: View {
    @EnvironmentObject private var model: AppModel
    var result: SchoolTestResult
    var language: AppLanguage

    private var missedCount: Int {
        max(result.total - result.score, 0)
    }

    private var scoreHeadline: String {
        if result.score == result.total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        return language.text(japanese: "\(result.score)問正解", english: "\(result.score) correct")
    }

    private var scoreDetail: String {
        if result.score == result.total {
            return language.text(japanese: "\(result.total)問すべて正解", english: "All \(result.total) correct")
        }
        return language.text(japanese: "\(missedCount)問見直し", english: "\(missedCount) to review")
    }

    private var scoreColor: Color {
        let ratio = Double(result.score) / Double(max(result.total, 1))
        if ratio >= 0.9 {
            return ParentPalette.success
        }
        if ratio >= 0.7 {
            return ParentPalette.warning
        }
        return ParentPalette.danger
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(scoreHeadline)
                    .font(.system(size: result.score == result.total ? 24 : 21, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(scoreDetail)
                    .font(.caption.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .foregroundStyle(scoreColor)
            .frame(width: 118)
            .padding(.vertical, 8)
            .background(scoreColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(result.stepTitle.isEmpty ? language.text(japanese: "ステップ未設定", english: "No step") : result.stepTitle)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                Text(language.text(
                    japanese: "テスト日 \(result.date.formatted(date: .abbreviated, time: .omitted))",
                    english: "Test date \(result.date.formatted(date: .abbreviated, time: .omitted))"
                ))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                if !result.missedWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(result.missedWords, systemImage: "text.badge.xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ParentPalette.danger)
                }

                if !result.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(result.note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.deleteSchoolTestResult(result)
            } label: {
                Image(systemName: "trash")
                    .font(.headline.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .tapFeedback()
            .tint(ParentPalette.danger)
            .accessibilityLabel(language.text(japanese: "学校テスト結果を削除", english: "Delete school test result"))
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
    }
}

private struct ParentPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color = ParentPalette.primary
    var content: Content

    init(title: String, systemImage: String, tint: Color = ParentPalette.primary, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(ParentPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 6)
    }
}

private struct ParentWordStepPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingStepChooser = false
    var language: AppLanguage

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "ステップ一覧", english: "Word Steps"),
            systemImage: "rectangle.stack.fill"
        ) {
            HStack {
                SettingValueRow(
                    title: language.text(japanese: "登録日ごとの単語集", english: "Word sets by date"),
                    value: "\(model.wordSteps.count)"
                )

                Spacer()
            }

            if orderedSteps.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "ステップがありません", english: "No steps yet"),
                    systemImage: "rectangle.stack.fill",
                    description: Text(language.text(japanese: "単語を登録するとここに表示されます。", english: "Registered words will appear here."))
                )
                .frame(minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let step = model.selectedWordStep {
                        ParentWordStepCard(
                            step: step,
                            language: language,
                            isSelected: true
                        ) {
                            showingStepChooser = true
                        }
                    }

                    Button {
                        showingStepChooser = true
                    } label: {
                        Label(language.text(japanese: "ステップを探す", english: "Find Step"), systemImage: "magnifyingglass")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tapFeedback()
                    .tint(ParentPalette.primary)
                }
            }
        }
        .sheet(isPresented: $showingStepChooser) {
            ParentStepChooserSheet(
                title: language.text(japanese: "ステップを探す", english: "Find Step"),
                language: language,
                selectedStepID: model.selectedWordStepID
            ) { step in
                model.selectedWordStepID = step.id
            }
            .environmentObject(model)
            .presentationDetents([.large])
        }
    }
}

private struct ParentWordStepCard: View {
    var step: WordStep
    var language: AppLanguage
    var isSelected: Bool
    var action: () -> Void

    private var wordSummary: String {
        step.words.map(\.text).joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title(language: language))
                            .font(.title3.monospacedDigit().weight(.heavy))
                            .foregroundStyle(ParentPalette.ink)
                        Text("\(formattedStepDate(step.registeredDate, language: language)) ・ \(step.words.count) \(language.text(japanese: "単語", english: "words"))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Label(language.text(japanese: "選択中", english: "Selected"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ParentPalette.primary)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(ParentPalette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text(wordSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ParentPalette.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(isSelected ? ParentPalette.primarySoft : ParentPalette.surfaceTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(isSelected ? 0.07 : 0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
            .tapFeedback()
    }
}

private struct ParentWordListPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var rawWords = ""
    @State private var showingWordCamera = false
    @State private var isScanningWordImage = false
    @State private var importMessage: String?
    @State private var importSucceeded = false
    var language: AppLanguage

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "単語リスト", english: "Word List"),
            systemImage: "list.bullet.rectangle"
        ) {
            Text(language.text(
                japanese: "1行に1単語。問題で日本語や説明を出す時は「friend | 友[とも]だち」のように書けます。",
                english: "One word per line. Add a test hint like \"friend | friend meaning.\""
            ))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            TextEditor(text: $rawWords)
                .font(.title3.monospaced())
                .frame(minHeight: 180, maxHeight: 210)
                .padding(8)
                .background(ParentPalette.surfaceTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ParentPalette.primary.opacity(0.16), lineWidth: 1)
                )

            if let importMessage {
                WordImportStatusBanner(
                    message: importMessage,
                    isSuccess: importSucceeded,
                    isScanning: isScanningWordImage
                )
            }

            HStack {
                Button {
                    startCameraImport()
                } label: {
                    Label(
                        isScanningWordImage ? language.text(japanese: "読み取り中", english: "Scanning") : language.text(japanese: "カメラで読み取り", english: "Scan Camera"),
                        systemImage: "camera.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            .tapFeedback()
                .tint(ParentPalette.primary)
                .disabled(isScanningWordImage)

                Button {
                    rawWords = wordListEditorText(model.words)
                    importMessage = nil
                } label: {
                    Label(language.text(japanese: "読み直す", english: "Reload"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            .tapFeedback()

                Spacer()

                Button {
                    model.replaceWords(from: rawWords)
                } label: {
                    Label(language.text(japanese: "単語を保存", english: "Save Words"), systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
            .tapFeedback()
                .disabled(parseWordListEntries(from: rawWords).isEmpty)
            }
            .font(.subheadline.weight(.bold))

            Text(language.text(japanese: "現在 \(model.words.count) 単語", english: "Current: \(model.words.count) words"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.words) { word in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(word.text)
                                    .font(.headline.weight(.semibold))
                                if !word.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(language.text(japanese: "出題ヒント:", english: "Prompt:"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        RubyPromptText(
                                            text: word.promptText,
                                            baseFontSize: 13,
                                            rubyFontSize: 7,
                                            baseColor: ParentPalette.primary,
                                            rubyColor: ParentPalette.neutral,
                                            maxLines: 1
                                        )
                                    }
                                }
                                Text(language.text(
                                    japanese: "登録日: \(formattedStepDate(word.registeredAt, language: language))",
                                    english: "Registered: \(formattedStepDate(word.registeredAt, language: language))"
                                ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 210)
        }
        .onAppear {
            rawWords = wordListEditorText(model.words)
        }
        .sheet(isPresented: $showingWordCamera) {
            WordCameraPicker { image in
                scanWordImage(image)
            }
            .ignoresSafeArea()
        }
    }

    private func startCameraImport() {
        importSucceeded = false

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            importMessage = language.text(
                japanese: "この端末ではカメラが使えません。iPad実機で試してください。",
                english: "Camera is not available on this device. Try it on a real iPad."
            )
            return
        }

        showingWordCamera = true
    }

    private func scanWordImage(_ image: UIImage) {
        isScanningWordImage = true
        importSucceeded = false
        importMessage = language.text(japanese: "宿題の文字を読み取っています。", english: "Scanning the homework text.")

        Task {
            do {
                let importedWords = try await WordListImageTextRecognizer(language: model.settings.language).recognizeWords(in: image)
                await MainActor.run {
                    let addedCount = appendImportedWords(importedWords)
                    isScanningWordImage = false

                    if importedWords.isEmpty {
                        importSucceeded = false
                        importMessage = language.text(
                            japanese: "英単語を見つけられませんでした。明るい場所で、紙全体が入るように撮り直してください。",
                            english: "No English words were found. Retake it in good light with the whole page visible."
                        )
                    } else if addedCount == 0 {
                        importSucceeded = true
                        importMessage = language.text(
                            japanese: "読み取った単語はすでにリストに入っています。",
                            english: "The scanned words are already in the list."
                        )
                    } else {
                        importSucceeded = true
                        importMessage = language.text(
                            japanese: "\(addedCount)単語を下に追加しました。保存前に余分な単語や読み間違いを直してください。",
                            english: "Added \(addedCount) words below. Edit extra or misread words before saving."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isScanningWordImage = false
                    importSucceeded = false
                    importMessage = language.text(
                        japanese: "読み取りに失敗しました。もう一度撮り直してください。",
                        english: "Scanning failed. Please retake the photo."
                    )
                }
            }
        }
    }

    private func appendImportedWords(_ importedWords: [String]) -> Int {
        let existingWords = parseWordListEntries(from: rawWords).map(\.text)

        var seen = Set(existingWords)
        var additions: [String] = []

        for word in importedWords {
            let normalized = normalize(word)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            additions.append(normalized)
        }

        guard !additions.isEmpty else {
            return 0
        }

        let currentText = rawWords.trimmingCharacters(in: .whitespacesAndNewlines)
        rawWords = currentText.isEmpty
            ? additions.joined(separator: "\n")
            : currentText + "\n" + additions.joined(separator: "\n")

        return additions.count
    }
}

private struct WordImportStatusBanner: View {
    var message: String
    var isSuccess: Bool
    var isScanning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.headline.weight(.bold))
            }

            Text(message)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSuccess ? ParentPalette.success : ParentPalette.warning)
        .padding(10)
        .background(isSuccess ? ParentPalette.successSoft : ParentPalette.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct WordCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onImage: (UIImage) -> Void
        var dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private struct TestSettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "テスト設定", english: "Test Settings"),
            systemImage: "slider.horizontal.3"
        ) {
            SettingBlock(title: language.text(japanese: "表示言語", english: "Screen Language")) {
                Picker("", selection: $model.settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingBlock(title: language.text(japanese: "読み上げ", english: "Speech")) {
                Picker(language.text(japanese: "英語音声", english: "Voice"), selection: $model.settings.language) {
                    Text("US English").tag("en-US")
                    Text("UK English").tag("en-GB")
                }
                .pickerStyle(.segmented)

                SliderSetting(
                    title: language.text(japanese: "速さ", english: "Speed"),
                    value: $model.settings.speechRate,
                    range: 0.30...0.55,
                    format: "%.2f"
                )

                Stepper(value: $model.settings.maxReplays, in: 0...5) {
                    SettingValueRow(
                        title: language.text(japanese: "聞き直し", english: "Replays"),
                        value: "\(model.settings.maxReplays)"
                    )
                }
            }

            SettingBlock(title: language.text(japanese: "出題の出し方", english: "Question Format")) {
                Picker(language.text(japanese: "出題形式", english: "Prompt Mode"), selection: $model.settings.testPromptMode) {
                    ForEach(TestPromptMode.allCases) { mode in
                        Text(mode.shortLabel(language: language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(language.text(japanese: "テストの出題形式", english: "Test question format"))

                Text(model.settings.testPromptMode.description(language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(language.text(
                    japanese: "文字は単語リストの右側を表示します。漢字の読みは「学校[がっこう]」のように書けます。",
                    english: "Text prompts use the right side of the word list. Add readings with brackets when needed."
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingBlock(title: language.text(japanese: "テスト", english: "Test")) {
                Stepper(value: $model.settings.secondsPerWord, in: 10...90, step: 5) {
                    SettingValueRow(
                        title: language.text(japanese: "1単語の時間", english: "Seconds per word"),
                        value: "\(model.settings.secondsPerWord)"
                    )
                }
            }

            SettingBlock(title: language.text(japanese: "れんしゅう", english: "Practice")) {
                Stepper(value: $model.settings.practiceRepetitions, in: 3...5) {
                    SettingValueRow(
                        title: language.text(japanese: "初回に同じ単語を書く回数", english: "First practice writes"),
                        value: "\(model.settings.practiceRepetitions)"
                    )
                }
            }

            SettingBlock(title: language.text(japanese: "OCR判定", english: "OCR Grading")) {
                SliderSetting(
                    title: language.text(japanese: "書き直し", english: "Rewrite"),
                    value: $model.settings.lowConfidence,
                    range: 0.10...0.60,
                    format: "%.2f"
                )
            }

            Button {
                model.settings = model.settings
            } label: {
                Label(language.text(japanese: "設定を保存", english: "Save Settings"), systemImage: "square.and.arrow.down.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tapFeedback()
        }
    }
}

private struct SettingBlock<Content: View>: View {
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SliderSetting: View {
    var title: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct ParentGradingPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSessionID: String?
    @State private var sessionFilter: ParentGradingSessionFilter = .unreviewed
    var language: AppLanguage

    private var sessions: [ParentGradingSession] {
        let testSessions = Dictionary(grouping: model.attempts, by: \.sessionID).map { sessionID, attempts in
            let sortedAttempts = attempts.sorted { $0.date < $1.date }
            return ParentGradingSession(
                id: "test-\(sessionID.uuidString)",
                kind: .test,
                sequenceNumber: 0,
                date: sortedAttempts.first?.date ?? Date(),
                attempts: sortedAttempts,
                samples: []
            )
        }
        .sorted { $0.date < $1.date }
        .enumerated()
        .map { index, session in
            session.numbered(index + 1)
        }

        let practiceSessions = Dictionary(grouping: model.practiceSamples, by: \.sessionID).map { sessionID, samples in
            let sortedSamples = samples.sorted { $0.date < $1.date }
            let firstMode = sortedSamples.first?.mode
            let kind: ParentGradingSessionKind = firstMode == SessionMode.review.rawValue ? .review : .practice

            return ParentGradingSession(
                id: "practice-\(sessionID.uuidString)",
                kind: kind,
                sequenceNumber: 0,
                date: sortedSamples.first?.date ?? Date(),
                attempts: [],
                samples: sortedSamples
            )
        }

        let numberedPracticeSessions = numberSessions(practiceSessions, kind: .practice)
            + numberSessions(practiceSessions, kind: .review)

        return (testSessions + numberedPracticeSessions).sorted { $0.date > $1.date }
    }

    private var filteredSessions: [ParentGradingSession] {
        sessionFilter.apply(to: sessions)
    }

    private func numberSessions(_ sessions: [ParentGradingSession], kind: ParentGradingSessionKind) -> [ParentGradingSession] {
        sessions
            .filter { $0.kind == kind }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { index, session in
                session.numbered(index + 1)
            }
    }

    var body: some View {
        let activeSession = filteredSessions.first { $0.id == selectedSessionID } ?? filteredSessions.first

        ParentPanel(
            title: language.text(japanese: "採点", english: "Grade"),
            systemImage: "checkmark.seal.fill",
            tint: ParentPalette.primary
        ) {
            if sessions.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "まだ採点する記録がありません", english: "Nothing to grade yet"),
                    systemImage: "checkmark.seal",
                    description: Text(language.text(japanese: "練習やテストをするとここに表示されます。", english: "Practice and test sessions will appear here."))
                )
                .frame(minHeight: 240)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    GradingWorkHeader(
                        filter: $sessionFilter,
                        activeSession: activeSession,
                        filteredCount: filteredSessions.count,
                        totalCount: sessions.count,
                        language: language
                    )

                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            sessionFilter.emptyTitle(language: language),
                            systemImage: "checkmark.seal",
                            description: Text(sessionFilter.emptyMessage(language: language))
                        )
                        .frame(minHeight: 260)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ParentGradingSessionPicker(
                                    sessions: filteredSessions,
                                    selectedID: activeSession?.id,
                                    language: language,
                                    select: { selectedSessionID = $0 }
                                )
                                .frame(width: 220)

                                ScrollView {
                                    if let activeSession {
                                        ParentGradingSessionCard(
                                            session: activeSession,
                                            showsOnlyUngraded: sessionFilter == .unreviewed,
                                            language: language
                                        )
                                            .environmentObject(model)
                                    }
                                }
                                .frame(maxHeight: 760)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                ParentGradingSessionPicker(
                                    sessions: filteredSessions,
                                    selectedID: activeSession?.id,
                                    language: language,
                                    select: { selectedSessionID = $0 }
                                )
                                .frame(maxHeight: 180)

                                ScrollView {
                                    if let activeSession {
                                        ParentGradingSessionCard(
                                            session: activeSession,
                                            showsOnlyUngraded: sessionFilter == .unreviewed,
                                            language: language
                                        )
                                            .environmentObject(model)
                                    }
                                }
                                .frame(maxHeight: 760)
                            }
                        }
                    }
                }
                .onAppear {
                    if selectedSessionID == nil {
                        selectedSessionID = filteredSessions.first?.id
                    }
                }
                .onChange(of: filteredSessions.map(\.id)) { _, ids in
                    if selectedSessionID == nil || !(ids.contains(selectedSessionID ?? "")) {
                        selectedSessionID = ids.first
                    }
                }
            }
        }
    }
}

private enum ParentGradingSessionFilter: String, CaseIterable, Identifiable {
    case unreviewed
    case today
    case all

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "未採点", english: "Ungraded")
        case .today:
            return language.text(japanese: "今日", english: "Today")
        case .all:
            return language.text(japanese: "すべて", english: "All")
        }
    }

    func apply(to sessions: [ParentGradingSession]) -> [ParentGradingSession] {
        switch self {
        case .unreviewed:
            return sessions.filter { $0.unreviewedCount > 0 }
        case .today:
            return sessions.filter { Calendar.current.isDateInToday($0.date) }
        case .all:
            return sessions
        }
    }

    func emptyTitle(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "未採点はありません", english: "No ungraded sessions")
        case .today:
            return language.text(japanese: "今日の記録はありません", english: "No sessions today")
        case .all:
            return language.text(japanese: "記録がありません", english: "No sessions")
        }
    }

    func emptyMessage(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "採点が必要なものだけ、ここに出ます。", english: "Only sessions that need grading appear here.")
        case .today:
            return language.text(japanese: "今日、練習かテストをすると表示されます。", english: "Practice or test today to show sessions here.")
        case .all:
            return language.text(japanese: "練習やテストをすると表示されます。", english: "Practice or test to show sessions here.")
        }
    }
}

private struct GradingWorkHeader: View {
    @Binding var filter: ParentGradingSessionFilter
    var activeSession: ParentGradingSession?
    var filteredCount: Int
    var totalCount: Int
    var language: AppLanguage

    private var unreviewedCount: Int {
        activeSession?.unreviewedCount ?? 0
    }

    private var title: String {
        if unreviewedCount > 0 {
            return language.text(japanese: "未採点をチェック", english: "Check Ungraded")
        }
        return language.text(japanese: "この回は採点済み", english: "This Session Is Done")
    }

    private var subtitle: String {
        if let activeSession {
            return activeSession.title(language: language)
        }
        return language.text(japanese: "採点する回を選んでください", english: "Choose a session")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(ParentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(unreviewedCount)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text(language.text(japanese: "件", english: "left"))
                        .font(.headline.weight(.heavy))
                }
                .foregroundStyle(unreviewedCount > 0 ? ParentPalette.warning : ParentPalette.success)

                Picker("", selection: $filter) {
                    ForEach(ParentGradingSessionFilter.allCases) { filter in
                        Text(filter.title(language: language)).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityLabel(language.text(japanese: "採点記録の表示", english: "Grading session filter"))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    ParentPalette.primarySoft,
                    Color.white.opacity(0.95)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.text(
            japanese: "\(title)。\(subtitle)。未採点 \(unreviewedCount) 件。表示 \(filteredCount) / \(totalCount)。",
            english: "\(title). \(subtitle). \(unreviewedCount) ungraded. Showing \(filteredCount) of \(totalCount)."
        ))
    }
}

private enum ParentGradingSessionKind: Equatable {
    case test
    case practice
    case review

    func title(number: Int, language: AppLanguage) -> String {
        switch self {
        case .test:
            return language.text(japanese: "テスト \(number)回目", english: "Test #\(number)")
        case .practice:
            return language.text(japanese: "れんしゅう \(number)回目", english: "Practice #\(number)")
        case .review:
            return language.text(japanese: "ふくしゅう \(number)回目", english: "Review #\(number)")
        }
    }

    var systemImage: String {
        switch self {
        case .test:
            return "checklist.checked"
        case .practice, .review:
            return "pencil.and.scribble"
        }
    }

    var tint: Color {
        ParentPalette.primary
    }
}

private struct ParentGradingSession: Identifiable {
    var id: String
    var kind: ParentGradingSessionKind
    var sequenceNumber: Int
    var date: Date
    var attempts: [SpellingAttempt]
    var samples: [PracticeSample]

    var itemCount: Int {
        attempts.count + samples.count
    }

    var approvedCount: Int {
        attempts.filter { $0.parentReviewDecision == .approved }.count
            + samples.filter { $0.parentReviewDecision == .approved }.count
    }

    var needsPracticeCount: Int {
        attempts.filter { $0.parentReviewDecision == .needsPractice }.count
            + samples.filter { $0.parentReviewDecision == .needsPractice }.count
    }

    var unreviewedCount: Int {
        itemCount - approvedCount - needsPracticeCount
    }

    func title(language: AppLanguage) -> String {
        kind.title(number: sequenceNumber, language: language)
    }

    func numbered(_ number: Int) -> ParentGradingSession {
        ParentGradingSession(
            id: id,
            kind: kind,
            sequenceNumber: number,
            date: date,
            attempts: attempts,
            samples: samples
        )
    }
}

private struct ParentGradingSessionPicker: View {
    var sessions: [ParentGradingSession]
    var selectedID: String?
    var language: AppLanguage
    var select: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sessions) { session in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            select(session.id)
                        }
                    } label: {
                        ParentGradingSessionChip(
                            session: session,
                            isSelected: session.id == selectedID,
                            language: language
                        )
                    }
                    .buttonStyle(.plain)
            .tapFeedback()
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityAddTraits(session.id == selectedID ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ParentGradingSessionChip: View {
    var session: ParentGradingSession
    var isSelected: Bool
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title(language: language))
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            }

            Spacer(minLength: 4)

            VStack(spacing: 2) {
                Image(systemName: session.kind.systemImage)
                    .font(.caption.weight(.bold))
                Text(session.unreviewedCount > 0 ? "\(session.unreviewedCount)" : "OK")
                    .font(.caption.monospacedDigit().weight(.heavy))
            }
            .frame(width: 42)
        }
        .foregroundStyle(isSelected ? .white : session.kind.tint)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isSelected ? session.kind.tint : Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.04), radius: 7, x: 0, y: 4)
    }
}

private struct ParentGradingSessionCard: View {
    var session: ParentGradingSession
    var showsOnlyUngraded: Bool
    var language: AppLanguage

    private var visibleAttempts: [SpellingAttempt] {
        guard showsOnlyUngraded else {
            return session.attempts
        }
        return session.attempts.filter { $0.parentReviewDecision == .unreviewed }
    }

    private var visibleSamples: [PracticeSample] {
        guard showsOnlyUngraded else {
            return session.samples
        }
        return session.samples.filter { $0.parentReviewDecision == .unreviewed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: session.kind.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(ParentPalette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title(language: language))
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(session.unreviewedCount > 0
                    ? language.text(japanese: "あと \(session.unreviewedCount)件", english: "\(session.unreviewedCount) left")
                    : language.text(japanese: "採点済み", english: "Done")
                )
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(session.unreviewedCount > 0 ? ParentPalette.warning : ParentPalette.success)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background((session.unreviewedCount > 0 ? ParentPalette.warningSoft : ParentPalette.successSoft))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 12) {
                ForEach(visibleAttempts) { attempt in
                    ParentAttemptGradingCard(attempt: attempt, language: language)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                ForEach(visibleSamples) { sample in
                    ParentPracticeGradingCard(sample: sample, language: language)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: visibleAttempts.map(\.id))
            .animation(.easeInOut(duration: 0.22), value: visibleSamples.map(\.id))
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
    }
}

private struct GradingCountPill: View {
    var title: String
    var value: Int
    var tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.heavy))
            Text(title)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(tint)
        .frame(minWidth: 46)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ParentAttemptGradingCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingReviewDecision: ParentReviewDecision?
    @State private var isCompletingReview = false
    var attempt: SpellingAttempt
    var language: AppLanguage

    private var isApproved: Bool {
        attempt.parentReviewDecision == .approved
    }

    private var needsPractice: Bool {
        attempt.parentReviewDecision == .needsPractice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GradingItemHeader(
                word: attempt.word,
                decision: attempt.parentReviewDecision,
                language: language,
                detail: attempt.recognizedText.isEmpty ? nil : "OCR: \(attempt.recognizedText)"
            )

            if let drawingData = attempt.drawingData {
                DrawingPreview(drawingData: drawingData, topPadding: 100, bottomPadding: 190)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            }

            if isApproved {
                ParentApprovedBanner(language: language)
            }

            ParentReviewButtons(
                decision: attempt.parentReviewDecision,
                pendingDecision: pendingReviewDecision,
                language: language,
                approve: {
                    runReviewFeedback(.approved) {
                        model.updateAttemptParentReview(attempt, decision: .approved)
                    }
                },
                needsPractice: {
                    runReviewFeedback(.needsPractice) {
                        model.updateAttemptParentReview(attempt, decision: .needsPractice)
                    }
                }
            )

            if needsPractice {
                ParentNeedsPracticeBanner(isTest: true, language: language)

                ParentExampleEditor(
                    word: attempt.word,
                    initialData: attempt.parentExampleDrawingData,
                    language: language,
                    affectsTestScore: true,
                    save: { data in
                        model.updateAttemptParentReview(attempt, decision: .needsPractice, exampleDrawingData: data)
                    }
                )
            }
        }
        .padding(12)
        .background(gradingBackground(for: attempt.parentReviewDecision))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if let pendingReviewDecision {
                ParentReviewActionToast(decision: pendingReviewDecision, language: language)
                    .padding(10)
                    .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .scaleEffect(isCompletingReview ? 0.985 : 1)
        .shadow(
            color: reviewTint(for: pendingReviewDecision ?? attempt.parentReviewDecision).opacity(isCompletingReview ? 0.22 : 0),
            radius: isCompletingReview ? 14 : 0,
            x: 0,
            y: 8
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: pendingReviewDecision)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isCompletingReview)
    }

    private func runReviewFeedback(_ decision: ParentReviewDecision, commit: @escaping () -> Void) {
        guard pendingReviewDecision == nil else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            pendingReviewDecision = decision
            isCompletingReview = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.easeInOut(duration: 0.18)) {
                commit()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    pendingReviewDecision = nil
                    isCompletingReview = false
                }
            }
        }
    }
}

private struct ParentPracticeGradingCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingReviewDecision: ParentReviewDecision?
    @State private var isCompletingReview = false
    var sample: PracticeSample
    var language: AppLanguage

    private var modeLabel: String {
        if sample.mode == SessionMode.review.rawValue {
            return language.text(japanese: "ふくしゅう", english: "Review")
        }
        return language.text(japanese: "れんしゅう", english: "Practice")
    }

    private var isApproved: Bool {
        sample.parentReviewDecision == .approved
    }

    private var needsPractice: Bool {
        sample.parentReviewDecision == .needsPractice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GradingItemHeader(
                word: sample.word,
                decision: sample.parentReviewDecision,
                language: language,
                detail: modeLabel
            )

            DrawingPreview(drawingData: sample.drawingData, topPadding: 100, bottomPadding: 190)
                .frame(height: 220)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )

            if isApproved {
                ParentApprovedBanner(language: language)
            }

            ParentReviewButtons(
                decision: sample.parentReviewDecision,
                pendingDecision: pendingReviewDecision,
                language: language,
                approve: {
                    runReviewFeedback(.approved) {
                        model.updatePracticeSampleParentReview(sample, decision: .approved)
                    }
                },
                needsPractice: {
                    runReviewFeedback(.needsPractice) {
                        model.updatePracticeSampleParentReview(sample, decision: .needsPractice)
                    }
                }
            )

            if needsPractice {
                ParentNeedsPracticeBanner(isTest: false, language: language)

                ParentExampleEditor(
                    word: sample.word,
                    initialData: sample.parentExampleDrawingData,
                    language: language,
                    affectsTestScore: false,
                    save: { data in
                        model.updatePracticeSampleParentReview(sample, decision: .needsPractice, exampleDrawingData: data)
                    }
                )
            }
        }
        .padding(12)
        .background(gradingBackground(for: sample.parentReviewDecision))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if let pendingReviewDecision {
                ParentReviewActionToast(decision: pendingReviewDecision, language: language)
                    .padding(10)
                    .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .scaleEffect(isCompletingReview ? 0.985 : 1)
        .shadow(
            color: reviewTint(for: pendingReviewDecision ?? sample.parentReviewDecision).opacity(isCompletingReview ? 0.22 : 0),
            radius: isCompletingReview ? 14 : 0,
            x: 0,
            y: 8
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: pendingReviewDecision)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isCompletingReview)
    }

    private func runReviewFeedback(_ decision: ParentReviewDecision, commit: @escaping () -> Void) {
        guard pendingReviewDecision == nil else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            pendingReviewDecision = decision
            isCompletingReview = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.easeInOut(duration: 0.18)) {
                commit()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    pendingReviewDecision = nil
                    isCompletingReview = false
                }
            }
        }
    }
}

private struct GradingItemHeader: View {
    var word: String
    var decision: ParentReviewDecision
    var language: AppLanguage
    var detail: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(word)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(ParentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(decision.label(language: language))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(reviewTint(for: decision))
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(reviewTint(for: decision).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ParentReviewButtons: View {
    var decision: ParentReviewDecision
    var pendingDecision: ParentReviewDecision?
    var language: AppLanguage
    var approve: () -> Void
    var needsPractice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: approve) {
                Label(
                    pendingDecision == .approved ? language.text(japanese: "OK 保存中", english: "Saving OK") : "OK",
                    systemImage: pendingDecision == .approved || decision == .approved ? "checkmark.seal.fill" : "checkmark.circle.fill"
                )
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .scaleEffect(pendingDecision == .approved ? 1.04 : 1)
            }
            .buttonStyle(.borderedProminent)
            .tapFeedback()
            .tint(ParentPalette.success)
            .allowsHitTesting(pendingDecision == nil)

            Button(action: needsPractice) {
                Label(
                    pendingDecision == .needsPractice ? language.text(japanese: "直そう 保存中", english: "Saving Fix") : language.text(japanese: "直そう", english: "Needs Fix"),
                    systemImage: pendingDecision == .needsPractice ? "pencil.circle.fill" : "pencil.and.scribble"
                )
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .scaleEffect(pendingDecision == .needsPractice ? 1.04 : 1)
            }
            .buttonStyle(.bordered)
            .tapFeedback()
            .tint(ParentPalette.warning)
            .allowsHitTesting(pendingDecision == nil)
        }
    }
}

private struct ParentReviewActionToast: View {
    var decision: ParentReviewDecision
    var language: AppLanguage

    private var title: String {
        switch decision {
        case .approved:
            return language.text(japanese: "OK 保存しました", english: "OK saved")
        case .needsPractice:
            return language.text(japanese: "直そう 保存しました", english: "Fix saved")
        case .unreviewed:
            return language.text(japanese: "保存しました", english: "Saved")
        }
    }

    private var systemImage: String {
        switch decision {
        case .approved:
            return "checkmark.seal.fill"
        case .needsPractice:
            return "pencil.circle.fill"
        case .unreviewed:
            return "checkmark.circle.fill"
        }
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(reviewTint(for: decision).gradient)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: reviewTint(for: decision).opacity(0.26), radius: 12, x: 0, y: 6)
    }
}

private struct ParentNeedsPracticeBanner: View {
    var isTest: Bool
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(ParentPalette.warning)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "直そうにしました", english: "Marked Needs Fix"))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(ParentPalette.warning)
                Text(language.text(japanese: "お手本を書くと、子供の復習に出せます。", english: "Add a model for the child to review."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ParentPalette.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ParentPalette.warning.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct ParentApprovedBanner: View {
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
            Text(language.text(japanese: "OK! よく書けています", english: "OK! Nicely written"))
            Image(systemName: "star.fill")
        }
        .font(.headline.weight(.heavy))
        .foregroundStyle(ParentPalette.success)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(ParentPalette.successSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ParentExampleEditor: View {
    var word: String
    var initialData: Data?
    var language: AppLanguage
    var affectsTestScore: Bool
    var save: (Data) -> Void

    @State private var drawing = PKDrawing()
    @StateObject private var capture = DrawingCapture()
    @State private var didLoad = false
    @State private var hasSavedModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(language.text(japanese: "親のお手本", english: "Parent Model"), systemImage: "pencil.and.scribble")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ParentPalette.warning)

                Spacer()

                if hasSavedModel {
                    Label(language.text(japanese: "保存済み", english: "Saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(ParentPalette.success)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(ParentPalette.successSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Text(language.text(japanese: "\(word) の見本を書く", english: "Write a model for \(word)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                FourLineGuide(mode: .practice, labels: parentGuideLabels(language: language))
                PencilCanvasView(drawing: $drawing, capture: capture)
            }
            .frame(height: 210)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ParentPalette.warning.opacity(0.22), lineWidth: 1)
            )

            HStack {
                Button {
                    drawing = PKDrawing()
                    capture.latestDrawing = PKDrawing()
                } label: {
                    Label(language.text(japanese: "消す", english: "Clear"), systemImage: "eraser.fill")
                }
                .buttonStyle(.bordered)
            .tapFeedback()

                Spacer()

                Button {
                    let latestDrawing = capture.latestDrawing
                    guard !latestDrawing.bounds.isNull, !latestDrawing.bounds.isEmpty else {
                        return
                    }
                    save(latestDrawing.dataRepresentation())
                    hasSavedModel = true
                } label: {
                    Label(
                        hasSavedModel ? language.text(japanese: "保存しなおす", english: "Save Again") : language.text(japanese: "お手本を保存", english: "Save Model"),
                        systemImage: hasSavedModel ? "checkmark.circle.fill" : "square.and.arrow.down.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            .tapFeedback()
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(12)
        .background(ParentPalette.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            loadInitialDrawingIfNeeded()
        }
    }

    private func loadInitialDrawingIfNeeded() {
        guard !didLoad else {
            return
        }
        didLoad = true

        if let initialData, let initialDrawing = try? PKDrawing(data: initialData) {
            drawing = initialDrawing
            capture.latestDrawing = initialDrawing
            hasSavedModel = true
        }
    }
}

private func parentGuideLabels(language: AppLanguage) -> [String] {
    if language == .japanese {
        return ["トップライン", "ミッドライン", "ベースライン", "ディセンダーライン"]
    }
    return ["Top line", "Mid line", "Base line", "Descender"]
}

private func reviewTint(for decision: ParentReviewDecision) -> Color {
    switch decision {
    case .unreviewed:
        return ParentPalette.neutral
    case .approved:
        return ParentPalette.success
    case .needsPractice:
        return ParentPalette.warning
    }
}

private func gradingBackground(for decision: ParentReviewDecision) -> Color {
    switch decision {
    case .unreviewed:
        return ParentPalette.surface
    case .approved:
        return ParentPalette.successSoft
    case .needsPractice:
        return ParentPalette.warningSoft
    }
}

private struct AnswerReviewPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var reviewAttempts: [SpellingAttempt] {
        Array(model.attempts
            .filter { $0.decision == .needsReview || $0.decision == .rewrite || $0.decision == .timeExpired || $0.decision == .autoIncorrect }
            .reversed())
    }

    private var reviewSummaries: [ReviewAttemptSummary] {
        Dictionary(grouping: reviewAttempts, by: { normalize($0.word) })
            .compactMap { word, attempts in
                let sortedAttempts = attempts.sorted { $0.date > $1.date }
                guard let latestAttempt = sortedAttempts.first else {
                    return nil
                }

                return ReviewAttemptSummary(
                    id: word,
                    word: latestAttempt.word,
                    latestAttempt: latestAttempt,
                    attemptCount: sortedAttempts.count,
                    needsReviewCount: sortedAttempts.filter { $0.decision == .needsReview }.count,
                    needsPracticeCount: sortedAttempts.filter { $0.parentReviewDecision == .needsPractice }.count
                )
            }
            .sorted { $0.latestAttempt.date > $1.latestAttempt.date }
    }

    private var latestPracticeSamples: [PracticeSample] {
        Array(model.practiceSamples.reversed().prefix(8))
    }

    private var total: Int {
        max(model.todaysAttempts.count, 1)
    }

    private var correctRatio: Double {
        Double(model.todaysCorrectCount) / Double(total)
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "成績サマリー", english: "Results"),
            systemImage: "chart.pie.fill"
        ) {
            HStack(spacing: 16) {
                ProgressRing(progress: correctRatio)
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text(japanese: "今日の結果", english: "Today's result"))
                        .font(.headline.weight(.bold))
                    SettingValueRow(
                        title: language.text(japanese: "正解", english: "Correct"),
                        value: "\(model.todaysCorrectCount)"
                    )
                    SettingValueRow(
                        title: language.text(japanese: "見直し", english: "Review"),
                        value: "\(model.reviewWords.count)"
                    )
                    SettingValueRow(
                        title: language.text(japanese: "回答", english: "Attempts"),
                        value: "\(model.todaysAttempts.count)"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if reviewSummaries.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "確認待ちはありません", english: "No answers need review"),
                    systemImage: "checkmark.circle.fill",
                    description: Text(language.text(japanese: "テスト後にここへ表示されます。", english: "Items appear here after a test."))
                )
                .frame(minHeight: 190)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(reviewSummaries.prefix(8)) { summary in
                            ReviewAttemptSummaryCard(summary: summary, language: language)
                                .environmentObject(model)
                        }
                    }
                }
                .frame(maxHeight: 370)
            }

            Divider()

            HStack {
                Label(language.text(japanese: "れんしゅう記録", english: "Practice Samples"), systemImage: "pencil.and.scribble")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ParentPalette.primary)

                Spacer()

                if !model.practiceSamples.isEmpty {
                    Button(role: .destructive) {
                        model.resetPracticeSamples()
                    } label: {
                        Label(language.text(japanese: "記録を消す", english: "Clear"), systemImage: "trash")
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
            .tapFeedback()
                }
            }

            if latestPracticeSamples.isEmpty {
                Text(language.text(
                    japanese: "練習で書いた単語は、ここに表示されます。",
                    english: "Words written in practice will appear here."
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                .background(ParentPalette.surfaceTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(latestPracticeSamples) { sample in
                            ParentPracticeSampleCard(sample: sample, language: language)
                        }
                    }
                }
                .frame(maxHeight: 430)
            }
        }
    }
}

private struct ReviewAttemptSummary: Identifiable {
    var id: String
    var word: String
    var latestAttempt: SpellingAttempt
    var attemptCount: Int
    var needsReviewCount: Int
    var needsPracticeCount: Int
}

private struct LearningHistoryPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var history: [LearningHistoryEntry] {
        let testEntries = model.attempts.map { attempt in
            LearningHistoryEntry(
                id: "test-\(attempt.id.uuidString)",
                date: attempt.date,
                word: attempt.word,
                modeLabel: language.text(japanese: "テスト", english: "Test"),
                detail: "\(attempt.decision.label(language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                systemImage: attempt.decision == .autoCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: attempt.decision == .autoCorrect ? ParentPalette.success : ParentPalette.warning,
                drawingData: attempt.drawingData
            )
        }

        let practiceEntries = model.practiceSamples.map { sample in
            let modeLabel = sample.mode == SessionMode.review.rawValue
                ? language.text(japanese: "ふくしゅう", english: "Review")
                : language.text(japanese: "れんしゅう", english: "Practice")

            return LearningHistoryEntry(
                id: "practice-\(sample.id.uuidString)",
                date: sample.date,
                word: sample.word,
                modeLabel: modeLabel,
                detail: language.text(japanese: "手書き記録", english: "Handwriting saved"),
                systemImage: "pencil.and.scribble",
                tint: ParentPalette.primary,
                drawingData: sample.drawingData
            )
        }

        let schoolEntries = model.schoolTestResults.map { result in
            LearningHistoryEntry(
                id: "school-\(result.id.uuidString)",
                date: result.date,
                word: result.stepTitle.isEmpty ? language.text(japanese: "学校テスト", english: "School Test") : result.stepTitle,
                modeLabel: language.text(japanese: "学校テスト", english: "School Test"),
                detail: "\(result.score)/\(result.total)" + (result.missedWords.isEmpty ? "" : " ・ \(result.missedWords)"),
                systemImage: "graduationcap.fill",
                tint: ParentPalette.primary,
                drawingData: nil
            )
        }

        return (testEntries + practiceEntries + schoolEntries).sorted { $0.date > $1.date }
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "学習履歴", english: "Learning History"),
            systemImage: "clock.arrow.circlepath"
        ) {
            HStack(spacing: 12) {
                SettingValueRow(
                    title: language.text(japanese: "アプリのテスト結果", english: "App Test Results"),
                    value: "\(model.attempts.count)"
                )
                SettingValueRow(
                    title: language.text(japanese: "手書き記録", english: "Handwriting"),
                    value: "\(model.practiceSamples.count)"
                )
                SettingValueRow(
                    title: language.text(japanese: "学校テスト", english: "School"),
                    value: "\(model.schoolTestResults.count)"
                )
            }

            Text(language.text(
                japanese: "アプリの練習・テスト結果と、学校で返ってきた結果を時系列で保存しています。",
                english: "Saved records include app practice, app test results, and school test results."
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if history.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "まだ履歴がありません", english: "No history yet"),
                    systemImage: "clock",
                    description: Text(language.text(japanese: "練習やテストをするとここに残ります。", english: "Practice and test records will appear here."))
                )
                .frame(minHeight: 220)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(history) { entry in
                            LearningHistoryCard(entry: entry, language: language)
                        }
                    }
                }
                .frame(maxHeight: 620)
            }
        }
    }
}

private struct LearningHistoryEntry: Identifiable {
    var id: String
    var date: Date
    var word: String
    var modeLabel: String
    var detail: String
    var systemImage: String
    var tint: Color
    var drawingData: Data?
}

private struct HandwritingListPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var handwritingEntries: [LearningHistoryEntry] {
        let testEntries = model.attempts.compactMap { attempt -> LearningHistoryEntry? in
            guard let drawingData = attempt.drawingData else {
                return nil
            }
            return LearningHistoryEntry(
                id: "test-writing-\(attempt.id.uuidString)",
                date: attempt.date,
                word: attempt.word,
                modeLabel: language.text(japanese: "テスト", english: "Test"),
                detail: "\(attempt.decision.label(language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                systemImage: attempt.decision == .autoCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: attempt.decision == .autoCorrect ? ParentPalette.success : ParentPalette.warning,
                drawingData: drawingData
            )
        }

        let practiceEntries = model.practiceSamples.map { sample in
            let modeLabel = sample.mode == SessionMode.review.rawValue
                ? language.text(japanese: "ふくしゅう", english: "Review")
                : language.text(japanese: "れんしゅう", english: "Practice")

            return LearningHistoryEntry(
                id: "practice-writing-\(sample.id.uuidString)",
                date: sample.date,
                word: sample.word,
                modeLabel: modeLabel,
                detail: language.text(japanese: "手書き記録", english: "Handwriting saved"),
                systemImage: "pencil.and.scribble",
                tint: ParentPalette.primary,
                drawingData: sample.drawingData
            )
        }

        return (testEntries + practiceEntries).sorted { $0.date > $1.date }
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "手書き一覧", english: "Handwriting List"),
            systemImage: "rectangle.stack.fill"
        ) {
            HStack {
                SettingValueRow(
                    title: language.text(japanese: "保存された手書き", english: "Saved handwriting"),
                    value: "\(handwritingEntries.count)"
                )

                Spacer()
            }

            Text(language.text(
                japanese: "練習・復習・テストで書いた内容を、親が確認しやすい大きさで表示します。",
                english: "Review all practice, review, and test handwriting at a larger size."
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if handwritingEntries.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "まだ手書きがありません", english: "No handwriting yet"),
                    systemImage: "pencil.and.scribble",
                    description: Text(language.text(japanese: "練習やテストをするとここに残ります。", english: "Practice and test handwriting will appear here."))
                )
                .frame(minHeight: 260)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(handwritingEntries) { entry in
                            ParentHandwritingListCard(entry: entry, language: language)
                        }
                    }
                }
                .frame(maxHeight: 760)
            }
        }
    }
}

private struct ParentHandwritingListCard: View {
    var entry: LearningHistoryEntry
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(entry.tint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.word)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ParentPalette.ink)
                    Text("\(entry.modeLabel) ・ \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let drawingData = entry.drawingData {
                DrawingPreview(drawingData: drawingData)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.24), lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ParentPalette.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct LearningHistoryCard: View {
    var entry: LearningHistoryEntry
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(entry.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.word)
                        .font(.headline.weight(.bold))
                    Text("\(entry.modeLabel) ・ \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let drawingData = entry.drawingData {
                DrawingPreview(drawingData: drawingData)
                    .frame(height: 140)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReviewAttemptSummaryCard: View {
    @EnvironmentObject private var model: AppModel
    var summary: ReviewAttemptSummary
    var language: AppLanguage

    private var attempt: SpellingAttempt {
        summary.latestAttempt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.word)
                        .font(.headline.weight(.bold))
                    Text(language.text(
                        japanese: "最新: \(attempt.date.formatted(date: .omitted, time: .shortened)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                        english: "Latest: \(attempt.date.formatted(date: .omitted, time: .shortened)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)"
                    ))
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(summaryDetail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(attempt.decision.label(language: language))
                    .font(.caption.weight(.bold))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(ParentPalette.warning.opacity(0.12))
                    .foregroundStyle(ParentPalette.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let drawingData = attempt.drawingData {
                DrawingPreview(drawingData: drawingData)
                    .frame(height: 140)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            }

            HStack {
                Button {
                    model.updateAttemptParentReview(attempt, decision: .approved)
                } label: {
                    Label(language.text(japanese: "正解", english: "Correct"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            .tapFeedback()

                Button {
                    model.updateAttemptParentReview(attempt, decision: .needsPractice)
                } label: {
                    Label(language.text(japanese: "もう一度", english: "Try Again"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            .tapFeedback()
            }
            .font(.caption.weight(.bold))
        }
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension ReviewAttemptSummaryCard {
    var summaryDetail: String {
        language.text(
            japanese: "同じ単語の記録 \(summary.attemptCount)回 ・ 確認待ち \(summary.needsReviewCount)回 ・ 直そう \(summary.needsPracticeCount)回",
            english: "\(summary.attemptCount) records for this word ・ \(summary.needsReviewCount) need review ・ \(summary.needsPracticeCount) need fix"
        )
    }
}

private struct ParentPracticeSampleCard: View {
    var sample: PracticeSample
    var language: AppLanguage

    private var modeLabel: String {
        if sample.mode == SessionMode.review.rawValue {
            return language.text(japanese: "ふくしゅう", english: "Review")
        }
        return language.text(japanese: "れんしゅう", english: "Practice")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sample.word)
                        .font(.headline.weight(.bold))
                    Text("\(modeLabel) ・ \(sample.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "text.bubble.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ParentPalette.primary)
            }

            DrawingPreview(drawingData: sample.drawingData)
                .frame(height: 150)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )
        }
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(ParentPalette.primary.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(ParentPalette.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(progress, 1)) * 100).rounded()))%")
                .font(.title3.monospacedDigit().weight(.heavy))
                .foregroundStyle(ParentPalette.primary)
        }
    }
}

private struct DrawingPreview: UIViewRepresentable {
    var drawingData: Data
    var horizontalPadding: CGFloat = 80
    var topPadding: CGFloat = 90
    var bottomPadding: CGFloat = 150

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if let drawing = try? PKDrawing(data: drawingData) {
            imageView.image = drawing.previewImage(
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                bottomPadding: bottomPadding
            )
        } else {
            imageView.image = nil
        }
    }
}

private struct ParentBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                ParentPalette.primarySoft,
                Color.white.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ParentDashboardView()
        .environmentObject(AppModel())
}
