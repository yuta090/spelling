import PencilKit
import SwiftUI

struct SpellingSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()
    @StateObject private var drawingCapture = DrawingCapture()

    let mode: SessionMode
    @State private var sessionWords: [SpellingWord]

    @State private var index = 0
    @State private var drawing = PKDrawing()
    @State private var decision: GradeDecision?
    @State private var candidates: [OCRCandidate] = []
    @State private var isChecking = false
    @State private var remainingSeconds = 30
    @State private var replayCount = 0
    @State private var timer: Timer?
    @State private var canvasResetID = UUID()
    @State private var showingSparkles = false
    @State private var sparkleSeed = 0
    @State private var isAdvancing = false
    @State private var sessionPracticeSamples: [PracticeSample] = []
    @State private var showingPracticeReview = false
    @State private var sessionAttempts: [SpellingAttempt] = []
    @State private var showingTestResults = false
    @State private var practiceRepeatIndex = 0
    @State private var sessionID = UUID()

    init(mode: SessionMode, words: [SpellingWord]) {
        self.mode = mode
        _sessionWords = State(initialValue: mode == .test ? words.shuffled() : words)
    }

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    private var capturesPracticeSamples: Bool {
        mode == .practice || mode == .review
    }

    private var currentWord: SpellingWord {
        guard !sessionWords.isEmpty else {
            return SpellingWord(text: "")
        }
        return sessionWords[min(index, max(sessionWords.count - 1, 0))]
    }

    private var practiceRepetitionCount: Int {
        switch mode {
        case .practice:
            return max(model.settings.practiceRepetitions, 3)
        case .review:
            return max(model.settings.practiceRepetitions, 1)
        case .test:
            return 1
        }
    }

    private var isLastPracticeRepeat: Bool {
        practiceRepeatIndex >= practiceRepetitionCount - 1
    }

    private var guideLabels: [String] {
        if language == .japanese {
            return ["トップライン", "ミッドライン", "ベースライン", "ディセンダーライン"]
        }
        return ["Top line", "Mid line", "Base line", "Descender"]
    }

    private var taskBannerTitle: String {
        switch mode {
        case .practice:
            return language.text(japanese: "れんしゅう中", english: "Practice Time")
        case .test:
            return language.text(japanese: "テスト中", english: "Test Time")
        case .review:
            return language.text(japanese: "ふくしゅう中", english: "Review Time")
        }
    }

    private var taskBannerMessage: String {
        switch mode {
        case .practice:
            return language.text(japanese: "お手本を見ながら、この単語を\(practiceRepetitionCount)かい書こう。", english: "Look at the word and write it \(practiceRepetitionCount) times.")
        case .test:
            return model.settings.testPromptMode.description(language: language) + " " + language.text(japanese: "書けたらこたえるを押してね。", english: "Write it, then submit.")
        case .review:
            return language.text(japanese: "のこった単語をもう一度書いて、できるようにしよう。", english: "Write the remaining words again.")
        }
    }

    private var taskBannerIcon: String {
        switch mode {
        case .practice:
            return "pencil.and.scribble"
        case .test:
            return "ear.and.waveform"
        case .review:
            return "book.fill"
        }
    }

    private var taskBannerTint: Color {
        switch mode {
        case .practice:
            return Color(red: 0.49, green: 0.30, blue: 0.78)
        case .test:
            return Color(red: 0.14, green: 0.38, blue: 0.76)
        case .review:
            return Color(red: 0.12, green: 0.50, blue: 0.34)
        }
    }

    private var currentPromptText: String {
        currentWord.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowSpeakerButton: Bool {
        if mode != .test {
            return true
        }
        return model.settings.testPromptMode.includesAudio || currentPromptText.isEmpty
    }

    private var shouldShowTextPrompt: Bool {
        mode == .test && model.settings.testPromptMode.showsPromptText
    }

    private var testPromptTitle: String {
        switch model.settings.testPromptMode {
        case .audioOnly:
            return language.text(japanese: "音をきいて書こう", english: "Listen and Write")
        case .textOnly:
            return language.text(japanese: "もんだいを読んで書こう", english: "Read and Write")
        case .audioAndText:
            return language.text(japanese: "音とヒントで書こう", english: "Listen, Read, Write")
        }
    }

    private var testPromptBody: String {
        guard shouldShowTextPrompt else {
            return language.text(japanese: "発音ボタンをおしてね。", english: "Tap the sound button.")
        }

        if currentPromptText.isEmpty {
            return language.text(japanese: "ヒントがまだありません。音を聞いて書こう。", english: "No text hint yet. Listen to the word.")
        }

        return currentPromptText
    }

    var body: some View {
        ZStack {
            SessionBackground()

            if showingPracticeReview {
                PracticeSessionReviewView(
                    samples: sessionPracticeSamples,
                    language: language,
                    onDone: {
                        dismiss()
                    }
                )
                .transition(.opacity)
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 28)
            } else if showingTestResults {
                TestSessionResultsView(
                    attempts: sessionAttempts,
                    language: language,
                    onDone: {
                        dismiss()
                    }
                )
                .transition(.opacity)
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 28)
            } else {
                VStack(spacing: 18) {
                    header

                    ChildTaskBanner(
                        title: taskBannerTitle,
                        message: taskBannerMessage,
                        systemImage: taskBannerIcon,
                        tint: taskBannerTint,
                        compact: true
                    )
                    .frame(maxWidth: 760)

                    wordHeader

                    if capturesPracticeSamples && practiceRepetitionCount > 1 {
                        PracticeRepeatGuide(
                            current: practiceRepeatIndex + 1,
                            total: practiceRepetitionCount,
                            language: language
                        )
                    }

                    GuidedWritingCanvas(
                        drawing: $drawing,
                        mode: mode.canvasMode,
                        guideLabels: guideLabels,
                        sampleText: mode.showsWord ? currentWord.text : nil,
                        capture: drawingCapture
                    )
                    .id(canvasResetID)
                    .frame(maxHeight: capturesPracticeSamples && practiceRepetitionCount > 1 ? 300 : 330)

                    if mode == .review {
                        ReviewHintPanel(word: currentWord.text, language: language)
                    }

                    controls
                    resultPanel
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }

            if showingSparkles {
                SparkleBurst(seed: sparkleSeed)
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            resetTimer()
            startTimerIfNeeded()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Label(language.text(japanese: "ホームにもどる", english: "Home"), systemImage: "house.fill")
                    .font(.headline.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.10, green: 0.32, blue: 0.74))

            Spacer()

            Label(mode.title(language: language), systemImage: mode == .review ? "book.fill" : "pencil")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.11, green: 0.30, blue: 0.70))

            Spacer()

            HStack(spacing: 10) {
                if mode == .test {
                    TimerPill(seconds: remainingSeconds, language: language)
                    TestProgressPill(current: index + 1, total: max(sessionWords.count, 1), language: language)
                } else {
                    ProgressPill(current: index + 1, total: max(sessionWords.count, 1))
                }
                if capturesPracticeSamples && practiceRepetitionCount > 1 {
                    RepeatPill(current: practiceRepeatIndex + 1, total: practiceRepetitionCount, language: language)
                }
            }
        }
        .frame(minHeight: 46)
    }

    @ViewBuilder
    private var wordHeader: some View {
        if mode == .test {
            testQuestionHeader
        } else {
            practiceWordHeader
        }
    }

    private var practiceWordHeader: some View {
        HStack(spacing: 18) {
            Spacer()

            speakerButton

            if mode.showsWord {
                Text(currentWord.text)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(minWidth: 240, alignment: .leading)
            }

            Spacer()
        }
        .frame(height: 72)
    }

    private var testQuestionHeader: some View {
        HStack(spacing: 16) {
            if shouldShowSpeakerButton {
                speakerButton
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(testPromptTitle, systemImage: shouldShowTextPrompt ? "text.bubble.fill" : "ear.and.waveform")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.13, green: 0.31, blue: 0.70))

                RubyPromptText(
                    text: testPromptBody,
                    baseFontSize: shouldShowTextPrompt && !currentPromptText.isEmpty ? 34 : 28,
                    rubyFontSize: 12,
                    baseColor: shouldShowTextPrompt && currentPromptText.isEmpty ? Color(red: 0.65, green: 0.34, blue: 0.05) : Color(red: 0.12, green: 0.20, blue: 0.34),
                    rubyColor: Color(red: 0.48, green: 0.32, blue: 0.65),
                    maxLines: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 760, minHeight: 86)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.74, green: 0.83, blue: 0.96), lineWidth: 1)
        )
    }

    private var speakerButton: some View {
        Button {
            playWord()
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(red: 0.14, green: 0.34, blue: 0.76))
                .frame(width: 58, height: 58)
                .background(Color(red: 0.82, green: 0.90, blue: 1.0))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(mode == .test && replayCount >= model.settings.maxReplays)
        .opacity(mode == .test && replayCount >= model.settings.maxReplays ? 0.45 : 1)
        .accessibilityLabel(language.text(japanese: "発音を聞く", english: "Play word"))
    }

    private var controls: some View {
        HStack(spacing: 18) {
            if mode == .test {
                if decision == .rewrite {
                    SessionControlButton(
                        title: language.text(japanese: "消す", english: "Clear"),
                        systemImage: "eraser.fill",
                        style: .secondary
                    ) {
                        clearCanvas()
                    }

                    Spacer()

                    SessionControlButton(
                        title: language.text(japanese: "書き直す", english: "Rewrite"),
                        systemImage: "pencil.and.scribble",
                        style: .primary
                    ) {
                        clearCanvas()
                    }
                } else if decision == .timeExpired {
                    Spacer()

                    SessionControlButton(
                        title: index == sessionWords.count - 1 ? language.text(japanese: "おわる", english: "Finish") : language.text(japanese: "つぎへ", english: "Next"),
                        systemImage: index == sessionWords.count - 1 ? "star.fill" : "arrow.right",
                        style: index == sessionWords.count - 1 ? .finish : .primary
                    ) {
                        moveNext()
                    }
                } else {
                    SessionControlButton(
                        title: language.text(japanese: "消す", english: "Clear"),
                        systemImage: "eraser.fill",
                        style: .secondary
                    ) {
                        clearCanvas()
                    }

                    SessionControlButton(
                        title: language.text(japanese: "パス", english: "Pass"),
                        systemImage: "forward.fill",
                        style: .secondary
                    ) {
                        passWord()
                    }

                    Spacer()

                    SessionControlButton(
                        title: isChecking
                            ? language.text(japanese: "まってね", english: "Saving")
                            : (index == sessionWords.count - 1 ? language.text(japanese: "こたえる", english: "Submit") : language.text(japanese: "つぎへ", english: "Next")),
                        systemImage: isChecking ? "hourglass" : (index == sessionWords.count - 1 ? "checkmark" : "arrow.right"),
                        style: .primary
                    ) {
                        checkAnswer()
                    }
                    .disabled(isChecking)
                }
            } else {
                SessionControlButton(
                    title: language.text(japanese: "消す", english: "Clear"),
                    systemImage: "eraser.fill",
                    style: .secondary
                ) {
                    clearCanvas()
                }

                Spacer()

                    SessionControlButton(
                        title: practiceNextButtonTitle,
                        systemImage: practiceNextButtonIcon,
                        style: .primary
                    ) {
                        celebrateThenMoveNext()
                    }
                    .disabled(isAdvancing)
            }
        }
        .frame(maxWidth: 760)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let decision, mode != .test || decision == .rewrite || decision == .timeExpired {
            HStack(spacing: 14) {
                Image(systemName: decision == .autoCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(decision == .autoCorrect ? .green : .orange)

                VStack(alignment: .leading, spacing: 5) {
                    Text(decision.label(language: language))
                        .font(.headline.weight(.bold))
                    Text(resultMessage(for: decision))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if mode != .test {
                    Text(language.text(japanese: "OCR: ", english: "OCR: ") + (candidates.first?.text.isEmpty == false ? candidates.first?.text ?? "-" : "-"))
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760)
            .padding(14)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.77, green: 0.84, blue: 0.95), lineWidth: 1)
            )
        }
    }

    private func resultMessage(for decision: GradeDecision) -> String {
        switch decision {
        case .autoCorrect:
            return language.text(japanese: "よくできました。", english: "Nicely done.")
        case .autoIncorrect:
            return language.text(japanese: "もう一度れんしゅうに入ります。", english: "This word will go into review.")
        case .needsReview:
            return language.text(japanese: "保護者メニューで確認できます。", english: "Saved for parent review.")
        case .rewrite:
            if mode == .test {
                return language.text(japanese: "読みにくいかも。大きく書き直そう。", english: "Hard to read. Write it larger.")
            }
            return language.text(japanese: "大きく、はっきり書いてみよう。", english: "Write it again with larger letters.")
        case .timeExpired:
            return language.text(japanese: "時間切れです。つぎへ進めます。", english: "Time is up. You can move on.")
        }
    }

    private func clearCanvas() {
        drawing = PKDrawing()
        drawingCapture.latestDrawing = PKDrawing()
        canvasResetID = UUID()
        decision = nil
        candidates = []
        if mode == .test {
            resetTimer()
            startTimerIfNeeded()
        }
    }

    private func moveNext() {
        savePracticeDrawingIfNeeded()

        if capturesPracticeSamples, !isLastPracticeRepeat {
            practiceRepeatIndex += 1
            clearCanvas()
            return
        }

        if index == sessionWords.count - 1 {
            if capturesPracticeSamples {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingPracticeReview = true
                }
            } else if mode == .test {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingTestResults = true
                }
            } else {
                dismiss()
            }
        } else {
            index += 1
            practiceRepeatIndex = 0
            clearCanvas()
            replayCount = 0
            resetTimer()
            startTimerIfNeeded()
        }
    }

    private var practiceNextButtonTitle: String {
        if capturesPracticeSamples, !isLastPracticeRepeat {
            return language.text(japanese: "\(practiceRepeatIndex + 2)かいめを書く", english: "Write round \(practiceRepeatIndex + 2)")
        }
        if index == sessionWords.count - 1 {
            return language.text(japanese: "チェックへ", english: "Review")
        }
        return language.text(japanese: "つぎの単語へ", english: "Next word")
    }

    private var practiceNextButtonIcon: String {
        if capturesPracticeSamples, !isLastPracticeRepeat {
            return "pencil.line"
        }
        return index == sessionWords.count - 1 ? "checklist" : "arrow.right"
    }

    private func celebrateThenMoveNext() {
        guard !isAdvancing else {
            return
        }

        stopTimer()
        isAdvancing = true
        sparkleSeed += 1
        withAnimation(.easeOut(duration: 0.12)) {
            showingSparkles = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeIn(duration: 0.18)) {
                showingSparkles = false
            }
            moveNext()
            isAdvancing = false
        }
    }

    private func savePracticeDrawingIfNeeded() {
        let latestDrawing = drawingCapture.latestDrawing
        guard capturesPracticeSamples, !latestDrawing.bounds.isNull, !latestDrawing.bounds.isEmpty else {
            return
        }

        let sample = PracticeSample(
            word: normalize(currentWord.text),
            drawingData: latestDrawing.dataRepresentation(),
            mode: mode.rawValue,
            sessionID: sessionID
        )
        model.addPracticeSample(sample)
        sessionPracticeSamples.append(sample)
    }

    private func passWord() {
        stopTimer()
        let attempt = model.addAttempt(
            word: currentWord.text,
            recognizedText: "",
            decision: .needsReview,
            drawingData: drawingCapture.latestDrawing.dataRepresentation(),
            sessionID: sessionID
        )
        sessionAttempts.append(attempt)
        moveNext()
    }

    private func playWord() {
        guard mode != .test || replayCount < model.settings.maxReplays else {
            return
        }
        replayCount += 1
        speech.speak(currentWord.text, language: model.settings.language, rate: model.settings.speechRate)
    }

    private func resetTimer() {
        remainingSeconds = model.settings.secondsPerWord
    }

    private func startTimerIfNeeded() {
        stopTimer()
        guard mode == .test else {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                tickTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickTimer() {
        guard decision == nil, !isChecking else {
            return
        }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            let latestDrawing = drawingCapture.latestDrawing
            decision = .timeExpired
            let attempt = model.addAttempt(
                word: currentWord.text,
                recognizedText: "",
                decision: .timeExpired,
                drawingData: latestDrawing.dataRepresentation(),
                sessionID: sessionID
            )
            sessionAttempts.append(attempt)
            stopTimer()
        }
    }

    private func checkAnswer() {
        guard decision == nil else {
            return
        }
        stopTimer()
        isChecking = true
        let latestDrawing = drawingCapture.latestDrawing
        let image = latestDrawing.spellingImage(defaultBounds: CGRect(x: 0, y: 0, width: 1000, height: 260))

        Task {
            defer { isChecking = false }
            do {
                let recognized = try await VisionSpellingOCR(language: model.settings.language).recognize(image, expected: currentWord.text)
                let hasInk = !latestDrawing.bounds.isNull && !latestDrawing.bounds.isEmpty
                let grade = OCRGrader(settings: model.settings).grade(candidates: recognized, expected: currentWord.text, hasInk: hasInk)
                candidates = recognized
                if grade == .rewrite {
                    decision = .rewrite
                    return
                }
                let attempt = model.addAttempt(
                    word: currentWord.text,
                    recognizedText: recognized.first?.text ?? "",
                    decision: grade,
                    drawingData: latestDrawing.dataRepresentation(),
                    sessionID: sessionID
                )
                sessionAttempts.append(attempt)
                decision = nil
                moveNext()
            } catch {
                let hasInk = !latestDrawing.bounds.isNull && !latestDrawing.bounds.isEmpty
                let fallbackDecision: GradeDecision = hasInk ? .needsReview : .rewrite
                candidates = []
                if fallbackDecision == .rewrite {
                    decision = .rewrite
                    return
                }
                let attempt = model.addAttempt(
                    word: currentWord.text,
                    recognizedText: "",
                    decision: fallbackDecision,
                    drawingData: latestDrawing.dataRepresentation(),
                    sessionID: sessionID
                )
                sessionAttempts.append(attempt)
                decision = nil
                moveNext()
            }
        }
    }
}

