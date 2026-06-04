import PencilKit
import SwiftUI

struct ParentDashboardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                ParentWordListPanel()
                    .tabItem {
                        Label("Words", systemImage: "list.bullet")
                    }

                TestSettingsPanel()
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }

                AnswerReviewPanel()
                    .tabItem {
                        Label("Review", systemImage: "checklist")
                    }
            }
            .navigationTitle("Parent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ParentWordListPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var rawWords = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextEditor(text: $rawWords)
                .font(.title3.monospaced())
                .frame(minHeight: 260)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    rawWords = model.words.map(\.text).joined(separator: "\n")
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    model.replaceWords(from: rawWords)
                } label: {
                    Label("Save Words", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalize(rawWords).isEmpty)
            }

            Text("Current: \(model.words.count) words")
                .font(.headline)
                .foregroundStyle(.secondary)

            List(model.words) { word in
                Text(word.text)
                    .font(.title3)
            }
            .listStyle(.plain)
        }
        .padding(24)
        .onAppear {
            rawWords = model.words.map(\.text).joined(separator: "\n")
        }
    }
}

private struct TestSettingsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Speech") {
                Picker("Language", selection: $model.settings.language) {
                    Text("US English").tag("en-US")
                    Text("UK English").tag("en-GB")
                }
                SliderSetting(title: "Speed", value: $model.settings.speechRate, range: 0.30...0.55, format: "%.2f")
                Stepper("Replays: \(model.settings.maxReplays)", value: $model.settings.maxReplays, in: 0...5)
            }

            Section("Test") {
                Stepper("Seconds per word: \(model.settings.secondsPerWord)", value: $model.settings.secondsPerWord, in: 10...90, step: 5)
            }

            Section("OCR grading") {
                SliderSetting(title: "Auto-correct confidence", value: $model.settings.autoCorrectConfidence, range: 0.60...0.98, format: "%.2f")
                SliderSetting(title: "Rewrite confidence", value: $model.settings.lowConfidence, range: 0.10...0.60, format: "%.2f")
                Text("Language correction is intentionally off for grading so spelling mistakes are not silently corrected.")
                    .foregroundStyle(.secondary)
            }
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
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct AnswerReviewPanel: View {
    @EnvironmentObject private var model: AppModel

    private var reviewAttempts: [SpellingAttempt] {
        Array(model.attempts
            .filter { $0.decision == .needsReview || $0.decision == .rewrite || $0.decision == .timeExpired }
            .reversed())
    }

    var body: some View {
        List {
            if reviewAttempts.isEmpty {
                Text("No answers need review.")
                    .foregroundStyle(.secondary)
            }

            ForEach(reviewAttempts) { attempt in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(attempt.word)
                                .font(.title2.weight(.bold))
                            Text("OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(attempt.decision.label)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if let drawingData = attempt.drawingData {
                        DrawingPreview(drawingData: drawingData)
                            .frame(height: 120)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                            )
                    }

                    HStack {
                        Button {
                            model.updateAttempt(attempt, decision: .autoCorrect)
                        } label: {
                            Label("Correct", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            model.updateAttempt(attempt, decision: .autoIncorrect)
                        } label: {
                            Label("Try Again", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.plain)
    }
}

private struct DrawingPreview: UIViewRepresentable {
    var drawingData: Data

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.isUserInteractionEnabled = false
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 7)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
    }
}

#Preview {
    ParentDashboardView()
        .environmentObject(AppModel())
}
