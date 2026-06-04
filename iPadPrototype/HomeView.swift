import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's Spelling")
                            .font(.largeTitle.weight(.bold))
                        Text("\(model.words.count) words")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Parent") {
                        showingParent = true
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 16) {
                    HomeActionButton(title: "Practice", systemImage: "pencil.and.scribble") {
                        activeMode = .practice
                    }
                    HomeActionButton(title: "Test", systemImage: "checkmark.circle.fill") {
                        activeMode = .test
                    }
                    HomeActionButton(title: "Review", systemImage: "arrow.counterclockwise.circle.fill", disabled: model.reviewWords.isEmpty) {
                        activeMode = .review
                    }
                }

                ResultsSummaryView()

                WordPreviewList(words: model.words)
                Spacer(minLength: 0)
            }
            .padding(28)
            .navigationDestination(item: $activeMode) { mode in
                SpellingSessionView(
                    mode: mode,
                    words: mode == .review ? model.reviewWords : model.words
                )
            }
            .sheet(isPresented: $showingParent) {
                ParentDashboardView()
                    .environmentObject(model)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingResults = true
                    } label: {
                        Label("Results", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                ResultsView()
                    .environmentObject(model)
            }
        }
    }
}

private struct HomeActionButton: View {
    var title: String
    var systemImage: String
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .semibold))
                Text(title)
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(disabled ? Color.gray.opacity(0.45) : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct ResultsSummaryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            SummaryMetric(title: "Today", value: "\(model.todaysCorrectCount)/\(model.todaysAttempts.count)")
            SummaryMetric(title: "Review", value: "\(model.reviewWords.count)")
            SummaryMetric(title: "Attempts", value: "\(model.todaysAttempts.count)")
        }
    }
}

private struct SummaryMetric: View {
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

private struct WordPreviewList: View {
    var words: [SpellingWord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Word List")
                .font(.title2.weight(.bold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(words) { word in
                    Text(word.text)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppModel())
}
