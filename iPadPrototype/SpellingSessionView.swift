import PencilKit
import SwiftUI

struct SpellingSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()
    @StateObject private var drawingCapture = DrawingCapture()

    let mode: SessionMode
    private let onPracticeProgressChange: (PracticeSessionResumeState?) -> Void
    private let onPracticeCompleted: () -> Void
    private let onPracticeStartTest: () -> Void
    private let onPracticeRetryWords: ([String]) -> Void
    /// ホームへ戻る操作。指定時はアイリス遷移を挟むためこちらを使う（未指定は素の dismiss）。
    private let onRequestClose: (() -> Void)?
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
    @State private var completedPracticeWordCount = 0
    @State private var practiceCelebrationStyle = PracticeCelebrationStyle.random()
    @State private var isAdvancing = false
    @State private var sessionPracticeSamples: [PracticeSample] = []
    @State private var showingPracticeReview = false
    @State private var sessionAttempts: [SpellingAttempt] = []
    @State private var showingTestResults = false
    @State private var practiceRepeatIndex = 0
    @State private var sessionID = UUID()
    @State private var didLoadSessionPracticeSamples = false
    @State private var showingSpeakerHint = false
    @State private var speakerHintPhase = false
    @State private var didShowSpeakerHint = false
    @State private var pendingTestGradeCount = 0
    @State private var shouldShowTestResultsAfterGrading = false
    @State private var measuredWritingCanvasSize: CGSize = .zero
    @State private var compactPracticeDrawings: [UUID: PKDrawing] = [:]
    @State private var compactPracticeCanvasSizes: [UUID: CGSize] = [:]
    @State private var compactPracticeResetIDs: [UUID: UUID] = [:]
    @State private var compactPracticeMissingWordIDs: Set<UUID> = []
    @State private var practiceCelebrationCoinReward = AppModel.practiceCoinReward

    init(
        mode: SessionMode,
        words: [SpellingWord],
        resumeState: PracticeSessionResumeState? = nil,
        onPracticeProgressChange: @escaping (PracticeSessionResumeState?) -> Void = { _ in },
        onPracticeCompleted: @escaping () -> Void = {},
        onPracticeStartTest: @escaping () -> Void = {},
        onPracticeRetryWords: @escaping ([String]) -> Void = { _ in },
        onRequestClose: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onPracticeProgressChange = onPracticeProgressChange
        self.onPracticeCompleted = onPracticeCompleted
        self.onPracticeStartTest = onPracticeStartTest
        self.onPracticeRetryWords = onPracticeRetryWords
        self.onRequestClose = onRequestClose

        let orderedWords = mode == .test ? words.shuffled() : words
        let maxIndex = max(orderedWords.count - 1, 0)
        let shouldResumePractice = mode == .practice && resumeState?.wordIDs == orderedWords.map(\.id)
        let initialIndex = shouldResumePractice ? min(max(resumeState?.index ?? 0, 0), maxIndex) : 0
        let initialRepeatIndex = shouldResumePractice ? max(resumeState?.repeatIndex ?? 0, 0) : 0
        let initialSessionID = shouldResumePractice ? (resumeState?.sessionID ?? UUID()) : UUID()

        _sessionWords = State(initialValue: orderedWords)
        _index = State(initialValue: initialIndex)
        _practiceRepeatIndex = State(initialValue: initialRepeatIndex)
        _sessionID = State(initialValue: initialSessionID)
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

    private var currentInkDrawing: PKDrawing {
        hasInk(drawingCapture.latestDrawing) ? drawingCapture.latestDrawing : drawing
    }

    private var hasCurrentDrawingInk: Bool {
        hasInk(drawingCapture.latestDrawing) || hasInk(drawing)
    }

    private var completedPracticeWordsInSession: Int {
        guard mode == .practice else {
            return 0
        }
        return min(max(index, 0), sessionWords.count)
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

    /// 最後のラウンド（なぞり文字をゆっくり消して自分で書かせる回）かどうか。
    private var isGuideFadeRound: Bool {
        mode == .practice && capturesPracticeSamples && practiceRepetitionCount > 1 && isLastPracticeRepeat
    }

    /// このラウンドで日本語訳・例文ヒントを表示するか。
    private var showsPracticeHint: Bool {
        guard mode != .test else { return false }
        switch model.settings.practiceHintTiming {
        case .never:
            return false
        case .everyRound:
            return true
        case .lastRound:
            return isLastPracticeRepeat
        }
    }

    private var isPracticeRepeatAdvanceButton: Bool {
        mode == .practice && capturesPracticeSamples && !isLastPracticeRepeat
    }

    private var writingCanvasHeight: CGFloat {
        let baseHeight: CGFloat = capturesPracticeSamples && practiceRepetitionCount > 1 ? 300 : 330
        return baseHeight * CGFloat(model.settings.writingAreaSize.heightMultiplier)
    }

    private var writingCanvasMaxWidth: CGFloat {
        CGFloat(model.settings.writingAreaSize.singleCanvasMaxWidth)
    }

    private var compactPracticeGridMaxWidth: CGFloat {
        CGFloat(model.settings.writingAreaSize.compactPracticeGridMaxWidth)
    }

    private var usesCompactPracticeGrid: Bool {
        model.settings.writingAreaSize.usesTwoColumnPracticeLayout
            && capturesPracticeSamples
            && sessionWords.count > 1
    }

    private var compactPracticeCanvasHeight: CGFloat {
        max(190, writingCanvasHeight)
    }

    private var compactPracticeBatchSize: Int {
        usesCompactPracticeGrid ? 2 : 1
    }

    private var compactPracticeWords: [SpellingWord] {
        guard usesCompactPracticeGrid, !sessionWords.isEmpty else {
            return []
        }
        let start = min(max(index, 0), max(sessionWords.count - 1, 0))
        let end = min(start + compactPracticeBatchSize, sessionWords.count)
        return Array(sessionWords[start..<end])
    }

    private var compactPracticeWordIDs: [UUID] {
        compactPracticeWords.map(\.id)
    }

    private var compactPracticeBatchEndIndex: Int {
        min(index + max(compactPracticeWords.count, 1), sessionWords.count)
    }

    private var compactPracticeIsFinalBatch: Bool {
        compactPracticeBatchEndIndex >= sessionWords.count
    }

    private var compactPracticeHasAnyInk: Bool {
        compactPracticeWords.contains { word in
            hasInk(compactPracticeDrawing(for: word))
        }
    }

    private var currentWritingCanvasSize: DrawingCanvasSize? {
        guard measuredWritingCanvasSize.width > 0, measuredWritingCanvasSize.height > 0 else {
            return nil
        }
        let contentOffset = drawingCapture.latestContentOffset
        return DrawingCanvasSize(
            width: Double(measuredWritingCanvasSize.width),
            height: Double(measuredWritingCanvasSize.height),
            contentOffsetX: Double(contentOffset.x),
            contentOffsetY: Double(contentOffset.y)
        )
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

    private var isCanvasInputEnabled: Bool {
        if mode != .test {
            return true
        }
        return decision == nil && !isChecking && remainingSeconds > 0 && !showingTestResults
    }

    private var canEditCanvas: Bool {
        if mode != .test {
            return true
        }
        return decision != .timeExpired && !isChecking && !showingTestResults
    }

    private var canUndoCanvas: Bool {
        canEditCanvas && !currentInkDrawing.strokes.isEmpty
    }

    private var canClearCanvas: Bool {
        canEditCanvas && hasCurrentDrawingInk
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

    private func goHome() {
        // 戻る操作はアイリス遷移で実際の pop が遅れるため、先にタイマーを止めて
        // 遷移中にテストの時間切れが誤って記録されないようにする。
        stopTimer()
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        ZStack {
            SessionBackground()

            if showingPracticeReview {
                PracticeSessionReviewView(
                    samples: sessionPracticeSamples,
                    language: language,
                    onStartTest: mode == .practice && !sessionWords.isEmpty ? onPracticeStartTest : nil,
                    onPracticeRetry: mode == .practice ? onPracticeRetryWords : nil,
                    onDone: {
                        goHome()
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
                        goHome()
                    }
                )
                .transition(.opacity)
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 28)
            } else {
                VStack(spacing: 18) {
                    header

                    if mode == .review {
                        ChildTaskBanner(
                            title: taskBannerTitle,
                            message: taskBannerMessage,
                            systemImage: taskBannerIcon,
                            tint: taskBannerTint,
                            compact: true
                        )
                        .frame(maxWidth: 760)
                    }

                    if usesCompactPracticeGrid {
                        compactPracticeHeader
                    } else {
                        wordHeader
                    }

                    if capturesPracticeSamples && practiceRepetitionCount > 1 {
                        PracticeRepeatGuide(
                            current: practiceRepeatIndex + 1,
                            total: practiceRepetitionCount,
                            language: language
                        )
                    }

                    if usesCompactPracticeGrid {
                        compactPracticeGrid
                    } else {
                        GuidedWritingCanvas(
                            drawing: $drawing,
                            mode: mode.canvasMode,
                            guideLabels: guideLabels,
                            sampleText: mode.showsWord ? currentWord.text : nil,
                            capture: drawingCapture,
                            isInputEnabled: isCanvasInputEnabled,
                            minimumHeight: 0,
                            fadesSampleText: isGuideFadeRound
                        )
                        .id(canvasResetID)
                        .frame(maxWidth: writingCanvasMaxWidth)
                        .frame(height: writingCanvasHeight)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: WritingCanvasSizePreferenceKey.self, value: proxy.size)
                            }
                        )
                    }

                    if mode == .review {
                        ReviewHintPanel(word: currentWord.text, language: language)
                    }

                    if usesCompactPracticeGrid {
                        compactPracticeControls
                    } else {
                        controls
                    }
                    resultPanel
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }

            if showingSparkles {
                PracticeWordCelebrationOverlay(
                    count: completedPracticeWordCount,
                    total: sessionWords.count,
                    style: practiceCelebrationStyle,
                    language: language,
                    seed: sparkleSeed,
                    coinReward: practiceCelebrationCoinReward
                )
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.async {
                loadSessionPracticeSamplesIfNeeded()
                clampPracticeRepeatIndexIfNeeded()
                resetTimer()
                startTimerIfNeeded()
                showSpeakerHintIfNeeded()
            }
        }
        .onDisappear {
            stopTimer()
            showingSpeakerHint = false
        }
        .onPreferenceChange(WritingCanvasSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else {
                return
            }
            guard measuredWritingCanvasSize != size else {
                return
            }
            measuredWritingCanvasSize = size
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                goHome()
            } label: {
                Label(language.text(japanese: "ホームにもどる", english: "Home"), systemImage: "house.fill")
                    .font(.headline.weight(.bold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .tapFeedback()
            .foregroundStyle(Color(red: 0.10, green: 0.32, blue: 0.74))

            Spacer()

            Label(mode.title(language: language), systemImage: mode == .review ? "book.fill" : "pencil")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.11, green: 0.30, blue: 0.70))

            Spacer()

            HStack(spacing: 10) {
                if mode == .test {
                    TestTimerBar(seconds: remainingSeconds, totalSeconds: model.settings.secondsPerWord, language: language)
                    TestProgressPill(current: index + 1, total: max(sessionWords.count, 1), language: language)
                } else if mode == .practice {
                    PracticeGoalBadge(
                        completed: completedPracticeWordsInSession,
                        total: max(sessionWords.count, 1),
                        language: language
                    )
                } else {
                    ProgressPill(current: index + 1, total: max(sessionWords.count, 1))
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
            VStack(spacing: 8) {
                practiceWordHeader
                // 練習・復習では日本語訳・例文をヒント表示（テストは答えが見えてしまうので出さない）。
                // 表示タイミングは設定（既定は最後のラウンドのみ）に従う。
                if showsPracticeHint {
                    ExampleHintView(word: currentWord.text, language: language)
                }
            }
        }
    }

    private var compactPracticeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.grid.2x2.fill")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color(red: 0.48, green: 0.30, blue: 0.76))
                .frame(width: 52, height: 52)
                .background(Color(red: 0.95, green: 0.90, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(japanese: "2こまとめて書こう", english: "Write Two at a Time"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.24, blue: 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(compactPracticeWords.map(\.text).joined(separator: " / "))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.12, green: 0.32, blue: 0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }

            Spacer()
        }
        .frame(maxWidth: 1120)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.78, green: 0.84, blue: 0.96), lineWidth: 1)
        )
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
            ZStack {
                if showingSpeakerHint && mode == .test {
                    SpeakerHintPulse(phase: speakerHintPhase)
                }

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(red: 0.14, green: 0.34, blue: 0.76))
                    .frame(width: 58, height: 58)
                    .background(Color(red: 0.82, green: 0.90, blue: 1.0))
                    .clipShape(Circle())
                    .scaleEffect(showingSpeakerHint && speakerHintPhase ? 1.08 : 1)
            }
            .frame(width: mode == .test ? 82 : 58, height: mode == .test ? 82 : 58)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .tapFeedback()
        .disabled(mode == .test && replayCount >= model.settings.maxReplays)
        .opacity(mode == .test && replayCount >= model.settings.maxReplays ? 0.45 : 1)
        .accessibilityLabel(language.text(japanese: "発音を聞く", english: "Play word"))
    }

    private var compactPracticeGrid: some View {
        LazyVGrid(columns: compactPracticeGridColumns, spacing: 14) {
            ForEach(compactPracticeWords) { word in
                CompactPracticeWritingCell(
                    word: word,
                    drawing: compactPracticeDrawingBinding(for: word),
                    resetID: compactPracticeResetIDs[word.id] ?? word.id,
                    canvasHeight: compactPracticeCanvasHeight,
                    guideLabels: guideLabels,
                    language: language,
                    isMissing: compactPracticeMissingWordIDs.contains(word.id),
                    fadesSampleText: isGuideFadeRound,
                    onPlay: {
                        speech.speak(word.text, language: model.settings.language, rate: model.settings.speechRate)
                    },
                    onClear: {
                        clearCompactPracticeDrawing(for: word)
                    },
                    onMeasure: { size in
                        guard size.width > 0, size.height > 0 else {
                            return
                        }
                        compactPracticeCanvasSizes[word.id] = size
                    }
                )
            }
        }
        .frame(maxWidth: compactPracticeGridMaxWidth)
        .onAppear {
            prepareCompactPracticeBatch()
        }
        .onChange(of: compactPracticeWordIDs) { _, _ in
            prepareCompactPracticeBatch()
        }
        .onChange(of: practiceRepeatIndex) { _, _ in
            prepareCompactPracticeBatch()
        }
    }

    private var compactPracticeGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 330), spacing: 14, alignment: .top),
            GridItem(.flexible(minimum: 330), spacing: 14, alignment: .top)
        ]
    }

    private var controls: some View {
        HStack(spacing: 18) {
            if mode == .test {
                if decision == .rewrite {
                    CanvasEditControls(
                        language: language,
                        canUndo: canUndoCanvas,
                        canClear: canClearCanvas,
                        undo: undoLastStroke,
                        clearAll: clearCanvas
                    )

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
                        title: isChecking
                            ? language.text(japanese: "まってね", english: "Saving")
                            : (index == sessionWords.count - 1 ? language.text(japanese: "おわる", english: "Finish") : language.text(japanese: "つぎへ", english: "Next")),
                        systemImage: isChecking ? "hourglass" : (index == sessionWords.count - 1 ? "star.fill" : "arrow.right"),
                        style: index == sessionWords.count - 1 ? .finish : .primary
                    ) {
                        moveNext()
                    }
                    .disabled(isChecking)
                } else {
                    CanvasEditControls(
                        language: language,
                        canUndo: canUndoCanvas,
                        canClear: canClearCanvas,
                        undo: undoLastStroke,
                        clearAll: clearCanvas
                    )

                    SessionControlButton(
                        title: language.text(japanese: "パス", english: "Pass"),
                        systemImage: "forward.fill",
                        style: .secondary,
                        minWidth: 118,
                        horizontalPadding: 16
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
                CanvasEditControls(
                    language: language,
                    canUndo: canUndoCanvas,
                    canClear: canClearCanvas,
                    undo: undoLastStroke,
                    clearAll: clearCanvas
                )

                Spacer()

                    SessionControlButton(
                        title: practiceNextButtonTitle,
                        systemImage: practiceNextButtonIcon,
                        style: .primary,
                        funTapAnimations: isPracticeRepeatAdvanceButton,
                        canPlayFunTapAnimation: {
                            hasCurrentDrawingInk
                        }
                    ) {
                        celebrateThenMoveNext()
                    }
                    .disabled(isAdvancing)
            }
        }
        .frame(maxWidth: 760)
    }

    private var compactPracticeControls: some View {
        HStack(spacing: 16) {
            SessionControlButton(
                title: language.text(japanese: "この画面を消す", english: "Clear Page"),
                systemImage: "eraser.fill",
                style: .secondary,
                minWidth: 170,
                horizontalPadding: 18
            ) {
                clearCompactPracticeBatch()
            }
            .disabled(!compactPracticeHasAnyInk)

            Spacer()

            SessionControlButton(
                title: compactPracticeNextButtonTitle,
                systemImage: compactPracticeNextButtonIcon,
                style: compactPracticeIsFinalBatch && isLastPracticeRepeat ? .finish : .primary,
                minWidth: 230,
                funTapAnimations: !isLastPracticeRepeat,
                canPlayFunTapAnimation: {
                    compactPracticeHasAnyInk
                }
            ) {
                compactPracticeMoveNext()
            }
            .disabled(isAdvancing)
        }
        .frame(maxWidth: 1120)
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
            if usesCompactPracticeGrid, !compactPracticeMissingWordIDs.isEmpty {
                return language.text(japanese: "オレンジの欄にも単語を書いてね。", english: "Write in the orange-marked area too.")
            }
            if !hasCurrentDrawingInk {
                return language.text(japanese: "まず、お手本を見て単語を書いてね。", english: "Write the word first.")
            }
            return language.text(japanese: "大きく、はっきり書いてみよう。", english: "Write it again with larger letters.")
        case .timeExpired:
            return language.text(japanese: "時間切れです。つぎへ進めます。", english: "Time is up. You can move on.")
        }
    }

    private func clearCanvas() {
        setCanvasDrawing(PKDrawing())
        canvasResetID = UUID()
        decision = nil
        candidates = []
    }

    private func undoLastStroke() {
        let activeDrawing = currentInkDrawing
        guard !activeDrawing.strokes.isEmpty else {
            return
        }

        let updatedDrawing = PKDrawing(strokes: Array(activeDrawing.strokes.dropLast()))
        setCanvasDrawing(updatedDrawing)
        canvasResetID = UUID()
        decision = nil
        candidates = []
    }

    private func setCanvasDrawing(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        drawingCapture.latestDrawing = newDrawing
    }

    private func moveNext() {
        moveNext(saveDrawing: true)
    }

    private func moveNext(saveDrawing: Bool) {
        if saveDrawing {
            guard requirePracticeInkIfNeeded() else {
                return
            }
            savePracticeDrawingIfNeeded()
        }

        if capturesPracticeSamples, !isLastPracticeRepeat {
            practiceRepeatIndex += 1
            publishPracticeProgressIfNeeded()
            clearCanvas()
            return
        }

        if index == sessionWords.count - 1 {
            if capturesPracticeSamples {
                if mode == .practice {
                    onPracticeCompleted()
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingPracticeReview = true
                }
            } else if mode == .test {
                finishTestWhenGradesAreReady()
            } else {
                goHome()
            }
        } else {
            index += 1
            practiceRepeatIndex = 0
            publishPracticeProgressIfNeeded()
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

    private var compactPracticeNextButtonTitle: String {
        if !isLastPracticeRepeat {
            return language.text(japanese: "\(practiceRepeatIndex + 2)かいめを書く", english: "Write round \(practiceRepeatIndex + 2)")
        }
        if compactPracticeIsFinalBatch {
            return language.text(japanese: "チェックへ", english: "Review")
        }
        let count = min(compactPracticeBatchSize, max(sessionWords.count - compactPracticeBatchEndIndex, 1))
        return language.text(japanese: "つぎの\(count)こへ", english: "Next \(count)")
    }

    private var compactPracticeNextButtonIcon: String {
        if !isLastPracticeRepeat {
            return "pencil.line"
        }
        return compactPracticeIsFinalBatch ? "checklist" : "arrow.right"
    }

    private func celebrateThenMoveNext() {
        guard !isAdvancing else {
            return
        }

        guard mode == .practice, capturesPracticeSamples, isLastPracticeRepeat else {
            moveNext()
            return
        }

        guard requirePracticeInkIfNeeded() else {
            return
        }

        isAdvancing = true
        savePracticeDrawingIfNeeded()
        model.awardPracticeCoins()
        practiceCelebrationCoinReward = AppModel.practiceCoinReward
        completedPracticeWordCount = practicedWordCountInSession()
        practiceCelebrationStyle = PracticeCelebrationStyle.random()
        sparkleSeed += 1

        withAnimation(.easeOut(duration: 0.16)) {
            showingSparkles = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            withAnimation(.easeIn(duration: 0.18)) {
                showingSparkles = false
            }
            moveNext(saveDrawing: false)
            isAdvancing = false
        }
    }

    private func compactPracticeMoveNext() {
        guard !isAdvancing else {
            return
        }

        guard requireCompactPracticeInk() else {
            return
        }

        saveCompactPracticeDrawings()

        if !isLastPracticeRepeat {
            practiceRepeatIndex += 1
            publishPracticeProgressIfNeeded()
            clearCompactPracticeBatch()
            return
        }

        let completedWords = compactPracticeWords.count
        isAdvancing = true
        model.awardPracticeCoins(AppModel.practiceCoinReward * completedWords)
        practiceCelebrationCoinReward = AppModel.practiceCoinReward * completedWords
        completedPracticeWordCount = practicedWordCountInSession()
        practiceCelebrationStyle = PracticeCelebrationStyle.random()
        sparkleSeed += 1

        withAnimation(.easeOut(duration: 0.16)) {
            showingSparkles = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            withAnimation(.easeIn(duration: 0.18)) {
                showingSparkles = false
            }
            finishCompactPracticeBatch()
            isAdvancing = false
        }
    }

    private func finishCompactPracticeBatch() {
        if compactPracticeIsFinalBatch {
            if mode == .practice {
                onPracticeCompleted()
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                showingPracticeReview = true
            }
            return
        }

        index = compactPracticeBatchEndIndex
        practiceRepeatIndex = 0
        publishPracticeProgressIfNeeded()
        clearCompactPracticeBatch()
    }

    private func prepareCompactPracticeBatch() {
        let activeIDs = Set(compactPracticeWords.map(\.id))
        guard !activeIDs.isEmpty else {
            return
        }

        for id in activeIDs {
            if compactPracticeDrawings[id] == nil {
                compactPracticeDrawings[id] = PKDrawing()
            }
            if compactPracticeResetIDs[id] == nil {
                compactPracticeResetIDs[id] = UUID()
            }
        }

        compactPracticeDrawings = compactPracticeDrawings.filter { activeIDs.contains($0.key) }
        compactPracticeCanvasSizes = compactPracticeCanvasSizes.filter { activeIDs.contains($0.key) }
        compactPracticeResetIDs = compactPracticeResetIDs.filter { activeIDs.contains($0.key) }
        compactPracticeMissingWordIDs = compactPracticeMissingWordIDs.intersection(activeIDs)
    }

    private func compactPracticeDrawing(for word: SpellingWord) -> PKDrawing {
        compactPracticeDrawings[word.id] ?? PKDrawing()
    }

    private func compactPracticeDrawingBinding(for word: SpellingWord) -> Binding<PKDrawing> {
        Binding(
            get: {
                compactPracticeDrawings[word.id] ?? PKDrawing()
            },
            set: { newDrawing in
                compactPracticeDrawings[word.id] = newDrawing
                if hasInk(newDrawing) {
                    compactPracticeMissingWordIDs.remove(word.id)
                    if compactPracticeMissingWordIDs.isEmpty, decision == .rewrite {
                        decision = nil
                    }
                }
            }
        )
    }

    private func compactPracticeCanvasSize(for wordID: UUID) -> DrawingCanvasSize? {
        guard let size = compactPracticeCanvasSizes[wordID], size.width > 0, size.height > 0 else {
            return nil
        }
        return DrawingCanvasSize(width: Double(size.width), height: Double(size.height))
    }

    private func clearCompactPracticeDrawing(for word: SpellingWord) {
        compactPracticeDrawings[word.id] = PKDrawing()
        compactPracticeResetIDs[word.id] = UUID()
        compactPracticeMissingWordIDs.remove(word.id)
    }

    private func clearCompactPracticeBatch() {
        for word in compactPracticeWords {
            compactPracticeDrawings[word.id] = PKDrawing()
            compactPracticeResetIDs[word.id] = UUID()
        }
        compactPracticeMissingWordIDs.removeAll()
    }

    private func requireCompactPracticeInk() -> Bool {
        let missingIDs = Set(compactPracticeWords.compactMap { word -> UUID? in
            hasInk(compactPracticeDrawing(for: word)) ? nil : word.id
        })

        guard missingIDs.isEmpty else {
            compactPracticeMissingWordIDs = missingIDs
            candidates = []
            withAnimation(.easeInOut(duration: 0.16)) {
                decision = .rewrite
            }
            return false
        }

        compactPracticeMissingWordIDs.removeAll()
        return true
    }

    private func saveCompactPracticeDrawings() {
        for word in compactPracticeWords {
            let latestDrawing = compactPracticeDrawing(for: word)
            guard hasInk(latestDrawing) else {
                continue
            }

            let sample = PracticeSample(
                word: normalize(word.text),
                drawingData: latestDrawing.dataRepresentation(),
                canvasSize: compactPracticeCanvasSize(for: word.id),
                mode: mode.rawValue,
                sessionID: sessionID
            )
            model.addPracticeSample(sample)
            sessionPracticeSamples.append(sample)
        }
    }

    private func savePracticeDrawingIfNeeded() {
        let latestDrawing = currentInkDrawing
        guard capturesPracticeSamples, hasInk(latestDrawing) else {
            return
        }

        let sample = PracticeSample(
            word: normalize(currentWord.text),
            drawingData: latestDrawing.dataRepresentation(),
            canvasSize: currentWritingCanvasSize,
            mode: mode.rawValue,
            sessionID: sessionID
        )
        model.addPracticeSample(sample)
        sessionPracticeSamples.append(sample)
    }

    private func requirePracticeInkIfNeeded() -> Bool {
        guard capturesPracticeSamples else {
            return true
        }

        guard hasCurrentDrawingInk else {
            candidates = []
            withAnimation(.easeInOut(duration: 0.16)) {
                decision = .rewrite
            }
            return false
        }

        return true
    }

    private func hasInk(_ drawing: PKDrawing) -> Bool {
        !drawing.bounds.isNull && !drawing.bounds.isEmpty
    }

    private func practicedWordCountInSession() -> Int {
        Set(sessionPracticeSamples.map(\.word)).count
    }

    private func loadSessionPracticeSamplesIfNeeded() {
        guard capturesPracticeSamples, !didLoadSessionPracticeSamples else {
            return
        }

        didLoadSessionPracticeSamples = true
        let savedSamples = model.practiceSamples
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        if !savedSamples.isEmpty {
            sessionPracticeSamples = savedSamples
        }
    }

    private func clampPracticeRepeatIndexIfNeeded() {
        guard capturesPracticeSamples else {
            return
        }
        practiceRepeatIndex = min(max(practiceRepeatIndex, 0), max(practiceRepetitionCount - 1, 0))
    }

    private func publishPracticeProgressIfNeeded() {
        guard mode == .practice, !sessionWords.isEmpty else {
            return
        }

        guard index > 0 || practiceRepeatIndex > 0 || !sessionPracticeSamples.isEmpty else {
            return
        }

        onPracticeProgressChange(
            PracticeSessionResumeState(
                wordIDs: sessionWords.map(\.id),
                index: min(max(index, 0), max(sessionWords.count - 1, 0)),
                repeatIndex: min(max(practiceRepeatIndex, 0), max(practiceRepetitionCount - 1, 0)),
                sessionID: sessionID
            )
        )
    }

    private func passWord() {
        stopTimer()
        let attempt = model.addAttempt(
            word: currentWord.text,
            recognizedText: "",
            decision: .needsReview,
            drawingData: drawingCapture.latestDrawing.dataRepresentation(),
            canvasSize: currentWritingCanvasSize,
            sessionID: sessionID
        )
        sessionAttempts.append(attempt)
        moveNext()
    }

    private func playWord() {
        guard mode != .test || replayCount < model.settings.maxReplays else {
            return
        }
        withAnimation(.easeIn(duration: 0.12)) {
            showingSpeakerHint = false
        }
        replayCount += 1
        speech.speak(currentWord.text, language: model.settings.language, rate: model.settings.speechRate)
    }

    private func showSpeakerHintIfNeeded() {
        guard mode == .test, shouldShowSpeakerButton, !didShowSpeakerHint else {
            return
        }

        didShowSpeakerHint = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard shouldShowSpeakerButton, replayCount == 0, decision == nil, !showingTestResults else {
                return
            }

            showingSpeakerHint = true
            speakerHintPhase = false

            for _ in 0..<3 {
                guard showingSpeakerHint, replayCount == 0, decision == nil else {
                    return
                }

                withAnimation(.easeOut(duration: 0.38)) {
                    speakerHintPhase = true
                }
                try? await Task.sleep(nanoseconds: 380_000_000)

                withAnimation(.easeIn(duration: 0.16)) {
                    speakerHintPhase = false
                }
                try? await Task.sleep(nanoseconds: 160_000_000)
            }

            withAnimation(.easeIn(duration: 0.18)) {
                showingSpeakerHint = false
            }
        }
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
        guard mode == .test, !isChecking, !showingTestResults, decision != .timeExpired else {
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
                canvasSize: currentWritingCanvasSize,
                sessionID: sessionID
            )
            sessionAttempts.append(attempt)
            stopTimer()
        }
    }

    private func checkAnswer() {
        guard decision == nil, !isChecking else {
            return
        }

        let submittedWord = currentWord.text
        let submittedDrawing = currentInkDrawing
        guard hasInk(submittedDrawing) else {
            candidates = []
            decision = .rewrite
            return
        }

        stopTimer()

        let submittedAt = Date()
        let submittedDrawingData = submittedDrawing.dataRepresentation()
        let submittedCanvasSize = currentWritingCanvasSize
        let isFinalWord = index == sessionWords.count - 1
        enqueueTestGrade(
            word: submittedWord,
            drawingData: submittedDrawingData,
            canvasSize: submittedCanvasSize,
            submittedAt: submittedAt
        )

        if isFinalWord {
            isChecking = true
            shouldShowTestResultsAfterGrading = true
            showTestResultsIfReady()
        } else {
            decision = nil
            candidates = []
            moveNext(saveDrawing: false)
        }
    }

    private func enqueueTestGrade(word: String, drawingData: Data, canvasSize: DrawingCanvasSize?, submittedAt: Date) {
        pendingTestGradeCount += 1
        let recognitionLanguage = model.settings.language
        let settings = model.settings
        let sessionID = sessionID

        Task.detached(priority: .utility) {
            let result = await gradeTestDrawing(
                word: word,
                drawingData: drawingData,
                recognitionLanguage: recognitionLanguage,
                settings: settings
            )

            await MainActor.run {
                let attempt = model.addAttempt(
                    word: word,
                    recognizedText: result.recognizedText,
                    decision: result.decision,
                    drawingData: drawingData,
                    canvasSize: canvasSize,
                    date: submittedAt,
                    sessionID: sessionID
                )
                sessionAttempts.append(attempt)
                sessionAttempts.sort { $0.date < $1.date }
                pendingTestGradeCount = max(pendingTestGradeCount - 1, 0)
                showTestResultsIfReady()
            }
        }
    }

    private func showTestResultsIfReady() {
        guard shouldShowTestResultsAfterGrading, pendingTestGradeCount == 0 else {
            return
        }

        isChecking = false
        shouldShowTestResultsAfterGrading = false
        withAnimation(.easeInOut(duration: 0.18)) {
            showingTestResults = true
        }
    }

    private func finishTestWhenGradesAreReady() {
        shouldShowTestResultsAfterGrading = true
        if pendingTestGradeCount > 0 {
            isChecking = true
        }
        showTestResultsIfReady()
    }
}

