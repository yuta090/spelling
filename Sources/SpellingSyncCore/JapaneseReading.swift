import Foundation

/// 漢字まじりの和文を、子の学年に合わせて読みやすく整える（OS内蔵の日本語辞書を使用・オフライン）。
///
/// 方針（CLAUDE.md 子ども原則＝ふりがな／やさしい表記）:
/// - **習った学年以内の漢字はそのまま**残す（読める）。
/// - **学年を超える漢字を含む語だけ**、その語の読み（ひらがな）に置き換える。
/// - かな・記号・分かち書きのスペースはそのまま保つ。
///
/// 読みは内蔵辞書由来のため稀に外れることがある（例: 私→わたくし）。ただし学年を超える漢字の
/// フォールバックでのみ使うので、「読めない漢字を出す」よりは確実に良い。
/// 許可学年の決定（1学年前ルール）と漢字→配当学年の判定は `KanjiLevelGate` / `KyoikuKanji` に委譲。
///
/// 区切り（語境界）と読みは `CFStringTokenizer`（Foundation）に依存する。Apple プラットフォーム
/// （iOS / macOS）の内蔵辞書を使うため、テストも macOS の `swift test` 上で動く。
public enum JapaneseReading {

    /// `text` のうち、許可学年 `maxGrade` を超える漢字を含む語だけをひらがな読みに置き換える。
    /// すべて許可学年以内なら `text` をそのまま返す（変換コストもかけない）。
    public static func kanaizingOverGrade(_ text: String, maxGrade: Int) -> String {
        guard !text.isEmpty else { return text }
        if KanjiLevelGate.isWithin(text, maxGrade: maxGrade) { return text }

        let ns = text as NSString
        let cf = text as CFString
        let fullRange = CFRangeMake(0, ns.length)
        let locale = CFLocaleCreate(nil, CFLocaleIdentifier("ja" as CFString))
        guard let tokenizer = CFStringTokenizerCreate(nil, cf, fullRange, kCFStringTokenizerUnitWordBoundary, locale) else {
            return text
        }

        var output = ""
        var cursor = 0   // 直前トークンの終端（UTF-16）。トークン間の空白などをそのまま拾うため。
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !type.isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let start = range.location
            let length = range.length

            // トークンの手前にある区切り（スペース等）は原文のまま足す。
            if start > cursor {
                output += ns.substring(with: NSRange(location: cursor, length: start - cursor))
            }

            let surface = ns.substring(with: NSRange(location: start, length: length))
            // この語が許可学年を超える漢字を含むときだけ、読みに置き換える。
            if !KanjiLevelGate.offendingKanji(in: surface, maxGrade: maxGrade).isEmpty,
               let reading = hiraganaReading(of: tokenizer), !reading.isEmpty {
                output += reading
            } else {
                output += surface
            }

            cursor = start + length
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // 末尾の残り（最後のトークン以降）も原文のまま。
        if cursor < ns.length {
            output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }

        return output.isEmpty ? text : output
    }

    /// 子向けの例文和訳を表示用に整える。
    ///
    /// **順序が重要**: まず漢字のまま `wakachi`（語境界が明確なうちに文節を区切る）→ そのあと
    /// `kanaizingOverGrade` で学年を超える漢字をかなに落とす。逆順だと、かな化した複合語
    /// （例: 蔵書→ぞうしょ）が再トークナイズで「ぞう しょ」のように割れてしまう。
    /// `kanaizingOverGrade` はスペースを保つのでこの順序で破綻しない。
    public static func readableExample(_ ja: String, maxGrade: Int) -> String {
        kanaizingOverGrade(wakachi(ja), maxGrade: maxGrade)
    }

