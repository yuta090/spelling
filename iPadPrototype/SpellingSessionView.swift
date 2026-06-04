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

    private var currentWord: SpellingWord {
        guard !words.isEmpty else {
            return SpellingWord(text: "")
        }
        return words[min(index, max(words.count - 1, 0))]
    }

    var body: some View {
        VStack(spacing: 22) {
            header

            if mode.showsWord {
                Text(currentWord.text)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GuidedWritingCanvas(drawing: $drawing, mode: mode.canvasMode)
                .id(canvasResetID)

            controls
            resultPanel
            Spacer(minLength: 0)
        }
        .padding(28)
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    dismiss()
                }
            }
        }
        .onAppear {
            resetTimer()
            startTimerIfNeeded()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Word \(index + 1) of \(words.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(mode == .test ? "Listen and write." : "Listen, look, and write.")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Button {
                playWord()
            } label: {
                Label("Play", systemImage: "speaker.wave.2.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(mode == .test && replayCount >= model.settings.maxReplays)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                clearCanvas()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .buttonStyle(.bordered)

            Spacer()

            if mode == .test {
                Text("\(remainingSeconds)s")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(remainingSeconds <= 5 ? .red : .secondary)
                    .frame(minWidth: 70)
            }

            Button {
                checkAnswer()
            } label: {
                if isChecking {
                    ProgressView()
                } else {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)

            Button {
                moveNext()
            } label: {
                Label(index == words.count - 1 ? "Finish" : "Next", systemImage: index == words.count - 1 ? "flag.checkered" : "arrow.right")
            }
            .buttonStyle(.bordered)
        }
        .font(.title3)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let decision {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(decision.label)
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text(candidates.first?.text ?? "-")
                        .font(.title3.monospaced())
                        .foregroundStyle(.secondary)
                }

                if decision == .needsReview {
                    Text("Saved for parent review.")
                        .foregroundStyle(.secondary)
                } else if decision == .rewrite {
                    Text("Write it again with larger letters.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func clearCanvas() {
        drawing = PKDrawing()
        canvasResetID = UUID()
        decision = nil
        candidates = []
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

#Preview {
    NavigationStack {
        SpellingSessionView(mode: .practice, words: [SpellingWord(text: "cat")])
            .environmentObject(AppModel())
    }
}