private struct TestGradeResult: Sendable {
    var recognizedText: String
    var decision: GradeDecision
}

private struct WritingCanvasSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private func gradeTestDrawing(
    word: String,
    drawingData: Data,
    recognitionLanguage: String,
    settings: TestSettings
) async -> TestGradeResult {
    do {
        let drawing = try PKDrawing(data: drawingData)
        let image = drawing.spellingImage(defaultBounds: CGRect(x: 0, y: 0, width: 1000, height: 260))
        let recognized = try await VisionSpellingOCR(language: recognitionLanguage).recognize(image, expected: word)
        var grade = OCRGrader(settings: settings).grade(candidates: recognized, expected: word, hasInk: true)
        if grade == .rewrite {
            grade = .needsReview
        }
        return TestGradeResult(recognizedText: recognized.first?.text ?? "", decision: grade)
    } catch {
        return TestGradeResult(recognizedText: "", decision: .needsReview)
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

private struct PracticeGoalBadge: View {
    var completed: Int
    var total: Int
    var language: AppLanguage

    private var safeTotal: Int {
        max(total, 1)
    }

    private var safeCompleted: Int {
        min(max(completed, 0), safeTotal)
    }

    private var remaining: Int {
        max(safeTotal - safeCompleted, 0)
    }

    private var progress: Double {
        min(max(Double(safeCompleted) / Double(safeTotal), 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.86, blue: 0.24),
                                Color(red: 0.98, green: 0.52, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.orange.opacity(0.20), radius: 5, x: 0, y: 3)

                Image(systemName: remaining == 0 ? "star.fill" : "flag.fill")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(remainingText)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.14, green: 0.25, blue: 0.44))
                        .contentTransition(.numericText())

                    Spacer(minLength: 4)

                    Text("\(safeCompleted)/\(safeTotal)")
                        .font(.caption.monospacedDigit().weight(.heavy))
                        .foregroundStyle(Color(red: 0.43, green: 0.37, blue: 0.54))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.66))

                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.34, green: 0.72, blue: 0.36),
                                        Color(red: 0.88, green: 0.72, blue: 0.18)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)

                Text(language.text(japanese: "きょうのれんしゅう", english: "today's practice"))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.58))
            }
        }
        .frame(width: 218, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.76),
                    Color(red: 0.88, green: 0.98, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color(red: 0.32, green: 0.40, blue: 0.58).opacity(0.12), radius: 10, x: 0, y: 5)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: safeCompleted)
        .accessibilityLabel(accessibilityText)
    }

    private var remainingText: String {
        if remaining == 0 {
            return language.text(japanese: "できた！", english: "Done!")
        }
        return language.text(japanese: "あと \(remaining)こ", english: "\(remaining) left")
    }

    private var accessibilityText: String {
        language.text(
            japanese: "今日の練習。\(safeCompleted)個できました。あと\(remaining)個です。",
            english: "Today's practice. \(safeCompleted) done. \(remaining) left."
        )
    }
}

