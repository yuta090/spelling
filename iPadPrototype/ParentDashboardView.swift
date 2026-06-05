import PencilKit
import SwiftUI
import UIKit

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
                    ParentStatusStrip(language: language)

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
                .foregroundStyle(Color(red: 0.16, green: 0.48, blue: 0.18))

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
            .foregroundStyle(Color(red: 0.16, green: 0.48, blue: 0.18))
            .background(.white.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
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
            return language.text(japanese: "記録", english: "Records")
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
            return language.text(japanese: "成績と履歴", english: "Results & history")
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
        switch self {
        case .grading:
            return Color(red: 0.13, green: 0.40, blue: 0.78)
        case .words:
            return Color(red: 0.17, green: 0.56, blue: 0.24)
        case .records:
            return Color(red: 0.56, green: 0.34, blue: 0.78)
        case .settings:
            return Color(red: 0.42, green: 0.48, blue: 0.56)
        }
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
                    .background(isSelected ? .white.opacity(0.22) : section.tint.opacity(0.12))
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
            .foregroundStyle(isSelected ? .white : section.tint)
            .frame(width: 172, height: 64, alignment: .leading)
            .padding(.horizontal, 12)
            .background(isSelected ? section.tint : .white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? section.tint : section.tint.opacity(0.22), lineWidth: isSelected ? 0 : 1)
            )
            .shadow(color: isSelected ? section.tint.opacity(0.20) : .black.opacity(0.05), radius: isSelected ? 12 : 7, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ParentStatusStrip: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    private var unreviewedCount: Int {
        model.attempts.filter { $0.parentReviewDecision == .unreviewed }.count
            + model.practiceSamples.filter { $0.parentReviewDecision == .unreviewed }.count
    }

    var body: some View {
        let progress = model.todayStepProgress
        let stepTitle = model.selectedWordStep?.title(language: language)
            ?? language.text(japanese: "ステップなし", english: "No step")

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statusTiles(stepTitle: stepTitle, progress: progress)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    statusTiles(stepTitle: stepTitle, progress: progress)
                }
                .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private func statusTiles(stepTitle: String, progress: TodayStepProgress) -> some View {
        ParentStatusTile(
            title: language.text(japanese: "今の単語集", english: "Current Step"),
            value: stepTitle,
            systemImage: "rectangle.stack.fill",
            tint: Color(red: 0.16, green: 0.42, blue: 0.78)
        )
        ParentStatusTile(
            title: language.text(japanese: "単語", english: "Words"),
            value: "\(model.activeWords.count)",
            systemImage: "textformat.abc",
            tint: Color(red: 0.17, green: 0.56, blue: 0.24)
        )
        ParentStatusTile(
            title: language.text(japanese: "未採点", english: "Ungraded"),
            value: "\(unreviewedCount)",
            systemImage: "exclamationmark.circle.fill",
            tint: unreviewedCount > 0 ? Color(red: 0.90, green: 0.46, blue: 0.13) : Color(red: 0.30, green: 0.60, blue: 0.28)
        )
        ParentStatusTile(
            title: language.text(japanese: "今日のクリア", english: "Today"),
            value: progress.totalWords == 0 ? "0/0" : "\(progress.clearedCount)/\(progress.totalWords)",
            systemImage: "checkmark.circle.fill",
            tint: Color(red: 0.56, green: 0.34, blue: 0.78)
        )
    }
}

private struct ParentStatusTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.monospacedDigit().weight(.heavy))
                    .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 170, height: 54)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private enum ParentRecordSection: String, CaseIterable, Identifiable {
    case results
    case handwriting
    case history

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .results:
            return language.text(japanese: "成績", english: "Results")
        case .handwriting:
            return language.text(japanese: "手書き", english: "Writing")
        case .history:
            return language.text(japanese: "履歴", english: "History")
        }
    }
}

private struct ParentRecordsWorkspace: View {
    @State private var selectedRecordSection: ParentRecordSection = .results
    var language: AppLanguage

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedRecordSection) {
                ForEach(ParentRecordSection.allCases) { section in
                    Text(section.title(language: language)).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(language.text(japanese: "記録の表示切り替え", english: "Record view"))

            selectedPanel
        }
    }

    @ViewBuilder
    private var selectedPanel: some View {
        switch selectedRecordSection {
        case .results:
            AnswerReviewPanel(language: language)
        case .handwriting:
            HandwritingListPanel(language: language)
        case .history:
            LearningHistoryPanel(language: language)
        }
    }
}

private struct ParentPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color = Color(red: 0.19, green: 0.54, blue: 0.22)
    var content: Content

    init(title: String, systemImage: String, tint: Color = Color(red: 0.19, green: 0.54, blue: 0.22), @ViewBuilder content: () -> Content) {
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
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.77, green: 0.86, blue: 0.72), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 6)
    }
}