private struct ProgressPill: View {
    var current: Int
    var total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(.headline.monospacedDigit().weight(.bold))
            .foregroundStyle(Color(red: 0.13, green: 0.32, blue: 0.73))
            .frame(minWidth: 76)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.65, green: 0.78, blue: 0.97), lineWidth: 1)
            )
    }
}

private struct TestProgressPill: View {
    var current: Int
    var total: Int
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(current)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(language.text(japanese: "もんめ", english: "of"))
                .font(.headline.weight(.bold))
            Text("/ \(total)")
                .font(.title3.monospacedDigit().weight(.heavy))
        }
        .foregroundStyle(Color(red: 0.13, green: 0.32, blue: 0.73))
        .frame(minWidth: 130)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.48, green: 0.67, blue: 0.96), lineWidth: 1.5)
        )
        .accessibilityLabel(language.text(japanese: "\(current)問目 / \(total)問", english: "Question \(current) of \(total)"))
    }
}

private struct PracticeRepeatGuide: View {
    var current: Int
    var total: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.52, green: 0.31, blue: 0.78))
                .frame(width: 68, height: 68)
                .background(Color(red: 0.95, green: 0.90, blue: 1.0))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text(japanese: "この単語は \(total) かい", english: "\(total) rounds for this word"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.12, green: 0.24, blue: 0.44))
                Text(language.text(japanese: "\(current)かいめ", english: "Round \(current)"))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.50, green: 0.27, blue: 0.75))
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                ForEach(1...total, id: \.self) { step in
                    Text("\(step)")
                        .font(.title3.monospacedDigit().weight(.heavy))
                        .foregroundStyle(stepForeground(step))
                        .frame(width: 44, height: 44)
                        .background(stepBackground(step))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(stepBorder(step), lineWidth: step == current ? 3 : 1.5)
                        )
                }
            }
        }
        .frame(maxWidth: 760)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.88),
                    Color(red: 0.94, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.82, green: 0.70, blue: 0.95), lineWidth: 2)
        )
        .shadow(color: Color.purple.opacity(0.08), radius: 10, x: 0, y: 5)
        .accessibilityLabel(language.text(japanese: "この単語は\(total)回。今は\(current)回目です。", english: "This word has \(total) rounds. Current round \(current)."))
    }

    private func stepForeground(_ step: Int) -> Color {
        if step < current {
            return .white
        }
        if step == current {
            return .white
        }
        return Color(red: 0.37, green: 0.32, blue: 0.47)
    }

    private func stepBackground(_ step: Int) -> Color {
        if step < current {
            return Color(red: 0.38, green: 0.70, blue: 0.32)
        }
        if step == current {
            return Color(red: 0.51, green: 0.30, blue: 0.78)
        }
        return .white.opacity(0.92)
    }

    private func stepBorder(_ step: Int) -> Color {
        if step <= current {
            return Color(red: 0.51, green: 0.30, blue: 0.78)
        }
        return Color(red: 0.80, green: 0.75, blue: 0.88)
    }
}