private struct SpeakerHintPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var phase: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.18, green: 0.45, blue: 0.92).opacity(phase ? 0.06 : 0.16))
                .frame(width: reduceMotion ? 76 : 82, height: reduceMotion ? 76 : 82)
                .scaleEffect(reduceMotion ? 1 : (phase ? 1.06 : 0.84))

            Circle()
                .stroke(Color(red: 0.18, green: 0.45, blue: 0.92).opacity(phase ? 0.08 : 0.62), lineWidth: phase ? 2 : 5)
                .frame(width: 72, height: 72)
                .scaleEffect(reduceMotion ? 1 : (phase ? 1.16 : 0.78))
        }
        .allowsHitTesting(false)
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

private struct CompactPracticeWritingCell: View {
    var word: SpellingWord
    @Binding var drawing: PKDrawing
    var resetID: UUID
    var canvasHeight: CGFloat
    var guideLabels: [String]
    var language: AppLanguage
    var isMissing: Bool
    var fadesSampleText = false
    var onPlay: () -> Void
    var onClear: () -> Void
    var onMeasure: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color(red: 0.14, green: 0.34, blue: 0.76))
                        .frame(width: 44, height: 44)
                        .background(Color(red: 0.82, green: 0.90, blue: 1.0))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tapFeedback()
                .accessibilityLabel(language.text(japanese: "\(word.text) の発音を聞く", english: "Play \(word.text)"))

                Text(word.text)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.20, blue: 0.40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)

                Spacer(minLength: 6)

                Button(action: onClear) {
                    Label(language.text(japanese: "消す", english: "Clear"), systemImage: "eraser.fill")
                        .font(.subheadline.weight(.heavy))
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color(red: 0.13, green: 0.34, blue: 0.75))
                        .frame(width: 42, height: 42)
                        .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tapFeedback(scale: 0.94)
                .accessibilityLabel(language.text(japanese: "\(word.text) を消す", english: "Clear \(word.text)"))
            }

            GuidedWritingCanvas(
                drawing: $drawing,
                mode: .practice,
                guideLabels: guideLabels,
                sampleText: word.text,
                capture: nil,
                isInputEnabled: true,
                minimumHeight: 0,
                fadesSampleText: fadesSampleText
            )
            .id(resetID)
            .frame(height: canvasHeight)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onMeasure(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            onMeasure(newSize)
                        }
                }
            )
            .overlay(alignment: .topLeading) {
                if isMissing {
                    Label(language.text(japanese: "ここも書いてね", english: "Write here too"), systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color(red: 0.85, green: 0.38, blue: 0.06))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(red: 1.0, green: 0.94, blue: 0.84))
                        .clipShape(Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isMissing ? Color(red: 0.94, green: 0.46, blue: 0.08) : Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: isMissing ? 2.5 : 1)
        )
        .shadow(color: Color(red: 0.30, green: 0.40, blue: 0.60).opacity(0.08), radius: 10, x: 0, y: 5)
        .animation(.spring(response: 0.24, dampingFraction: 0.80), value: isMissing)
    }
}

