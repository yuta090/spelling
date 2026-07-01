#if DEBUG
import Foundation

/// AI(VLM)による手書き綴り判定の**純粋な結果表現とパース/プロンプト**（I/O非依存・テスト可能）。
/// **DEBUG専用**（`#if DEBUG`）＝AI-OCR比較機能はプロンプト文字列も含め Release にはビルドしない。
///
/// 用途: DEBUG のAI-OCR比較ページ。1つの手書き答案を複数モデルに投げ、各モデルの
/// 「何と読めたか / 正解か / 判読できたか / 一言」を横並びで見る。実ネットワークは
/// アプリ側 `OpenRouterClient`（DEBUGのみ）が担い、ここは**プロンプト生成と応答パースだけ**を持つ。

/// 1モデルの判定内容（モデルが返した JSON をパースしたもの）。
public struct AIOCRVerdict: Equatable, Sendable, Codable {
    /// モデルが読み取った文字列。
    public var reading: String
    /// モデル自身の「出題語と一致するか」判定（欠落時 nil）。
    public var correct: Bool?
    /// 判読できたか（読めない手書きを捏造せず false を返せるか。欠落時 nil）。
    public var legible: Bool?
    /// 一言コメント。
    public var comment: String

    public init(reading: String, correct: Bool? = nil, legible: Bool? = nil, comment: String = "") {
        self.reading = reading
        self.correct = correct
        self.legible = legible
        self.comment = comment
    }

    /// モデルの自己申告に頼らず、読み取り文字列を正規化して出題語と一致するか判定する
    /// （大文字小文字・前後空白・英字以外を無視）。誤受理(FA)/誤拒否(FR)の客観比較に使う。
    public func readingMatchesTarget(_ target: String) -> Bool {
        AIOCRText.normalize(reading) == AIOCRText.normalize(target)
    }
}

public enum AIOCRText {
    /// 比較用の正規化：小文字化し、英字以外（空白・記号・数字）をすべて除去する。
    public static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { ($0.value >= 97 && $0.value <= 122) })
    }
}

public enum AIOCRPrompt {
    /// 各モデルへ送る指示文。厳密な JSON だけを返させ、読めないときは捏造せず legible:false を返させる。
    public static func instruction(target: String) -> String {
        """
        You are grading a young child's handwritten English spelling.
        The child was asked to write the word: "\(target)".
        Look ONLY at the handwriting in the image. Do NOT guess or autocorrect.
        If you cannot read it, do not invent letters — set "legible" to false.
        Reply with ONLY a compact JSON object, no code fences, no extra text:
        {"reading":"<exact letters you see>","correct":<true|false>,"legible":<true|false>,"comment":"<max 8 words>"}
        "correct" = whether the letters actually written spell "\(target)" exactly.
        """
    }
}

public enum AIOCRResponseParser {
    /// モデルの生テキスト応答から JSON を取り出して `AIOCRVerdict` にする。
    /// コードフェンス（```json ... ```）や前後の余計なテキストを許容する。
    /// 応答内のバランスした `{...}` 候補を順に試し、**`reading` を持つ最初のオブジェクト**を採用する
    /// （前置きの散文や verdict でない先行オブジェクトに惑わされない）。パースできなければ nil。
    public static func parse(_ content: String) -> AIOCRVerdict? {
        for slice in jsonObjectCandidates(in: content) {
            guard let data = slice.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reading = stringValue(raw["reading"]) else {
                continue
            }
            return AIOCRVerdict(
                reading: reading,
                correct: boolValue(raw["correct"]),
                legible: boolValue(raw["legible"]),
                comment: stringValue(raw["comment"]) ?? ""
            )
        }
        return nil
    }

    /// 文字列中のトップレベルでバランスした `{...}` を出現順にすべて返す（ネスト対応）。
    /// **オブジェクト開始（`{`）より前の引用符は無視**する（前置き散文の未対応クォートに惑わされない）。
    static func jsonObjectCandidates(in content: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in content.indices {
            let char = content[index]

            if depth == 0 {
                // まだオブジェクトの外：波括弧の開始だけ探す（クォートは無視）。
                if char == "{" {
                    start = index
                    depth = 1
                }
                continue
            }

            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            switch char {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    result.append(String(content[start...index]))
                }
            default:
                break
            }
        }
        return result
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let string = any as? String { return string }
        return nil
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        if let bool = any as? Bool { return bool }
        if let number = any as? NSNumber { return number.boolValue }
        if let string = any as? String {
            switch string.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
#endif
