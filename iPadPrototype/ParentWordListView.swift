import SwiftUI

struct ParentWordListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rawWords = ""

    var body: some View {
        NavigationStack {
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
                        dismiss()
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.text)
                            .font(.title3)
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
                rawWords = model.words.map(\.text).joined(separator: "\n")
            }
        }
    }
}

#Preview {
    ParentWordListView()
        .environmentObject(AppModel())
}