private struct PracticeRepeatGuide: View {
    var current: Int
    var total: Int
    var language: AppLanguage

    private var remaining: Int {
        max(total - current, 0)
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(language.text(japanese: "\(current)かいめ", english: "Round \(current)"))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.14, green: 0.24, blue: 0.42))

                Label(remainingMessage, systemImage: remaining == 0 ? "sparkles" : "pencil.tip")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(remaining == 0 ? Color(red: 0.32, green: 0.55, blue: 0.18) : Color(red: 0.54, green: 0.31, blue: 0.74))
            }
            .frame(width: 188, alignment: .leading)

            HStack(spacing: 12) {
                ForEach(Array(1...max(total, 1)), id: \.self) { step in
                    PracticeRoundBubble(
                        step: step,
                        current: current,
                        language: language
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: 760)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.93, blue: 0.74),
                    Color(red: 0.88, green: 0.98, blue: 0.91),
                    Color(red: 0.92, green: 0.91, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color(red: 0.40, green: 0.30, blue: 0.62).opacity(0.14), radius: 16, x: 0, y: 8)
        .shadow(color: .white.opacity(0.78), radius: 1, x: -1, y: -1)
        .accessibilityLabel(language.text(japanese: "この単語は\(total)回。今は\(current)回目です。", english: "This word has \(total) rounds. Current round \(current)."))
    }

    private var remainingMessage: String {
        if remaining == 0 {
            return language.text(japanese: "このあとチェック", english: "Review next")
        }
        return language.text(japanese: "あと \(remaining)かい", english: "\(remaining) left")
    }
}

private struct PracticeRoundBubble: View {
    var step: Int
    var current: Int
    var language: AppLanguage

    private var isDone: Bool {
        step < current
    }