private struct ParentWordStepPanel: View {
    @EnvironmentObject private var model: AppModel
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
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(orderedSteps) { step in
                            ParentWordStepCard(
                                step: step,
                                language: language,
                                isSelected: step.id == model.selectedWordStepID
                            ) {
                                model.selectedWordStepID = step.id
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
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
                            .foregroundStyle(isSelected ? Color(red: 0.10, green: 0.30, blue: 0.70) : Color(red: 0.12, green: 0.22, blue: 0.38))
                        Text("\(formattedStepDate(step.registeredDate, language: language)) ・ \(step.words.count) \(language.text(japanese: "単語", english: "words"))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Label(language.text(japanese: "選択中", english: "Selected"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.14, green: 0.42, blue: 0.78))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color(red: 0.90, green: 0.96, blue: 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text(wordSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.34))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(isSelected ? Color(red: 0.92, green: 0.97, blue: 1.0) : Color(red: 0.98, green: 0.99, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(red: 0.42, green: 0.63, blue: 0.92) : Color(red: 0.77, green: 0.86, blue: 0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                .background(Color(red: 0.96, green: 0.99, blue: 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
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
                .tint(Color(red: 0.14, green: 0.42, blue: 0.78))
                .disabled(isScanningWordImage)

                Button {
                    rawWords = wordListEditorText(model.words)
                    importMessage = nil
                } label: {
                    Label(language.text(japanese: "読み直す", english: "Reload"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    model.replaceWords(from: rawWords)
                } label: {
                    Label(language.text(japanese: "単語を保存", english: "Save Words"), systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
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
                                            baseColor: Color(red: 0.18, green: 0.38, blue: 0.72),
                                            rubyColor: Color(red: 0.46, green: 0.32, blue: 0.64),
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
        .foregroundStyle(isSuccess ? Color(red: 0.15, green: 0.48, blue: 0.22) : Color(red: 0.65, green: 0.34, blue: 0.05))
        .padding(10)
        .background(isSuccess ? Color(red: 0.90, green: 0.97, blue: 0.88) : Color(red: 1.0, green: 0.95, blue: 0.84))
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
        .background(Color(red: 0.97, green: 0.99, blue: 0.96))
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
            title: language.text(japanese: "採点モード", english: "Grading Mode"),
            systemImage: "checkmark.seal.fill",
            tint: Color(red: 0.12, green: 0.36, blue: 0.72)
        ) {
            HStack {
                SettingValueRow(
                    title: sessionFilter.title(language: language),
                    value: "\(filteredSessions.count)/\(sessions.count)"
                )

                Spacer()
            }

            Text(language.text(
                japanese: "最初は未採点だけ表示します。過去分は「今日」「すべて」で見られます。",
                english: "Only ungraded sessions show first. Use Today or All for older sessions."
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if sessions.isEmpty {
                ContentUnavailableView(
                    language.text(japanese: "まだ採点する記録がありません", english: "Nothing to grade yet"),
                    systemImage: "checkmark.seal",
                    description: Text(language.text(japanese: "練習やテストをするとここに表示されます。", english: "Practice and test sessions will appear here."))
                )
                .frame(minHeight: 240)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $sessionFilter) {
                        ForEach(ParentGradingSessionFilter.allCases) { filter in
                            Text(filter.title(language: language)).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel(language.text(japanese: "採点記録の表示", english: "Grading session filter"))

                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            sessionFilter.emptyTitle(language: language),
                            systemImage: "checkmark.seal",
                            description: Text(sessionFilter.emptyMessage(language: language))
                        )
                        .frame(minHeight: 260)
                    } else {
                        ParentGradingSessionPicker(
                            sessions: filteredSessions,
                            selectedID: activeSession?.id,
                            language: language,
                            select: { selectedSessionID = $0 }
                        )

                        ScrollView {
                            if let activeSession {
                                ParentGradingSessionCard(session: activeSession, language: language)
                                    .environmentObject(model)
                            }
                        }
                        .frame(maxHeight: 760)
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
        switch self {
        case .test:
            return Color(red: 0.15, green: 0.38, blue: 0.76)
        case .practice:
            return Color(red: 0.48, green: 0.28, blue: 0.72)
        case .review:
            return Color(red: 0.11, green: 0.48, blue: 0.34)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
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
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityAddTraits(session.id == selectedID ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 88)
    }
}

private struct ParentGradingSessionChip: View {
    var session: ParentGradingSession
    var isSelected: Bool
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: session.kind.systemImage)
                    .font(.subheadline.weight(.bold))
                Text(session.title(language: language))
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
            }

            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)

            HStack(spacing: 6) {
                Text("\(session.itemCount)\(language.text(japanese: "件", english: ""))")
                Text("OK \(session.approvedCount)")
                Text("\(language.text(japanese: "直す", english: "Fix")) \(session.needsPracticeCount)")
            }
            .font(.caption2.monospacedDigit().weight(.bold))
        }
        .foregroundStyle(isSelected ? .white : session.kind.tint)
        .frame(width: 190, alignment: .leading)
        .padding(10)
        .background(isSelected ? session.kind.tint : session.kind.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(session.kind.tint.opacity(isSelected ? 0 : 0.30), lineWidth: 1)
        )
    }
}

private struct ParentGradingSessionCard: View {
    var session: ParentGradingSession
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: session.kind.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(session.kind.tint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title(language: language))
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    GradingCountPill(
                        title: language.text(japanese: "件", english: "Items"),
                        value: session.itemCount,
                        tint: Color(red: 0.16, green: 0.42, blue: 0.78)
                    )
                    GradingCountPill(
                        title: "OK",
                        value: session.approvedCount,
                        tint: Color(red: 0.20, green: 0.62, blue: 0.24)
                    )
                    GradingCountPill(
                        title: language.text(japanese: "直す", english: "Fix"),
                        value: session.needsPracticeCount,
                        tint: Color(red: 0.90, green: 0.45, blue: 0.12)
                    )
                }
            }

            VStack(spacing: 12) {
                ForEach(session.attempts) { attempt in
                    ParentAttemptGradingCard(attempt: attempt, language: language)
                }

                ForEach(session.samples) { sample in
                    ParentPracticeGradingCard(sample: sample, language: language)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.98, green: 0.99, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1)
        )
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
                detail: "\(language.text(japanese: "テスト", english: "Test")) ・ OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)",
                decision: attempt.parentReviewDecision,
                language: language
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
                language: language,
                approve: {
                    model.updateAttemptParentReview(attempt, decision: .approved)
                },
                needsPractice: {
                    model.updateAttemptParentReview(attempt, decision: .needsPractice)
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gradingBorder(for: attempt.parentReviewDecision), lineWidth: isApproved ? 2 : 1)
        )
    }
}

private struct ParentPracticeGradingCard: View {
    @EnvironmentObject private var model: AppModel
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
                detail: "\(modeLabel) ・ \(sample.date.formatted(date: .omitted, time: .shortened))",
                decision: sample.parentReviewDecision,
                language: language
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
                language: language,
                approve: {
                    model.updatePracticeSampleParentReview(sample, decision: .approved)
                },
                needsPractice: {
                    model.updatePracticeSampleParentReview(sample, decision: .needsPractice)
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gradingBorder(for: sample.parentReviewDecision), lineWidth: isApproved ? 2 : 1)
        )
    }
}