private struct RepeatPill: View {
    var current: Int
    var total: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.subheadline.weight(.bold))
            Text(language.text(japanese: "れんしゅう", english: "Practice"))
                .font(.subheadline.weight(.bold))
            Text("\(current) / \(total)")
                .font(.headline.monospacedDigit().weight(.bold))
        }
        .foregroundStyle(Color(red: 0.48, green: 0.28, blue: 0.72))
        .accessibilityLabel(language.text(japanese: "練習 \(current) 回目 / \(total) 回", english: "Practice \(current) of \(total)"))
        .frame(minWidth: 76)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.78, green: 0.68, blue: 0.94), lineWidth: 1)
        )
    }
}

private struct TimerPill: View {
    var seconds: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "timer")
            Text(language.text(japanese: "のこり", english: "left"))
            Text("\(max(seconds, 0))")
                .monospacedDigit()
            Text(language.text(japanese: "秒", english: "s"))
        }
        .font(.headline.weight(.bold))
        .foregroundStyle(seconds <= 5 ? .red : Color(red: 0.20, green: 0.22, blue: 0.28))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.76, green: 0.82, blue: 0.92), lineWidth: 1)
        )
    }
}

private enum SessionButtonStyleKind {
    case primary
    case secondary
    case finish
}

private struct SessionControlButton: View {
    var title: String
    var systemImage: String
    var style: SessionButtonStyleKind
    var action: () -> Void

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return Color(red: 0.13, green: 0.34, blue: 0.75)
        case .finish:
            return Color(red: 0.34, green: 0.18, blue: 0.02)
        }
    }

    private var background: LinearGradient {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [Color(red: 0.14, green: 0.41, blue: 0.84), Color(red: 0.10, green: 0.32, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.96, blue: 1.0), Color(red: 0.91, green: 0.96, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .finish:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.86, blue: 0.22), Color(red: 0.98, green: 0.55, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch style {
        case .finish:
            return Color(red: 0.94, green: 0.48, blue: 0.05)
        case .primary:
            return .clear
        case .secondary:
            return Color(red: 0.60, green: 0.76, blue: 0.96)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .finish:
            return Color.orange.opacity(0.30)
        case .primary:
            return Color.blue.opacity(0.18)
        case .secondary:
            return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .frame(minWidth: 190)
                .padding(.vertical, 15)
                .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: style == .primary ? 0 : 2)
        )
        .shadow(color: shadowColor, radius: style == .finish ? 12 : 8, x: 0, y: 5)
    }
}