    private var isCurrent: Bool {
        step == current
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
                    .shadow(color: shadowColor, radius: isCurrent ? 10 : 5, x: 0, y: isCurrent ? 6 : 3)
                    .overlay(alignment: .topTrailing) {
                        if isCurrent {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(red: 0.98, green: 0.64, blue: 0.08))
                                .padding(7)
                        }
                    }

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.system(size: isCurrent ? 30 : 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(numberColor)
                }
            }
            .frame(width: isCurrent ? 76 : 62, height: isCurrent ? 58 : 52)
            .scaleEffect(isCurrent ? 1.04 : 1)

            Text(statusText)
                .font(.caption.weight(.heavy))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: current)
        .accessibilityLabel(accessibilityText)
    }

    private var background: LinearGradient {
        if isDone {
            return LinearGradient(
                colors: [Color(red: 0.32, green: 0.70, blue: 0.36), Color(red: 0.18, green: 0.56, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isCurrent {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.82, blue: 0.22), Color(red: 1.0, green: 0.58, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.white.opacity(0.94), Color(red: 0.91, green: 0.96, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        if isCurrent {
            return Color(red: 0.96, green: 0.47, blue: 0.08).opacity(0.22)
        }
        return Color(red: 0.30, green: 0.38, blue: 0.56).opacity(0.10)
    }

    private var numberColor: Color {
        isCurrent ? .white : Color(red: 0.22, green: 0.30, blue: 0.48)
    }

    private var statusText: String {
        if isDone {
            return language.text(japanese: "できた", english: "Done")
        }
        if isCurrent {
            return language.text(japanese: "いま", english: "Now")
        }
        return language.text(japanese: "つぎ", english: "Next")
    }

    private var statusColor: Color {
        if isDone {
            return Color(red: 0.16, green: 0.46, blue: 0.23)
        }
        if isCurrent {
            return Color(red: 0.76, green: 0.30, blue: 0.06)
        }
        return Color(red: 0.38, green: 0.42, blue: 0.58)
    }

    private var accessibilityText: String {
        language.text(
            japanese: "\(step)回目 \(statusText)",
            english: "Round \(step), \(statusText)"
        )
    }
}

private enum PracticeCelebrationStyle: CaseIterable {
    case gold
    case blue
    case green
    case pink
    case sunrise

    static func random() -> PracticeCelebrationStyle {
        allCases.randomElement() ?? .gold
    }

    var systemImage: String {
        switch self {
        case .gold:
            return "star.circle.fill"
        case .blue:
            return "checkmark.seal.fill"
        case .green:
            return "trophy.fill"
        case .pink:
            return "sparkles"
        case .sunrise:
            return "sun.max.fill"
        }
    }

    var tint: Color {
        switch self {
        case .gold:
            return Color(red: 0.96, green: 0.66, blue: 0.05)
        case .blue:
            return Color(red: 0.16, green: 0.42, blue: 0.86)
        case .green:
            return Color(red: 0.20, green: 0.62, blue: 0.26)
        case .pink:
            return Color(red: 0.78, green: 0.28, blue: 0.72)
        case .sunrise:
            return Color(red: 0.92, green: 0.40, blue: 0.10)
        }
    }

    var burstVariant: CelebrationBurstVariant {
        switch self {
        case .gold:
            return .stars
        case .blue:
            return .rings
        case .green:
            return .leaves
        case .pink:
            return .sparkles
        case .sunrise:
            return .rays
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .gold:
            return language.text(japanese: "できた！", english: "Done!")
        case .blue:
            return language.text(japanese: "いいかんじ！", english: "Nice!")
        case .green:
            return language.text(japanese: "よく書けたね！", english: "Well done writing!")
        case .pink:
            return language.text(japanese: "すごい！", english: "Great!")
        case .sunrise:
            return language.text(japanese: "そのちょうし！", english: "Keep going!")
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .gold:
            return [Color(red: 1.0, green: 0.95, blue: 0.62), Color(red: 1.0, green: 0.82, blue: 0.28)]
        case .blue:
            return [Color(red: 0.82, green: 0.92, blue: 1.0), Color(red: 0.70, green: 0.82, blue: 1.0)]
        case .green:
            return [Color(red: 0.84, green: 1.0, blue: 0.74), Color(red: 0.72, green: 0.93, blue: 0.64)]
        case .pink:
            return [Color(red: 1.0, green: 0.83, blue: 0.96), Color(red: 0.92, green: 0.78, blue: 1.0)]
        case .sunrise:
            return [Color(red: 1.0, green: 0.88, blue: 0.58), Color(red: 1.0, green: 0.70, blue: 0.44)]
        }
    }
}

private struct PracticeWordCelebrationOverlay: View {
    var count: Int
    var total: Int
    var style: PracticeCelebrationStyle
    var language: AppLanguage
    var seed: Int
    var coinReward: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateCoin = false

    private var completedCount: Int {
        min(max(count, 1), max(total, 1))
    }

    private var remainingCount: Int {
        max(total - completedCount, 0)
    }

    var body: some View {
        ZStack {
            SparkleBurst(seed: seed, variant: style.burstVariant)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(style.tint.opacity(animateCoin ? 0 : 0.34), lineWidth: 8)
                        .frame(width: animateCoin ? 104 : 74, height: animateCoin ? 104 : 74)
                        .scaleEffect(reduceMotion ? 1 : (animateCoin ? 1.08 : 0.72))
                        .opacity(reduceMotion ? 0 : (animateCoin ? 0 : 1))

                    PracticeCoinView(tint: style.tint)
                        .frame(width: 78, height: 78)
                        .scaleEffect(reduceMotion ? 1 : (animateCoin ? 1 : 0.62))
                        .rotationEffect(.degrees(reduceMotion ? 0 : (animateCoin ? 0 : -18)))
                        .offset(y: reduceMotion ? 0 : (animateCoin ? 0 : -46))
                        .opacity(animateCoin ? 1 : 0)
                        .shadow(color: style.tint.opacity(0.34), radius: animateCoin ? 14 : 4, x: 0, y: animateCoin ? 8 : 2)

                    Text("+\(coinReward)")
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(style.tint)
                        .clipShape(Capsule())
                        .offset(x: 52, y: -34)
                        .scaleEffect(reduceMotion ? 1 : (animateCoin ? 1 : 0.5))
                        .opacity(animateCoin ? 1 : 0)
                }
                .frame(width: 140, height: 94)

                Text(style.title(language: language))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                PracticeProgressMeter(
                    completed: completedCount,
                    total: max(total, 1),
                    remaining: remainingCount,
                    language: language,
                    tint: style.tint
                )
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 42)
            .background(
                LinearGradient(
                    colors: style.backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.86), lineWidth: 3)
            )
            .shadow(color: style.tint.opacity(0.28), radius: 24, x: 0, y: 12)
        }
        .allowsHitTesting(false)
        .onAppear {
            animateCoin = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62).delay(0.05)) {
                animateCoin = true
            }
        }
    }
}

private struct PracticeCoinView: View {
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.22),
                            Color(red: 0.95, green: 0.62, blue: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.82), lineWidth: 4)
                .padding(7)

            Circle()
                .stroke(tint.opacity(0.46), lineWidth: 3)
                .padding(14)

            Image(systemName: "star.fill")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .orange.opacity(0.32), radius: 3, x: 0, y: 2)
        }
    }
}

private struct PracticeProgressMeter: View {
    var completed: Int
    var total: Int
    var remaining: Int
    var language: AppLanguage
    var tint: Color

    private var progress: Double {
        guard total > 0 else {
            return 0
        }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    private var dotCount: Int {
        min(max(total, 1), 8)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(language.text(japanese: "\(completed)こ れんしゅうできた", english: "\(completed) practiced"))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()

                Text(remaining == 0
                    ? language.text(japanese: "ぜんぶできた", english: "all done")
                    : language.text(japanese: "あと \(remaining)こ", english: "\(remaining) left")
                )
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(remaining == 0 ? Color(red: 0.20, green: 0.56, blue: 0.20) : Color(red: 0.13, green: 0.31, blue: 0.70))
            }
            .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.62))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint)
                        .frame(width: max(proxy.size.width * progress, 12))
                }
            }
            .frame(height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.82), lineWidth: 2)
            )

            HStack(spacing: 8) {
                ForEach(0..<dotCount, id: \.self) { dot in
                    let threshold = Int(ceil(Double(dot + 1) * Double(total) / Double(dotCount)))
                    Circle()
                        .fill(completed >= threshold ? tint : Color.white.opacity(0.72))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(completed >= threshold ? Color.white.opacity(0.86) : tint.opacity(0.30), lineWidth: 2)
                        )
                }
            }
        }
        .frame(width: 430)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TestTimerBar: View {
    var seconds: Int
    var totalSeconds: Int
    var language: AppLanguage

    private var progress: Double {
        guard totalSeconds > 0 else {
            return 0
        }
        return min(max(Double(seconds) / Double(totalSeconds), 0), 1)
    }

    private var tint: Color {
        if seconds <= 5 {
            return Color(red: 0.90, green: 0.18, blue: 0.14)
        }
        if progress <= 0.45 {
            return Color(red: 0.96, green: 0.58, blue: 0.12)
        }
        return Color(red: 0.18, green: 0.58, blue: 0.28)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                Text(language.text(japanese: "のこり", english: "left"))
                Text("\(max(seconds, 0))")
                    .monospacedDigit()
                Text(language.text(japanese: "秒", english: "s"))
            }
            .font(.headline.weight(.bold))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.88, green: 0.92, blue: 0.98))

                    RoundedRectangle(cornerRadius: 5)
                        .fill(tint)
                        .frame(width: max(proxy.size.width * progress, 8))
                        .animation(.linear(duration: 0.22), value: seconds)
                }
            }
            .frame(height: 10)
        }
        .foregroundStyle(seconds <= 5 ? Color(red: 0.82, green: 0.08, blue: 0.07) : Color(red: 0.20, green: 0.22, blue: 0.28))
        .frame(width: 230, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.76, green: 0.82, blue: 0.92), lineWidth: 1)
        )
        .accessibilityLabel(language.text(japanese: "残り \(max(seconds, 0)) 秒", english: "\(max(seconds, 0)) seconds left"))
    }
}

private enum SessionButtonStyleKind {
    case primary
    case secondary
    case finish
}

private struct CanvasEditControls: View {
    var language: AppLanguage
    var canUndo: Bool
    var canClear: Bool
    var undo: () -> Void
    var clearAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CanvasEditButton(
                title: language.text(japanese: "1つもどす", english: "Undo"),
                systemImage: "arrow.uturn.backward",
                isEnabled: canUndo,
                action: undo
            )

