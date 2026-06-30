import Foundation

/// おぼえる練習（手書きの前・タップで選ぶ）の「まちがい選択肢」を作る純ロジック。
///
/// 設計意図（docs/age-tiered-generation-spec / required-first フロー）：
/// - 必須のクリアは**手書き満点テスト**のまま。これは“覚えるための”前段で、正解の綴りを
///   文の中で見分けさせる（多肢選択）。多肢選択そのものはクリア条件にしない。
/// - 子がやりがちな 3 種のまちがいを作る：
///   1. `similarSpelling` 似た綴り（cats → kats / cots：1文字を紛らわしい字に置換）
///   2. `inflection`      かたちちがい（cats → cat、cat → cats、動詞なら playing/played）
///   3. `typo`            微妙なスペルミス（apple → applle / aple / appel：ダブり・脱字・入れ替え）
///
/// 音が近いおとり（home ↔ comb 等）は別物として `ConfusablesSound` が担う。ここは綴りの形だけ。
///
/// 入力の前提：**ASCII 英字のみ**（a–z / A–Z）。アポストロフィ・ハイフン・アクセント・
/// 非ラテン文字を含む語は対象外＝空を返す（`don't` を `dont` 等に崩さない／決定論を保つ）。
///
/// 不変条件：
/// - 正解そのもの（大文字小文字無視）は絶対に返さない。
/// - 全件ユニーク・ASCII 英字のみ・2 文字以上・**決定論**（同じ入力→同じ出力／乱数なし）。

public enum SpellingDistractorKind: String, Sendable, Codable, CaseIterable {
    /// 似た綴り（1文字を紛らわしい字に置換）。
    case similarSpelling
    /// かたちちがい（複数形・三単現・過去形など）。
    case inflection
    /// 微妙なスペルミス（ダブり字・脱字・となり入れ替え）。
    case typo
}

/// まちがい選択肢 1 件。
public struct SpellingDistractor: Equatable, Sendable {
    public var text: String
    public var kind: SpellingDistractorKind

    public init(text: String, kind: SpellingDistractorKind) {
        self.text = text
        self.kind = kind
    }
}

public enum SpellingDistractorGenerator {

    /// `answer`（登録語の正しい綴り）に対するまちがい選択肢を作る。
    /// - partOfSpeech: 品詞（任意）。動詞のとき ing/ed の形ちがいも作る。
    /// - kinds: 使う種類（既定＝全種）。
    /// - limit: 最大件数（任意・正の数のみ）。0 以下は空を返す。絞るときは種類が偏らないよう round-robin。
    public static func make(for answer: String,
                            partOfSpeech: String? = nil,
                            kinds: Set<SpellingDistractorKind> = Set(SpellingDistractorKind.allCases),
                            limit: Int? = nil) -> [SpellingDistractor] {
        let word = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 2 else { return [] }
        // ASCII 英字のみ対象（句読点・記号・アクセント・非ラテンは扱わない）。
        guard word.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        if let limit, limit <= 0 { return [] }

        // 種類ごとに候補を作る（固定順・固定中身＝決定論）。
        let groups: [(SpellingDistractorKind, [String])] = [
            (.similarSpelling, kinds.contains(.similarSpelling) ? similarSpellings(of: word) : []),
            (.inflection, kinds.contains(.inflection) ? inflections(of: word, partOfSpeech: partOfSpeech) : []),
            (.typo, kinds.contains(.typo) ? typos(of: word) : []),
        ]

        var result: [SpellingDistractor] = []
        var seen: Set<String> = [word.lowercased()]   // 正解そのものは除外（大小無視）

        func add(_ text: String, _ kind: SpellingDistractorKind) {
            guard text.count >= 2, text.allSatisfy({ $0.isASCII && $0.isLetter }) else { return }
            let key = text.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(SpellingDistractor(text: text, kind: kind))
        }

        // round-robin（各種類の同じ位置を順に拾う）→ 種類が偏らない。
        let maxLen = groups.map { $0.1.count }.max() ?? 0
        for i in 0..<maxLen {
            for (kind, candidates) in groups where i < candidates.count {
                add(candidates[i], kind)
            }
        }

        if let limit, result.count > limit {
            return Array(result.prefix(limit))
        }
        return result
    }

