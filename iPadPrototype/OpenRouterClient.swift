#if DEBUG
import Foundation
import PencilKit
import UIKit
import SpellingSyncCore

/// DEBUG専用: 手書き答案を OpenRouter 経由で複数の VLM に投げ、判定を横並び比較するための最小クライアント。
/// 本番ビルドには含めない（`#if DEBUG`）。純粋なプロンプト生成/応答パースは `SpellingSyncCore` 側。

/// 1モデルの判定結果（アプリ側＝ネットワーク結果を含む）。
struct AIModelResult: Identifiable, Codable, Equatable {
    var id = UUID()
    var modelSlug: String
    /// パース済み判定（失敗時 nil）。
    var verdict: AIOCRVerdict?
    /// モデルの生応答（デバッグ表示用・失敗診断）。
    var rawContent: String?
    var latencyMs: Int?
    var errorMessage: String?
}

/// 1答案ぶんの比較レコード（親採点風カードの1枚）。
struct AIJudgmentRecord: Identifiable, Codable, Equatable {
    /// 対応する答案(SpellingAttempt)のID。
    var id: UUID
    /// この送信ジョブの世代ID。clear→再送で古いTaskが新しいレコードを上書きしないための照合キー。
    var runID: UUID
    var target: String
    var localRecognizedText: String
    /// 端末OCRの自動判定（`GradeDecision.rawValue`）。
    var localDecision: String
    var date: Date
    /// 実行中は空、完了で3モデルぶん埋まる。
    var results: [AIModelResult]
    /// まだ結果が来ていない（送信中）か。
    var isRunning: Bool = false
}

enum OpenRouterConfig {
    /// 比較する3モデル（scripts/ocr-bench/bench.py と揃える）。
    static let models = [
        "google/gemini-2.5-flash-lite",
        "openai/gpt-5.4-nano",
        "anthropic/claude-haiku-4.5"
    ]

    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// APIキー取得（DEBUG）。優先: 環境変数 → リポジトリの `.env.local`（gitignore 済み）。
    /// `.env.local` はシミュレータ実行時に `#filePath` から辿って読む（実機には無いので nil＝「キー未設定」表示）。
    /// 秘密はリポジトリにコミットしない（`.env.local` は追跡外）。
    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env.trimmingCharacters(in: .whitespaces)
        }
        return dotEnvValue("OPENROUTER_API_KEY")
    }

    static func dotEnvValue(_ key: String) -> String? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(".env.local")
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                for rawLine in text.split(separator: "\n") {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix(key + "=") else { continue }
                    let value = line.dropFirst(key.count + 1)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
                    return value.isEmpty ? nil : value
                }
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

struct OpenRouterClient {
    var apiKey: String? = OpenRouterConfig.apiKey
    var session: URLSession = .shared

    /// 1モデルに手書きPNGを投げて判定を得る。ネットワーク/パース失敗は `errorMessage` に載せて返す（throwしない）。
    func judge(imagePNG: Data, target: String, model: String) async -> AIModelResult {
        let start = Date()
        guard let apiKey else {
            return AIModelResult(modelSlug: model, errorMessage: "APIキー未設定（.env.local に OPENROUTER_API_KEY を設定）")
        }

        var request = URLRequest(url: OpenRouterConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let dataURL = "data:image/png;base64,\(imagePNG.base64EncodedString())"
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": 120,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": AIOCRPrompt.instruction(target: target)],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                return AIModelResult(modelSlug: model, latencyMs: ms, errorMessage: "HTTP \(http.statusCode): \(detail)")
            }

            guard let content = Self.extractContent(from: data) else {
                return AIModelResult(modelSlug: model, latencyMs: ms, errorMessage: "応答から content を取得できず")
            }

            let verdict = AIOCRResponseParser.parse(content)
            return AIModelResult(
                modelSlug: model,
                verdict: verdict,
                rawContent: content,
                latencyMs: ms,
                errorMessage: verdict == nil ? "JSONをパースできず" : nil
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return AIModelResult(modelSlug: model, latencyMs: ms, errorMessage: error.localizedDescription)
        }
    }

    /// OpenRouter (OpenAI互換) 応答から `choices[0].message.content` を取り出す。
    static func extractContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }
        if let text = message["content"] as? String {
            return text
        }
        // content が配列（[{type:text,text:...}]）で来る実装にも一応対応。
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }
}

enum AIJudgmentImage {
    /// 答案の手書きを、白背景・適度に縮小した PNG にする（コスト/レイテンシ抑制のため長辺 640px 目安）。
    static func png(for attempt: SpellingAttempt) -> Data? {
        guard let drawingData = attempt.drawingData,
              let drawing = try? PKDrawing(data: drawingData),
              let preview = drawing.previewImage(canvasSize: attempt.canvasSize) else {
            return nil
        }
        return whiteBacked(preview, maxLongSide: 640).pngData()
    }

    private static func whiteBacked(_ image: UIImage, maxLongSide: CGFloat) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        let scale = longSide > maxLongSide ? maxLongSide / longSide : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