            CanvasEditButton(
                title: language.text(japanese: "ぜんぶ消す", english: "Clear All"),
                systemImage: "eraser.fill",
                isEnabled: canClear,
                action: clearAll
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasEditButton: View {
    var title: String
    var systemImage: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .frame(width: 138)
                .foregroundStyle(isEnabled ? Color(red: 0.13, green: 0.34, blue: 0.75) : Color(red: 0.48, green: 0.54, blue: 0.62))
                .background(isEnabled ? Color(red: 0.91, green: 0.96, blue: 1.0) : Color(red: 0.94, green: 0.96, blue: 0.98))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isEnabled ? Color(red: 0.60, green: 0.76, blue: 0.96) : Color(red: 0.78, green: 0.84, blue: 0.90), lineWidth: 2)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .tapFeedback(scale: 0.94)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private enum PracticeButtonTapEffectStyle: CaseIterable {
    case goldPop
    case blueShower
    case pinkTwinkle
    case greenGlow
    case violetSpray
    case orangeComet
    case rainbowTrail
    case pearlDust
    case bigStar
    case sideBurst

    static func random() -> PracticeButtonTapEffectStyle {
        allCases.randomElement() ?? .goldPop
    }

    var tint: Color {
        switch self {
        case .goldPop:
            return Color(red: 0.95, green: 0.70, blue: 0.08)
        case .blueShower:
            return Color(red: 0.22, green: 0.62, blue: 0.96)
        case .pinkTwinkle:
            return Color(red: 0.95, green: 0.34, blue: 0.76)
        case .greenGlow:
            return Color(red: 0.24, green: 0.72, blue: 0.35)
        case .violetSpray:
            return Color(red: 0.52, green: 0.38, blue: 0.88)
        case .orangeComet:
            return Color(red: 0.98, green: 0.56, blue: 0.12)
        case .rainbowTrail:
            return Color(red: 0.28, green: 0.64, blue: 0.96)
        case .pearlDust:
            return Color.white
        case .bigStar:
            return Color(red: 1.0, green: 0.76, blue: 0.10)
        case .sideBurst:
            return Color(red: 0.42, green: 0.76, blue: 0.95)
        }
    }

    var accent: Color {
        switch self {
        case .goldPop:
            return Color(red: 1.0, green: 0.88, blue: 0.28)
        case .blueShower:
            return Color(red: 0.72, green: 0.88, blue: 1.0)
        case .pinkTwinkle:
            return Color(red: 1.0, green: 0.74, blue: 0.92)
        case .greenGlow:
            return Color(red: 0.78, green: 0.95, blue: 0.38)
        case .violetSpray:
            return Color(red: 0.92, green: 0.80, blue: 1.0)
        case .orangeComet:
            return Color(red: 1.0, green: 0.82, blue: 0.26)
        case .rainbowTrail:
            return Color(red: 0.96, green: 0.42, blue: 0.62)
        case .pearlDust:
            return Color(red: 1.0, green: 0.90, blue: 0.55)
        case .bigStar:
            return Color(red: 0.98, green: 0.52, blue: 0.12)
        case .sideBurst:
            return Color(red: 1.0, green: 0.78, blue: 0.24)
        }
    }

    func scale(active: Bool, reduceMotion: Bool) -> CGFloat {
        guard active, !reduceMotion else {
            return 1
        }
        return self == .bigStar ? 1.04 : 1.02
    }

    func rotation(active: Bool, reduceMotion: Bool) -> Double {
        0
    }

    func yOffset(active: Bool, reduceMotion: Bool) -> CGFloat {
        0
    }

    var particles: [ButtonSparkleParticle] {
        switch self {
        case .goldPop:
            return [
                .init(startX: 0.48, startY: 0.45, dx: -82, dy: -54, size: 18, delay: 0.00, symbol: "sparkles", color: tint, rotation: -22),
                .init(startX: 0.52, startY: 0.46, dx: -24, dy: -72, size: 24, delay: 0.03, symbol: "star.fill", color: accent, rotation: 18),
                .init(startX: 0.56, startY: 0.48, dx: 74, dy: -48, size: 18, delay: 0.06, symbol: "sparkle", color: tint, rotation: 28),
                .init(startX: 0.50, startY: 0.54, dx: 28, dy: 42, size: 15, delay: 0.08, symbol: "sparkles", color: accent, rotation: -12)
            ]
        case .blueShower:
            return [
                .init(startX: 0.30, startY: 0.40, dx: -48, dy: -68, size: 17, delay: 0.01, symbol: "sparkle", color: accent, rotation: -20),
                .init(startX: 0.45, startY: 0.42, dx: -8, dy: -82, size: 22, delay: 0.04, symbol: "sparkles", color: tint, rotation: 12),
                .init(startX: 0.58, startY: 0.43, dx: 42, dy: -74, size: 16, delay: 0.07, symbol: "star.fill", color: accent, rotation: 24),
                .init(startX: 0.72, startY: 0.46, dx: 70, dy: -42, size: 15, delay: 0.10, symbol: "sparkle", color: tint, rotation: -18)
            ]
        case .pinkTwinkle:
            return [
                .init(startX: 0.44, startY: 0.45, dx: -70, dy: -36, size: 17, delay: 0.00, symbol: "sparkles", color: tint, rotation: -24),
                .init(startX: 0.52, startY: 0.44, dx: 0, dy: -78, size: 20, delay: 0.03, symbol: "sparkle", color: accent, rotation: 16),
                .init(startX: 0.58, startY: 0.48, dx: 76, dy: -34, size: 17, delay: 0.06, symbol: "sparkles", color: tint, rotation: 24),
                .init(startX: 0.52, startY: 0.56, dx: -18, dy: 44, size: 15, delay: 0.09, symbol: "star.fill", color: accent, rotation: -12)
            ]
        case .greenGlow:
            return [
                .init(startX: 0.34, startY: 0.46, dx: -58, dy: -48, size: 16, delay: 0.00, symbol: "sparkle", color: tint, rotation: -16),
                .init(startX: 0.46, startY: 0.44, dx: -12, dy: -74, size: 20, delay: 0.04, symbol: "sparkles", color: accent, rotation: 18),
                .init(startX: 0.61, startY: 0.45, dx: 48, dy: -60, size: 16, delay: 0.08, symbol: "star.fill", color: tint, rotation: 28),
                .init(startX: 0.68, startY: 0.55, dx: 78, dy: 26, size: 14, delay: 0.11, symbol: "sparkle", color: accent, rotation: -24)
            ]
        case .violetSpray:
            return [
                .init(startX: 0.26, startY: 0.50, dx: -72, dy: -18, size: 16, delay: 0.00, symbol: "sparkles", color: tint, rotation: -18),
                .init(startX: 0.42, startY: 0.45, dx: -34, dy: -64, size: 18, delay: 0.03, symbol: "sparkle", color: accent, rotation: 18),
                .init(startX: 0.58, startY: 0.45, dx: 34, dy: -64, size: 18, delay: 0.06, symbol: "sparkles", color: tint, rotation: -24),
                .init(startX: 0.74, startY: 0.50, dx: 72, dy: -18, size: 16, delay: 0.09, symbol: "star.fill", color: accent, rotation: 26)
            ]
        case .orangeComet:
            return [
                .init(startX: 0.34, startY: 0.58, dx: -60, dy: 22, size: 14, delay: 0.00, symbol: "sparkle", color: accent, rotation: -16),
                .init(startX: 0.46, startY: 0.48, dx: -12, dy: -62, size: 17, delay: 0.02, symbol: "sparkles", color: tint, rotation: 16),
                .init(startX: 0.56, startY: 0.44, dx: 46, dy: -82, size: 22, delay: 0.05, symbol: "star.fill", color: accent, rotation: 34),
                .init(startX: 0.62, startY: 0.48, dx: 92, dy: -42, size: 16, delay: 0.08, symbol: "sparkle", color: tint, rotation: 28)
            ]
        case .rainbowTrail:
            return [
                .init(startX: 0.22, startY: 0.48, dx: -42, dy: -34, size: 14, delay: 0.00, symbol: "sparkle", color: Color(red: 0.28, green: 0.64, blue: 0.96), rotation: -22),
                .init(startX: 0.38, startY: 0.47, dx: -20, dy: -68, size: 17, delay: 0.03, symbol: "sparkles", color: Color(red: 0.40, green: 0.78, blue: 0.38), rotation: 14),
                .init(startX: 0.54, startY: 0.45, dx: 24, dy: -76, size: 19, delay: 0.06, symbol: "star.fill", color: Color(red: 1.0, green: 0.74, blue: 0.18), rotation: 24),
                .init(startX: 0.70, startY: 0.48, dx: 62, dy: -36, size: 15, delay: 0.09, symbol: "sparkle", color: Color(red: 0.96, green: 0.42, blue: 0.62), rotation: -16)
            ]
        case .pearlDust:
            return [
                .init(startX: 0.40, startY: 0.44, dx: -54, dy: -44, size: 15, delay: 0.00, symbol: "sparkle", color: accent, rotation: -14),
                .init(startX: 0.49, startY: 0.45, dx: -12, dy: -70, size: 17, delay: 0.04, symbol: "sparkles", color: tint, rotation: 16),
                .init(startX: 0.57, startY: 0.45, dx: 44, dy: -58, size: 15, delay: 0.08, symbol: "sparkle", color: accent, rotation: 20),
                .init(startX: 0.64, startY: 0.56, dx: 66, dy: 20, size: 14, delay: 0.11, symbol: "star.fill", color: Color(red: 0.76, green: 0.90, blue: 1.0), rotation: -18)
            ]
        case .bigStar:
            return [
                .init(startX: 0.50, startY: 0.46, dx: 0, dy: -68, size: 30, delay: 0.00, symbol: "star.fill", color: tint, rotation: 18),
                .init(startX: 0.42, startY: 0.50, dx: -72, dy: -26, size: 17, delay: 0.05, symbol: "sparkles", color: accent, rotation: -18),
                .init(startX: 0.58, startY: 0.50, dx: 72, dy: -26, size: 17, delay: 0.07, symbol: "sparkle", color: tint, rotation: 22),
                .init(startX: 0.50, startY: 0.58, dx: 0, dy: 44, size: 14, delay: 0.10, symbol: "sparkles", color: accent, rotation: -10)
            ]
        case .sideBurst:
            return [
                .init(startX: 0.18, startY: 0.36, dx: -54, dy: -30, size: 15, delay: 0.00, symbol: "sparkle", color: tint, rotation: -20),
                .init(startX: 0.20, startY: 0.64, dx: -58, dy: 22, size: 15, delay: 0.04, symbol: "sparkles", color: accent, rotation: 18),
                .init(startX: 0.82, startY: 0.36, dx: 54, dy: -30, size: 15, delay: 0.02, symbol: "star.fill", color: accent, rotation: 22),
                .init(startX: 0.80, startY: 0.64, dx: 58, dy: 22, size: 15, delay: 0.06, symbol: "sparkle", color: tint, rotation: -16)
            ]
        }
    }
}

private struct SessionControlButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var systemImage: String
    var style: SessionButtonStyleKind
    var minWidth: CGFloat = 190
    var horizontalPadding: CGFloat = 24
    var funTapAnimations = false
    var canPlayFunTapAnimation: () -> Bool = { true }
    var action: () -> Void
    @State private var tapEffectStyle = PracticeButtonTapEffectStyle.goldPop
    @State private var tapEffectActive = false
    @State private var tapEffectSeed = 0
    @State private var isWaitingForFunTapAction = false

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
        Button {
            handleTap()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .frame(minWidth: minWidth)
                .padding(.vertical, 15)
                .padding(.horizontal, horizontalPadding)
                .foregroundStyle(foregroundColor)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: style == .primary ? 0 : 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .scaleEffect(tapEffectStyle.scale(active: tapEffectActive, reduceMotion: reduceMotion))
        .rotationEffect(.degrees(tapEffectStyle.rotation(active: tapEffectActive, reduceMotion: reduceMotion)))
        .offset(y: tapEffectStyle.yOffset(active: tapEffectActive, reduceMotion: reduceMotion))
        .overlay {
            if funTapAnimations && tapEffectActive {
                PracticeButtonTapEffectOverlay(
                    style: tapEffectStyle,
                    seed: tapEffectSeed
                )
            }
        }
        .shadow(color: shadowColor, radius: style == .finish ? 12 : 8, x: 0, y: 5)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: tapEffectActive)
        .disabled(isWaitingForFunTapAction)
    }