private struct ReviewHintPanel: View {
    var word: String
    var language: AppLanguage

    private var hint: String {
        let prefix = String(word.prefix(min(3, word.count)))
        return language.text(
            japanese: "\(prefix) から始まるよ。音をよく聞いてみよう。",
            english: "It starts with \(prefix). Listen closely and try again."
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.title.weight(.bold))
                .foregroundStyle(Color(red: 0.96, green: 0.68, blue: 0.05))
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text(japanese: "ヒント", english: "Hint"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.66, green: 0.30, blue: 0.04))
                Text(hint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: 760)
        .padding(14)
        .background(Color(red: 1.0, green: 0.96, blue: 0.84).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.95, green: 0.75, blue: 0.32), lineWidth: 1)
        )
    }
}

private struct PracticeSessionReviewView: View {
    var samples: [PracticeSample]
    var language: AppLanguage
    var onDone: () -> Void

    @State private var showingCelebration = false
    @State private var celebrationSeed = 0

    private var sampleGroups: [PracticeSampleGroup] {
        groupedPracticeSamples(samples)
    }

    private var writtenSummary: String {
        language.text(
            japanese: "\(sampleGroups.count)こ・\(samples.count)かい書きました",
            english: "\(sampleGroups.count) words ・ \(samples.count) writes"
        )
    }

