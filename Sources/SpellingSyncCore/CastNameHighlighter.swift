import Foundation

// 例文テキスト中の「なかま」名の出現箇所を分割する純ロジック。
// 親側プレビューが「名前が問題に入る」ことを色付きで見せるための土台（描画はアプリ層）。
// 方針：
// - 生成済みの文字列を書き換えない（分割して返すだけ。結合すれば必ず原文に戻る）。
// - 英字名は単語境界を要求する（"Ken" が "Kendama" の中で光らない）。
//   日本語名はスペースが無いので出現一致のみ（「ゆきは…」の助詞続きを許す）。
// - 同じ位置に複数の名前が一致し得るときは長い名前を優先する（ゆう vs ゆうた）。
public enum CastNameHighlighter {

    public struct Segment: Equatable, Sendable {
        public var text: String
        public var isName: Bool

        public init(text: String, isName: Bool) {
            self.text = text
            self.isName = isName
        }
    }

    /// テキストを「名前」と「それ以外」の交互のセグメント列に分割する。
    public static func segments(in text: String, names: [String]) -> [Segment] {
        let candidates = names
            .filter { !$0.isEmpty }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        guard !candidates.isEmpty, !text.isEmpty else {
            return text.isEmpty ? [] : [Segment(text: text, isName: false)]
        }

        let chars = Array(text)
        var segments: [Segment] = []
        var literal: [Character] = []
        var index = 0
        while index < chars.count {
            if let name = matchName(at: index, in: chars, candidates: candidates) {
                if !literal.isEmpty {
                    segments.append(Segment(text: String(literal), isName: false))
                    literal = []
                }
                segments.append(Segment(text: name, isName: true))
                index += name.count
            } else {
                literal.append(chars[index])
                index += 1
            }
        }
        if !literal.isEmpty {
            segments.append(Segment(text: String(literal), isName: false))
        }
        return segments
    }

    /// index 位置で一致する名前（長い順に試す）。英字名は前後が英字でないことを要求する。
    private static func matchName(at index: Int, in chars: [Character], candidates: [String]) -> String? {
        for name in candidates {
            let nameChars = Array(name)
            let end = index + nameChars.count
            guard end <= chars.count, Array(chars[index..<end]) == nameChars else { continue }
            if isASCIILetterName(nameChars) {
                let beforeOK = index == 0 || !isASCIILetter(chars[index - 1])
                let afterOK = end == chars.count || !isASCIILetter(chars[end])
                guard beforeOK && afterOK else { continue }
            }
            return name
        }
        return nil
    }

    private static func isASCIILetterName(_ chars: [Character]) -> Bool {
        chars.allSatisfy { isASCIILetter($0) }
    }

    private static func isASCIILetter(_ ch: Character) -> Bool {
        ch.isASCII && ch.isLetter
    }
}