    /// 和文を**分かち書き**にする（文節ごとに半角スペースを入れる）。
    ///
    /// かな化した文（漢字が減って読みの切れ目が見えにくい）でも、子どもが語のかたまりを
    /// 追えるようにするのが目的。助詞・語尾などの付属語は前の自立語にくっつけ、自立語の前で区切る。
    /// 形態素解析の品詞は使えないため、「1文字のひらがな」と「よく使う付属語の語形」を付属語とみなす
    /// 簡易ヒューリスティック。二次的な訳文サブ行に使う前提で、多少の揺れは許容する。
    ///
    /// - 句読点・記号は直前の文節にくっつける（句点の前にスペースを入れない）。
    /// - 入力にあったスペースは一度落とし、文節境界に1つだけ入れ直す（二重スペースを作らない）。
    public static func wakachi(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let ns = text as NSString
        let cf = text as CFString
        let fullRange = CFRangeMake(0, ns.length)
        let locale = CFLocaleCreate(nil, CFLocaleIdentifier("ja" as CFString))
        guard let tokenizer = CFStringTokenizerCreate(nil, cf, fullRange, kCFStringTokenizerUnitWordBoundary, locale) else {
            return text
        }

        var bunsetsu: [String] = []
        var current = ""
        var cursor = 0

        func flush() {
            if !current.isEmpty { bunsetsu.append(current) }
            current = ""
        }

        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !type.isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let start = range.location
            let length = range.length

            // トークン間の区切り（原文）から、空白は落とし、句読点・記号は直前の文節にくっつける。
            if start > cursor {
                let gap = ns.substring(with: NSRange(location: cursor, length: start - cursor))
                current += gap.filter { !$0.isWhitespace }
            }

            // トークンが空白そのものになる場合がある（分かち書き入力）。空白は文節境界として
            // 入れ直すので、ここでは落とす（落とした結果が空ならスキップ）。
            let surface = ns.substring(with: NSRange(location: start, length: length)).filter { !$0.isWhitespace }
            if surface.isEmpty {
                cursor = start + length
                type = CFStringTokenizerAdvanceToNextToken(tokenizer)
                continue
            }
            if current.isEmpty || isOnlyPunctuation(current) || endsWithOpenDelimiter(current) || shouldAttach(surface) {
                // 付属語／記号のみ／開き括弧の直後／文節の途中 → くっつける。
                current += surface
            } else {
                // 自立語 → 新しい文節へ。
                flush()
                current = surface
            }

            cursor = start + length
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // 末尾の残り（句点など）は直前の文節へ。
        if cursor < ns.length {
            let gap = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            current += gap.filter { !$0.isWhitespace }
        }
        flush()

        return bunsetsu.joined(separator: " ")
    }

    /// 開き括弧・開きクォートで終わっているか？（直後の語はくっつけてスペースを入れない）
    private static func endsWithOpenDelimiter(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return openDelimiters.contains(last)
    }

    private static let openDelimiters: Set<Character> = [
        "「", "『", "（", "(", "〔", "【", "〈", "《", "｛", "[", "{", "〝", "“", "‘"
    ]

    /// 前の文節にくっつける付属語か？（助詞・語尾・1文字ひらがな・記号のみ）
    private static func shouldAttach(_ token: String) -> Bool {
        if isOnlyPunctuation(token) { return true }
        if token.count == 1, isAllHiragana(token) { return true }
        return attachingWords.contains(token)
    }

    private static func isAllHiragana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
    }

    /// 文字・数字を含まない（句読点・記号・空白だけ）か？
    private static func isOnlyPunctuation(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { scalar in
            let ch = Character(scalar)
            return !ch.isLetter && !ch.isNumber
        }
    }

    /// 前の語にくっつく代表的な付属語（助詞・助動詞・語尾）。1文字ひらがなは別途くっつけるので、
    /// ここには主に2文字以上のものを入れる。
    private static let attachingWords: Set<String> = [
        // 助詞
        "から", "まで", "より", "など", "のに", "ので", "けど", "でも", "しか", "だけ",
        "ほど", "くらい", "ぐらい", "こそ", "とは", "には", "では", "へは", "とも", "って",
        // 助動詞・語尾
        "です", "ます", "だっ", "でし", "まし", "ません", "ない", "なかっ", "たい", "そう",
        "らしい", "よう", "れる", "られる", "せる", "させる", "ちゃ", "じゃ", "ながら", "つつ",
        "ました", "ません", "でした", "ください", "くださ", "ている", "ています", "てる"
    ]

    /// 現在のトークンのひらがな読み（ローマ字転写 → ひらがな変換）。取れなければ nil。
    private static func hiraganaReading(of tokenizer: CFStringTokenizer) -> String? {
        guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription
        ) as? String else {
            return nil
        }
        let mutable = NSMutableString(string: latin)
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return mutable as String
    }
}