    var body: some View {
        ZStack {
            if showingCelebration {
                SparkleBurst(seed: celebrationSeed)
                    .transition(.opacity)
                    .zIndex(2)
            }

            VStack(spacing: 18) {
                HStack {
                    Label(language.text(japanese: "れんしゅうチェック", english: "Practice Check"), systemImage: "checklist")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.31, blue: 0.70))

                    Spacer()

                    Text(writtenSummary)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }

                ChildTaskBanner(
                    title: language.text(japanese: "書いたものを見てみよう", english: "Check Your Writing"),
                    message: language.text(japanese: "自分が書いた単語を見て、できたところをたしかめよう。", english: "Look at the words you wrote and check your work."),
                    systemImage: "eye.fill",
                    tint: Color(red: 0.48, green: 0.30, blue: 0.76),
                    compact: true
                )

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Image(systemName: "star.fill")
                        Image(systemName: "sparkles")
                    }
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color(red: 0.96, green: 0.68, blue: 0.06))
                    Text(language.text(japanese: "がんばったね！", english: "Great effort!"))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.82, green: 0.22, blue: 0.07))
                    Text(language.text(japanese: "自分が書いた単語を見てみよう", english: "Look over the words you wrote"))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                    Text(language.text(
                        japanese: "あとで保護者メニューでも見られるので、アドバイスをもらえます。",
                        english: "Parents can see these later and give advice."
                    ))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.72),
                            Color(red: 0.86, green: 0.98, blue: 0.70),
                            Color(red: 0.84, green: 0.93, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.96, green: 0.70, blue: 0.16), lineWidth: 2)
                )

                if samples.isEmpty {
                    ContentUnavailableView(
                        language.text(japanese: "まだ手書きがありません", english: "No handwriting saved"),
                        systemImage: "pencil.and.scribble",
                        description: Text(language.text(japanese: "単語を書いてから「つぎへ」を押すと保存されます。", english: "Write a word, then tap Next to save it."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(sampleGroups) { group in
                                PracticeSampleGroupReviewCard(group: group, language: language)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button(action: onDone) {
                    Label(language.text(japanese: "ホームにもどる", english: "Back Home"), systemImage: "house.fill")
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 240)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            guard !samples.isEmpty else {
                return
            }
            celebrationSeed += 1
            withAnimation(.easeOut(duration: 0.12)) {
                showingCelebration = true
            }
        }
    }

    private func groupedPracticeSamples(_ samples: [PracticeSample]) -> [PracticeSampleGroup] {
        var groups: [PracticeSampleGroup] = []

        for sample in samples {
            if let index = groups.firstIndex(where: { $0.word == sample.word }) {
                groups[index].samples.append(sample)
            } else {
                groups.append(PracticeSampleGroup(word: sample.word, samples: [sample]))
            }
        }

        return groups
    }
}

private struct TestSessionResultsView: View {
    var attempts: [SpellingAttempt]
    var language: AppLanguage
    var onDone: () -> Void

    @State private var showingCompletionCelebration = false
    @State private var celebrationSeed = 0

    private var correctCount: Int {
        attempts.filter { $0.decision == .autoCorrect }.count
    }

    private var isPerfect: Bool {
        !attempts.isEmpty && correctCount == attempts.count
    }

    var body: some View {
        ZStack {
            if showingCompletionCelebration {
                SparkleBurst(seed: celebrationSeed)
                    .transition(.opacity)
                    .zIndex(2)
            }

            VStack(spacing: 18) {
                HStack {
                    Label(language.text(japanese: "テスト結果", english: "Test Results"), systemImage: "checklist")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.31, blue: 0.70))

                    Spacer()

                    Text("\(attempts.count) \(language.text(japanese: "こ回答", english: "answers"))")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }

                ChildTaskBanner(
                    title: language.text(japanese: "結果を見よう", english: "Review Your Results"),
                    message: language.text(japanese: "できた単語と、あとで直す単語をたしかめよう。", english: "Check the words you got and the words to fix later."),
                    systemImage: "checklist.checked",
                    tint: Color(red: 0.14, green: 0.38, blue: 0.76),
                    compact: true
                )

                VStack(spacing: 10) {
                    if isPerfect {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                            Image(systemName: "crown.fill")
                            Image(systemName: "sparkles")
                        }
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.10))
                    }

                    Image(systemName: isPerfect ? "crown.fill" : "trophy.fill")
                        .font(.system(size: isPerfect ? 72 : 58, weight: .bold))
                        .foregroundStyle(isPerfect ? Color(red: 1.0, green: 0.72, blue: 0.08) : Color(red: 0.96, green: 0.68, blue: 0.04))
                    Text(isPerfect ? language.text(japanese: "ぜんぶできた！", english: "Perfect!") : language.text(japanese: "がんばったね！", english: "Great effort!"))
                        .font(.system(size: isPerfect ? 40 : 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(isPerfect ? Color(red: 0.78, green: 0.22, blue: 0.05) : Color(red: 0.80, green: 0.20, blue: 0.08))
                    Text(isPerfect
                        ? language.text(japanese: "最後までぜんぶ正解です。", english: "Every word was correct.")
                        : language.text(japanese: "最後までやりきりました。直すところはあとで見よう。", english: "You finished the test. Review fixes later.")
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    Text("\(correctCount)/\(max(attempts.count, 1))  \(language.text(japanese: "正解", english: "correct"))")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.35, blue: 0.74))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 24)
                        .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
                .padding(isPerfect ? 24 : 18)
                .background(
                    Group {
                        if isPerfect {
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.95, blue: 0.62),
                                    Color(red: 0.78, green: 0.96, blue: 0.55),
                                    Color(red: 0.78, green: 0.90, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            Color.white.opacity(0.88)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isPerfect ? Color(red: 0.98, green: 0.64, blue: 0.08) : Color(red: 0.76, green: 0.84, blue: 0.96), lineWidth: isPerfect ? 3 : 1)
                )
                .shadow(color: isPerfect ? Color.orange.opacity(0.28) : .clear, radius: 16, x: 0, y: 8)

                if attempts.isEmpty {
                    ContentUnavailableView(
                        language.text(japanese: "まだ結果がありません", english: "No results yet"),
                        systemImage: "checklist",
                        description: Text(language.text(japanese: "テストを進めるとここに表示されます。", english: "Test answers will appear here."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(attempts) { attempt in
                                TestAttemptResultCard(attempt: attempt, language: language)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button(action: onDone) {
                    Label(language.text(japanese: "ホームにもどる", english: "Back Home"), systemImage: "house.fill")
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 240)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            guard !attempts.isEmpty else {
                return
            }
            celebrationSeed += 1
            withAnimation(.easeOut(duration: 0.12)) {
                showingCompletionCelebration = true
            }
        }
    }
}

private struct TestAttemptResultCard: View {
    var attempt: SpellingAttempt
    var language: AppLanguage

    private var isCorrect: Bool {
        attempt.decision == .autoCorrect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attempt.word)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                    Text("OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    attempt.decision.label(language: language),
                    systemImage: isCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(isCorrect ? Color.green : Color.orange)
            }

            if let drawingData = attempt.drawingData {
                PracticeDrawingPreview(drawingData: drawingData)
                    .frame(height: 210)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1)
        )
    }
}

struct RubyPromptText: View {
    var text: String
    var baseFontSize: CGFloat
    var rubyFontSize: CGFloat
    var baseColor: Color
    var rubyColor: Color
    var maxLines: Int? = nil

    private var segments: [RubyTextSegment] {
        parseRubyTextSegments(text)
    }

    var body: some View {
        RubyFlowLayout(horizontalSpacing: 0, verticalSpacing: 4, maxLines: maxLines) {
            ForEach(segments) { segment in
                RubyPromptSegmentView(
                    segment: segment,
                    baseFontSize: baseFontSize,
                    rubyFontSize: rubyFontSize,
                    baseColor: baseColor,
                    rubyColor: rubyColor
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rubyPromptAccessibilityText(text))
    }
}

private struct RubyPromptSegmentView: View {
    var segment: RubyTextSegment
    var baseFontSize: CGFloat
    var rubyFontSize: CGFloat
    var baseColor: Color
    var rubyColor: Color

    var body: some View {
        switch segment.kind {
        case .plain:
            Text(segment.base)
                .font(.system(size: baseFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(baseColor)
                .fixedSize()
        case .ruby:
            VStack(spacing: -1) {
                Text(segment.ruby)
                    .font(.system(size: rubyFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(rubyColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(segment.base)
                    .font(.system(size: baseFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }
}

private struct RubyFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    var maxLines: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, proposal: proposal).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> RubyFlowLayoutResult {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var items: [RubyFlowLayoutItem] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var lineCount = 1

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let shouldWrap = cursor.x > 0 && cursor.x + size.width > availableWidth
            if shouldWrap {
                guard maxLines == nil || lineCount < maxLines! else {
                    break
                }
                cursor.x = 0
                cursor.y += lineHeight + verticalSpacing
                lineHeight = 0
                lineCount += 1
            }

            items.append(RubyFlowLayoutItem(index: index, origin: cursor, size: size))
            cursor.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x)
        }

        let width = proposal.width ?? max(usedWidth - horizontalSpacing, 0)
        return RubyFlowLayoutResult(
            size: CGSize(width: max(width, 0), height: cursor.y + lineHeight),
            items: items
        )
    }
}

private struct RubyFlowLayoutResult {
    var size: CGSize
    var items: [RubyFlowLayoutItem]
}

private struct RubyFlowLayoutItem {
    var index: Int
    var origin: CGPoint
    var size: CGSize
}

private struct RubyTextSegment: Identifiable {
    enum Kind {
        case plain
        case ruby
    }

    var id = UUID()
    var kind: Kind
    var base: String
    var ruby: String
}

private func parseRubyTextSegments(_ text: String) -> [RubyTextSegment] {
    var segments: [RubyTextSegment] = []
    var buffer = ""
    var index = text.startIndex

    func appendPlain(_ value: String) {
        for character in value {
            segments.append(RubyTextSegment(kind: .plain, base: String(character), ruby: ""))
        }
    }

    while index < text.endIndex {
        if text[index] == "[", let closing = text[index...].firstIndex(of: "]") {
            let readingStart = text.index(after: index)
            let reading = String(text[readingStart..<closing]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !reading.isEmpty, let split = splitRubyBase(from: buffer) {
                appendPlain(split.prefix)
                segments.append(RubyTextSegment(kind: .ruby, base: split.base, ruby: reading))
                buffer = ""
                index = text.index(after: closing)
                continue
            }
        }

        buffer.append(text[index])
        index = text.index(after: index)
    }

    appendPlain(buffer)
    return segments
}

private func splitRubyBase(from text: String) -> (prefix: String, base: String)? {
    guard !text.isEmpty else {
        return nil
    }

    var current = text.endIndex
    while current > text.startIndex {
        let previous = text.index(before: current)
        let character = text[previous]
        if character.isWhitespace || character.isASCII {
            break
        }
        current = previous
    }

    let base = String(text[current...])
    guard !base.isEmpty else {
        return nil
    }

    return (String(text[..<current]), base)
}

func rubyPromptAccessibilityText(_ text: String) -> String {
    parseRubyTextSegments(text).map { segment in
        switch segment.kind {
        case .plain:
            return segment.base
        case .ruby:
            return "\(segment.base) \(segment.ruby)"
        }
    }
    .joined()
}

private struct PracticeSampleGroup: Identifiable {
    var word: String
    var samples: [PracticeSample]

    var id: UUID {
        samples.first?.id ?? UUID()
    }
}

private struct PracticeSampleGroupReviewCard: View {
    var group: PracticeSampleGroup
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.word)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                Spacer()
                Label(language.text(japanese: "\(group.samples.count)かい", english: "\(group.samples.count) writes"), systemImage: "rectangle.grid.1x2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(group.samples.indices, id: \.self) { sampleIndex in
                        PracticeSampleAttemptTile(
                            sample: group.samples[sampleIndex],
                            round: sampleIndex + 1,
                            language: language
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(12)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: 1)
        )
    }
}

private struct PracticeSampleAttemptTile: View {
    var sample: PracticeSample
    var round: Int
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(language.text(japanese: "\(round)かいめ", english: "Round \(round)"), systemImage: "pencil.line")
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(Color(red: 0.48, green: 0.30, blue: 0.72))

            PracticeDrawingPreview(
                drawingData: sample.drawingData,
                horizontalPadding: 70,
                topPadding: 95,
                bottomPadding: 190
            )
            .frame(height: 150)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
        }
        .frame(width: 214, alignment: .leading)
        .padding(10)
        .background(Color(red: 0.97, green: 0.98, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.80, green: 0.84, blue: 0.94), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.text(japanese: "\(sample.word) \(round)回目の手書き", english: "\(sample.word) handwriting round \(round)"))
    }
}

private struct PracticeDrawingPreview: UIViewRepresentable {
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

private struct SparkleBurst: View {
    var seed: Int
    @State private var animate = false

    private let items: [SparkleItem] = [
        SparkleItem(x: -220, y: -120, size: 34, delay: 0.00, color: Color(red: 0.96, green: 0.70, blue: 0.08), symbol: "sparkles"),
        SparkleItem(x: 210, y: -110, size: 28, delay: 0.04, color: Color(red: 0.28, green: 0.67, blue: 0.92), symbol: "star.fill"),
        SparkleItem(x: -160, y: 90, size: 26, delay: 0.08, color: Color(red: 0.39, green: 0.73, blue: 0.32), symbol: "sparkle"),
        SparkleItem(x: 170, y: 115, size: 32, delay: 0.02, color: Color(red: 0.93, green: 0.33, blue: 0.22), symbol: "sparkles"),
        SparkleItem(x: -60, y: -160, size: 24, delay: 0.10, color: Color(red: 0.62, green: 0.43, blue: 0.84), symbol: "star.fill"),
        SparkleItem(x: 70, y: -150, size: 22, delay: 0.12, color: Color(red: 0.98, green: 0.78, blue: 0.18), symbol: "sparkle"),
        SparkleItem(x: -20, y: 145, size: 28, delay: 0.06, color: Color(red: 0.18, green: 0.58, blue: 0.86), symbol: "star.fill")
    ]

    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height * 0.52

            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(animate ? 0 : 0.20))
                    .frame(width: animate ? 380 : 90, height: animate ? 380 : 90)
                    .position(x: centerX, y: centerY)

                ForEach(items) { item in
                    Image(systemName: item.symbol)
                        .font(.system(size: item.size, weight: .bold))
                        .foregroundStyle(item.color)
                        .scaleEffect(animate ? 1.2 : 0.2)
                        .opacity(animate ? 0 : 1)
                        .rotationEffect(.degrees(animate ? 22 : -12))
                        .position(
                            x: centerX + (animate ? item.x : 0),
                            y: centerY + (animate ? item.y : 0)
                        )
                        .animation(.easeOut(duration: 0.58).delay(item.delay), value: animate)
                }
            }
            .id(seed)
        }
        .allowsHitTesting(false)
        .onAppear {
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
    }
}

private struct SparkleItem: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var delay: Double
    var color: Color
    var symbol: String
}

private struct SessionBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.98, blue: 1.0),
                Color(red: 1.0, green: 0.99, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        SpellingSessionView(mode: .practice, words: [SpellingWord(text: "apple")])
            .environmentObject(AppModel())
    }
}