private struct GradingItemHeader: View {
    var word: String
    var detail: String
    var decision: ParentReviewDecision
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.10, green: 0.27, blue: 0.62))
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(decision.label(language: language))
                .font(.caption.weight(.heavy))
                .foregroundStyle(reviewTint(for: decision))
                .padding(.vertical, 6)
                .padding(.horizontal, 9)
                .background(reviewTint(for: decision).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ParentReviewButtons: View {
    var decision: ParentReviewDecision
    var language: AppLanguage
    var approve: () -> Void
    var needsPractice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: approve) {
                Label("OK", systemImage: decision == .approved ? "checkmark.seal.fill" : "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.20, green: 0.62, blue: 0.24))

            Button(action: needsPractice) {
                Label(language.text(japanese: "直そう", english: "Needs Fix"), systemImage: "pencil.and.scribble")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 0.90, green: 0.45, blue: 0.12))
        }
    }
}

private struct ParentNeedsPracticeBanner: View {
    var isTest: Bool
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.90, green: 0.45, blue: 0.12))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "直そうとして保存されています", english: "Saved as Needs Fix"))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color(red: 0.58, green: 0.27, blue: 0.05))
                Text(isTest
                    ? language.text(japanese: "このテスト回答は不正解扱いになります。お手本を書くと、あとで子供に見せられます。", english: "This test answer counts as incorrect. Add a model so the child can review it later.")
                    : language.text(japanese: "この練習記録は直すポイントとして残ります。お手本を書くと、あとで子供に見せられます。", english: "This practice entry is saved as a fix point. Add a model so the child can review it later.")
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(red: 1.0, green: 0.93, blue: 0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.95, green: 0.62, blue: 0.26), lineWidth: 1)
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
        .foregroundStyle(Color(red: 0.52, green: 0.30, blue: 0.02))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.88, blue: 0.28),
                    Color(red: 0.74, green: 0.94, blue: 0.38)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
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
                    .foregroundStyle(Color(red: 0.66, green: 0.30, blue: 0.04))

                Spacer()

                if hasSavedModel {
                    Label(language.text(japanese: "保存済み", english: "Saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color(red: 0.20, green: 0.58, blue: 0.24))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Color(red: 0.89, green: 0.97, blue: 0.87))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Text(language.text(
                japanese: affectsTestScore
                    ? "\(word) の見本を保存すると、この回答は「直そう」のまま残り、不正解として集計されます。"
                    : "\(word) の見本を保存すると、この練習は「直そう」のまま残ります。",
                english: affectsTestScore
                    ? "Saving a model keeps this answer marked Needs Fix and counted as incorrect."
                    : "Saving a model keeps this practice entry marked Needs Fix."
            ))
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
                    .stroke(Color(red: 0.95, green: 0.75, blue: 0.32), lineWidth: 1)
            )

            HStack {
                Button {
                    drawing = PKDrawing()
                    capture.latestDrawing = PKDrawing()
                } label: {
                    Label(language.text(japanese: "消す", english: "Clear"), systemImage: "eraser.fill")
                }
                .buttonStyle(.bordered)

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
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(12)
        .background(Color(red: 1.0, green: 0.97, blue: 0.88))
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
        return Color.gray
    case .approved:
        return Color(red: 0.20, green: 0.62, blue: 0.24)
    case .needsPractice:
        return Color(red: 0.90, green: 0.45, blue: 0.12)
    }
}

