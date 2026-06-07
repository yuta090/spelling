import PencilKit
import SwiftUI

struct TestSessionView: View {
    private let words = [
        SpellingWord(text: "cat"),
        SpellingWord(text: "dog"),
        SpellingWord(text: "friend"),
        SpellingWord(text: "school")
    ]

    @StateObject private var speech = SpeechPlayer()
    @State private var index = 0
    @State private var drawing = PKDrawing()
    @State private var decision: GradeDecision?
    @State private var candidates: [OCRCandidate] = []
    @State private var isChecking = false

    private var currentWord: SpellingWord {
        words[index]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                GuidedWritingCanvas(drawing: $drawing, mode: .test)
                controls
                resultPanel
            }
            .padding(28)
            .navigationTitle("Today's Test")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Parent") {}
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Word \(index + 1) of \(words.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Listen, write, then tap Done.")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Button {
                speech.speak(currentWord.text)
            } label: {
                Label("Play", systemImage: "speaker.wave.2.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tapFeedback()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                drawing = PKDrawing()
                decision = nil
                candidates = []
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .tapFeedback()

            Spacer()

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
            .tapFeedback()
            .disabled(isChecking)

            Button {
                index = min(index + 1, words.count - 1)
                drawing = PKDrawing()
                decision = nil
                candidates = []
            } label: {
                Label("Next", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)
            .tapFeedback()
            .disabled(index == words.count - 1)
        }
        .font(.title3)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let decision {
            VStack(alignment: .leading, spacing: 8) {
                Text(decision.rawValue)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func checkAnswer() {
        isChecking = true
        let image = drawing.spellingImage(defaultBounds: CGRect(x: 0, y: 0, width: 1000, height: 260))

        Task {
            defer { isChecking = false }
            do {
                let recognized = try await VisionSpellingOCR().recognize(image, expected: currentWord.text)
                candidates = recognized
                let hasInk = !drawing.bounds.isNull && !drawing.bounds.isEmpty
                decision = OCRGrader().grade(candidates: recognized, expected: currentWord.text, hasInk: hasInk)
            } catch {
                candidates = []
                let hasInk = !drawing.bounds.isNull && !drawing.bounds.isEmpty
                decision = hasInk ? .needsReview : .rewrite
            }
        }
    }
}

#Preview {
    TestSessionView()
}
