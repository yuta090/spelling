import PencilKit
import SpellingSyncCore
import StoreKit
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
    @State private var selectedSection: ParentSection = UITestSupport.isActive ? .words : .grading

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
                    if selectedSection == .words || selectedSection == .records {
                        ParentCurrentStepCard(language: language)
                    }

                    GeometryReader { proxy in
                        ScrollView {
                            selectedPanel(width: proxy.size.width)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .padding(.bottom, 8)
                        }
                    }
                    .animation(.easeInOut(duration: 0.16), value: selectedSection)
                    .frame(maxHeight: .infinity)

                    if selectedSection != .grading {
                        Text(language.text(
                            japanese: "※ データは端末内に保存されます。iCloud同期にはまだ対応していません。",
                            english: "Data is saved on this device. iCloud sync is not included yet."
                        ))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
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
            return language.text(japanese: "学校とアプリ", english: "School & app")
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
                    EmptyStateView(
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

private enum ParentRecordDetailSheet: String, Identifiable {
    case appTests
    case handwriting
    case allHistory

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .appTests:
            return language.text(japanese: "アプリのテスト結果", english: "App Test Results")
        case .handwriting:
            return language.text(japanese: "手書き一覧", english: "Handwriting")
        case .allHistory:
            return language.text(japanese: "すべての記録", english: "All Records")
        }
    }

    var systemImage: String {
        switch self {
        case .appTests:
            return "checklist.checked"
        case .handwriting:
            return "pencil.and.scribble"
        case .allHistory:
            return "clock.arrow.circlepath"
        }
    }
}

/// 親向け「学習レポート」カード。直近7/30日の頑張りを数字で見せる（採点感より努力を肯定する）。
/// 集計は純粋ロジック `SpellingSyncCore.LearningReportBuilder`（AppModel.learningReport 経由）。
private struct LearningReportCard: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage
    @State private var days = 7

    var body: some View {
        // 1回だけ集計する（body 内で複数回参照しても再集計しないように local に保持）。
        let report = model.learningReport(days: days)
        ParentPanel(
            title: language.text(japanese: "学習レポート", english: "Learning Report"),
            systemImage: "chart.bar.fill",
            tint: ParentPalette.primary,
            showsHeader: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $days) {
                    Text(language.text(japanese: "7日", english: "7 days")).tag(7)
                    Text(language.text(japanese: "30日", english: "30 days")).tag(30)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(language.text(japanese: "レポートの期間", english: "Report period"))

                if report.totalEvents == 0 {
                    Text(language.text(japanese: "この期間の記録はまだありません。", english: "No records in this period yet."))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text(language.text(japanese: "\(report.currentStreakDays)日 れんぞく学習", english: "\(report.currentStreakDays)-day streak"))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(ParentPalette.ink)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    metric(report.totalEvents, label: language.text(japanese: "練習・テスト回数", english: "Practices/tests"))
                    metric(report.distinctWords, label: language.text(japanese: "とりくんだ語", english: "Words worked on"))
                    metric(report.learnedWords, label: language.text(japanese: "おぼえた語", english: "Words learned"))
                    metric(report.activeDays, label: language.text(japanese: "学習した日数", english: "Active days"))
                }
            }
        }
    }

    private func metric(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.heavy)).monospacedDigit()
                .foregroundStyle(ParentPalette.primary)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ParentRecordsWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingOtherSteps = false
    @State private var showingMoreRecords = false
    @State private var presentedRecordDetail: ParentRecordDetailSheet?
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
            LearningReportCard(language: language)
                .environmentObject(model)

            ParentPanel(
                title: language.text(japanese: "ステップ別の結果", english: "Step Results"),
                systemImage: "rectangle.stack.fill",
                tint: ParentPalette.primary,
                showsHeader: false
            ) {
                if orderedSteps.isEmpty {
                    EmptyStateView(
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

            if !orderedSteps.isEmpty {
                DisclosureGroup(isExpanded: $showingMoreRecords) {
                    ParentRecordDetailLauncher(language: language) { detail in
                        presentedRecordDetail = detail
                    }
                    .padding(.top, 8)
                } label: {
                    ParentMoreRecordsHeader(language: language)
                }
                .padding(12)
                .background(.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            }
        }
        .sheet(item: $presentedRecordDetail) { detail in
            ParentRecordDetailSheetView(detail: detail, language: language)
                .environmentObject(model)
                .presentationDetents([.large])
        }
    }
}

private struct ParentMoreRecordsHeader: View {
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 34, height: 34)
                .background(ParentPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(language.text(japanese: "その他の記録", english: "Other Records"))
                .font(.headline.weight(.heavy))
                .foregroundStyle(ParentPalette.ink)

            Spacer()
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
                Text(language.text(japanese: "ほかのステップ", english: "Other Steps"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
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

private struct ParentRecordDetailLauncher: View {
    var language: AppLanguage
    var open: (ParentRecordDetailSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ParentRecordDetailButton(
                    detail: .appTests,
                    language: language
                ) {
                    open(.appTests)
                }

                ParentRecordDetailButton(
                    detail: .handwriting,
                    language: language
                ) {
                    open(.handwriting)
                }

                ParentRecordDetailButton(
                    detail: .allHistory,
                    language: language
                ) {
                    open(.allHistory)
                }
            }
        }
        .padding(14)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ParentRecordDetailButton: View {
    var detail: ParentRecordDetailSheet
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: detail.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ParentPalette.primary)
                    .frame(width: 32, height: 32)
                    .background(ParentPalette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.title(language: language))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 12)
            .background(ParentPalette.surfaceTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ParentPalette.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }
}

private struct ParentRecordDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var detail: ParentRecordDetailSheet
    var language: AppLanguage

    var body: some View {
        NavigationStack {
            ZStack {
                ParentBackground()

                ScrollView {
                    detailPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(22)
                }
            }
            .navigationTitle(detail.title(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        switch detail {
        case .appTests:
            ParentAppTestResultsPanel(language: language)
        case .handwriting:
            HandwritingListPanel(language: language)
        case .allHistory:
            LearningHistoryPanel(language: language)
        }
    }
}

private struct ParentAppTestResultsPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var attempts: [SpellingAttempt] {
        Array(model.attempts.reversed())
    }

    private var correctCount: Int {
        model.attempts.filter { $0.decision == .autoCorrect || $0.parentReviewDecision == .approved }.count
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "アプリのテスト結果", english: "App Test Results"),
            systemImage: "checklist.checked"
        ) {
            HStack(spacing: 12) {
                SettingValueRow(
                    title: language.text(japanese: "回答", english: "Answers"),
                    value: "\(model.attempts.count)"
                )
                SettingValueRow(
                    title: language.text(japanese: "正解", english: "Correct"),
                    value: "\(correctCount)"
                )
                SettingValueRow(
                    title: language.text(japanese: "見直し", english: "Review"),
                    value: "\(model.reviewWords.count)"
                )
            }

            if attempts.isEmpty {
                EmptyStateView(
                    language.text(japanese: "まだアプリのテスト結果はありません", english: "No app test results yet"),
                    systemImage: "checklist",
                    description: Text(language.text(japanese: "子供がテストをするとここに表示されます。", english: "App test answers will appear here."))
                )
                .frame(minHeight: 260)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(attempts) { attempt in
                        ParentAppTestResultRow(attempt: attempt, language: language)
                    }
                }
            }
        }
    }
}

private struct ParentAppTestResultRow: View {
    var attempt: SpellingAttempt
    var language: AppLanguage

    private var isCleared: Bool {
        attempt.parentReviewDecision == .approved
            || (attempt.parentReviewDecision == .unreviewed && attempt.decision == .autoCorrect)
    }