private func gradingBackground(for decision: ParentReviewDecision) -> Color {
    switch decision {
    case .unreviewed:
        return Color.white.opacity(0.92)
    case .approved:
        return Color(red: 1.0, green: 0.98, blue: 0.80)
    case .needsPractice:
        return Color(red: 1.0, green: 0.96, blue: 0.88)
    }
}

private func gradingBorder(for decision: ParentReviewDecision) -> Color {
    switch decision {
    case .unreviewed:
        return Color(red: 0.72, green: 0.82, blue: 0.96)
    case .approved:
        return Color(red: 0.95, green: 0.68, blue: 0.12)
    case .needsPractice:
        return Color(red: 0.95, green: 0.62, blue: 0.26)
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
                    .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.78))

                Spacer()

                if !model.practiceSamples.isEmpty {
                    Button(role: .destructive) {
                        model.resetPracticeSamples()
                    } label: {
                        Label(language.text(japanese: "記録を消す", english: "Clear"), systemImage: "trash")
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
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
                .background(Color(red: 0.97, green: 0.99, blue: 0.96))
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
                tint: attempt.decision == .autoCorrect ? Color.green : Color.orange,
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
                tint: Color(red: 0.16, green: 0.42, blue: 0.78),
                drawingData: sample.drawingData
            )
        }

        return (testEntries + practiceEntries).sorted { $0.date > $1.date }
    }

    var body: some View {
        ParentPanel(
            title: language.text(japanese: "学習履歴", english: "Learning History"),
            systemImage: "clock.arrow.circlepath"
        ) {
            HStack(spacing: 12) {
                SettingValueRow(
                    title: language.text(japanese: "テスト回答", english: "Test answers"),
                    value: "\(model.attempts.count)"
                )
                SettingValueRow(
                    title: language.text(japanese: "手書き記録", english: "Handwriting"),
                    value: "\(model.practiceSamples.count)"
                )
            }

            Text(language.text(
                japanese: "いつ、どのモードで、どの単語を書いたかを保存しています。",
                english: "Saved records show when each word was practiced or tested."
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
                tint: attempt.decision == .autoCorrect ? Color.green : Color.orange,
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
                tint: Color(red: 0.16, green: 0.42, blue: 0.78),
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
                        .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
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
        .background(Color(red: 0.98, green: 0.99, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.77, green: 0.86, blue: 0.72), lineWidth: 1)
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
        .background(Color(red: 0.98, green: 0.99, blue: 0.97))
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
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(Color.orange)
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

                Button {
                    model.updateAttemptParentReview(attempt, decision: .needsPractice)
                } label: {
                    Label(language.text(japanese: "もう一度", english: "Try Again"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.bold))
        }
        .padding(10)
        .background(Color(red: 0.98, green: 0.99, blue: 0.97))
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
                    .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.78))
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
        .background(Color(red: 0.97, green: 0.99, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(Color(red: 0.36, green: 0.70, blue: 0.22), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(progress, 1)) * 100).rounded()))%")
                .font(.title3.monospacedDigit().weight(.heavy))
                .foregroundStyle(Color(red: 0.26, green: 0.58, blue: 0.18))
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
                Color(red: 0.94, green: 0.99, blue: 0.93),
                Color(red: 1.0, green: 0.99, blue: 0.96)
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
