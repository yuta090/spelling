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
                    wordHeader

                    GuidedWritingCanvas(
                        drawing: $drawing,
                        mode: mode.canvasMode,
                        guideLabels: guideLabels,
                        sampleText: mode.showsWord ? currentWord.text : nil,
                        capture: drawingCapture
                    )
                    .id(canvasResetID)
                    .frame(maxHeight: 330)

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

    private var wordHeader: some View {
        HStack(spacing: 18) {
            Spacer()

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
            return language.text(japanese: "もう一回", english: "Again")
        }
        if index == sessionWords.count - 1 {
            return language.text(japanese: "おわる", english: "Finish")
        }
        return language.text(japanese: "つぎへ", english: "Next")
    }

    private var practiceNextButtonIcon: String {
        if capturesPracticeSamples, !isLastPracticeRepeat {
            return "arrow.counterclockwise"
        }
        return index == sessionWords.count - 1 ? "flag.checkered" : "arrow.right"
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

private struct RepeatPill: View {
    var current: Int
    var total: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
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

                    Text(language.text(japanese: "\(samples.count) こ書きました", english: "\(samples.count) words written"))
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }

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
                            ForEach(samples) { sample in
                                PracticeSampleReviewCard(sample: sample, language: language)
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

private struct PracticeSampleReviewCard: View {
    var sample: PracticeSample
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(sample.word)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                Spacer()
                Label(language.text(japanese: "手書き", english: "Written"), systemImage: "pencil.line")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            PracticeDrawingPreview(drawingData: sample.drawingData)
                .frame(height: 210)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )
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

private struct PracticeDrawingPreview: UIViewRepresentable {
    var drawingData: Data

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if let drawing = try? PKDrawing(data: drawingData) {
            imageView.image = drawing.previewImage()
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