    private var tint: Color {
        isCleared ? ParentPalette.success : ParentPalette.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: isCleared ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(attempt.word)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Text(formattedLocalizedDateTime(attempt.date, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(attempt.parentReviewDecision == .unreviewed ? attempt.decision.label(language: language) : attempt.parentReviewDecision.label(language: language))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(tint)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !attempt.recognizedText.isEmpty {
                Text("OCR: \(attempt.recognizedText)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let drawingData = attempt.drawingData {
                DrawingPreview(drawingData: drawingData, canvasSize: attempt.canvasSize)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
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

private struct ParentStepRecordCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSchoolEntry = false
    @State private var showingResultHistory = false
    @State private var testDate = Date()
    @State private var missedSchoolWordIDs = Set<UUID>()
    @State private var selectedResultItemID: String?
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

    private var appTestSummaries: [ParentStepAppTestSummary] {
        Dictionary(grouping: stepAttempts, by: \.sessionID)
            .compactMap { sessionID, attempts -> ParentStepAppTestSummary? in
                let sortedAttempts = attempts.sorted { $0.date < $1.date }
                guard let firstDate = sortedAttempts.first?.date else {
                    return nil
                }

                var latestByWord: [String: SpellingAttempt] = [:]
                for attempt in sortedAttempts {
                    latestByWord[normalize(attempt.word)] = attempt
                }

                let correctCount = step.words.filter { word in
                    guard let attempt = latestByWord[normalize(word.text)] else {
                        return false
                    }
                    return attemptIsCleared(attempt)
                }.count
                let missedWords = step.words.compactMap { word -> String? in
                    guard let attempt = latestByWord[normalize(word.text)] else {
                        return nil
                    }
                    return attemptIsCleared(attempt) ? nil : word.text
                }
                let unansweredWords = step.words.compactMap { word -> String? in
                    latestByWord[normalize(word.text)] == nil ? word.text : nil
                }

                return ParentStepAppTestSummary(
                    sessionID: sessionID,
                    date: firstDate,
                    correct: correctCount,
                    total: step.words.count,
                    missedWords: missedWords,
                    unansweredWords: unansweredWords
                )
            }
            .sorted { $0.date > $1.date }
    }

    private var resultTimelineItems: [ParentStepTestTimelineItem] {
        let appItems = appTestSummaries.map { ParentStepTestTimelineItem(appSummary: $0) }
        let schoolItems = schoolResults.map { ParentStepTestTimelineItem(schoolResult: $0) }
        return (appItems + schoolItems).sorted { $0.date > $1.date }
    }

    private var selectedResultItem: ParentStepTestTimelineItem? {
        if let selectedResultItemID,
           let item = resultTimelineItems.first(where: { $0.id == selectedResultItemID }) {
            return item
        }
        return resultTimelineItems.first
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
            && model.homeReviewWordIDs == reviewWordIDs
    }

    private var isSelectedStep: Bool {
        step.id == model.selectedWordStepID
    }

    private var cardTitle: String {
        isSelectedStep
            ? language.text(japanese: "結果まとめ", english: "Results Summary")
            : step.title(language: language)
    }

    private var schoolScoreText: String {
        guard let latestSchoolResult else {
            return language.text(japanese: "未入力", english: "Not entered")
        }
        if latestSchoolResult.score == latestSchoolResult.total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        return language.text(japanese: "\(latestSchoolResult.score)/\(latestSchoolResult.total) 正解", english: "\(latestSchoolResult.score)/\(latestSchoolResult.total) correct")
    }

    private var appResultText: String {
        guard appTestSessionCount > 0 else {
            return language.text(japanese: "未実施", english: "Not yet")
        }
        return language.text(japanese: "\(learnedCount)語できた", english: "\(learnedCount) learned")
    }

    private var schoolScoreColor: Color {
        guard let latestSchoolResult else {
            return ParentPalette.neutral
        }
        return latestSchoolResult.score == latestSchoolResult.total ? ParentPalette.success : ParentPalette.warning
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
                message: "",
                buttonTitle: nil,
                systemImage: "checkmark.seal.fill",
                tint: ParentPalette.success,
                kind: .none
            )
        }

        if latestSchoolResult == nil {
            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "まずやること", english: "First Action"),
                title: language.text(japanese: "学校のテスト結果を入力", english: "Enter school test result"),
                message: language.text(japanese: "点数と間違えた単語を入力すると、復習すべきか判断できます。", english: "Enter score and missed words to decide whether review is needed."),
                buttonTitle: language.text(japanese: "結果を入力", english: "Enter result"),
                systemImage: "graduationcap.fill",
                tint: ParentPalette.primary,
                kind: .enterSchoolTest,
                infoTitle: language.text(japanese: "学校のテスト結果について", english: "About school test results"),
                infoMessage: language.text(
                    japanese: "点数と間違えた単語を入力すると、次に復習する単語を選びやすくなります。",
                    english: "Entering the score and missed words makes it easier to choose what to review next."
                )
            )
        }

        if !reviewWords.isEmpty {
            if reviewWordsAreOnHome {
                return ParentStepRecordPrimaryAction(
                    eyebrow: language.text(japanese: "準備できました", english: "Ready"),
                    title: language.text(japanese: "\(reviewWords.count)語をホームに出しました", english: "\(reviewWords.count) words sent to Home"),
                    message: "",
                    buttonTitle: nil,
                    systemImage: "checkmark.circle.fill",
                    tint: ParentPalette.success,
                    kind: .none,
                    infoTitle: language.text(japanese: "復習のしくみ", english: "How Review Works"),
                    infoMessage: language.text(
                        japanese: "学校のテスト結果やアプリで間違えた単語だけをホームに出して、まとめて練習できます。",
                        english: "Only words missed in school or app tests are sent to Home for focused review."
                    )
                )
            }

            return ParentStepRecordPrimaryAction(
                eyebrow: language.text(japanese: "まずやること", english: "First Action"),
                title: language.text(japanese: "見直しが必要な単語 \(reviewWords.count)語", english: "\(reviewWords.count) words need review"),
                message: language.text(japanese: "この\(reviewWords.count)語を子供ホームの練習に出します。", english: "Send these \(reviewWords.count) words to Kid Home practice."),
                buttonTitle: language.text(japanese: "子供ホームに出す", english: "Send to Kid Home"),
                systemImage: "arrow.counterclockwise.circle.fill",
                tint: ParentPalette.warning,
                kind: .reviewWords,
                infoTitle: language.text(japanese: "復習のしくみ", english: "How Review Works"),
                infoMessage: language.text(
                    japanese: "学校のテスト結果やアプリで間違えた単語だけをホームに出して、まとめて練習できます。",
                    english: "Only words missed in school or app tests are sent to Home for focused review."
                )
            )
        }

        return ParentStepRecordPrimaryAction(
            eyebrow: language.text(japanese: "状態", english: "Status"),
            title: language.text(japanese: "このステップは確認済み", english: "This step is checked"),
            message: "",
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
                    Text(cardTitle)
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    if !isSelectedStep {
                        Label(formattedStepDate(step.registeredDate, language: language), systemImage: "calendar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !isSelectedStep {
                    Button {
                        model.selectedWordStepID = step.id
                    } label: {
                        Label(language.text(japanese: "選ぶ", english: "Select"), systemImage: "cursorarrow.rays")
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
                ParentStepSourceSummaryTile(
                    title: language.text(japanese: "アプリのテスト", english: "App Test"),
                    value: appResultText,
                    detail: nil,
                    systemImage: "brain.head.profile",
                    tint: ParentPalette.primary
                )

                ParentStepSourceSummaryTile(
                    title: language.text(japanese: "学校のテスト", english: "School Test"),
                    value: schoolScoreText,
                    detail: nil,
                    systemImage: "graduationcap.fill",
                    tint: schoolScoreColor,
                    valueTint: schoolScoreColor
                )
            }

            if !resultTimelineItems.isEmpty {
                Button {
                    showingResultHistory = true
                } label: {
                    Label(language.text(japanese: "結果の履歴を開く", english: "Open Result History"), systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .tint(ParentPalette.primary)
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
                    Label(language.text(japanese: "別の日の結果を入力", english: "Enter Another Date"), systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .tint(ParentPalette.primary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(isSelectedStep ? 0.96 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(isSelectedStep ? 0.09 : 0.05), radius: isSelectedStep ? 14 : 9, x: 0, y: 6)
        .onAppear {
            prepareSchoolDefaultsIfNeeded()
            selectDefaultResultItemIfNeeded()
        }
        .onValueChange(of: resultTimelineItems.map(\.id)) { _ in
            selectDefaultResultItemIfNeeded()
        }
        .sheet(isPresented: $showingResultHistory) {
            ParentStepResultHistorySheet(
                items: resultTimelineItems,
                selectedID: $selectedResultItemID,
                language: language
            )
            .environmentObject(model)
            .presentationDetents([.large])
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
            .frame(maxWidth: .infinity, alignment: .trailing)
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
                model.sendReviewWordsToHome(reviewWordIDs, stepID: step.id)
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

    private func selectDefaultResultItemIfNeeded() {
        let resultIDs = Set(resultTimelineItems.map(\.id))
        if let selectedResultItemID, resultIDs.contains(selectedResultItemID) {
            return
        }
        selectedResultItemID = resultTimelineItems.first?.id
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
        let savedResult = model.addSchoolTestResult(result)
        selectedResultItemID = "school-\(savedResult.id.uuidString)"
        testDate = Date()
        missedSchoolWordIDs.removeAll()
        note = ""
        prepareSchoolDefaultsIfNeeded()
        showingSchoolEntry = false
    }
}

private struct ParentStepResultHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var items: [ParentStepTestTimelineItem]
    @Binding var selectedID: String?
    var language: AppLanguage

    private var selectedItem: ParentStepTestTimelineItem? {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) {
            return item
        }
        return items.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParentBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        if items.isEmpty {
                            EmptyStateView(
                                language.text(japanese: "まだ結果はありません", english: "No results yet"),
                                systemImage: "clock",
                                description: Text(language.text(japanese: "アプリか学校の結果が入るとここに表示されます。", english: "App or school results will appear here."))
                            )
                            .frame(minHeight: 280)
                        } else {
                            ParentStepTestTimelinePicker(
                                items: items,
                                selectedID: selectedItem?.id,
                                language: language
                            ) { itemID in
                                selectedID = itemID
                            }

                            if let selectedItem {
                                switch selectedItem.source {
                                case .app:
                                    if let appSummary = selectedItem.appSummary {
                                        ParentStepAppTestResultCard(summary: appSummary, language: language)
                                    }
                                case .school:
                                    if let schoolResult = selectedItem.schoolResult {
                                        SchoolTestResultCard(result: schoolResult, language: language, showsStepTitle: false)
                                            .environmentObject(model)
                                    }
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            }
            .navigationTitle(language.text(japanese: "結果の履歴", english: "Result History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
        }
        .onAppear {
            if let selectedID, items.contains(where: { $0.id == selectedID }) {
                return
            }
            selectedID = items.first?.id
        }
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
                        japanese: "最初はすべて正解として扱います。学校のテストで間違えた単語だけタップしてください。選んだ単語はホームの復習に出せます。",
                        english: "All words start as correct. Tap only the words missed on the school test. Selected words can be sent to Home review."
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
                        Label(language.text(japanese: "全問OK", english: "All OK"), systemImage: "checkmark.seal.fill")
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

private struct ParentStepSourceSummaryTile: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color
    var valueTint: Color = ParentPalette.ink

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Text(value)
                    .font(.title3.monospacedDigit().weight(.heavy))
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.035), radius: 7, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let detail, !detail.isEmpty else {
            return "\(title): \(value)"
        }
        return "\(title): \(value), \(detail)"
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
            title: language.text(japanese: "学校のテスト結果を入力", english: "Enter School Test Result"),
            systemImage: "graduationcap.fill",
            tint: ParentPalette.primary
        ) {
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
                        Label(language.text(japanese: "学校のテスト結果を保存", english: "Save School Test Result"), systemImage: "square.and.arrow.down.fill")
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
                EmptyStateView(
                    language.text(japanese: "まだ学校のテスト結果がありません", english: "No school test results yet"),
                    systemImage: "graduationcap",
                    description: Text(language.text(japanese: "返ってきたら点数を入れます。", english: "Enter the score when it comes back."))
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
        .onValueChange(of: selectedStepID) { _ in
            if total <= 0 {
                applyDefaultTotal()
            }
        }
        .onValueChange(of: total) { newTotal in
            score = min(score, max(newTotal, 1))
        }
        .sheet(isPresented: $showingStepChooser) {
            ParentStepChooserSheet(
                title: language.text(japanese: "学校結果のステップを選ぶ", english: "Choose School Test Step"),
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

private struct ParentStepAppTestSummary: Equatable {
    var sessionID: UUID
    var date: Date
    var correct: Int
    var total: Int
    var missedWords: [String]
    var unansweredWords: [String]

    var id: String {
        "app-\(sessionID.uuidString)"
    }
}

private enum ParentStepTestTimelineSource {
    case app
    case school

    var systemImage: String {
        switch self {
        case .app:
            return "checkmark.circle.fill"
        case .school:
            return "graduationcap.fill"
        }
    }

    var tint: Color {
        switch self {
        case .app:
            return ParentPalette.neutral
        case .school:
            return ParentPalette.primary
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .app:
            return language.text(japanese: "アプリテスト", english: "App test")
        case .school:
            return language.text(japanese: "学校結果", english: "School result")
        }
    }
}

private struct ParentStepTestTimelineItem: Identifiable, Equatable {
    var id: String
    var source: ParentStepTestTimelineSource
    var date: Date
    var score: Int
    var total: Int
    var appSummary: ParentStepAppTestSummary?
    var schoolResult: SchoolTestResult?

    init(appSummary: ParentStepAppTestSummary) {
        self.id = appSummary.id
        self.source = .app
        self.date = appSummary.date
        self.score = appSummary.correct
        self.total = appSummary.total
        self.appSummary = appSummary
        self.schoolResult = nil
    }

    init(schoolResult: SchoolTestResult) {
        self.id = "school-\(schoolResult.id.uuidString)"
        self.source = .school
        self.date = schoolResult.date
        self.score = schoolResult.score
        self.total = schoolResult.total
        self.appSummary = nil
        self.schoolResult = schoolResult
    }

    func scoreText(language: AppLanguage, includesCorrectLabel: Bool = false) -> String {
        if source == .school && score == total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        let base = "\(score)/\(max(total, 1))"
        guard includesCorrectLabel else {
            return base
        }
        return language.text(japanese: "\(base) 正解", english: "\(base) correct")
    }
}

private struct ParentStepTestTimelinePicker: View {
    var items: [ParentStepTestTimelineItem]
    var selectedID: String?
    var language: AppLanguage
    var select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(language.text(japanese: "テスト結果", english: "Test Results"), systemImage: "clock.fill")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                select(item.id)
                            }
                        } label: {
                            ParentStepTestTimelineChip(
                                item: item,
                                isSelected: item.id == selectedID,
                                language: language
                            )
                        }
                        .buttonStyle(.plain)
                        .tapFeedback()
                        .accessibilityAddTraits(item.id == selectedID ? .isSelected : [])
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.035), radius: 7, x: 0, y: 4)
    }
}

private struct ParentStepTestTimelineChip: View {
    var item: ParentStepTestTimelineItem
    var isSelected: Bool
    var language: AppLanguage

    private var tint: Color {
        item.source.tint
    }

    private var backgroundColor: Color {
        if isSelected {
            return tint
        }
        return item.source == .school ? ParentPalette.primarySoft : Color.white.opacity(0.9)
    }

    private var foregroundColor: Color {
        isSelected ? .white : tint
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.source.systemImage)
                .font(.caption.weight(.heavy))
                .frame(width: 22, height: 22)
                .background(isSelected ? Color.white.opacity(0.18) : tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.scoreText(language: language))
                    .font(.subheadline.monospacedDigit().weight(.heavy))
                    .lineLimit(1)
                Text(formattedCompactResultDate(item.date, language: language))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(foregroundColor)
        .frame(minWidth: item.source == .school ? 108 : 92, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 9)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    item.source == .school ? tint.opacity(isSelected ? 0 : 0.44) : ParentPalette.neutral.opacity(0.12),
                    lineWidth: 1.2
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.035), radius: 7, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.source.label(language: language)) \(item.scoreText(language: language, includesCorrectLabel: true)) \(formattedCompactResultDate(item.date, language: language))")
    }
}

private struct ParentStepAppTestResultCard: View {
    var summary: ParentStepAppTestSummary
    var language: AppLanguage

    private var scoreHeadline: String {
        if summary.correct == summary.total && summary.unansweredWords.isEmpty {
            return language.text(japanese: "全問正解", english: "All Correct")
        }
        if !summary.unansweredWords.isEmpty {
            return language.text(
                japanese: "\(summary.correct)/\(max(summary.total, 1)) 正解 ・ \(summary.unansweredWords.count)問未回答",
                english: "\(summary.correct)/\(max(summary.total, 1)) correct, \(summary.unansweredWords.count) unanswered"
            )
        }
        return language.text(japanese: "\(summary.correct)/\(max(summary.total, 1)) 正解", english: "\(summary.correct)/\(max(summary.total, 1)) correct")
    }

    private var scoreColor: Color {
        summary.correct == summary.total && summary.unansweredWords.isEmpty ? ParentPalette.success : ParentPalette.warning
    }

    private var statusIconName: String {
        if summary.correct == summary.total && summary.unansweredWords.isEmpty {
            return "checkmark.circle.fill"
        }
        if !summary.unansweredWords.isEmpty {
            return "questionmark.circle.fill"
        }
        return "exclamationmark.circle.fill"
    }

    private var detailRows: [(text: String, color: Color)] {
        var rows: [(String, Color)] = []
        if !summary.missedWords.isEmpty {
            rows.append((
                language.text(
                    japanese: "まちがい: \(summary.missedWords.joined(separator: " / "))",
                    english: "Missed: \(summary.missedWords.joined(separator: " / "))"
                ),
                ParentPalette.warning
            ))
        }
        if !summary.unansweredWords.isEmpty {
            rows.append((
                language.text(
                    japanese: "未回答: \(summary.unansweredWords.joined(separator: " / "))",
                    english: "Unanswered: \(summary.unansweredWords.joined(separator: " / "))"
                ),
                ParentPalette.neutral
            ))
        }
        if rows.isEmpty {
            rows.append((
                language.text(japanese: "アプリではまちがいなし", english: "No misses in the app"),
                .secondary
            ))
        }
        return rows
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIconName)
                .font(.title3.weight(.heavy))
                .foregroundStyle(scoreColor)
                .frame(width: 40, height: 40)
                .background(scoreColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(scoreHeadline)
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .foregroundStyle(scoreColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                    Text(row.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
    }
}

private func formattedCompactResultDate(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language == .japanese ? Locale(identifier: "ja_JP") : Locale(identifier: "en_US")
    formatter.dateFormat = language == .japanese ? "M月d日" : "MMM d"
    return formatter.string(from: date)
}

private struct SchoolTestResultCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingDeleteConfirmation = false

    var result: SchoolTestResult
    var language: AppLanguage
    var showsStepTitle = true

    private var missedCount: Int {
        max(result.total - result.score, 0)
    }

    private var scoreHeadline: String {
        if result.score == result.total {
            return language.text(japanese: "満点", english: "Perfect")
        }
        return language.text(japanese: "\(result.score)/\(result.total) 正解", english: "\(result.score)/\(result.total) correct")
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

    private var missedWordsText: String {
        result.missedWords.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var missedWordsLabel: String {
        if missedWordsText.isEmpty {
            return language.text(japanese: "まちがいなし", english: "No missed words")
        }
        return language.text(japanese: "まちがい: \(missedWordsText)", english: "Missed: \(missedWordsText)")
    }

    private var missedWordsColor: Color {
        missedWordsText.isEmpty ? ParentPalette.success : ParentPalette.danger
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
                if showsStepTitle {
                    Text(result.stepTitle.isEmpty ? language.text(japanese: "ステップ未設定", english: "No step") : result.stepTitle)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)

                    Text(formattedLocalizedDate(result.date, language: language))
                        .font(Font.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Label(
                    missedWordsLabel,
                    systemImage: missedWordsText.isEmpty ? "checkmark.circle.fill" : "text.badge.xmark"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(missedWordsColor)
                .lineLimit(2)
                .minimumScaleFactor(0.74)

                if !result.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(result.note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.headline.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .tapFeedback()
            .tint(ParentPalette.danger)
            .accessibilityLabel(language.text(japanese: "学校のテスト結果を削除", english: "Delete school test result"))
        }
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
        .alert(
            language.text(japanese: "テスト結果を削除しますか？", english: "Delete this test result?"),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(language.text(japanese: "削除", english: "Delete"), role: .destructive) {
                model.deleteSchoolTestResult(result)
            }
            Button(language.text(japanese: "キャンセル", english: "Cancel"), role: .cancel) {}
        } message: {
            Text(language.text(
                japanese: "この学校のテスト結果は元に戻せません。",
                english: "This school test result cannot be restored."
            ))
        }
    }
}

private struct ParentPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color = ParentPalette.primary
    var showsHeader = true
    var content: Content

    init(title: String, systemImage: String, tint: Color = ParentPalette.primary, showsHeader: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.showsHeader = showsHeader
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                Label(title, systemImage: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
            }

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
    @State private var showingNewStep = false
    var language: AppLanguage

    private var orderedSteps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "ステップ管理", english: "Step Management"),
            systemImage: "rectangle.stack.fill"
        ) {
            ParentNewStepButton(language: language) {
                showingNewStep = true
            }

            if orderedSteps.isEmpty {
                EmptyStateView(
                    language.text(japanese: "ステップがありません", english: "No steps yet"),
                    systemImage: "rectangle.stack.fill",
                    description: Text(language.text(japanese: "最初のステップを作ってください。", english: "Create the first step."))
                )
                .frame(minHeight: 120)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.primary)
                        .frame(width: 34, height: 34)
                        .background(ParentPalette.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(language.text(japanese: "登録済み", english: "Registered"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)

                    Spacer()

                    Text("\(model.wordSteps.count)")
                        .font(.title3.monospacedDigit().weight(.heavy))
                        .foregroundStyle(ParentPalette.primary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(ParentPalette.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
                .background(ParentPalette.surfaceTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showingNewStep) {
            ParentNewStepSheet(language: language)
                .environmentObject(model)
                .presentationDetents([.large])
        }
    }
}

private struct ParentNewStepButton: View {
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(ParentPalette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(japanese: "新しいステップを作る", english: "Create New Step"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Text(language.text(japanese: "日付と単語を入力", english: "Enter date and words"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ParentPalette.primary)
            }
            .padding(12)
            .background(ParentPalette.primarySoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ParentPalette.primary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }
}

/// カメラ取り込みの日本語訳オプション（親・子で共用）。設定に直接ひもづくので自動保存・次回適用。
/// トグルを切り替えると、入力欄のテキストにもその場で日本語訳を付け直す。
struct ImportJapaneseOptionsView: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage
    @Binding var draftText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.settings.importAttachJapanese) {
                Label(
                    language.text(japanese: "取り込み時に日本語訳をつける", english: "Add Japanese translation on import"),
                    systemImage: "character.book.closed"
                )
                .font(.subheadline.weight(.bold))
            }

            if model.settings.importAttachJapanese {
                Toggle(isOn: $model.settings.importUseKanji) {
                    Label(
                        language.text(japanese: "漢字をつかう（ふりがな付き）", english: "Use kanji (with furigana)"),
                        systemImage: "textformat"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.leading, 4)
            }
        }
        .tint(ParentPalette.primary)
        .padding(12)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onValueChange(of: model.settings.importAttachJapanese) { _ in reapply() }
        .onValueChange(of: model.settings.importUseKanji) { _ in reapply() }
    }

    private func reapply() {
        let updated = reapplyJapanese(
            to: draftText,
            knownWords: model.words,
            attachJapanese: model.settings.importAttachJapanese,
            useKanji: model.settings.importUseKanji
        )
        if updated != draftText {
            draftText = updated
        }
    }
}

func formattedImportedWordLine(
    _ word: String,
    knownWords: [SpellingWord],
    attachJapanese: Bool,
    useKanji: Bool
) -> String {
    let normalized = normalize(word)
    guard !normalized.isEmpty else {
        return ""
    }

    guard attachJapanese else {
        return normalized
    }

    // すでに登録済みの単語に手入力の訳があればそれを優先（漢字なし指定ならふりがなへ変換）。
    if let prompt = knownPrompt(for: normalized, in: knownWords) {
        let adjusted = useKanji ? prompt : japanesePromptWithoutKanji(prompt)
        return "\(normalized) | \(adjusted)"
    }

    if let prompt = BasicJapaneseWordPrompt.prompt(for: normalized, useKanji: useKanji) {
        return "\(normalized) | \(prompt)"
    }

    // 同梱辞書（EJDict）でフォールバック。guard/scope など内蔵に無い語もカバー。
    if let dbGloss = WordBank.shared.japanese(for: normalized) {
        let adjusted = useKanji ? dbGloss : japanesePromptWithoutKanji(dbGloss)
        return "\(normalized) | \(adjusted)"
    }

    return normalized
}

/// 取り込み済みの入力欄テキストを、現在の設定で日本語訳を付け直す（後からトグルを切り替えても反映できるように）。
/// 手入力済みの訳はできるだけ保持し、漢字なしのときだけふりがなへ変換する。
func reapplyJapanese(
    to rawText: String,
    knownWords: [SpellingWord],
    attachJapanese: Bool,
    useKanji: Bool
) -> String {
    let entries = parseWordListEntries(from: rawText)
    let lines = entries.compactMap { entry -> String? in
        let word = normalize(entry.text)
        guard !word.isEmpty else {
            return nil
        }
        guard attachJapanese else {
            return word
        }

        let existing = (entry.promptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if useKanji {
            if existing.contains(where: { $0.isHan }) {
                prompt = existing // すでに漢字あり → そのまま
            } else if let dictKanji = BasicJapaneseWordPrompt.prompt(for: word, useKanji: true),
                      dictKanji.contains(where: { $0.isHan }) {
                prompt = dictKanji // かなのみ → 辞書の漢字へ
            } else if !existing.isEmpty {
                prompt = existing
            } else {
                prompt = BasicJapaneseWordPrompt.prompt(for: word, useKanji: true) ?? ""
            }
        } else {
            let base = existing.isEmpty ? (BasicJapaneseWordPrompt.prompt(for: word, useKanji: false) ?? "") : existing
            prompt = japanesePromptWithoutKanji(base)
        }

        var finalPrompt = prompt
        // 辞書に無ければ同梱辞書（EJDict）でフォールバック。
        if finalPrompt.isEmpty, let dbGloss = WordBank.shared.japanese(for: word) {
            finalPrompt = useKanji ? dbGloss : japanesePromptWithoutKanji(dbGloss)
        }

        return finalPrompt.isEmpty ? word : "\(word) | \(finalPrompt)"
    }
    return lines.joined(separator: "\n")
}

func knownPrompt(for word: String, in knownWords: [SpellingWord]) -> String? {
    knownWords
        .first { normalize($0.text) == word && !$0.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
        .promptText
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 「漢字[よみ]」形式の訳をふりがな（よみ）だけに変換する。漢字を持たない訳はそのまま。
/// 例: "学校[がっこう]がすき" -> "がっこうがすき"
func japanesePromptWithoutKanji(_ text: String) -> String {
    var result = ""
    var buffer = ""
    var index = text.startIndex

    while index < text.endIndex {
        if text[index] == "[", let closing = text[index...].firstIndex(of: "]") {
            let readingStart = text.index(after: index)
            let reading = String(text[readingStart..<closing]).trimmingCharacters(in: .whitespacesAndNewlines)
            // 直前の漢字（連続するHan）だけを base とする。かな（「を」「お」等）は残す。
            var cut = buffer.endIndex
            while cut > buffer.startIndex {
                let previous = buffer.index(before: cut)
                if !buffer[previous].isHan {
                    break
                }
                cut = previous
            }
            let hasBase = cut < buffer.endIndex
            if !reading.isEmpty, hasBase {
                result += String(buffer[..<cut])
                result += reading
                buffer = ""
                index = text.index(after: closing)
                continue
            }
            // base が無い／読みが空 → ブラケットはそのまま文字として扱う（表示パーサと整合）
        }

        buffer.append(text[index])
        index = text.index(after: index)
    }

    result += buffer
    return result
}

enum BasicJapaneseWordPrompt {
    // 漢字（ふりがな付き）を使いたい単語。ここに無い語はかな表記の prompts を使う。
    private static let kanjiPrompts: [String: String] = [
        "animal": "動[どう]物[ぶつ]",
        "bear": "熊[くま]",
        "beautiful": "美[うつく]しい",
        "big": "大[おお]きい",
        "bird": "鳥[とり]",
        "black": "黒[くろ]",
        "blue": "青[あお]",
        "book": "本[ほん]",
        "brother": "兄[きょう]弟[だい]",
        "brown": "茶[ちゃ]色[いろ]",
        "car": "車[くるま]",
        "cat": "猫[ねこ]",
        "cold": "寒[さむ]い",
        "color": "色[いろ]",
        "come": "来[く]る",
        "cow": "牛[うし]",
        "day": "日[ひ]",
        "desk": "机[つくえ]",
        "dog": "犬[いぬ]",
        "drink": "飲[の]む",
        "eat": "食[た]べる",
        "egg": "卵[たまご]",
        "family": "家[か]族[ぞく]",
        "fish": "魚[さかな]",
        "flower": "花[はな]",
        "friend": "友[とも]だち",
        "go": "行[い]く",
        "good": "良[よ]い",
        "grass": "草[くさ]",
        "green": "緑[みどり]",
        "home": "家[いえ]",
        "homework": "宿[しゅく]題[だい]",
        "horse": "馬[うま]",
        "hot": "暑[あつ]い",
        "house": "家[いえ]",
        "i": "私[わたし]",
        "long": "長[なが]い",
        "meat": "肉[にく]",
        "month": "月[つき]",
        "moon": "月[つき]",
        "mountain": "山[やま]",
        "name": "名[な]前[まえ]",
        "night": "夜[よる]",
        "ocean": "海[うみ]",
        "one": "一[いち]",
        "paper": "紙[かみ]",
        "pencil": "鉛[えん]筆[ぴつ]",
        "pig": "豚[ぶた]",
        "play": "遊[あそ]ぶ",
        "rain": "雨[あめ]",
        "read": "読[よ]む",
        "red": "赤[あか]",
        "river": "川[かわ]",
        "room": "部屋[へや]",
        "run": "走[はし]る",
        "sad": "悲[かな]しい",
        "school": "学[がっ]校[こう]",
        "sea": "海[うみ]",
        "sheep": "羊[ひつじ]",
        "short": "短[みじか]い",
        "sing": "歌[うた]う",
        "sister": "姉[し]妹[まい]",
        "sky": "空[そら]",
        "sleep": "寝[ね]る",
        "small": "小[ちい]さい",
        "snow": "雪[ゆき]",
        "star": "星[ほし]",
        "student": "生[せい]徒[と]",
        "sun": "太[たい]陽[よう]",
        "swim": "泳[およ]ぐ",
        "teacher": "先[せん]生[せい]",
        "today": "今日[きょう]",
        "tree": "木[き]",
        "walk": "歩[ある]く",
        "water": "水[みず]",
        "week": "週[しゅう]",
        "white": "白[しろ]",
        "wind": "風[かぜ]",
        "write": "書[か]く",
        "year": "年[とし]",
        "yellow": "黄[き]色[いろ]"
    ]

    private static let prompts: [String: String] = [
        "a": "ひとつの",
        "about": "について",
        "after": "あとで",
        "again": "もういちど",
        "all": "すべて",
        "also": "また",
        "and": "そして",
        "animal": "どうぶつ",
        "apple": "りんご",
        "around": "まわり",
        "baby": "あかちゃん",
        "bad": "よくない",
        "bag": "かばん",
        "banana": "バナナ",
        "be": "である",
        "bear": "くま",
        "beautiful": "うつくしい",
        "because": "なぜなら",
        "bed": "ベッド",
        "before": "まえに",
        "big": "おおきい",
        "bird": "とり",
        "black": "くろ",
        "blue": "あお",
        "book": "ほん",
        "boy": "おとこのこ",
        "bread": "パン",
        "brother": "きょうだい",
        "brown": "ちゃいろ",
        "bus": "バス",
        "cake": "ケーキ",
        "car": "くるま",
        "cat": "ねこ",
        "chair": "いす",
        "cheese": "チーズ",
        "class": "クラス",
        "cloud": "くも",
        "cold": "さむい",
        "color": "いろ",
        "come": "くる",
        "cow": "うし",
        "day": "ひ",
        "desk": "つくえ",
        "dog": "いぬ",
        "door": "ドア",
        "drink": "のむ",
        "duck": "あひる",
        "eat": "たべる",
        "egg": "たまご",
        "family": "かぞく",
        "father": "おとうさん",
        "fish": "さかな",
        "flower": "はな",
        "food": "たべもの",
        "friend": "ともだち",
        "frog": "かえる",
        "game": "ゲーム",
        "girl": "おんなのこ",
        "go": "いく",
        "good": "よい",
        "grandfather": "おじいさん",
        "grandmother": "おばあさん",
        "grass": "くさ",
        "grape": "ぶどう",
        "green": "みどり",
        "happy": "うれしい",
        "home": "いえ",
        "homework": "しゅくだい",
        "horse": "うま",
        "hot": "あつい",
        "house": "いえ",
        "i": "わたし",
        "juice": "ジュース",
        "jump": "とぶ",
        "lesson": "レッスン",
        "lion": "ライオン",
        "little": "ちいさい",
        "long": "ながい",
        "meat": "にく",
        "milk": "ミルク",
        "monkey": "さる",
        "month": "つき",
        "moon": "つき",
        "mother": "おかあさん",
        "mountain": "やま",
        "mouse": "ねずみ",
        "name": "なまえ",
        "night": "よる",
        "ocean": "うみ",
        "one": "いち",
        "orange": "オレンジ",
        "paper": "かみ",
        "peach": "もも",
        "pear": "なし",
        "pen": "ペン",
        "pencil": "えんぴつ",
        "pig": "ぶた",
        "pink": "ピンク",
        "play": "あそぶ",
        "purple": "むらさき",
        "rabbit": "うさぎ",
        "rain": "あめ",
        "read": "よむ",
        "red": "あか",
        "rice": "ごはん",
        "river": "かわ",
        "room": "へや",
        "run": "はしる",
        "sad": "かなしい",
        "school": "がっこう",
        "sea": "うみ",
        "sheep": "ひつじ",
        "short": "みじかい",
        "sing": "うたう",
        "sister": "しまい",
        "sky": "そら",
        "sleep": "ねる",
        "small": "ちいさい",
        "snow": "ゆき",
        "soup": "スープ",
        "star": "ほし",
        "student": "せいと",
        "sun": "たいよう",
        "swim": "およぐ",
        "table": "テーブル",
        "tall": "せがたかい",
        "teacher": "せんせい",
        "test": "テスト",
        "tiger": "トラ",
        "today": "きょう",
        "tomorrow": "あした",
        "tree": "き",
        "walk": "あるく",
        "water": "みず",
        "week": "しゅう",
        "white": "しろ",
        "window": "まど",
        "wind": "かぜ",
        "write": "かく",
        "year": "とし",
        "yellow": "きいろ",
        "you": "あなた",
        // --- 追加分（小・中学でよく出る語）---
        "two": "ふたつ", "three": "みっつ", "four": "よっつ", "five": "いつつ",
        "six": "むっつ", "seven": "ななつ", "eight": "やっつ", "nine": "ここのつ",
        "ten": "とお", "hundred": "ひゃく", "thousand": "せん", "number": "すうじ",
        "monday": "げつようび", "tuesday": "かようび", "wednesday": "すいようび",
        "thursday": "もくようび", "friday": "きんようび", "saturday": "どようび",
        "sunday": "にちようび",
        "morning": "あさ", "noon": "ひる", "evening": "ゆうがた", "time": "じかん",
        "hour": "じかん", "minute": "ふん", "yesterday": "きのう", "now": "いま",
        "weekend": "しゅうまつ", "future": "みらい", "past": "かこ",
        "spring": "はる", "summer": "なつ", "autumn": "あき", "winter": "ふゆ",
        "weather": "てんき", "sunny": "はれ", "cloudy": "くもり", "rainy": "あめ",
        "warm": "あたたかい", "cool": "すずしい",
        "head": "あたま", "face": "かお", "eye": "め", "ear": "みみ", "nose": "はな",
        "mouth": "くち", "tooth": "は", "hand": "て", "foot": "あし", "arm": "うで",
        "finger": "ゆび", "neck": "くび", "back": "せなか", "stomach": "おなか", "body": "からだ",
        "parent": "おや", "child": "こども", "son": "むすこ", "daughter": "むすめ",
        "uncle": "おじ", "aunt": "おば", "cousin": "いとこ", "husband": "おっと", "wife": "つま",
        "elephant": "ぞう", "giraffe": "きりん", "panda": "パンダ", "penguin": "ペンギン",
        "dolphin": "いるか", "whale": "くじら", "snake": "へび", "turtle": "かめ",
        "fox": "きつね", "wolf": "おおかみ", "deer": "しか", "goat": "やぎ",
        "chicken": "にわとり", "owl": "ふくろう", "ant": "あり", "bee": "はち",
        "insect": "むし", "dinosaur": "きょうりゅう", "dragon": "りゅう",
        "strawberry": "いちご", "watermelon": "すいか", "lemon": "レモン", "melon": "メロン",
        "tomato": "トマト", "potato": "じゃがいも", "carrot": "にんじん", "onion": "たまねぎ",
        "corn": "とうもろこし", "mushroom": "きのこ", "pumpkin": "かぼちゃ", "tea": "おちゃ",
        "coffee": "コーヒー", "sugar": "さとう", "salt": "しお", "candy": "あめ",
        "chocolate": "チョコレート", "cookie": "クッキー", "hamburger": "ハンバーガー",
        "pizza": "ピザ", "noodle": "めん", "vegetable": "やさい", "fruit": "くだもの",
        "breakfast": "あさごはん", "lunch": "ひるごはん", "dinner": "ばんごはん",
        "city": "まち", "town": "まち", "country": "くに", "world": "せかい",
        "station": "えき", "hospital": "びょういん", "library": "としょかん", "park": "こうえん",
        "store": "みせ", "restaurant": "レストラン", "museum": "はくぶつかん",
        "zoo": "どうぶつえん", "temple": "おてら", "shrine": "じんじゃ", "bridge": "はし",
        "road": "みち", "airport": "くうこう", "building": "たてもの",
        "bicycle": "じてんしゃ", "train": "でんしゃ", "airplane": "ひこうき", "ship": "ふね",
        "boat": "ボート", "truck": "トラック", "taxi": "タクシー",
        "doctor": "いしゃ", "nurse": "かんごし", "police": "けいさつ", "farmer": "のうか",
        "cook": "コック", "singer": "かしゅ",
        "subject": "きょうか", "math": "すうがく", "science": "りか", "english": "えいご",
        "history": "れきし", "music": "おんがく", "art": "びじゅつ", "question": "しつもん",
        "answer": "こたえ", "word": "ことば", "sentence": "ぶん", "story": "ものがたり",
        "picture": "え", "notebook": "ノート", "eraser": "けしごむ", "ruler": "じょうぎ",
        "scissors": "はさみ",
        "angry": "おこった", "hungry": "おなかがすいた", "thirsty": "のどがかわいた",
        "tired": "つかれた", "sleepy": "ねむい", "scared": "こわい", "kind": "しんせつ",
        "strong": "つよい", "weak": "よわい", "fast": "はやい", "slow": "おそい",
        "easy": "かんたん", "difficult": "むずかしい", "new": "あたらしい", "old": "ふるい",
        "young": "わかい", "clean": "きれい", "dirty": "きたない", "heavy": "おもい",
        "light": "かるい", "dark": "くらい", "bright": "あかるい", "quiet": "しずか",
        "busy": "いそがしい", "important": "たいせつ", "famous": "ゆうめい",
        "expensive": "たかい", "cheap": "やすい", "delicious": "おいしい", "sweet": "あまい",
        "spicy": "からい", "fun": "たのしい", "interesting": "おもしろい",
        "open": "あける", "close": "しめる", "stop": "とめる", "push": "おす", "pull": "ひく",
        "carry": "はこぶ", "throw": "なげる", "catch": "とる", "hold": "もつ", "give": "あげる",
        "buy": "かう", "sell": "うる", "make": "つくる", "build": "たてる", "break": "こわす",
        "fix": "なおす", "wash": "あらう", "study": "べんきょうする", "teach": "おしえる",
        "learn": "まなぶ", "remember": "おぼえる", "forget": "わすれる", "think": "かんがえる",
        "know": "しる", "understand": "わかる", "speak": "はなす", "say": "いう",
        "tell": "つたえる", "ask": "きく", "listen": "きく", "look": "みる", "see": "みる",
        "watch": "みる", "show": "みせる", "find": "みつける", "lose": "なくす", "win": "かつ",
        "help": "たすける", "wait": "まつ", "meet": "あう", "visit": "たずねる",
        "arrive": "つく", "leave": "でる", "enter": "はいる", "climb": "のぼる",
        "fall": "おちる", "fly": "とぶ", "ride": "のる", "drive": "うんてんする",
        "cry": "なく", "laugh": "わらう", "cut": "きる", "draw": "かく", "paint": "ぬる",
        "dance": "おどる", "wear": "きる", "use": "つかう", "want": "ほしい", "like": "すき",
        "love": "あいする", "hate": "きらい", "hope": "のぞむ", "try": "ためす",
        "finish": "おわる", "become": "なる", "feel": "かんじる", "live": "すむ",
        "grow": "そだつ", "change": "かえる", "move": "うごく", "work": "はたらく",
        "rest": "やすむ", "sit": "すわる", "stand": "たつ",
        "guard": "まもる", "scope": "はんい", "dream": "ゆめ", "idea": "アイデア",
        "problem": "もんだい", "reason": "りゆう", "fact": "じじつ", "news": "ニュース",
        "example": "れい", "group": "グループ", "team": "チーム", "member": "メンバー",
        "peace": "へいわ", "nature": "しぜん", "environment": "かんきょう",
        "energy": "エネルギー", "machine": "きかい", "computer": "コンピューター",
        "phone": "でんわ", "letter": "てがみ", "money": "おかね", "job": "しごと",
        // --- 追加分 第2弾（日常・教科でよく出る語）---
        "accept": "うけいれる", "across": "わたって", "agree": "さんせいする", "allow": "ゆるす",
        "almost": "ほとんど", "along": "そって", "already": "すでに", "always": "いつも",
        "anger": "いかり", "ankle": "あしくび", "another": "べつの", "appear": "あらわれる",
        "attack": "こうげきする", "bacon": "ベーコン", "ball": "ボール", "balloon": "ふうせん",
        "bamboo": "たけ", "bank": "ぎんこう", "baseball": "やきゅう", "basket": "かご",
        "basketball": "バスケットボール", "bat": "こうもり", "bathroom": "おふろ", "beach": "はまべ",
        "beans": "まめ", "bedroom": "しんしつ", "beef": "ぎゅうにく", "beetle": "カブトムシ",
        "behind": "うしろ", "believe": "しんじる", "belt": "ベルト", "beside": "となり",
        "between": "あいだ", "blackboard": "こくばん", "blood": "ち", "bone": "ほね",
        "both": "りょうほう", "bottle": "びん", "bowl": "ボウル", "box": "はこ",
        "brain": "のう", "branch": "えだ", "brush": "ブラシ", "button": "ボタン",
        "cabbage": "キャベツ", "camel": "ラクダ", "camera": "カメラ", "cap": "キャップ",
        "castle": "しろ", "cave": "どうくつ", "ceiling": "てんじょう", "celebrate": "おいわいする",
        "chalk": "チョーク", "check": "しらべる", "cheek": "ほお", "chestnut": "くり",
        "chin": "あご", "choose": "えらぶ", "church": "きょうかい", "cinema": "えいがかん",
        "circle": "まる", "classmate": "クラスメート", "classroom": "きょうしつ", "clock": "とけい",
        "clothes": "ふく", "club": "クラブ", "coat": "コート", "collect": "あつめる",
        "comic": "まんが", "company": "かいしゃ", "compare": "くらべる", "complete": "かんせいする",
        "continue": "つづける", "copy": "うつす", "cost": "かかる", "count": "かぞえる",
        "crab": "かに", "crocodile": "ワニ", "crow": "からす", "cup": "コップ",
        "curry": "カレー", "decide": "きめる", "desert": "さばく", "dessert": "デザート",
        "dictionary": "じしょ", "disappear": "きえる", "donut": "ドーナツ", "doubt": "うたがう",
        "dragonfly": "トンボ", "drawing": "え", "dress": "ドレス", "drum": "ドラム",
        "each": "それぞれ", "elbow": "ひじ", "engine": "エンジン", "enjoy": "たのしむ",
        "erase": "けす", "escape": "にげる", "exam": "しけん", "exercise": "うんどうする",
        "explain": "せつめいする", "express": "あらわす", "factory": "こうじょう", "farm": "のうじょう",
        "fear": "きょうふ", "few": "すこし", "field": "のはら", "fight": "たたかう",
        "fire": "ほのお", "floor": "ゆか", "flour": "こむぎこ", "flute": "フルート",
        "fog": "きり", "follow": "ついていく", "forehead": "ひたい", "forest": "もり",
        "fork": "フォーク", "from": "から", "front": "まえ", "garden": "にわ",
        "garlic": "にんにく", "gather": "あつまる", "ginger": "しょうが", "glass": "ガラス",
        "glasses": "めがね", "gloves": "てぶくろ", "goal": "もくひょう", "golf": "ゴルフ",
        "goodbye": "さようなら", "grade": "せいせき", "grasshopper": "バッタ", "guess": "すいそくする",
        "guitar": "ギター", "gym": "たいいくかん", "ham": "ハム", "hamster": "ハムスター",
        "happen": "おこる", "happiness": "しあわせ", "hat": "ぼうし", "he": "かれ",
        "heart": "こころ", "helicopter": "ヘリコプター", "hello": "こんにちは", "here": "ここ",
        "hide": "かくれる", "hill": "おか", "hippo": "カバ", "hotel": "ホテル",
        "how": "どうやって", "ice": "こおり", "imagine": "そうぞうする", "inside": "なか",
        "introduce": "しょうかいする", "invite": "しょうたいする", "island": "しま", "it": "それ",
        "jacket": "ジャケット", "jellyfish": "クラゲ", "join": "さんかする", "joy": "よろこび",
        "judo": "じゅうどう", "just": "ちょうど", "kangaroo": "カンガルー", "karate": "からて",
        "key": "かぎ", "kitchen": "だいどころ", "kite": "たこあげ", "kiwi": "キウイ",
        "knife": "ナイフ", "koala": "コアラ", "lake": "みずうみ", "lamp": "ランプ",
        "lead": "みちびく", "leaf": "はっぱ", "lettuce": "レタス", "lie": "うそ",
        "line": "せん", "lip": "くちびる", "lizard": "トカゲ", "mango": "マンゴー",
        "many": "たくさんの", "map": "ちず", "marathon": "マラソン", "market": "いちば",
        "match": "しあい", "maybe": "たぶん", "meal": "しょくじ", "measure": "はかる",
        "memory": "きおく", "mirror": "かがみ", "more": "もっと", "mosquito": "か",
        "most": "いちばん", "motorcycle": "バイク", "movie": "えいが", "much": "たくさん",
        "muscle": "きんにく", "my": "わたしの", "nail": "つめ", "near": "ちかく",
        "net": "ネット", "never": "けっして", "no": "いいえ", "octopus": "たこ",
        "office": "じむしょ", "often": "よく", "oil": "あぶら", "on": "うえ",
        "only": "だけ", "other": "ほかの", "outside": "そと", "over": "うえに",
        "page": "ページ", "pan": "フライパン", "pancake": "パンケーキ", "pants": "ズボン",
        "parrot": "オウム", "pay": "はらう", "peanut": "ピーナッツ", "pepper": "こしょう",
        "photo": "しゃしん", "piano": "ピアノ", "pigeon": "はと", "pineapple": "パイナップル",
        "plan": "けいかく", "plant": "うえる", "plate": "さら", "please": "おねがい",
        "plum": "うめ", "pocket": "ポケット", "point": "てん", "pond": "いけ",
        "pool": "プール", "popcorn": "ポップコーン", "pork": "ぶたにく", "pot": "なべ",
        "practice": "れんしゅうする", "prepare": "じゅんびする", "principal": "こうちょう", "prize": "しょう",
        "promise": "やくそく", "protect": "まもる", "pudding": "プリン", "quiz": "クイズ",
        "race": "レース", "racket": "ラケット", "radish": "だいこん", "rainbow": "にじ",
        "ramen": "ラーメン", "rat": "ねずみ", "realize": "きづく", "really": "ほんとうに",
        "recognize": "みわける", "refuse": "ことわる", "repeat": "くりかえす", "report": "レポート",
        "ring": "ゆびわ", "rock": "いわ", "rocket": "ロケット", "roof": "やね",
        "root": "ね", "rose": "バラ", "rule": "ルール", "same": "おなじ",
        "sand": "すな", "sausage": "ソーセージ", "scarf": "マフラー", "schedule": "よてい",
        "score": "とくてん", "seal": "アザラシ", "search": "さがす", "secret": "ひみつ",
        "seed": "たね", "shadow": "かげ", "shape": "かたち", "share": "わけあう",
        "shark": "サメ", "she": "かのじょ", "shirt": "シャツ", "shoes": "くつ",
        "shrimp": "えび", "skate": "スケート", "ski": "スキー", "skin": "はだ",
        "skirt": "スカート", "smoke": "けむり", "snack": "おやつ", "snail": "かたつむり",
        "soap": "せっけん", "soccer": "サッカー", "socks": "くつした", "some": "いくつかの",
        "sometimes": "ときどき", "song": "うた", "soon": "すぐに", "sorry": "ごめんなさい",
        "sparrow": "すずめ", "spell": "つづる", "spinach": "ほうれんそう", "spoon": "スプーン",
        "sport": "スポーツ", "square": "しかく", "squid": "いか", "squirrel": "りす",
        "stadium": "スタジアム", "stairs": "かいだん", "still": "まだ", "stone": "いし",
        "storm": "あらし", "subway": "ちかてつ", "sunflower": "ひまわり", "sushi": "すし",
        "swan": "はくちょう", "sweater": "セーター", "swimming": "すいえい", "tennis": "テニス",
        "textbook": "きょうかしょ", "thanks": "ありがとう", "that": "あれ", "theater": "げきじょう",
        "there": "そこ", "these": "これら", "they": "かれら", "this": "これ",
        "those": "あれら", "throat": "のど", "through": "とおって", "thunder": "かみなり",
        "ticket": "きっぷ", "toe": "あしのゆび", "tofu": "とうふ", "tongue": "した",
        "too": "…すぎる", "towel": "タオル", "tower": "タワー", "triangle": "さんかく",
        "trumpet": "トランペット", "truth": "しんじつ", "umbrella": "かさ", "under": "した",
        "uniform": "せいふく", "valley": "たに", "very": "とても", "violin": "バイオリン",
        "volleyball": "バレーボール", "wall": "かべ", "we": "わたしたち", "what": "なに",
        "wheat": "こむぎ", "wheel": "しゃりん", "when": "いつ", "where": "どこ",
        "which": "どれ", "who": "だれ", "why": "なぜ", "wish": "ねがい",
        "with": "いっしょに", "without": "なしで", "worm": "みみず", "wrist": "てくび",
        "yes": "はい", "yogurt": "ヨーグルト", "your": "あなたの", "zebra": "シマウマ",
    ]

    static func prompt(for word: String, useKanji: Bool = false) -> String? {
        if useKanji, let kanji = kanjiPrompts[word] {
            return kanji
        }
        return prompts[word]
    }
}

private struct ParentNewStepSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var stepDate = Date()
    @State private var rawWords = ""
    @State private var showingWordCamera = false
    @State private var isScanningWordImage = false
    @StateObject private var scanProgress = ScanProgressModel()
    @State private var statusMessage: String?
    @State private var statusSucceeded = false
    var language: AppLanguage

    private var entries: [WordListEntry] {
        parseWordListEntries(from: rawWords)
    }

    private var demoWordListText: String {
        """
        cat | ねこ
        dog | いぬ
        name | 名前[なまえ]
        school | 学校[がっこう]
        """
    }

    private var wordInputPlaceholder: String {
        language.text(
            japanese: "例:\ncat | ねこ\ndog | いぬ\nname | 名前[なまえ]\nschool | 学校[がっこう]",
            english: "Example:\ncat | cat\ndog | dog\nname | name\nschool | school"
        )
    }

    private var datePickerLocale: Locale {
        Locale(identifier: language == .japanese ? "ja_JP" : "en_US")
    }

    private var datePickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = datePickerLocale
        return calendar
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParentBackground()

                VStack(spacing: 16) {
                    ParentPanel(
                        title: language.text(japanese: "新しいステップを作る", english: "Create New Step"),
                        systemImage: "plus.circle.fill"
                    ) {
                        HStack(spacing: 12) {
                            Label(language.text(japanese: "登録日", english: "Date"), systemImage: "calendar")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(ParentPalette.ink)

                            DatePicker(
                                "",
                                selection: $stepDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .environment(\.locale, datePickerLocale)
                            .environment(\.calendar, datePickerCalendar)
                            .tint(ParentPalette.primary)

                            Spacer()

                            Text(language.text(japanese: "\(entries.count) 単語", english: "\(entries.count) words"))
                                .font(.headline.monospacedDigit().weight(.heavy))
                                .foregroundStyle(ParentPalette.primary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(ParentPalette.primarySoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(12)
                        .background(ParentPalette.surfaceTint)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ParentPalette.primary.opacity(0.14), lineWidth: 1)
                        )

                        HStack(alignment: .center, spacing: 10) {
                            Label(
                                language.text(japanese: "1行に1単語。日本語は | の右に書きます。", english: "One word per line. Put prompts after |."),
                                systemImage: "text.alignleft"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                appendDemoWords()
                            } label: {
                                Label(language.text(japanese: "デモ単語を挿入", english: "Insert Demo Words"), systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.heavy))
                            }
                            .buttonStyle(.bordered)
                            .tapFeedback()
                            .tint(ParentPalette.primary)
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $rawWords)
                                .font(.title3.monospaced())
                                .frame(minHeight: 210, maxHeight: 260)
                                .padding(8)
                                .background(ParentPalette.surfaceTint)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ParentPalette.primary.opacity(0.16), lineWidth: 1)
                                )

                            if rawWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(wordInputPlaceholder)
                                    .font(.title3.monospaced())
                                    .foregroundStyle(.secondary.opacity(0.55))
                                    .padding(.top, 16)
                                    .padding(.leading, 14)
                                    .allowsHitTesting(false)
                            }
                        }

                        if let statusMessage {
                            WordImportStatusBanner(
                                message: statusMessage,
                                isSuccess: statusSucceeded,
                                isScanning: isScanningWordImage,
                                scanProgress: scanProgress.fraction
                            )
                        }

                        ImportJapaneseOptionsView(language: language, draftText: $rawWords)

                        HStack {
                            Button {
                                startCameraImport()
                            } label: {
                                Label(
                                    isScanningWordImage ? language.text(japanese: "読み取り中", english: "Scanning") : language.text(japanese: "カメラで読み取り", english: "Scan Camera"),
                                    systemImage: "camera.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tapFeedback()
                            .disabled(isScanningWordImage)

                            Button {
                                rawWords = ""
                                statusMessage = nil
                            } label: {
                                Label(language.text(japanese: "消す", english: "Clear"), systemImage: "eraser.fill")
                            }
                            .buttonStyle(.bordered)
                            .tapFeedback()
                            .disabled(rawWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Button {
                                saveStep()
                            } label: {
                                Label(
                                    language.text(japanese: "ステップを作成", english: "Create Step"),
                                    systemImage: "checkmark.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tapFeedback()
                            .tint(ParentPalette.primary)
                            .disabled(entries.isEmpty)
                        }
                        .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: 760)

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
            .fullScreenCover(isPresented: $showingWordCamera) {
                WordCameraImportSheet(language: language) { image in
                    scanWordImage(image)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func saveStep() {
        let result = model.addWordsToStep(from: rawWords, registeredAt: stepDate)
        if result.added > 0 || result.updated > 0 {
            dismiss()
            return
        }

        statusSucceeded = false
        statusMessage = language.text(
            japanese: "新しく追加できる単語がありません。",
            english: "There are no new words to add."
        )
    }

    private func appendDemoWords() {
        let currentText = rawWords.trimmingCharacters(in: .whitespacesAndNewlines)
        rawWords = currentText.isEmpty
            ? demoWordListText
            : currentText + "\n" + demoWordListText

        statusSucceeded = true
        statusMessage = language.text(
            japanese: "デモ単語を入力欄に追加しました。必要に応じて書き換えてください。",
            english: "Added demo words to the editor. Edit them as needed."
        )
    }

    private func startCameraImport() {
        statusSucceeded = false

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            statusMessage = language.text(
                japanese: "この端末ではカメラが使えません。iPad実機で試してください。",
                english: "Camera is not available on this device. Try it on a real iPad."
            )
            return
        }

        showingWordCamera = true
    }

    private func scanWordImage(_ image: UIImage) {
        isScanningWordImage = true
        scanProgress.start()
        statusSucceeded = false
        statusMessage = language.text(japanese: "宿題の文字を読み取っています。", english: "Scanning the homework text.")

        Task {
            do {
                let importedWords = try await WordListImageTextRecognizer(language: model.settings.language).recognizeWords(in: image) { fraction in
                    Task { @MainActor in scanProgress.report(fraction) }
                }
                await MainActor.run {
                    let addedCount = appendImportedWords(importedWords)
                    scanProgress.finish()
                    isScanningWordImage = false

                    if importedWords.isEmpty {
                        statusSucceeded = false
                        statusMessage = language.text(
                            japanese: "英単語を見つけられませんでした。",
                            english: "No English words were found."
                        )
                    } else if addedCount == 0 {
                        statusSucceeded = true
                        statusMessage = language.text(
                            japanese: "読み取った単語はすでに入っています。",
                            english: "The scanned words are already listed."
                        )
                    } else {
                        statusSucceeded = true
                        statusMessage = language.text(
                            japanese: "\(addedCount)単語を追加しました。日本語がわかる単語は自動で付けました。",
                            english: "Added \(addedCount) words. Japanese hints were added when available."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    scanProgress.reset()
                    isScanningWordImage = false
                    statusSucceeded = false
                    statusMessage = language.text(
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
        let importedLines = additions.map {
            formattedImportedWordLine(
                $0,
                knownWords: model.words,
                attachJapanese: model.settings.importAttachJapanese,
                useKanji: model.settings.importUseKanji
            )
        }
        rawWords = currentText.isEmpty
            ? importedLines.joined(separator: "\n")
            : currentText + "\n" + importedLines.joined(separator: "\n")

        return additions.count
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
    @State private var showingAllWords = false
    @State private var showingBatchManager = false
    @State private var showingLevelSet = false
    @State private var isScanningWordImage = false
    @StateObject private var scanProgress = ScanProgressModel()
    @State private var importMessage: String?
    @State private var importSucceeded = false
    var language: AppLanguage

    private var selectedStep: WordStep? {
        model.selectedWordStep
    }

    private var demoWordListText: String {
        """
        cat | ねこ
        dog | いぬ
        name | 名前[なまえ]
        school | 学校[がっこう]
        """
    }

    private var wordInputPlaceholder: String {
        language.text(
            japanese: "例:\ncat | ねこ\ndog | いぬ\nname | 名前[なまえ]\nschool | 学校[がっこう]",
            english: "Example:\ncat | cat\ndog | dog\nname | name\nschool | school"
        )
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "このステップの単語", english: "Step Words"),
            systemImage: "list.bullet.rectangle"
        ) {
            if let step = selectedStep {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text(
                            japanese: "\(step.words.count)単語を編集中",
                            english: "Editing \(step.words.count) words"
                        ))
                        .font(.headline.monospacedDigit().weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    }

                    Spacer()

                    Button {
                        showingLevelSet = true
                    } label: {
                        Label(language.text(japanese: "レベルで作成", english: "By Level"), systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("parent.byLevel")
                    .tapFeedback()
                    .tint(ParentPalette.primary)

                    Button {
                        showingBatchManager = true
                    } label: {
                        Label(language.text(japanese: "登録の管理", english: "Manage"), systemImage: "calendar.badge.clock")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tapFeedback()
                    .tint(ParentPalette.primary)

                    Button {
                        showingAllWords = true
                    } label: {
                        Label(language.text(japanese: "全単語を見る", english: "All Words"), systemImage: "tray.full.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tapFeedback()
                    .tint(ParentPalette.primary)
                }

                Button {
                    startCameraImport()
                } label: {
                    Label(
                        isScanningWordImage ? language.text(japanese: "読み取り中", english: "Scanning") : language.text(japanese: "カメラで読み取り", english: "Scan Camera"),
                        systemImage: "camera.fill"
                    )
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tapFeedback()
                .tint(ParentPalette.primary)
                .disabled(isScanningWordImage)

                HStack(alignment: .center, spacing: 10) {
                    Label(
                        language.text(japanese: "1行に1単語。日本語は | の右に書きます。", english: "One word per line. Put prompts after |."),
                        systemImage: "text.alignleft"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        appendDemoWords()
                    } label: {
                        Label(language.text(japanese: "デモ単語を挿入", english: "Insert Demo Words"), systemImage: "plus.circle.fill")
                            .font(.caption.weight(.heavy))
                    }
                    .buttonStyle(.bordered)
                    .tapFeedback()
                    .tint(ParentPalette.primary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $rawWords)
                        .font(.title3.monospaced())
                        .frame(minHeight: 180, maxHeight: 230)
                        .padding(8)
                        .background(ParentPalette.surfaceTint)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ParentPalette.primary.opacity(0.16), lineWidth: 1)
                        )

                    if rawWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(wordInputPlaceholder)
                            .font(.title3.monospaced())
                            .foregroundStyle(.secondary.opacity(0.55))
                            .padding(.top, 16)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }

                if let importMessage {
                    WordImportStatusBanner(
                        message: importMessage,
                        isSuccess: importSucceeded,
                        isScanning: isScanningWordImage,
                        scanProgress: scanProgress.fraction
                    )
                }

                ImportJapaneseOptionsView(language: language, draftText: $rawWords)

                HStack(spacing: 10) {
                    Button {
                        reloadSelectedStep()
                    } label: {
                        Label(language.text(japanese: "戻す", english: "Reload"), systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tapFeedback()

                    Button {
                        saveSelectedStep(step)
                    } label: {
                        Label(language.text(japanese: "このステップを保存", english: "Save This Step"), systemImage: "square.and.arrow.down.fill")
                            .font(.title3.weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tapFeedback()
                    .tint(ParentPalette.primary)
                    .disabled(parseWordListEntries(from: rawWords).isEmpty)
                }
            } else {
                EmptyStateView(
                    language.text(japanese: "ステップがありません", english: "No step"),
                    systemImage: "rectangle.stack.fill",
                    description: Text(language.text(japanese: "先に新しいステップを作ってください。", english: "Create a step first."))
                )
                .frame(minHeight: 220)
            }
        }
        .onAppear {
            reloadSelectedStep()
        }
        .onValueChange(of: model.selectedWordStepID) { _ in
            reloadSelectedStep()
        }
        .fullScreenCover(isPresented: $showingWordCamera) {
            WordCameraImportSheet(language: language) { image in
                scanWordImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingAllWords) {
            ParentAllWordsSheet(language: language)
                .environmentObject(model)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingBatchManager) {
            WordRegistrationManagerView(language: language)
                .environmentObject(model)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingLevelSet) {
            WordLevelSetSheet(language: language)
                .environmentObject(model)
                .presentationDetents([.large])
        }
    }

    private func reloadSelectedStep() {
        rawWords = wordListEditorText(selectedStep?.words ?? [])
        importMessage = nil
    }

    private func saveSelectedStep(_ step: WordStep) {
        let count = model.replaceWords(in: step, from: rawWords)
        importSucceeded = true
        importMessage = language.text(
            japanese: "\(count)単語をこのステップに保存しました。",
            english: "Saved \(count) words in this step."
        )
    }

    private func appendDemoWords() {
        let currentText = rawWords.trimmingCharacters(in: .whitespacesAndNewlines)
        rawWords = currentText.isEmpty
            ? demoWordListText
            : currentText + "\n" + demoWordListText

        importSucceeded = true
        importMessage = language.text(
            japanese: "デモ単語を入力欄に追加しました。必要に応じて書き換えてください。",
            english: "Added demo words to the editor. Edit them as needed."
        )
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
        scanProgress.start()
        importSucceeded = false
        importMessage = language.text(japanese: "宿題の文字を読み取っています。", english: "Scanning the homework text.")

        Task {
            do {
                let importedWords = try await WordListImageTextRecognizer(language: model.settings.language).recognizeWords(in: image) { fraction in
                    Task { @MainActor in scanProgress.report(fraction) }
                }
                await MainActor.run {
                    let addedCount = appendImportedWords(importedWords)
                    scanProgress.finish()
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
                            japanese: "読み取った単語はこのステップに入っています。",
                            english: "The scanned words are already in this step."
                        )
                    } else {
                        importSucceeded = true
                        importMessage = language.text(
                            japanese: "\(addedCount)単語をこのステップに追加しました。日本語と読み間違いを確認して保存してください。",
                            english: "Added \(addedCount) words to this step. Check Japanese hints and misreads before saving."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    scanProgress.reset()
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
        let importedLines = additions.map {
            formattedImportedWordLine(
                $0,
                knownWords: model.words,
                attachJapanese: model.settings.importAttachJapanese,
                useKanji: model.settings.importUseKanji
            )
        }
        rawWords = currentText.isEmpty
            ? importedLines.joined(separator: "\n")
            : currentText + "\n" + importedLines.joined(separator: "\n")

        return additions.count
    }
}

private struct ParentWordRow: View {
    var word: SpellingWord
    var language: AppLanguage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.text)
                    .font(.headline.weight(.semibold))
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// レベル（US学年=Dolch / 難易度=NGSL頻度）を選んで、おすすめ単語のステップを自動作成する。
private struct WordLevelSetSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    private enum Axis: String, CaseIterable, Identifiable {
        case grade, difficulty
        var id: String { rawValue }
    }

    @State private var axis: Axis = .grade
    @State private var grade = "pre-K"
    @State private var band = 1
    @State private var count = 15
    @State private var statusMessage: String?
    @State private var showingPaywall = false

    private let grades = ["pre-K", "K", "1", "2", "3"]

    /// いま選んでいるレベル（学年軸 or 難易度軸）を型付きで表す。
    private var selectedLevel: ContentLevel? {
        ContentLevel(dolch: axis == .grade ? grade : nil, band: axis == .difficulty ? band : nil)
    }

    /// 選択中レベルが解放済みか（無料＝pre-K/K のみ、ほかは保護者プランで解放）。
    /// レベルを解釈できない（想定外の）場合は安全側に倒してロック扱い（fail-closed）。
    private var isSelectedLevelUnlocked: Bool {
        guard let level = selectedLevel else { return false }
        return ContentGate.isUnlocked(level, isSubscribed: model.hasFullAccess)
    }

    private func gradeLabel(_ g: String) -> String {
        switch g {
        case "pre-K": return language.text(japanese: "にゅうもん", english: "Pre-K")
        case "K": return language.text(japanese: "きほん", english: "K")
        default: return language.text(japanese: "US \(g)年生", english: "US Grade \(g)")
        }
    }

    private func bandLabel(_ b: Int) -> String {
        let name: String
        switch b {
        case 1: name = language.text(japanese: "とてもやさしい", english: "Very easy")
        case 2: name = language.text(japanese: "やさしい", english: "Easy")
        case 3: name = language.text(japanese: "ふつう", english: "Medium")
        case 4: name = language.text(japanese: "むずかしい", english: "Hard")
        default: name = language.text(japanese: "とてもむずかしい", english: "Very hard")
        }
        return "Lv\(b)・\(name)"
    }

    private var existing: Set<String> {
        Set(model.words.map { normalize($0.text) })
    }

    private var candidates: [LeveledWord] {
        WordBank.shared.leveledWords(
            dolch: axis == .grade ? grade : nil,
            band: axis == .difficulty ? band : nil,
            excluding: existing,
            limit: count
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $axis) {
                        Text(language.text(japanese: "US学年", english: "US Grade")).tag(Axis.grade)
                        Text(language.text(japanese: "難易度", english: "Difficulty")).tag(Axis.difficulty)
                    }
                    .pickerStyle(.segmented)

                    if axis == .grade {
                        Picker(language.text(japanese: "学年", english: "Grade"), selection: $grade) {
                            ForEach(grades, id: \.self) { Text(gradeLabel($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(language.text(
                            japanese: "Dolch（アメリカの小学校の読み・スペル用の語）。\"US 1年生\"はネイティブ向けの目安です。",
                            english: "Dolch sight words (US elementary reading/spelling). US grades are native-speaker levels."
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Picker(language.text(japanese: "難易度", english: "Difficulty"), selection: $band) {
                            ForEach(1...5, id: \.self) { Text("Lv\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(bandLabel(band))
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(ParentPalette.primary)
                        Text(language.text(
                            japanese: "NGSL（使われる頻度）による難易度。やさしい＝よく使う語。",
                            english: "Difficulty by NGSL word frequency. Easy = very common words."
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Stepper(value: $count, in: 5...30, step: 5) {
                        Text(language.text(japanese: "最大 \(count)語", english: "Up to \(count) words"))
                            .font(.subheadline.weight(.bold))
                    }

                    Divider()

                    if candidates.isEmpty {
                        Text(language.text(
                            japanese: "このレベルで追加できる新しい単語がありません（すでに登録済みかも）。",
                            english: "No new words available at this level (they may already be registered)."
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(language.text(japanese: "ふくまれる単語（\(candidates.count)）", english: "Words (\(candidates.count))"))
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(ParentPalette.ink)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(candidates) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.word)
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(ParentPalette.ink)
                                    Text(item.ja)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(ParentPalette.surfaceTint)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                }
                .padding(20)
            }

            // 主ボタンは最下部に固定して常に見えるようにする（スクロール不要）。
            VStack(alignment: .leading, spacing: 10) {
                if !isSelectedLevelUnlocked {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text(language.text(
                            japanese: "このレベルは保護者プランで解放されます（pre-K・K と手書き登録は無料）。",
                            english: "This level unlocks with the parent plan (pre-K, K, and handwriting entry are free)."
                        ))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ParentPalette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ParentPalette.success)
                }

                Button {
                    if isSelectedLevelUnlocked {
                        createSet()
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label(
                        isSelectedLevelUnlocked
                            ? language.text(japanese: "このセットを作る", english: "Create This Set")
                            : language.text(japanese: "プランで解放する", english: "Unlock with Plan"),
                        systemImage: isSelectedLevelUnlocked ? "plus.circle.fill" : "lock.fill"
                    )
                    .font(.headline.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tapFeedback()
                .tint(ParentPalette.primary)
                .disabled(isSelectedLevelUnlocked && candidates.isEmpty)
                .accessibilityIdentifier(isSelectedLevelUnlocked ? "level.create" : "level.unlock")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.bar)
            }
            .navigationTitle(language.text(japanese: "レベルで単語を作る", english: "Add Words by Level"))
            .navigationBarTitleDisplayMode(.inline)
            // レベルを変えたら、前の「作成しました」表示は消す（固定フッターに古い結果を残さない）。
            .onValueChange(of: selectedLevel) { _ in statusMessage = nil }
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView(language: language, store: model.store)
                    .environmentObject(model)
            }
        }
    }

    private func createSet() {
        guard isSelectedLevelUnlocked else { return }
        let words = candidates
        guard !words.isEmpty else { return }
        let rawText = words.map { "\($0.word) | \($0.ja)" }.joined(separator: "\n")
        let result = model.addWordsToStep(from: rawText)
        statusMessage = language.text(
            japanese: "\(result.added)語のステップを作りました。",
            english: "Created a step with \(result.added) words."
        )
    }
}

/// 保護者プラン（サブスク）の案内画面。**親ゲートの奥**でのみ表示する。
///
/// フェーズ1: UI のみ（StoreKit 未接続）。購入・復元は次アップデートで `StoreManager` に接続する。
/// App Store 審査の必須記載（プラン名/期間・含まれる機能・更新後の満額・トライアル長＋後価格・
/// 復元・利用規約・プライバシーポリシー）を満たすレイアウトにしてある。
private struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    private enum Plan: String, CaseIterable, Identifiable {
        case year, month
        var id: String { rawValue }
    }

    @ObservedObject var store: StoreManager

    @State private var selectedPlan: Plan = .year
    @State private var showComingSoon = false
    @State private var statusMessage: String?
    @State private var showStatus = false

    // 商品ロード前/失敗時のフォールバック価格（実価格は StoreKit `Product.displayPrice`）。
    private let monthlyPriceText = "¥580"
    private let yearlyPriceText = "¥4,800"
    // TODO(本番): 実URLに差し替える（審査で必須・到達可能であること）。
    private let termsURL = URL(string: "https://example.com/terms")!
    private let privacyURL = URL(string: "https://example.com/privacy")!

    /// 商品がロードできているか（`.storekit`/ASC 未設定なら false → CTA は「準備中」）。
    private var hasProducts: Bool { !store.products.isEmpty }

    private func planKind(_ plan: Plan) -> StoreManager.PlanKind { plan == .year ? .yearly : .monthly }

    private var selectedProduct: Product? { store.product(for: planKind(selectedPlan)) }

    /// 表示価格（商品があれば実価格、なければフォールバック）。
    private func priceText(_ plan: Plan) -> String {
        if let product = store.product(for: planKind(plan)) { return product.displayPrice }
        return plan == .year ? yearlyPriceText : monthlyPriceText
    }

    /// CTA の文言（対象者ならトライアル訴求、そうでなければ購読）。
    private var ctaTitle: String {
        if hasProducts && !store.isTrialEligible {
            return language.text(japanese: "購読する", english: "Subscribe")
        }
        return language.text(japanese: "無料で始める", english: "Start free trial")
    }

    /// 自動更新・トライアルの開示文（選択プランの実価格・eligibility で出し分け）。
    private var disclosureText: String {
        let renew = priceText(selectedPlan)
        let perJa = selectedPlan == .year ? "年" : "月"
        let perEn = selectedPlan == .year ? "yr" : "mo"
        if hasProducts && store.isTrialEligible {
            return language.text(
                japanese: "初回は7日間無料。体験後は \(renew)/\(perJa) で自動更新されます。いつでも解約できます。",
                english: "7-day free trial. After the trial it auto-renews at \(renew)/\(perEn). Cancel anytime."
            )
        }
        return language.text(
            japanese: "\(renew)/\(perJa) で自動更新されます。いつでも解約できます。",
            english: "Auto-renews at \(renew)/\(perEn). Cancel anytime."
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text(japanese: "保護者プラン", english: "Parent Plan"))
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(ParentPalette.ink)
                        Text(language.text(
                            japanese: "おうちの英語スペル学習を、フルに使えるように。",
                            english: "Unlock the full spelling-learning experience at home."
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        benefitRow(icon: "books.vertical.fill",
                                   title: language.text(japanese: "ぜんぶの単語セット", english: "All word sets"),
                                   detail: language.text(japanese: "US学年（Grade 1以降）・難易度（NGSL）ぜんぶからレベル生成。", english: "Generate sets from all US grades (1+) and NGSL difficulty bands."))
                        benefitRow(icon: "pencil.and.outline",
                                   title: language.text(japanese: "リモート採点", english: "Remote grading"),
                                   detail: language.text(japanese: "はなれていても、子の書き取りをスマホで採点。", english: "Grade your child's writing from your phone, anywhere."))
                        benefitRow(icon: "chart.bar.fill",
                                   title: language.text(japanese: "学習レポート", english: "Learning reports"),
                                   detail: language.text(japanese: "覚えた語数・連続日数など、がんばりを数字で。", english: "See words learned, streaks, and progress in numbers."))
                        benefitRow(icon: "arrow.triangle.2.circlepath",
                                   title: language.text(japanese: "複数端末で同期", english: "Multi-device sync"),
                                   detail: language.text(japanese: "iPad と iPhone など、家族の端末で続きを。", english: "Continue across the family's iPad and iPhone."))
                    }

                    VStack(spacing: 10) {
                        planCard(.year,
                                 title: language.text(japanese: "年額", english: "Yearly"),
                                 price: priceText(.year),
                                 per: language.text(japanese: "/年", english: "/yr"),
                                 badge: language.text(japanese: "おすすめ・約2ヶ月分お得", english: "Best value · ~2 months free"))
                        planCard(.month,
                                 title: language.text(japanese: "月額", english: "Monthly"),
                                 price: priceText(.month),
                                 per: language.text(japanese: "/月", english: "/mo"),
                                 badge: nil)
                    }

                    Text(disclosureText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await startPurchase() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.purchaseInFlight {
                                ProgressView().tint(.white)
                            }
                            Label(ctaTitle, systemImage: "sparkles")
                        }
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ParentPalette.primary)
                    .tapFeedback()
                    .disabled(store.purchaseInFlight)

                    HStack(spacing: 16) {
                        Button(language.text(japanese: "購入を復元", english: "Restore purchases")) {
                            Task { await startRestore() }
                        }
                        .disabled(store.purchaseInFlight)
                        Spacer()
                        Link(language.text(japanese: "利用規約", english: "Terms"), destination: termsURL)
                        Link(language.text(japanese: "プライバシー", english: "Privacy"), destination: privacyURL)
                    }
                    .font(.caption.weight(.bold))
                    .tint(ParentPalette.primary)
                }
                .padding(20)
            }
            .navigationTitle(language.text(japanese: "プラン", english: "Plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "とじる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                }
                #if DEBUG
                // デバッグ用：スクロール不要で確実に解放（開発・E2E用）。Release では出さない。
                ToolbarItem(placement: .primaryAction) {
                    Button(language.text(japanese: "解放", english: "Unlock")) {
                        model.debugUnlockAll = true
                        dismiss()
                    }
                    .accessibilityIdentifier("paywall.debugUnlock")
                }
                #endif
            }
            .alert(language.text(japanese: "準備中", english: "Coming soon"), isPresented: $showComingSoon) {
                Button(language.text(japanese: "OK", english: "OK"), role: .cancel) {}
            } message: {
                Text(language.text(
                    japanese: "商品を読み込めませんでした。少し時間をおいて試してください。",
                    english: "Couldn't load products. Please try again shortly."
                ))
            }
            .alert(language.text(japanese: "お知らせ", english: "Notice"), isPresented: $showStatus) {
                Button(language.text(japanese: "OK", english: "OK"), role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    /// 選択プランを購入する。商品が無ければ「準備中」、成功なら閉じる、承認待ちは通知。
    private func startPurchase() async {
        guard let product = selectedProduct else {
            showComingSoon = true
            return
        }
        do {
            switch try await store.purchase(product) {
            case .success:
                dismiss()
            case .pending:
                statusMessage = language.text(
                    japanese: "購入は承認待ちです。承認されると自動で反映されます。",
                    english: "Your purchase is pending approval and will apply automatically once approved."
                )
                showStatus = true
            case .cancelled:
                break
            }
        } catch {
            statusMessage = language.text(
                japanese: "購入を完了できませんでした。もう一度お試しください。",
                english: "Could not complete the purchase. Please try again."
            )
            showStatus = true
        }
    }

    /// 購入を復元する（商品ロードに依存しない）。
    private func startRestore() async {
        do {
            try await store.restore()
            statusMessage = model.isSubscribed
                ? language.text(japanese: "購入を復元しました。", english: "Your purchase was restored.")
                : language.text(japanese: "復元できる購入が見つかりませんでした。", english: "No purchases to restore.")
        } catch {
            statusMessage = language.text(japanese: "復元できませんでした。", english: "Couldn't restore purchases.")
        }
        showStatus = true
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(ParentPalette.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(ParentPalette.ink)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planCard(_ plan: Plan, title: String, price: String, per: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? ParentPalette.primary : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ParentPalette.success)
                    }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(price).font(.title3.weight(.heavy)).foregroundStyle(ParentPalette.ink)
                    Text(per).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(ParentPalette.surfaceTint)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? ParentPalette.primary : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// 登録1回ぶん（同じ source・登録時刻）の単語のまとまり。
private struct WordRegistrationBatch: Identifiable {
    let id: String
    let source: WordSource
    let date: Date
    let words: [SpellingWord]
}

/// 登録のまとまりごとに一覧表示して、まとめて削除できる親用ビュー。
private struct WordRegistrationManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    @State private var pendingDelete: WordRegistrationBatch?

    private var batches: [WordRegistrationBatch] {
        let groups = Dictionary(grouping: model.words) { word -> String in
            let second = Int(word.registeredAt.timeIntervalSinceReferenceDate.rounded())
            return "\(word.source.rawValue)#\(second)"
        }
        return groups.map { key, words -> WordRegistrationBatch in
            let sorted = words.sorted { $0.text < $1.text }
            return WordRegistrationBatch(
                id: key,
                source: sorted.first?.source ?? .parent,
                date: sorted.first?.registeredAt ?? Date(),
                words: sorted
            )
        }
        .sorted { $0.date > $1.date } // 新しい登録が上（直近のスパムをすぐ消せる）
    }

    var body: some View {
        NavigationStack {
            Group {
                if batches.isEmpty {
                    EmptyStateView(
                        language.text(japanese: "単語がありません", english: "No words"),
                        systemImage: "tray",
                        description: Text(language.text(japanese: "まだ単語が登録されていません。", english: "No words registered yet."))
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text(language.text(
                                japanese: "登録したタイミングごとにまとまっています。いらないまとまりは「まとめて削除」で消せます。",
                                english: "Grouped by when they were added. Remove unwanted groups with Delete."
                            ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(batches) { batch in
                                batchCard(batch)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(language.text(japanese: "登録のまとめ", english: "Registrations"))
            .navigationBarTitleDisplayMode(.inline)
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
            .alert(
                language.text(japanese: "このまとまりを削除しますか？", english: "Delete this group?"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { batch in
                Button(
                    language.text(japanese: "\(batch.words.count)個を削除", english: "Delete \(batch.words.count)"),
                    role: .destructive
                ) {
                    model.deleteWords(ids: Set(batch.words.map(\.id)))
                    pendingDelete = nil
                }
                Button(language.text(japanese: "やめる", english: "Cancel"), role: .cancel) {
                    pendingDelete = nil
                }
            } message: { batch in
                Text(batch.words.map(\.text).joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private func batchCard(_ batch: WordRegistrationBatch) -> some View {
        let isChild = batch.source == .child
        let tint = isChild ? Color(red: 0.49, green: 0.30, blue: 0.78) : ParentPalette.primary

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(isChild ? language.text(japanese: "こども", english: "Child") : language.text(japanese: "おとな", english: "Parent"))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(tint)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedLocalizedDateTime(batch.date, language: language))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Text(language.text(japanese: "\(batch.words.count)個", english: "\(batch.words.count) words"))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    pendingDelete = batch
                } label: {
                    Label(language.text(japanese: "まとめて削除", english: "Delete"), systemImage: "trash.fill")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .tint(ParentPalette.warning)
            }

            Text(batch.words.map(\.text).joined(separator: "、"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(ParentPalette.ink.opacity(0.85))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct ParentAllWordsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    private var steps: [WordStep] {
        Array(model.wordSteps.reversed())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParentBackground()

                ParentPanel(
                    title: language.text(japanese: "全単語", english: "All Words"),
                    systemImage: "tray.full.fill"
                ) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(steps) { step in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(step.title(language: language))
                                            .font(.headline.monospacedDigit().weight(.heavy))
                                            .foregroundStyle(ParentPalette.ink)
                                        Spacer()
                                        Text(language.text(japanese: "\(step.words.count) 単語", english: "\(step.words.count) words"))
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(ParentPalette.primary)
                                            .padding(.vertical, 5)
                                            .padding(.horizontal, 8)
                                            .background(ParentPalette.primarySoft)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }

                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(step.words) { word in
                                            ParentWordRow(word: word, language: language)
                                            Divider()
                                        }
                                    }
                                }
                                .padding(12)
                                .background(ParentPalette.surfaceTint)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
                    }
                    .font(.headline.weight(.bold))
                    .tapFeedback()
                }
            }
        }
    }
}

private struct ParentLegacyWordListPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var rawWords = ""
    @State private var showingWordCamera = false
    @State private var isScanningWordImage = false
    @StateObject private var scanProgress = ScanProgressModel()
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
                    isScanning: isScanningWordImage,
                    scanProgress: scanProgress.fraction
                )
            }

            ImportJapaneseOptionsView(language: language, draftText: $rawWords)

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
        .fullScreenCover(isPresented: $showingWordCamera) {
            WordCameraImportSheet(language: language) { image in
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
        scanProgress.start()
        importSucceeded = false
        importMessage = language.text(japanese: "宿題の文字を読み取っています。", english: "Scanning the homework text.")

        Task {
            do {
                let importedWords = try await WordListImageTextRecognizer(language: model.settings.language).recognizeWords(in: image) { fraction in
                    Task { @MainActor in scanProgress.report(fraction) }
                }
                await MainActor.run {
                    let addedCount = appendImportedWords(importedWords)
                    scanProgress.finish()
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
                            japanese: "\(addedCount)単語を下に追加しました。日本語と読み間違いを確認して保存してください。",
                            english: "Added \(addedCount) words below. Check Japanese hints and misreads before saving."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    scanProgress.reset()
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
        let importedLines = additions.map {
            formattedImportedWordLine(
                $0,
                knownWords: model.words,
                attachJapanese: model.settings.importAttachJapanese,
                useKanji: model.settings.importUseKanji
            )
        }
        rawWords = currentText.isEmpty
            ? importedLines.joined(separator: "\n")
            : currentText + "\n" + importedLines.joined(separator: "\n")

        return additions.count
    }
}

private struct WordImportStatusBanner: View {
    var message: String
    var isSuccess: Bool
    var isScanning: Bool
    var scanProgress: Double = 0

    var body: some View {
        Group {
            if isScanning {
                // 読み取り中はパーセンテージ付きの進捗バーを出す（古い端末でも進み具合がわかる）。
                ScanProgressBar(fraction: scanProgress, label: message, tint: ParentPalette.primary)
                    .foregroundStyle(ParentPalette.ink)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.headline.weight(.bold))

                    Text(message)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(isSuccess ? ParentPalette.success : ParentPalette.warning)
            }
        }
        .padding(10)
        .background(isScanning ? ParentPalette.surface : (isSuccess ? ParentPalette.successSoft : ParentPalette.warningSoft))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WordCameraImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?
    @State private var cropRect = WordImageCropRect.default
    var language: AppLanguage
    var onImage: (UIImage) -> Void

    var body: some View {
        Group {
            if let capturedImage {
                WordImageCropperView(
                    image: capturedImage,
                    language: language,
                    cropRect: $cropRect,
                    onScan: { croppedImage in
                        onImage(croppedImage)
                        dismiss()
                    },
                    onUseWholeImage: {
                        onImage(capturedImage.normalizedForCropping())
                        dismiss()
                    },
                    onRetake: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            cropRect = .default
                            self.capturedImage = nil
                        }
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            } else {
                WordCameraPicker(
                    onImage: { image in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            cropRect = .default
                            capturedImage = image
                        }
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            }
        }
    }
}

private struct WordImageCropperView: View {
    private let image: UIImage
    var language: AppLanguage
    @Binding var cropRect: WordImageCropRect
    var onScan: (UIImage) -> Void
    var onUseWholeImage: () -> Void
    var onRetake: () -> Void
    var onCancel: () -> Void
    // ドラッグはクロップ領域全体に付けた単一ジェスチャで処理し、開始位置で move/resize を判定する。
    // 要素ごとに .position＋.gesture を重ねるとヒットテストが不安定で「ドラッグできない」状態になりやすいため。
    // @GestureState は中断・終了時に自動で初期値へ戻るので、開始時のクロップ矩形の保持に使う。
    @GestureState private var gestureStartRect: WordImageCropRect?
    // ドラッグ中の操作モード（最初の onChanged で1回だけ決める）。
    @State private var activeDragMode: CropDragMode?

    init(
        image: UIImage,
        language: AppLanguage,
        cropRect: Binding<WordImageCropRect>,
        onScan: @escaping (UIImage) -> Void,
        onUseWholeImage: @escaping () -> Void,
        onRetake: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image.normalizedForCropping()
        self.language = language
        _cropRect = cropRect
        self.onScan = onScan
        self.onUseWholeImage = onUseWholeImage
        self.onRetake = onRetake
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.heavy))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tapFeedback()
                .accessibilityLabel(language.text(japanese: "閉じる", english: "Close"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(japanese: "読むところを合わせる", english: "Adjust Reading Area"))
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                    Text(language.text(japanese: "まんなかをドラッグで移動・四すみをドラッグで大きさ変更。", english: "Drag the middle to move · drag the corners to resize."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(ParentPalette.surface)

            GeometryReader { proxy in
                let container = CGRect(origin: .zero, size: proxy.size)
                let imageFrame = aspectFitRect(imageSize: image.size, in: container.insetBy(dx: 22, dy: 18))
                let cropFrame = cropRect.frame(in: imageFrame)

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.92)

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)

                    WordCropDimmingShape(imageFrame: imageFrame, cropFrame: cropFrame)
                        .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))

                    WordCropGridShape(cropFrame: cropFrame)
                        .stroke(.white.opacity(0.62), style: StrokeStyle(lineWidth: 1.4, dash: [7, 7]))

                    // 枠（見た目のみ）。操作は下の単一ジェスチャ層で受ける。
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ParentPalette.primary, lineWidth: 3)
                        .frame(width: cropFrame.width, height: cropFrame.height)
                        .position(x: cropFrame.midX, y: cropFrame.midY)
                        .allowsHitTesting(false)

                    // まんなか：ドラッグで移動できることを示すヒント。
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 24, weight: .heavy))
                        Text(language.text(japanese: "ドラッグでいどう", english: "Drag to move"))
                            .font(.caption2.weight(.heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(ParentPalette.primary.opacity(0.78), in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                    .allowsHitTesting(false)
                    .position(x: cropFrame.midX, y: cropFrame.midY)

                    // 四すみ：ドラッグで大きさ変更（斜め矢印で明示・見た目のみ）。
                    ForEach(WordCropHandle.allCases) { handle in
                        Circle()
                            .fill(.white)
                            .frame(width: 46, height: 46)
                            .overlay(
                                Circle()
                                    .stroke(ParentPalette.primary, lineWidth: 3)
                            )
                            .overlay(
                                Image(systemName: handle.resizeSymbol)
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(ParentPalette.primary)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 3)
                            .position(handle.position(in: cropFrame))
                            .allowsHitTesting(false)
                    }

                    // 操作層：画像全体を覆う単一ジェスチャ。開始位置で move/resize を判定する。
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(cropDragGesture(imageFrame: imageFrame, cropFrame: cropFrame))
                }
            }

            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Label(language.text(japanese: "撮り直す", english: "Retake"), systemImage: "camera.fill")
                        .frame(minWidth: 128)
                }
                .buttonStyle(.bordered)
                .tapFeedback()

                Button(action: onUseWholeImage) {
                    Label(language.text(japanese: "全体を使う", english: "Use Whole"), systemImage: "rectangle.expand.vertical")
                        .frame(minWidth: 128)
                }
                .buttonStyle(.bordered)
                .tapFeedback()

                Spacer()

                Button {
                    onScan(image.cropped(to: cropRect))
                } label: {
                    Label(language.text(japanese: "この範囲で読み取り", english: "Scan This Area"), systemImage: "doc.text.viewfinder")
                        .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .tapFeedback()
                .tint(ParentPalette.primary)
            }
            .font(.headline.weight(.bold))
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(ParentPalette.surface)
        }
        .background(Color.black.opacity(0.92))
    }

    /// クロップ領域全体に付ける単一ドラッグジェスチャ。
    /// 開始位置（四すみ近く＝リサイズ / 枠内＝移動）で操作を1回だけ決める。
    private func cropDragGesture(imageFrame: CGRect, cropFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureStartRect) { _, state, _ in
                if state == nil { state = cropRect }
            }
            .onChanged { value in
                let mode = activeDragMode ?? resolveDragMode(at: value.startLocation, cropFrame: cropFrame)
                if activeDragMode == nil { activeDragMode = mode }
                guard let mode else { return }

                let start = gestureStartRect ?? cropRect
                let deltaX = value.translation.width / max(imageFrame.width, 1)
                let deltaY = value.translation.height / max(imageFrame.height, 1)

                switch mode {
                case .move:
                    cropRect = start.moved(byX: deltaX, y: deltaY)
                case .resize(let handle):
                    cropRect = start.resized(handle: handle, deltaX: deltaX, deltaY: deltaY)
                }
            }
            .onEnded { _ in
                activeDragMode = nil
            }
    }

    /// ドラッグ開始位置から操作モードを決める。四すみの判定半径内ならリサイズ、枠内なら移動、外側は無視。
    private func resolveDragMode(at location: CGPoint, cropFrame: CGRect) -> CropDragMode? {
        let handleHitRadius: CGFloat = 44
        var nearest: (handle: WordCropHandle, distance: CGFloat)?
        for handle in WordCropHandle.allCases {
            let corner = handle.position(in: cropFrame)
            let distance = hypot(location.x - corner.x, location.y - corner.y)
            if distance <= handleHitRadius, nearest == nil || distance < nearest!.distance {
                nearest = (handle, distance)
            }
        }
        if let nearest {
            return .resize(nearest.handle)
        }
        if cropFrame.insetBy(dx: -8, dy: -8).contains(location) {
            return .move
        }
        return nil
    }
}

/// クロップ操作のモード。
private enum CropDragMode: Equatable {
    case move
    case resize(WordCropHandle)
}

private struct WordImageCropRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let `default` = WordImageCropRect(x: 0.08, y: 0.16, width: 0.84, height: 0.68)
    private static let minimumSize: CGFloat = 0.12

    func frame(in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + x * imageFrame.width,
            y: imageFrame.minY + y * imageFrame.height,
            width: width * imageFrame.width,
            height: height * imageFrame.height
        )
    }

    func moved(byX deltaX: CGFloat, y deltaY: CGFloat) -> WordImageCropRect {
        WordImageCropRect(
            x: min(max(x + deltaX, 0), 1 - width),
            y: min(max(y + deltaY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    func resized(handle: WordCropHandle, deltaX: CGFloat, deltaY: CGFloat) -> WordImageCropRect {
        var left = x
        var top = y
        var right = x + width
        var bottom = y + height

        switch handle {
        case .topLeft:
            left += deltaX
            top += deltaY
        case .topRight:
            right += deltaX
            top += deltaY
        case .bottomLeft:
            left += deltaX
            bottom += deltaY
        case .bottomRight:
            right += deltaX
            bottom += deltaY
        }

        left = min(max(left, 0), right - Self.minimumSize)
        top = min(max(top, 0), bottom - Self.minimumSize)
        right = max(min(right, 1), left + Self.minimumSize)
        bottom = max(min(bottom, 1), top + Self.minimumSize)

        return WordImageCropRect(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }
}

private enum WordCropHandle: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    /// その角の対角線に沿った両矢印（リサイズできることを示す）。
    var resizeSymbol: String {
        switch self {
        case .topLeft, .bottomRight:
            return "arrow.up.left.and.arrow.down.right"
        case .topRight, .bottomLeft:
            return "arrow.up.right.and.arrow.down.left"
        }
    }

    func position(in frame: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }
}

private struct WordCropDimmingShape: Shape {
    var imageFrame: CGRect
    var cropFrame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(imageFrame)
        path.addRoundedRect(in: cropFrame, cornerSize: CGSize(width: 8, height: 8))
        return path
    }
}

private struct WordCropGridShape: Shape {
    var cropFrame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let thirdWidth = cropFrame.width / 3
        let thirdHeight = cropFrame.height / 3

        for index in 1...2 {
            let x = cropFrame.minX + CGFloat(index) * thirdWidth
            path.move(to: CGPoint(x: x, y: cropFrame.minY))
            path.addLine(to: CGPoint(x: x, y: cropFrame.maxY))

            let y = cropFrame.minY + CGFloat(index) * thirdHeight
            path.move(to: CGPoint(x: cropFrame.minX, y: y))
            path.addLine(to: CGPoint(x: cropFrame.maxX, y: y))
        }

        return path
    }
}

private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
        return bounds
    }

    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale

    return CGRect(
        x: bounds.midX - width / 2,
        y: bounds.midY - height / 2,
        width: width,
        height: height
    )
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func cropped(to cropRect: WordImageCropRect) -> UIImage {
        let normalizedImage = normalizedForCropping()
        guard let cgImage = normalizedImage.cgImage else {
            return normalizedImage
        }

        let imageBounds = CGRect(origin: .zero, size: normalizedImage.size)
        let cropBounds = cropRect.frame(in: imageBounds)
        let pixelRect = CGRect(
            x: cropBounds.minX * normalizedImage.scale,
            y: cropBounds.minY * normalizedImage.scale,
            width: cropBounds.width * normalizedImage.scale,
            height: cropBounds.height * normalizedImage.scale
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isNull, pixelRect.width > 2, pixelRect.height > 2,
              let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            return normalizedImage
        }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }
}

private struct WordCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
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
        var onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct TestSettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SyncSession
    @State private var showingAccount = false
    @State private var showingOnboardingResetConfirm = false
    var language: AppLanguage

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "テスト設定", english: "Test Settings"),
            systemImage: "slider.horizontal.3"
        ) {
            SettingBlock(title: language.text(japanese: "アカウント・同期", english: "Account & Sync")) {
                Button {
                    showingAccount = true
                } label: {
                    HStack {
                        Image(systemName: session.activeHouseholdID != nil ? "checkmark.icloud.fill" : "icloud")
                        Text(session.activeHouseholdID != nil
                             ? language.text(japanese: "同期オン（タップで管理）", english: "Sync on (tap to manage)")
                             : language.text(japanese: "サインインして同期（任意）", english: "Sign in to sync (optional)"))
                    }
                }
                .sheet(isPresented: $showingAccount) {
                    AccountSyncView(session: session)
                }
            }

            SettingBlock(title: language.text(japanese: "初回設定", english: "First-time Setup")) {
                Button(role: .destructive) {
                    showingOnboardingResetConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(language.text(japanese: "初回設定をやり直す", english: "Redo first-time setup"))
                    }
                }
                .confirmationDialog(
                    language.text(japanese: "初回設定をやり直しますか？", english: "Redo first-time setup?"),
                    isPresented: $showingOnboardingResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button(language.text(japanese: "やり直す", english: "Redo"), role: .destructive) {
                        // 初回体験をもう一度。ホームの「タップで きせかえ」ヒントも復活させる。
                        model.hasShownHomeCharacterHint = false
                        // RootView がこれを見てオンボーディングを再表示する（この画面は自動的に閉じる）。
                        model.hasCompletedOnboarding = false
                    }
                    Button(language.text(japanese: "キャンセル", english: "Cancel"), role: .cancel) {}
                } message: {
                    Text(language.text(
                        japanese: "学年やキャラ・はいけいを選び直せます。登録した単語は消えません。",
                        english: "Re-pick grade, character and background. Your words are kept."
                    ))
                }
            }

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

            SettingBlock(title: language.text(japanese: "練習・テストの書く場所", english: "Practice/Test Writing Area")) {
                Picker(language.text(japanese: "大きさ", english: "Size"), selection: $model.settings.writingAreaSize) {
                    ForEach(WritingAreaSize.allCases) { size in
                        Text(size.label(language: language)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(language.text(japanese: "練習とテストの入力欄の大きさ", english: "Practice and test writing area size"))

                Text(language.text(
                    japanese: "書く欄の高さ・最大幅・お手本の文字サイズに反映されます。\(model.settings.writingAreaSize.description(language: language))",
                    english: "Changes the writing area height, max width, and model-word size. \(model.settings.writingAreaSize.description(language: language))"
                ))
                    .font(.caption.weight(.semibold))
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

                Text(language.text(japanese: "日本語訳・例文のヒント", english: "Meaning & example hint"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker(language.text(japanese: "ヒント表示", english: "Hint timing"), selection: $model.settings.practiceHintTiming) {
                    ForEach(PracticeHintTiming.allCases) { timing in
                        Text(timing.label(language: language)).tag(timing)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(language.text(japanese: "練習中のヒント表示タイミング", english: "Practice hint timing"))

                Text(model.settings.practiceHintTiming.description(language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(language.text(
                    japanese: "最後のラウンドでは、なぞるお手本の文字がゆっくり消えて、自分で書く練習になります。",
                    english: "On the final round the model letters fade out so the child writes from memory."
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingBlock(title: language.text(japanese: "OCR判定", english: "OCR Grading")) {
                SliderSetting(
                    title: language.text(japanese: "書き直し", english: "Rewrite"),
                    value: $model.settings.lowConfidence,
                    range: 0.10...0.60,
                    format: "%.2f"
                )
            }

            #if DEBUG
            SettingBlock(title: language.text(japanese: "デバッグ（開発用）", english: "Debug (Dev)")) {
                Toggle(isOn: $model.debugUnlockAll) {
                    Text(language.text(japanese: "有料コンテンツを全解放", english: "Unlock all paid content"))
                        .font(.subheadline.weight(.bold))
                }
                .tint(ParentPalette.primary)
                Toggle(isOn: $model.debugDisableDailyLimit) {
                    Text(language.text(japanese: "1日10語の上限を無効化", english: "Disable 10-words/day limit"))
                        .font(.subheadline.weight(.bold))
                }
                .tint(ParentPalette.primary)

                Divider()
                BenchExportRow()

                Text(language.text(
                    japanese: "開発ビルドのみ表示。課金ゲートと新規導入上限の動作確認、AI-OCRベンチ用の書き出し（手書きPNG＋親判定ラベル）。効果は DEBUG ビルドのみ。",
                    english: "Dev build only. Content gate / daily-limit testing, plus AI-OCR bench export (handwriting PNG + parent-decision labels)."
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif

            SettingBlock(title: language.text(japanese: "クレジット", english: "Credits")) {
                Text(language.text(
                    japanese: "例文: Tanaka Corpus（CC BY 2.0 FR）\n英和辞書: EJDict-hand（パブリックドメイン）",
                    english: "Examples: Tanaka Corpus (CC BY 2.0 FR)\nEN–JA dictionary: EJDict-hand (Public Domain)"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                EmptyStateView(
                    language.text(japanese: "まだ採点する記録がありません", english: "Nothing to grade yet"),
                    systemImage: "checkmark.seal",
                    description: Text(language.text(japanese: "練習やテストをするとここに表示されます。", english: "Practice and test sessions will appear here."))
                )
                .frame(minHeight: 240)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if filteredSessions.isEmpty {
                        EmptyStateView(
                            sessionFilter.emptyTitle(language: language),
                            systemImage: "checkmark.seal",
                            description: Text(sessionFilter.emptyMessage(language: language))
                        )
                        .frame(minHeight: 260)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 8) {
                                    ParentGradingFilterPicker(filter: $sessionFilter, language: language)

                                    ParentGradingSessionPicker(
                                        sessions: filteredSessions,
                                        selectedID: activeSession?.id,
                                        language: language,
                                        select: { selectedSessionID = $0 }
                                    )
                                }
                                .frame(width: 172)

                                Group {
                                    if let activeSession {
                                        ParentGradingSessionCard(
                                            session: activeSession,
                                            showsOnlyUngraded: sessionFilter == .unreviewed,
                                            language: language
                                        )
                                            .environmentObject(model)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: 700)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                ParentGradingFilterPicker(filter: $sessionFilter, language: language)

                                ParentGradingSessionPicker(
                                    sessions: filteredSessions,
                                    selectedID: activeSession?.id,
                                    language: language,
                                    select: { selectedSessionID = $0 }
                                )
                                .frame(maxHeight: 160)

                                Group {
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
                    scheduleSelectedSessionSync(filteredSessions.map(\.id))
                }
                .onValueChange(of: filteredSessions.map(\.id)) { ids in
                    scheduleSelectedSessionSync(ids)
                }
            }
        }
    }

    private func scheduleSelectedSessionSync(_ ids: [String]) {
        DispatchQueue.main.async {
            if selectedSessionID == nil || !(ids.contains(selectedSessionID ?? "")) {
                selectedSessionID = ids.first
            }
        }
    }
}

private enum ParentGradingSessionFilter: String, CaseIterable, Identifiable {
    case unreviewed
    case all

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "未採点", english: "Ungraded")
        case .all:
            return language.text(japanese: "すべて", english: "All")
        }
    }

    func apply(to sessions: [ParentGradingSession]) -> [ParentGradingSession] {
        switch self {
        case .unreviewed:
            return sessions.filter { $0.unreviewedCount > 0 }
        case .all:
            return sessions
        }
    }

    func emptyTitle(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "未採点はありません", english: "No ungraded sessions")
        case .all:
            return language.text(japanese: "記録がありません", english: "No sessions")
        }
    }

    func emptyMessage(language: AppLanguage) -> String {
        switch self {
        case .unreviewed:
            return language.text(japanese: "採点が必要なものだけ、ここに出ます。", english: "Only sessions that need grading appear here.")
        case .all:
            return language.text(japanese: "練習やテストをすると表示されます。", english: "Practice or test to show sessions here.")
        }
    }
}

private struct GradingWorkHeader: View {
    var activeSession: ParentGradingSession?
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
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(ParentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(unreviewedCount)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(language.text(japanese: "件", english: "left"))
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(unreviewedCount > 0 ? ParentPalette.warning : ParentPalette.success)
        }
        .padding(10)
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
            japanese: "\(title)。\(subtitle)。未採点 \(unreviewedCount) 件。",
            english: "\(title). \(subtitle). \(unreviewedCount) ungraded."
        ))
    }
}

private struct ParentGradingFilterPicker: View {
    @Binding var filter: ParentGradingSessionFilter
    var language: AppLanguage

    var body: some View {
        Picker("", selection: $filter) {
            ForEach(ParentGradingSessionFilter.allCases) { filter in
                Text(filter.title(language: language)).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(language.text(japanese: "採点記録の表示", english: "Grading session filter"))
    }
}

private enum ParentGradingSessionKind: Equatable {
    case test
    case practice
    case review

    func title(number: Int, language: AppLanguage) -> String {
        switch self {
        case .test:
            return language.text(japanese: "アプリのテスト \(number)回目", english: "App Test #\(number)")
        case .practice:
            return language.text(japanese: "れんしゅう \(number)回目", english: "Practice #\(number)")
        case .review:
            return language.text(japanese: "ふくしゅう \(number)回目", english: "Review #\(number)")
        }
    }

    /// パッと見で分かる短いラベル。
    func shortLabel(language: AppLanguage) -> String {
        switch self {
        case .test:
            return language.text(japanese: "テスト", english: "Test")
        case .practice:
            return language.text(japanese: "れんしゅう", english: "Practice")
        case .review:
            return language.text(japanese: "ふくしゅう", english: "Review")
        }
    }

    var systemImage: String {
        switch self {
        case .test:
            return "checklist.checked"
        case .practice:
            return "pencil.and.scribble"
        case .review:
            return "arrow.triangle.2.circlepath"
        }
    }

    /// 種別ごとに色を分けて見分けやすくする。
    var tint: Color {
        switch self {
        case .test:
            return Color(red: 0.20, green: 0.58, blue: 0.24)   // 緑＝テスト
        case .practice:
            return Color(red: 0.49, green: 0.30, blue: 0.78)   // 紫＝れんしゅう
        case .review:
            return Color(red: 0.90, green: 0.52, blue: 0.16)   // 橙＝ふくしゅう
        }
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
                    .font(.caption.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(formattedLocalizedDateTime(session.date, language: language))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
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
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? session.kind.tint : Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.04), radius: 7, x: 0, y: 4)
    }
}

private struct ParentGradingSessionCard: View {
    @EnvironmentObject private var model: AppModel
    var session: ParentGradingSession
    var showsOnlyUngraded: Bool
    var language: AppLanguage

    // 下書き：採点完了を押すまでモデルには保存しない。未指定はデフォルトOK扱い。
    @State private var decisionDrafts: [UUID: ParentReviewDecision] = [:]
    @State private var exampleDrafts: [UUID: Data] = [:]
    @State private var showsGuide = false

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

    private var visibleCount: Int {
        visibleAttempts.count + visibleSamples.count
    }

    private var fixCount: Int {
        visibleAttempts.filter { draftDecision(for: $0.id, current: $0.parentReviewDecision) == .needsPractice }.count
            + visibleSamples.filter { draftDecision(for: $0.id, current: $0.parentReviewDecision) == .needsPractice }.count
    }

    private func draftDecision(for id: UUID, current: ParentReviewDecision) -> ParentReviewDecision {
        decisionDrafts[id] ?? (current == .unreviewed ? .approved : current)
    }

    private var gradingColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 250), spacing: 10, alignment: .top),
            GridItem(.flexible(minimum: 250), spacing: 10, alignment: .top)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Label(session.kind.shortLabel(language: language), systemImage: session.kind.systemImage)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(session.kind.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title(language: language))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(ParentPalette.ink)
                        .lineLimit(1)
                    Text(formattedLocalizedDateTime(session.date, language: language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if visibleCount > 0 {
                    Button {
                        showsGuide = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ParentPalette.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text(japanese: "採点のヒント", english: "Grading tip"))
                    .popover(isPresented: $showsGuide) {
                        Text(language.text(
                            japanese: "ぜんぶOKがデフォルトです。直すものだけ「直そう」にして、最後に採点完了を押してください。",
                            english: "Everything defaults to OK. Mark only the ones to fix, then tap Done."
                        ))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(width: 280)
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Text(session.unreviewedCount > 0
                    ? language.text(japanese: "あと \(session.unreviewedCount)件", english: "\(session.unreviewedCount) left")
                    : language.text(japanese: "採点済み", english: "Done")
                )
                .font(.subheadline.monospacedDigit().weight(.heavy))
                .foregroundStyle(session.unreviewedCount > 0 ? ParentPalette.warning : ParentPalette.success)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background((session.unreviewedCount > 0 ? ParentPalette.warningSoft : ParentPalette.successSoft))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ScrollView {
                LazyVGrid(columns: gradingColumns, alignment: .leading, spacing: 10) {
                    ForEach(visibleAttempts) { attempt in
                        ParentAttemptGradingCard(
                            attempt: attempt,
                            language: language,
                            decision: draftDecision(for: attempt.id, current: attempt.parentReviewDecision),
                            exampleData: exampleDrafts[attempt.id] ?? attempt.parentExampleDrawingData,
                            setDecision: { decisionDrafts[attempt.id] = $0 },
                            setExample: { exampleDrafts[attempt.id] = $0 }
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }

                    ForEach(visibleSamples) { sample in
                        ParentPracticeGradingCard(
                            sample: sample,
                            language: language,
                            decision: draftDecision(for: sample.id, current: sample.parentReviewDecision),
                            exampleData: exampleDrafts[sample.id] ?? sample.parentExampleDrawingData,
                            setDecision: { decisionDrafts[sample.id] = $0 },
                            setExample: { exampleDrafts[sample.id] = $0 }
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.bottom, 4)
                .animation(.easeInOut(duration: 0.18), value: decisionDrafts)
                .animation(.easeInOut(duration: 0.22), value: visibleAttempts.map(\.id))
                .animation(.easeInOut(duration: 0.22), value: visibleSamples.map(\.id))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if visibleCount > 0 {
                Button {
                    completeGrading()
                } label: {
                    Label(
                        fixCount > 0
                            ? language.text(japanese: "採点完了（直す \(fixCount)こ・のこりはOK）", english: "Done — \(fixCount) to fix, rest OK")
                            : language.text(japanese: "ぜんぶOKで採点完了", english: "Mark all OK & Done"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.headline.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(ParentPalette.success)
                .tapFeedback(scale: 0.96, bounce: true)
            }
        }
        .padding(10)
        .background(ParentPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 5)
    }

    private func completeGrading() {
        let attemptsToCommit = visibleAttempts
        let samplesToCommit = visibleSamples

        withAnimation(.easeInOut(duration: 0.24)) {
            for attempt in attemptsToCommit {
                let decision = draftDecision(for: attempt.id, current: attempt.parentReviewDecision)
                let example = exampleDrafts[attempt.id] ?? attempt.parentExampleDrawingData
                model.updateAttemptParentReview(
                    attempt,
                    decision: decision,
                    exampleDrawingData: decision == .needsPractice ? example : nil
                )
            }
            for sample in samplesToCommit {
                let decision = draftDecision(for: sample.id, current: sample.parentReviewDecision)
                let example = exampleDrafts[sample.id] ?? sample.parentExampleDrawingData
                model.updatePracticeSampleParentReview(
                    sample,
                    decision: decision,
                    exampleDrawingData: decision == .needsPractice ? example : nil
                )
            }
        }
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
    var attempt: SpellingAttempt
    var language: AppLanguage
    var decision: ParentReviewDecision
    var exampleData: Data?
    var setDecision: (ParentReviewDecision) -> Void
    var setExample: (Data) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradingItemHeader(
                word: attempt.word,
                decision: decision,
                language: language,
                detail: attempt.recognizedText.isEmpty ? nil : "OCR: \(attempt.recognizedText)"
            )

            if let drawingData = attempt.drawingData {
                GradingDrawingPreview(drawingData: drawingData, mode: .test, storedCanvasSize: attempt.canvasSize)
            }

            if decision == .approved {
                ParentApprovedBanner(language: language)
            }

            ParentReviewButtons(
                decision: decision,
                pendingDecision: nil,
                language: language,
                approve: { setDecision(.approved) },
                needsPractice: { setDecision(.needsPractice) }
            )

            if decision == .needsPractice {
                ParentNeedsPracticeBanner(isTest: true, language: language)

                ParentExampleEditor(
                    word: attempt.word,
                    initialData: exampleData,
                    language: language,
                    affectsTestScore: true,
                    save: { data in setExample(data) }
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(gradingBackground(for: decision))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.18), value: decision)
    }
}

private struct ParentPracticeGradingCard: View {
    var sample: PracticeSample
    var language: AppLanguage
    var decision: ParentReviewDecision
    var exampleData: Data?
    var setDecision: (ParentReviewDecision) -> Void
    var setExample: (Data) -> Void

    private var modeLabel: String {
        if sample.mode == SessionMode.review.rawValue {
            return language.text(japanese: "ふくしゅう", english: "Review")
        }
        return language.text(japanese: "れんしゅう", english: "Practice")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradingItemHeader(
                word: sample.word,
                decision: decision,
                language: language,
                detail: modeLabel
            )

            GradingDrawingPreview(drawingData: sample.drawingData, mode: .practice, storedCanvasSize: sample.canvasSize)

            if decision == .approved {
                ParentApprovedBanner(language: language)
            }

            ParentReviewButtons(
                decision: decision,
                pendingDecision: nil,
                language: language,
                approve: { setDecision(.approved) },
                needsPractice: { setDecision(.needsPractice) }
            )

            if decision == .needsPractice {
                ParentNeedsPracticeBanner(isTest: false, language: language)

                ParentExampleEditor(
                    word: sample.word,
                    initialData: exampleData,
                    language: language,
                    affectsTestScore: false,
                    save: { data in setExample(data) }
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(gradingBackground(for: decision))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.18), value: decision)
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
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
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

    private var visualDecision: ParentReviewDecision {
        decision == .unreviewed ? .approved : decision
    }

    var body: some View {
        HStack(spacing: 0) {
            ParentReviewToggleButton(
                title: pendingDecision == .approved ? language.text(japanese: "保存中", english: "Saving") : "OK",
                systemImage: "checkmark.circle.fill",
                tint: ParentPalette.success,
                isSelected: visualDecision == .approved,
                isPending: pendingDecision == .approved,
                action: approve
            )

            ParentReviewToggleButton(
                title: pendingDecision == .needsPractice ? language.text(japanese: "保存中", english: "Saving") : language.text(japanese: "直そう", english: "Fix"),
                systemImage: "pencil.and.scribble",
                tint: ParentPalette.warning,
                isSelected: visualDecision == .needsPractice,
                isPending: pendingDecision == .needsPractice,
                action: needsPractice
            )
        }
        .padding(4)
        .background(Color.white.opacity(0.82))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .allowsHitTesting(pendingDecision == nil)
        .zIndex(1)
    }
}

private struct ParentReviewToggleButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var isSelected: Bool
    var isPending: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .foregroundStyle(isSelected ? .white : tint)
                .background(isSelected ? tint : Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .scaleEffect(isPending ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }
}

private struct GradingDrawingPreview: View {
    var drawingData: Data
    var mode: PracticeMode
    var storedCanvasSize: DrawingCanvasSize?
    var height: CGFloat = 172

    private var canvasSize: CGSize {
        let defaultSize = CGSize(width: 960, height: mode == .practice ? 300 : 330)
        if let storedSize = storedCanvasSize.flatMap({ size -> CGSize? in
            guard size.isUsable else {
                return nil
            }
            return size.cgSize
        }) {
            return storedSize
        }

        guard let drawing = try? PKDrawing(data: drawingData), !drawing.bounds.isNull, !drawing.bounds.isEmpty else {
            return defaultSize
        }

        return CGSize(
            width: max(defaultSize.width, drawing.bounds.maxX + 80),
            height: max(defaultSize.height, drawing.bounds.maxY + 20)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let fittedRect = fittedCanvasRect(in: proxy.size, canvasSize: canvasSize)

            ZStack {
                Color.white

                GradingCanvasSnapshotView(
                    drawingData: drawingData,
                    mode: mode,
                    canvasSize: canvasSize,
                    contentOffset: storedCanvasSize?.contentOffset ?? .zero
                )
                .frame(width: fittedRect.width, height: fittedRect.height)
                .position(x: fittedRect.midX, y: fittedRect.midY)
                .clipped()
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.22), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    private func fittedCanvasRect(in containerSize: CGSize, canvasSize: CGSize) -> CGRect {
        CanvasFitGeometry.fittedRect(in: containerSize, canvasSize: canvasSize)
    }
}

private struct GradingCanvasSnapshotView: UIViewRepresentable {
    var drawingData: Data
    var mode: PracticeMode
    var canvasSize: CGSize
    var contentOffset: CGPoint

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = WritingGuideSnapshotRenderer.image(
            drawingData: drawingData,
            mode: mode,
            canvasSize: canvasSize,
            contentOffset: contentOffset,
            scale: UIScreen.main.scale
        )
    }
}

enum WritingGuideSnapshotRenderer {
    static func image(
        drawingData: Data,
        mode: PracticeMode,
        canvasSize: CGSize,
        contentOffset: CGPoint = .zero,
        scale: CGFloat = 2
    ) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let layout = WritingGuideLayout(size: canvasSize)

        return renderer.image { context in
            let cgContext = context.cgContext
            UIColor.white.setFill()
            cgContext.fill(CGRect(origin: .zero, size: canvasSize))

            drawGuide(layout: layout, mode: mode, in: cgContext)

            guard let drawing = try? PKDrawing(data: drawingData) else {
                return
            }

            let drawingImage = drawing.image(
                from: CGRect(origin: contentOffset, size: canvasSize),
                scale: scale
            )
            drawingImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    private static func drawGuide(layout: WritingGuideLayout, mode: PracticeMode, in context: CGContext) {
        let lineStart = layout.lineStart(for: mode)
        let lineEnd = layout.lineEnd(for: mode)

        if mode == .practice {
            context.setFillColor(UIColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 0.52).cgColor)
            let bandPath = UIBezierPath(roundedRect: layout.practiceBandRect, cornerRadius: 24)
            context.addPath(bandPath.cgPath)
            context.fillPath()

            drawLine(from: lineStart, to: lineEnd, y: layout.top, color: UIColor.systemBlue.withAlphaComponent(0.06), width: 1, in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.mid, color: UIColor.systemBlue.withAlphaComponent(0.13), width: 1, dash: [8, 14], in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.baseline, color: UIColor.systemRed.withAlphaComponent(0.46), width: 2.4, in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.descender, color: UIColor.systemBlue.withAlphaComponent(0.07), width: 1, in: context)
        } else {
            let alpha: CGFloat = 0.38
            drawLine(from: lineStart, to: lineEnd, y: layout.top, color: UIColor.systemBlue.withAlphaComponent(alpha * 0.20), width: 1, in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.mid, color: UIColor.systemBlue.withAlphaComponent(alpha * 0.28), width: 1, dash: [10, 10], in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.baseline, color: UIColor.systemRed.withAlphaComponent(alpha * 0.90), width: 1.5, in: context)
            drawLine(from: lineStart, to: lineEnd, y: layout.descender, color: UIColor.systemBlue.withAlphaComponent(alpha * 0.20), width: 1, in: context)
        }
    }

    private static func drawLine(
        from start: CGFloat,
        to end: CGFloat,
        y: CGFloat,
        color: UIColor,
        width: CGFloat,
        dash: [CGFloat] = [],
        in context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        if !dash.isEmpty {
            context.setLineDash(phase: 0, lengths: dash)
        }
        context.move(to: CGPoint(x: start, y: y))
        context.addLine(to: CGPoint(x: end, y: y))
        context.strokePath()
        context.restoreGState()
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
                GeometryReader { proxy in
                    let layout = WritingGuideLayout(size: proxy.size)
                    Text(word)
                        .font(.system(size: layout.sampleTextFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.22))
                        .offset(y: layout.sampleTextYOffset)
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .padding(.horizontal, 80)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
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
                    let current = drawing
                    guard !current.strokes.isEmpty else {
                        return
                    }
                    let updated = PKDrawing(strokes: Array(current.strokes.dropLast()))
                    drawing = updated
                    capture.latestDrawing = updated
                } label: {
                    Label(language.text(japanese: "1つもどす", english: "Undo"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tapFeedback()
                .disabled(drawing.strokes.isEmpty)

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
                EmptyStateView(
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
                modeLabel: language.text(japanese: "アプリのテスト", english: "App Test"),
                detail: "\(attempt.decision.label(language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                systemImage: attempt.decision == .autoCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: attempt.decision == .autoCorrect ? ParentPalette.success : ParentPalette.warning,
                drawingData: attempt.drawingData,
                canvasSize: attempt.canvasSize
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
                drawingData: sample.drawingData,
                canvasSize: sample.canvasSize
            )
        }

        let schoolEntries = model.schoolTestResults.map { result in
            LearningHistoryEntry(
                id: "school-\(result.id.uuidString)",
                date: result.date,
                word: result.stepTitle.isEmpty ? language.text(japanese: "学校結果", english: "School Result") : result.stepTitle,
                modeLabel: language.text(japanese: "学校結果", english: "School Result"),
                detail: "\(result.score)/\(result.total)" + (result.missedWords.isEmpty ? "" : " ・ \(result.missedWords)"),
                systemImage: "graduationcap.fill",
                tint: ParentPalette.primary,
                drawingData: nil,
                canvasSize: nil
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
                    title: language.text(japanese: "学校結果", english: "School"),
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
                EmptyStateView(
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
    var canvasSize: DrawingCanvasSize?
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
                modeLabel: language.text(japanese: "アプリのテスト", english: "App Test"),
                detail: "\(attempt.decision.label(language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                systemImage: attempt.decision == .autoCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: attempt.decision == .autoCorrect ? ParentPalette.success : ParentPalette.warning,
                drawingData: drawingData,
                canvasSize: attempt.canvasSize
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
                drawingData: sample.drawingData,
                canvasSize: sample.canvasSize
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
                EmptyStateView(
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
                    .frame(maxWidth: .infinity, alignment: .top)
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
                    Text("\(entry.modeLabel) ・ \(formattedLocalizedDateTime(entry.date, language: language))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let drawingData = entry.drawingData {
                DrawingPreview(drawingData: drawingData, canvasSize: entry.canvasSize)
                    .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("\(entry.modeLabel) ・ \(formattedLocalizedDateTime(entry.date, language: language))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let drawingData = entry.drawingData {
                DrawingPreview(drawingData: drawingData, canvasSize: entry.canvasSize)
                    .frame(maxWidth: .infinity)
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
                        japanese: "最新: \(formattedLocalizedTime(attempt.date, language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                        english: "Latest: \(formattedLocalizedTime(attempt.date, language: language)) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)"
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
                DrawingPreview(drawingData: drawingData, canvasSize: attempt.canvasSize)
                    .frame(maxWidth: .infinity)
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
                    Text("\(modeLabel) ・ \(formattedLocalizedTime(sample.date, language: language))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "text.bubble.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ParentPalette.primary)
            }

            DrawingPreview(drawingData: sample.drawingData, canvasSize: sample.canvasSize)
                .frame(maxWidth: .infinity)
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
    var canvasSize: DrawingCanvasSize?
    var horizontalPadding: CGFloat = 80
    var topPadding: CGFloat = 90
    var bottomPadding: CGFloat = 150

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return imageView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 260, height: proposal.height ?? 150)
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if let drawing = try? PKDrawing(data: drawingData) {
            imageView.image = drawing.previewImage(
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                bottomPadding: bottomPadding,
                canvasSize: canvasSize
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
        .environmentObject(SyncSession())
}

#if DEBUG
// MARK: - AI-OCRベンチ用ローカル書き出し（暫定A / docs/HANDOFF-ai-ocr-2026-06-27.md）
// 端末ローカルの practiceSamples / attempts を、手書きPNG＋親判定ラベルのCSVにして zip 共有する。
// バックエンド不要で「実使用＋実親ラベル」の初回計測データを得る最速ルート。DEBUG ビルドのみ。

private struct BenchExportRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportURL: URL?
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                do {
                    exportURL = try BenchExport.makeZip(samples: model.practiceSamples, attempts: model.attempts)
                    let n = model.practiceSamples.count + model.attempts.count
                    status = "書き出し: 候補\(n)件（手書きありのみPNG化）"
                } catch {
                    exportURL = nil
                    status = "失敗: \(error.localizedDescription)"
                }
            } label: {
                Label("ベンチ用に書き出す（手書きPNG＋ラベル）", systemImage: "square.and.arrow.down.on.square")
                    .font(.subheadline.weight(.bold))
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("zip を共有 / 保存", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                }
            }
            if let status {
                Text(status).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum BenchExport {
    /// 手書きありの sample/attempt を PNG 化し、labels.csv とともに 1 つの zip にまとめて返す。
    static func makeZip(samples: [PracticeSample], attempts: [SpellingAttempt]) throws -> URL {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = fm.temporaryDirectory.appendingPathComponent("ocr-bench-export-\(stamp)", isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 列: filename, target(出題語), verdict(親判定), recognized_text(ローカルOCR), mode, source, date
        var rows = ["filename,target,verdict,recognized_text,mode,source,date"]
        var index = 0

        func emit(word: String, recognized: String, drawingData: Data?, canvasSize: DrawingCanvasSize?,
                  mode: String, source: String, decision: ParentReviewDecision, date: Date) {
            guard let drawingData,
                  let drawing = try? PKDrawing(data: drawingData),
                  let image = drawing.previewImage(canvasSize: canvasSize),
                  let png = whiteBacked(image).pngData() else { return }
            // 書き込み成功時のみ採番＆CSV行追加（labels.csv が欠損ファイルを指さないように）。
            let name = String(format: "%04d.png", index + 1)
            do {
                try png.write(to: dir.appendingPathComponent(name))
            } catch {
                return
            }
            index += 1
            rows.append([
                name, csv(word), verdict(decision), csv(recognized), csv(mode), source, iso(date)
            ].joined(separator: ","))
        }

        for s in samples {
            emit(word: s.word, recognized: "", drawingData: s.drawingData, canvasSize: s.canvasSize,
                 mode: s.mode, source: "practice", decision: s.parentReviewDecision, date: s.date)
        }
        for a in attempts {
            emit(word: a.word, recognized: a.recognizedText, drawingData: a.drawingData, canvasSize: a.canvasSize,
                 mode: "test", source: "test", decision: a.parentReviewDecision, date: a.date)
        }

        let csvData = Data((rows.joined(separator: "\n") + "\n").utf8)
        try csvData.write(to: dir.appendingPathComponent("labels.csv"))
        return try zipDirectory(dir)
    }

    private static func verdict(_ d: ParentReviewDecision) -> String {
        switch d {
        case .approved: return "correct"
        case .needsPractice: return "incorrect"
        case .unreviewed: return "unreviewed"
        }
    }

    private static func whiteBacked(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }

    private static func csv(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// ディレクトリを zip 化（依存なし。NSFileCoordinator の forUploading で zip コピーを得る）。
    private static func zipDirectory(_ dir: URL) throws -> URL {
        var zipURL: URL?
        var thrown: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &coordError) { tmp in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: tmp, to: dest)
                zipURL = dest
            } catch {
                thrown = error
            }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard let zipURL else {
            throw NSError(domain: "BenchExport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "zip 生成に失敗"])
        }
        return zipURL
    }
}
#endif
