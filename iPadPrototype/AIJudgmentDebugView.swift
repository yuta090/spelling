#if DEBUG
import SwiftUI
import PencilKit
import SpellingSyncCore

/// DEBUG専用: テスト答案の手書きを3モデルのAI(VLM)に投げ、判定を親採点風カードで横並び比較するページ。
/// 目的＝「端末OCRが読めない/誤受理する手書きを、AIならどう読むか」を実機の実データで確認する。
struct AIJudgmentDebugView: View {
    @EnvironmentObject private var model: AppModel

    private var attempts: [SpellingAttempt] {
        Array(model.attempts.sorted { $0.date > $1.date }.prefix(40))
    }

    private var keyMissing: Bool { OpenRouterConfig.apiKey == nil }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $model.debugAIJudgeOnTest) {
                    Text("テスト1問ごとに自動でAIへ送る")
                        .font(.subheadline.weight(.bold))
                }
                if keyMissing {
                    Label("APIキー未設定：.env.local に OPENROUTER_API_KEY=sk-or-... を追加（gitignore済）",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("モデル: " + OpenRouterConfig.models.map(Self.shortName).joined(separator: " / "))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } header: {
                Text("設定")
            }

            Section {
                if attempts.isEmpty {
                    Text("テスト答案がまだありません。テストをやると出ます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attempts) { attempt in
                        AIJudgmentAttemptCard(
                            attempt: attempt,
                            record: model.aiJudgments.first { $0.id == attempt.id },
                            keyMissing: keyMissing,
                            onSend: { model.runAIJudgment(for: attempt) }
                        )
                    }
                }
            } header: {
                Text("テスト答案（新しい順）")
            }
        }
        .navigationTitle("AI判定くらべ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("記録を消す", role: .destructive) { model.clearAIJudgments() }
                    .disabled(model.aiJudgments.isEmpty)
            }
        }
    }

    static func shortName(_ slug: String) -> String {
        slug.split(separator: "/").last.map(String.init) ?? slug
    }
}

private struct AIJudgmentAttemptCard: View {
    let attempt: SpellingAttempt
    let record: AIJudgmentRecord?
    let keyMissing: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AIDrawingThumbnail(drawingData: attempt.drawingData, canvasSize: attempt.canvasSize)
                    .frame(width: 150, height: 96)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(attempt.word)
                        .font(.title3.weight(.bold))
                    Text("端末OCR: \(attempt.decision.rawValue)"
                         + (attempt.recognizedText.isEmpty ? "" : " 「\(attempt.recognizedText)」"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onSend()
                } label: {
                    Label(record == nil ? "AIに送る" : "再送", systemImage: "paperplane.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .disabled(keyMissing || (record?.isRunning ?? false))
            }

            if let record {
                if record.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("3モデルに送信中…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(record.results) { result in
                            AIModelResultRow(result: result, target: record.target)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AIModelResultRow: View {
    let result: AIModelResult
    let target: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(AIJudgmentDebugView.shortName(result.modelSlug))
                .font(.caption2.weight(.bold))
                .frame(width: 118, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let error = result.errorMessage, result.verdict == nil {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let verdict = result.verdict {
                let matches = verdict.readingMatchesTarget(target)
                Image(systemName: matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(matches ? .green : .red)
                    .font(.caption)
                Text("「\(verdict.reading)」")
                    .font(.caption2.weight(.semibold).monospaced())
                if verdict.legible == false {
                    Text("読めない")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                if let ms = result.latencyMs {
                    Text("\(ms)ms").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("—").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// 自己完結の手書きプレビュー（他ファイルの preview は private のため新規に持つ）。
private struct AIDrawingThumbnail: View {
    let drawingData: Data?
    let canvasSize: DrawingCanvasSize?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "scribble")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var image: UIImage? {
        guard let drawingData, let drawing = try? PKDrawing(data: drawingData) else { return nil }
        return drawing.previewImage(canvasSize: canvasSize)
    }
}
#endif