    private func handleTap() {
        guard !isWaitingForFunTapAction else {
            return
        }

        guard funTapAnimations, canPlayFunTapAnimation(), !reduceMotion else {
            action()
            return
        }

        isWaitingForFunTapAction = true
        triggerFunTapAnimationIfNeeded()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            isWaitingForFunTapAction = false
            action()
        }
    }

    private func triggerFunTapAnimationIfNeeded() {
        guard funTapAnimations, canPlayFunTapAnimation(), !reduceMotion else {
            return
        }

        tapEffectStyle = PracticeButtonTapEffectStyle.random()
        tapEffectSeed += 1
        let currentSeed = tapEffectSeed
        tapEffectActive = false

        withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
            tapEffectActive = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard tapEffectSeed == currentSeed else {
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                tapEffectActive = false
            }
        }
    }
}

private struct ButtonSparkleParticle {
    var startX: CGFloat
    var startY: CGFloat
    var dx: CGFloat
    var dy: CGFloat
    var size: CGFloat
    var delay: Double
    var symbol: String
    var color: Color
    var rotation: Double
}

private struct PracticeButtonTapEffectOverlay: View {
    var style: PracticeButtonTapEffectStyle
    var seed: Int
    @State private var active = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(style.particles.enumerated()), id: \.offset) { _, particle in
                    Image(systemName: particle.symbol)
                        .font(.system(size: particle.size, weight: .heavy))
                        .foregroundStyle(particle.color)
                        .shadow(color: particle.color.opacity(0.28), radius: 4, x: 0, y: 2)
                        .scaleEffect(active ? 1.16 : 0.24)
                        .rotationEffect(.degrees(active ? particle.rotation : -particle.rotation * 0.25))
                        .opacity(active ? 0 : 1)
                        .position(
                            x: proxy.size.width * particle.startX + (active ? particle.dx : 0),
                            y: proxy.size.height * particle.startY + (active ? particle.dy : 0)
                        )
                        .animation(.easeOut(duration: 0.42).delay(particle.delay), value: active)
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: style.tint.opacity(0.42), radius: 5, x: 0, y: 2)
                    .scaleEffect(active ? 1.28 : 0.52)
                    .opacity(active ? 0 : 0.94)
                    .position(x: proxy.size.width - 28, y: proxy.size.height * 0.50)
                    .animation(.easeOut(duration: 0.28), value: active)
            }
        }
        .id(seed)
        .allowsHitTesting(false)
        .onAppear {
            active = false
            Task { @MainActor in
                await Task.yield()
                active = true
            }
        }
    }
}

private struct ExampleHintView: View {
    var word: String
    var language: AppLanguage

    // WordBank は同梱SQLiteへの同期参照（単一行・高速）なので、その場で引く。
    // ※ @State + onAppear だと、初期は中身が空で onAppear が発火せずヒントが出ないことがある。
    private var meaning: String? { WordBank.shared.japanese(for: word) }
    private var example: WordExample? { WordBank.shared.examples(for: word, limit: 1).first }

    var body: some View {
        Group {
            if meaning != nil || example != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let meaning {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(language.text(japanese: "いみ", english: "Meaning"), systemImage: "character.book.closed.fill")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.40))
                            Text(meaning)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.12, green: 0.24, blue: 0.45))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let example {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(language.text(japanese: "れいぶん", english: "Example"), systemImage: "text.quote")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color(red: 0.45, green: 0.32, blue: 0.66))
                            Text(example.en)
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.12, green: 0.24, blue: 0.45))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(example.ja)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.80, green: 0.84, blue: 0.95), lineWidth: 1)
                )
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var samples: [PracticeSample]
    var language: AppLanguage
    var onStartTest: (() -> Void)?
    var onPracticeRetry: (([String]) -> Void)?
    var onDone: () -> Void

    @State private var showingCelebration = false
    @State private var celebrationSeed = 0
    @State private var testButtonPulse = false
    @State private var selectedRetryWords = Set<String>()

    private var sampleGroups: [PracticeSampleGroup] {
        groupedPracticeSamples(samples)
    }

    private var writtenSummary: String {
        language.text(
            japanese: "\(sampleGroups.count)こ・\(samples.count)かい書きました",
            english: "\(sampleGroups.count) words ・ \(samples.count) writes"
        )
    }

    private var selectedRetryWordsInOrder: [String] {
        sampleGroups.map(\.word).filter { selectedRetryWords.contains($0) }
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
                                PracticeSampleGroupReviewCard(
                                    group: group,
                                    language: language,
                                    canSelect: onPracticeRetry != nil,
                                    isSelected: selectedRetryWords.contains(group.word)
                                ) {
                                    toggleRetrySelection(group.word)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack(spacing: 16) {
                    if let onPracticeRetry {
                        PracticeRetrySelectedButton(
                            count: selectedRetryWords.count,
                            language: language,
                            disabled: selectedRetryWords.isEmpty
                        ) {
                            onPracticeRetry(selectedRetryWordsInOrder)
                        }
                    } else {
                        Color.clear
                            .frame(width: 220)
                    }

                    Spacer(minLength: 0)

                    if let onStartTest {
                        PracticeStartTestButton(
                            language: language,
                            isAnimating: testButtonPulse,
                            reduceMotion: reduceMotion,
                            action: onStartTest
                        )
                    }

                    Spacer(minLength: 0)

                    PracticeReviewHomeButton(language: language, action: onDone)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
                    testButtonPulse = true
                }
            }
            guard !samples.isEmpty else {
                return
            }
            celebrationSeed += 1
            withAnimation(.easeOut(duration: 0.12)) {
                showingCelebration = true
            }
        }
    }

    private func toggleRetrySelection(_ word: String) {
        guard onPracticeRetry != nil else {
            return
        }

        if selectedRetryWords.contains(word) {
            selectedRetryWords.remove(word)
        } else {
            selectedRetryWords.insert(word)
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

private struct PracticeRetrySelectedButton: View {
    var count: Int
    var language: AppLanguage
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: disabled ? "hand.tap.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 20, weight: .heavy))
                Text(disabled
                     ? language.text(japanese: "えらんで練習", english: "Pick to Retry")
                     : language.text(japanese: "\(count)こ もう一回", english: "Retry \(count)")
                )
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }
            .foregroundStyle(disabled ? Color(red: 0.48, green: 0.42, blue: 0.58) : .white)
            .frame(width: 220)
            .padding(.vertical, 15)
            .background(disabled ? Color(red: 0.94, green: 0.91, blue: 0.98) : Color(red: 0.48, green: 0.30, blue: 0.76))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(disabled ? Color(red: 0.75, green: 0.68, blue: 0.86) : Color(red: 0.38, green: 0.22, blue: 0.64), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .disabled(disabled)
        .accessibilityLabel(language.text(japanese: "\(count)個をもう一回練習", english: "Retry \(count) words"))
    }
}

private struct PracticeStartTestButton: View {
    var language: AppLanguage
    var isAnimating: Bool
    var reduceMotion: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(reduceMotion ? 0.22 : (isAnimating ? 0.28 : 0.18)))
                        .frame(width: 42, height: 42)
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 22, weight: .heavy))
                        .offset(y: reduceMotion ? 0 : (isAnimating ? -1.5 : 1))
                }

                Text(language.text(japanese: "テストしてみる", english: "Try the Test"))
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .heavy))
                    .offset(x: reduceMotion ? 0 : (isAnimating ? 3 : 0))
                    .opacity(reduceMotion ? 0.86 : (isAnimating ? 1 : 0.72))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 300)
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.68, blue: 0.28),
                            Color(red: 0.08, green: 0.48, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    LinearGradient(
                        colors: [
                            .white.opacity(reduceMotion ? 0.08 : (isAnimating ? 0.16 : 0.06)),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.green.opacity(reduceMotion ? 0.18 : (isAnimating ? 0.25 : 0.16)), radius: reduceMotion ? 8 : (isAnimating ? 12 : 7), x: 0, y: reduceMotion ? 7 : (isAnimating ? 8 : 6))
            .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.012 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
        .accessibilityLabel(language.text(japanese: "テストしてみる", english: "Try the test"))
    }
}

