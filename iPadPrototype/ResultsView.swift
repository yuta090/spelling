import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ResultMetric(title: "Correct", value: "\(model.todaysCorrectCount)")
                    ResultMetric(title: "Today", value: "\(model.todaysAttempts.count)")
                    ResultMetric(title: "Review", value: "\(model.reviewWords.count)")
                }

                List {
                    ForEach(model.attempts.reversed()) { attempt in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attempt.word)
                                    .font(.title3.weight(.semibold))
                                Text("OCR: \(attempt.recognizedText.isEmpty ? "-" : attempt.recognizedText)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(attempt.decision.label)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
            .padding(24)
            .navigationTitle("Results")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset") {
                        model.resetResults()
                    }
                }
            }
        }
    }
}

private struct ResultMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ResultsView()
        .environmentObject(AppModel())
}
