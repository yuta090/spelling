import SwiftUI

struct ParentWordListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rawWords = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("1行に1単語。意味や説明を出したい時は `friend | 友[とも]だち` のように書けます。")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $rawWords)
                    .font(.title3.monospaced())
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button {
                        rawWords = wordListEditorText(model.words)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        model.replaceWords(from: rawWords)
                        dismiss()
                    } label: {
                        Label("Save Words", systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parseWordListEntries(from: rawWords).isEmpty)
                }

                Text("Current: \(model.words.count) words")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                List(model.words) { word in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.text)
                            .font(.title3)
                        if !word.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Hint:")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                RubyPromptText(
                                    text: word.promptText,
                                    baseFontSize: 16,
                                    rubyFontSize: 8,
                                    baseColor: Color(red: 0.20, green: 0.42, blue: 0.72),
                                    rubyColor: Color(red: 0.46, green: 0.32, blue: 0.64),
                                    maxLines: 1
                                )
                            }
                        }
                        Text("Registered: \(word.registeredAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
            .padding(24)
            .navigationTitle("Word List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                rawWords = wordListEditorText(model.words)
            }
        }
    }
}

#Preview {
    ParentWordListView()
        .environmentObject(AppModel())
}