private struct PracticeReviewHomeButton: View {
    var language: AppLanguage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(language.text(japanese: "ホームにもどる", english: "Back Home"), systemImage: "house.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.13, green: 0.32, blue: 0.73))
                .frame(width: 220)
                .padding(.vertical, 15)
                .background(.white.opacity(0.84))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.70, green: 0.80, blue: 0.94), lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .tapFeedback()
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

    private var attemptColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top),
            GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top)
        ]
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
                    Label(language.text(japanese: "アプリのテスト結果", english: "App Test Results"), systemImage: "checklist")
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
                        description: Text(language.text(japanese: "アプリのテストを進めるとここに表示されます。", english: "App test answers will appear here."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        LazyVGrid(columns: attemptColumns, alignment: .leading, spacing: 12) {
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
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderedProminent)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .tapFeedback()
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attempt.word)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Label(
                    attempt.decision.label(language: language),
                    systemImage: isCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(isCorrect ? Color.green : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            if let drawingData = attempt.drawingData {
                PracticeDrawingPreview(drawingData: drawingData, canvasSize: attempt.canvasSize)
                    .frame(height: 156)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private var reservesRubyLine: Bool {
        segments.contains { $0.kind == .ruby }
    }

    var body: some View {
        RubyFlowLayout(horizontalSpacing: 0, verticalSpacing: 4, maxLines: maxLines) {
            ForEach(segments) { segment in
                RubyPromptSegmentView(
                    segment: segment,
                    baseFontSize: baseFontSize,
                    rubyFontSize: rubyFontSize,
                    baseColor: baseColor,
                    rubyColor: rubyColor,
                    reservesRubyLine: reservesRubyLine
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
    var reservesRubyLine: Bool

    var body: some View {
        switch segment.kind {
        case .plain:
            if reservesRubyLine {
                VStack(spacing: -1) {
                    Text(" ")
                        .font(.system(size: rubyFontSize, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .hidden()
                    Text(segment.base)
                        .font(.system(size: baseFontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(baseColor)
                        .lineLimit(1)
                }
                .fixedSize()
            } else {
                Text(segment.base)
                    .font(.system(size: baseFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(baseColor)
                    .fixedSize()
            }
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
        // ふりがなは直前の漢字（Han）だけに付ける。かな（助詞「を」など）は base に含めない。
        if !character.isHan {
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
    var canSelect = false
    var isSelected = false
    var onToggle: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 9) {
                    if canSelect {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(isSelected ? Color(red: 0.48, green: 0.30, blue: 0.76) : Color(red: 0.58, green: 0.62, blue: 0.70))
                    }

                    Text(group.word)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.27, blue: 0.62))
                }
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
                .padding(.top, 5)
                .padding(.bottom, 2)
            }
        }
        .padding(12)
        .background(isSelected ? Color(red: 0.95, green: 0.90, blue: 1.0) : .white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color(red: 0.48, green: 0.30, blue: 0.76) : Color(red: 0.72, green: 0.82, blue: 0.96), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if canSelect {
                onToggle()
            }
        }
        .accessibilityAddTraits(canSelect && isSelected ? .isSelected : [])
    }
}

private struct PracticeSampleAttemptTile: View {
    var sample: PracticeSample
    var round: Int
    var language: AppLanguage
    private let tileWidth: CGFloat = 248
    private let previewHeight: CGFloat = 176
    private var previewWidth: CGFloat {
        tileWidth - 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .heavy))
                Text(language.text(japanese: "\(round)かいめ", english: "Round \(round)"))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(red: 0.48, green: 0.30, blue: 0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(red: 0.94, green: 0.90, blue: 1.0))
            .clipShape(Capsule())
            .frame(minHeight: 32, alignment: .center)

            PracticeDrawingPreview(
                drawingData: sample.drawingData,
                canvasSize: sample.canvasSize,
                horizontalPadding: 56,
                topPadding: 180,
                bottomPadding: 230,
                horizontalAlignment: .leftAnchored,
                targetAspectRatio: previewWidth / previewHeight,
                rightPadding: 96
            )
            .frame(width: previewWidth, height: previewHeight)
            .clipped()
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
        }
        .frame(width: tileWidth, alignment: .leading)
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
    var canvasSize: DrawingCanvasSize?
    var horizontalPadding: CGFloat = 80
    var topPadding: CGFloat = 90
    var bottomPadding: CGFloat = 150
    var horizontalAlignment: PKDrawing.PreviewHorizontalAlignment = .centered
    var minimumAspectRatio: CGFloat?
    var targetAspectRatio: CGFloat?
    var rightPadding: CGFloat?

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
        CGSize(width: proposal.width ?? 228, height: proposal.height ?? 176)
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if let drawing = try? PKDrawing(data: drawingData) {
            imageView.image = drawing.previewImage(
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                bottomPadding: bottomPadding,
                horizontalAlignment: horizontalAlignment,
                minimumAspectRatio: minimumAspectRatio,
                targetAspectRatio: targetAspectRatio,
                canvasSize: canvasSize,
                rightPadding: rightPadding
            )
        } else {
            imageView.image = nil
        }
    }
}

private enum CelebrationBurstVariant {
    case sparkles
    case stars
    case rings
    case leaves
    case rays
}

private struct SparkleBurst: View {
    var seed: Int
    var variant: CelebrationBurstVariant = .sparkles
    @State private var animate = false

    private var items: [SparkleItem] {
        switch variant {
        case .sparkles:
            return [
                SparkleItem(x: -220, y: -120, size: 34, delay: 0.00, color: Color(red: 0.96, green: 0.70, blue: 0.08), symbol: "sparkles"),
                SparkleItem(x: 210, y: -110, size: 28, delay: 0.04, color: Color(red: 0.28, green: 0.67, blue: 0.92), symbol: "star.fill"),
                SparkleItem(x: -160, y: 90, size: 26, delay: 0.08, color: Color(red: 0.39, green: 0.73, blue: 0.32), symbol: "sparkle"),
                SparkleItem(x: 170, y: 115, size: 32, delay: 0.02, color: Color(red: 0.93, green: 0.33, blue: 0.22), symbol: "sparkles"),
                SparkleItem(x: -60, y: -160, size: 24, delay: 0.10, color: Color(red: 0.62, green: 0.43, blue: 0.84), symbol: "star.fill"),
                SparkleItem(x: 70, y: -150, size: 22, delay: 0.12, color: Color(red: 0.98, green: 0.78, blue: 0.18), symbol: "sparkle"),
                SparkleItem(x: -20, y: 145, size: 28, delay: 0.06, color: Color(red: 0.18, green: 0.58, blue: 0.86), symbol: "star.fill")
            ]
        case .stars:
            return [
                SparkleItem(x: -230, y: -130, size: 38, delay: 0.00, color: Color(red: 1.0, green: 0.76, blue: 0.10), symbol: "star.fill"),
                SparkleItem(x: 220, y: -135, size: 34, delay: 0.04, color: Color(red: 1.0, green: 0.55, blue: 0.06), symbol: "star.circle.fill"),
                SparkleItem(x: -210, y: 120, size: 30, delay: 0.09, color: Color(red: 0.95, green: 0.30, blue: 0.18), symbol: "star.fill"),
                SparkleItem(x: 185, y: 130, size: 32, delay: 0.02, color: Color(red: 0.42, green: 0.68, blue: 0.96), symbol: "sparkles"),
                SparkleItem(x: -20, y: -170, size: 26, delay: 0.12, color: Color(red: 0.62, green: 0.43, blue: 0.84), symbol: "star.fill")
            ]
        case .rings:
            return [
                SparkleItem(x: -220, y: -110, size: 34, delay: 0.00, color: Color(red: 0.18, green: 0.48, blue: 0.94), symbol: "circle.circle.fill"),
                SparkleItem(x: 220, y: -105, size: 30, delay: 0.05, color: Color(red: 0.25, green: 0.70, blue: 0.96), symbol: "checkmark.seal.fill"),
                SparkleItem(x: -175, y: 125, size: 28, delay: 0.08, color: Color(red: 0.58, green: 0.45, blue: 0.94), symbol: "circle.circle.fill"),
                SparkleItem(x: 165, y: 130, size: 32, delay: 0.03, color: Color(red: 0.12, green: 0.58, blue: 0.78), symbol: "sparkles"),
                SparkleItem(x: 0, y: -170, size: 24, delay: 0.11, color: Color(red: 0.32, green: 0.48, blue: 0.92), symbol: "checkmark.seal.fill")
            ]
        case .leaves:
            return [
                SparkleItem(x: -210, y: -115, size: 34, delay: 0.00, color: Color(red: 0.20, green: 0.62, blue: 0.24), symbol: "leaf.fill"),
                SparkleItem(x: 210, y: -120, size: 30, delay: 0.06, color: Color(red: 0.46, green: 0.75, blue: 0.22), symbol: "trophy.fill"),
                SparkleItem(x: -170, y: 115, size: 28, delay: 0.08, color: Color(red: 0.70, green: 0.82, blue: 0.18), symbol: "leaf.fill"),
                SparkleItem(x: 175, y: 120, size: 32, delay: 0.02, color: Color(red: 0.16, green: 0.48, blue: 0.20), symbol: "sparkles"),
                SparkleItem(x: -10, y: -170, size: 25, delay: 0.13, color: Color(red: 0.94, green: 0.70, blue: 0.08), symbol: "star.fill")
            ]
        case .rays:
            return [
                SparkleItem(x: -215, y: -125, size: 36, delay: 0.00, color: Color(red: 0.96, green: 0.42, blue: 0.08), symbol: "sun.max.fill"),
                SparkleItem(x: 215, y: -120, size: 30, delay: 0.05, color: Color(red: 1.0, green: 0.74, blue: 0.12), symbol: "sparkles"),
                SparkleItem(x: -170, y: 120, size: 28, delay: 0.08, color: Color(red: 0.88, green: 0.24, blue: 0.20), symbol: "sun.max.fill"),
                SparkleItem(x: 180, y: 125, size: 32, delay: 0.03, color: Color(red: 0.40, green: 0.64, blue: 0.94), symbol: "star.fill"),
                SparkleItem(x: 0, y: -170, size: 26, delay: 0.12, color: Color(red: 0.98, green: 0.82, blue: 0.20), symbol: "sparkles")
            ]
        }
    }

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
    var id: String {
        "\(symbol)-\(Int(x))-\(Int(y))-\(String(format: "%.2f", delay))"
    }

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
