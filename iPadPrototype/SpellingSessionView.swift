import PencilKit
import SwiftUI

struct SpellingSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()

    var mode: SessionMode
    var words: [SpellingWord]

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

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    private var currentWord: SpellingWord {
        guard !words.isEmpty else {
            return SpellingWord(text: "")
        }
        return words[min(index, max(words.count - 1, 0))]
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

            VStack(spacing: 18) {
                header
                wordHeader

                GuidedWritingCanvas(
                    drawing: $drawing,
                    mode: mode.canvasMode,
                    guideLabels: guideLabels,
                    sampleText: mode.showsWord ? currentWord.text : nil
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
                }
                ProgressPill(current: index + 1, total: max(words.count, 1))
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
                if decision == nil {
                    SessionControlButton(
                        title: language.text(japanese: "パス", english: "Pass"),
                        systemImage: "forward.fill",
                        style: .secondary
                    ) {
                        passWord()
                    }

                    Spacer()

                    SessionControlButton(
                        title: isChecking ? language.text(japanese: "確認中", english: "Checking") : language.text(japanese: "こたえる", english: "Answer"),
                        systemImage: isChecking ? "hourglass" : "checkmark",
                        style: .primary
                    ) {
                        checkAnswer()
                    }
                    .disabled(isChecking)
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
                        title: index == words.count - 1 ? language.text(japanese: "おわる", english: "Finish") : language.text(japanese: "つぎへ", english: "Next"),
                        systemImage: index == words.count - 1 ? "flag.checkered" : "arrow.right",
                        style: .primary
                    ) {
                        celebrateThenMoveNext()
                    }
                    .disabled(isAdvancing)
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
                        title: index == words.count - 1 ? language.text(japanese: "おわる", english: "Finish") : language.text(japanese: "つぎへ", english: "Next"),
                        systemImage: index == words.count - 1 ? "flag.checkered" : "arrow.right",
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
        if let decision {
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

                Text(language.text(japanese: "OCR: ", english: "OCR: ") + (candidates.first?.text.isEmpty == false ? candidates.first?.text ?? "-" : "-"))
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
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
            return language.text(japanese: "大きく、はっきり書いてみよう。", english: "Write it again with larger letters.")
        case .timeExpired:
            return language.text(japanese: "時間切れです。つぎへ進めます。", english: "Time is up. You can move on.")
        }
    }

    private func clearCanvas() {
        drawing = PKDrawing()
        canvasResetID = UUID()
        decision = nil
        candidates = []
        if mode == .test {
            resetTimer()
            startTimerIfNeeded()
        }
    }

    private func moveNext() {
        if index == words.count - 1 {
            dismiss()
        } else {
            index += 1
            clearCanvas()
            replayCount = 0
            resetTimer()
            startTimerIfNeeded()
        }
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

    private func passWord() {
        stopTimer()
        model.addAttempt(
            word: currentWord.text,
            recognizedText: "",
            decision: .needsReview,
            drawingData: drawing.dataRepresentation()
        )
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
            decision = .timeExpired
            model.addAttempt(
                word: currentWord.text,
                recognizedText: "",
                decision: .timeExpired,
                drawingData: drawing.dataRepresentation()
            )
            stopTimer()
        }
    }

    private func checkAnswer() {
        guard decision == nil else {
            return
        }
        stopTimer()
        isChecking = true
        let image = drawing.spellingImage(defaultBounds: CGRect(x: 0, y: 0, width: 1000, height: 260))

        Task {
            defer { isChecking = false }
            do {
                let recognized = try await VisionSpellingOCR(language: model.settings.language).recognize(image, expected: currentWord.text)
                let grade = OCRGrader(settings: model.settings).grade(candidates: recognized, expected: currentWord.text)
                candidates = recognized
                decision = grade
                model.addAttempt(
                    word: currentWord.text,
                    recognizedText: recognized.first?.text ?? "",
                    decision: grade,
                    drawingData: drawing.dataRepresentation()
                )
            } catch {
                candidates = []
                decision = .rewrite
                model.addAttempt(
                    word: currentWord.text,
                    recognizedText: "",
                    decision: .rewrite,
                    drawingData: drawing.dataRepresentation()
                )
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
}

private struct SessionControlButton: View {
    var title: String
    var systemImage: String
    var style: SessionButtonStyleKind
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .frame(minWidth: 190)
                .padding(.vertical, 15)
                .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(style == .primary ? .white : Color(red: 0.13, green: 0.34, blue: 0.75))
        .background(style == .primary ? Color(red: 0.14, green: 0.41, blue: 0.84) : Color(red: 0.91, green: 0.96, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.60, green: 0.76, blue: 0.96), lineWidth: style == .primary ? 0 : 1)
        )
        .shadow(color: style == .primary ? Color.blue.opacity(0.18) : .clear, radius: 8, x: 0, y: 5)
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