    // MARK: - ケース合わせ

    /// 接尾辞を語のケースに合わせる（全大文字の語には大文字の接尾辞を付ける）。
    private static func cased(_ suffix: String, like word: String) -> String {
        let isAllUpper = !word.isEmpty && word.allSatisfy { $0.isUppercase }
        return isAllUpper ? suffix.uppercased() : suffix
    }

    // MARK: - 似た綴り

    /// 1文字を「紛らわしい字」に置換した候補。
    private static let confusionMap: [Character: [Character]] = [
        "c": ["k", "s"], "k": ["c"], "s": ["z", "c"], "z": ["s"],
        "a": ["o", "e"], "o": ["a", "u"], "u": ["a", "o"],
        "i": ["e", "y"], "e": ["i", "a"], "y": ["i"],
        "m": ["n"], "n": ["m"], "b": ["d"], "d": ["b"],
        "v": ["b"], "f": ["v"], "g": ["j"], "j": ["g"],
    ]

    private static func similarSpellings(of word: String) -> [String] {
        let chars = Array(word)
        var out: [String] = []
        for i in chars.indices {
            let lower = Character(chars[i].lowercased())
            guard let subs = confusionMap[lower] else { continue }
            for s in subs {
                var copy = chars
                copy[i] = chars[i].isUppercase ? Character(s.uppercased()) : s
                out.append(String(copy))
            }
        }
        return out
    }

    // MARK: - かたちちがい

    /// この語が複数で `+es` を取る語尾か（s で終わらない側＝box/dish/buzz/watch）。
    /// `box→boxs` のような誤った複数化を防ぐ。
    private static func takesEsPlural(_ lower: String) -> Bool {
        if lower.hasSuffix("ch") || lower.hasSuffix("sh") { return true }
        if let last = lower.last, last == "x" || last == "z" { return true }
        return false
    }

    private static func inflections(of word: String, partOfSpeech: String?) -> [String] {
        var out: [String] = []
        let lower = word.lowercased()
        let n = word.count

        // 複数 → 単数（**確実に言える語尾だけ**。ses/zes/xes の語幹推測は houses→hous 等の
        // 劣化を生むのでやらない。残りは末尾 s を1つ落とすだけ＝houses→house, boxes→boxe）。
        if lower.hasSuffix("ies"), n >= 5 {
            out.append(String(word.dropLast(3)) + cased("y", like: word))   // candies → candy（pies/ties は除外）
        } else if lower.hasSuffix("s"), n >= 4 {
            out.append(String(word.dropLast(1)))                            // cats→cat, apples→apple, houses→house
        }

        // 単数 → 複数（s で終わらない語のみ。sibilant は +es、それ以外は +s）。
        if !lower.hasSuffix("s") {
            out.append(word + cased(takesEsPlural(lower) ? "es" : "s", like: word))  // box→boxes, cat→cats
        }

        // 動詞は ing/ed の形ちがいも（既にその語尾なら足さない）。
        if let pos = partOfSpeech?.lowercased(), pos.hasPrefix("v") {
            if !lower.hasSuffix("ing") { out.append(word + cased("ing", like: word)) }  // play → playing
            if !lower.hasSuffix("ed") { out.append(word + cased("ed", like: word)) }    // play → played
        }
        return out
    }

    // MARK: - 微妙なスペルミス

    private static func typos(of word: String) -> [String] {
        let chars = Array(word)
        let n = chars.count
        var out: [String] = []

        // となり入れ替え（隣が違う字のときだけ）。apple → appel
        for i in 0..<(n - 1) where chars[i] != chars[i + 1] {
            var c = chars
            c.swapAt(i, i + 1)
            out.append(String(c))
        }
        // 脱字（2文字以上を保つ）。apple → aple
        if n >= 3 {
            for i in 0..<n {
                var c = chars
                c.remove(at: i)
                out.append(String(c))
            }
        }
        // ダブり字。apple → applle
        for i in 0..<n {
            var c = chars
            c.insert(chars[i], at: i)
            out.append(String(c))
        }
        return out
    }
}
