import Foundation

/// 文バンク前処理：候補文を検証・学年タグ付けして同梱用 `SentenceItem` 群を作る（純ロジック・TDD）。
/// 設計: docs/sentence-builder-design-2026-06-27.md §3（ビルド時タグ付けが本丸）
///
/// 方針（②confusables ビルドと同じ「Core=判定／CLI=IO」分離）：
///  - **学年の壁はここで保証する**：内容語をすべて lemma 化して `band`（NGSL）に当て、
///    1語でも未収録 or 上限超なら **その文は不採用**。`gradeBand = 内容語の最大band`。
///  - **文法の壁**：`grammar` タグの段階が上限を超えたら不採用（タグ無しは制約なし）。
///  - **子ども適切性**：語数しきい値（短文のみ）＋ブロックリスト。
///  - 機能語（a/the/be/代名詞…）は**学年判定から除外**（tokens には残す＝並べ替えで使う）。
///  - 決定論：`id` は文（正規化トークン列）から UUIDv5 を導く（再実行で同一＝同梱差分が安定）。
///
/// IO（CSV/JSON/sqlite 読み書き）は本 Core では行わない。`sentence-bank-build` CLI が用意する。
public enum SentenceBankBuilder {

    /// 文 id の名前空間（固定）。文ごとの安定 id を導くため。
    static let namespace = UUID(uuidString: "B6F6E2A0-5E3C-4C1B-9E2A-7D3F1C2B4A50")!

    /// 入力候補（curated/tanaka 共通）。内容語は常に `en` の見える語から導く（著者 lemma には頼らない）。
    /// `declaredBand` は著者が宣言した学年（curated のみ・1...5 前提）。level 未収録語があってもこれを採用し
    /// **警告**に留める（②と同じ方針＝人が承認したデータを level 欠落で壊さない）。nil（tanaka）は未収録＝不採用。
    public struct Candidate: Equatable, Sendable {
        public var en: String
        public var ja: String
        public var grammar: GrammarPoint?
        public var declaredBand: Int?
        public var source: String
        /// 安定 sourceID（教材＝authoring 由来）。built 文へそのまま通す。nil＝未指定（後方互換）。
        public var sourceID: String?

        public init(en: String, ja: String, grammar: GrammarPoint? = nil,
                    declaredBand: Int? = nil, source: String, sourceID: String? = nil) {
            self.en = en
            self.ja = ja
            self.grammar = grammar
            self.declaredBand = declaredBand
            self.source = source
            self.sourceID = sourceID
        }
    }

    /// 不採用理由。
    public enum RejectionReason: Equatable, Sendable {
        case emptyText                       // 英文が空 / トークン0
        case tooFewTokens                    // 2語未満（並べ替え/穴埋めにならない）
        case tooManyTokens(Int)              // 長すぎ（子ども向け短文の上限超）
        case unleveledContentWord(String)    // 内容語が level 未収録（原形でも当たらない）
        case overTargetBand(String, Int)     // 内容語の band が対象学年超（語, band）
        case grammarOverCeiling(GrammarStage)// 文法タグが上限超
        case blockedWord(String)             // 不適切語ブロックリストに一致
        case duplicate                       // 同じ文が既に採用済み
    }

    public struct Rejection: Equatable, Sendable {
        public var en: String
        public var reason: RejectionReason
        public init(en: String, reason: RejectionReason) {
            self.en = en
            self.reason = reason
        }
    }

    /// 警告の種類（採用は維持・人が確認する）。
    public enum WarningKind: Equatable, Sendable {
        /// 内容語が level 未収録だが著者の宣言バンドを採用した（②と同じ＝壊さない）。
        case contentWordNotLeveled(String)
    }

    public struct Warning: Equatable, Sendable {
        public var en: String
        public var kind: WarningKind
        public init(en: String, kind: WarningKind) {
            self.en = en
            self.kind = kind
        }
    }

    public struct Result: Equatable, Sendable {
        public var accepted: [SentenceItem]
        public var rejected: [Rejection]
        public var warnings: [Warning]
        public init(accepted: [SentenceItem], rejected: [Rejection], warnings: [Warning] = []) {
            self.accepted = accepted
            self.rejected = rejected
            self.warnings = warnings
        }
    }

    /// - candidates: 入力候補（順序保持）。
    /// - band: 語（小文字・原形）→ NGSL band。`level` 由来。
    /// - targetBand: 語彙の壁（この band 以下のみ採用）。
    /// - grammarCeiling: 文法の壁（この段階以下のみ採用）。
    /// - blocklist: 不適切語（小文字・原形）。
    /// - maxTokens: 子ども向け短文の上限トークン数。
    public static func build(candidates: [Candidate],
                             band: [String: Int],
                             targetBand: Int,
                             grammarCeiling: GrammarStage,
                             blocklist: Set<String> = [],
                             maxTokens: Int = 10) -> Result {
        var accepted: [SentenceItem] = []
        var rejected: [Rejection] = []
        var warnings: [Warning] = []
        var seen: Set<String> = []

        for c in candidates {
            let tokens = tokenize(c.en)
            guard !tokens.isEmpty else {
                rejected.append(Rejection(en: c.en, reason: .emptyText)); continue
            }
            if tokens.count < 2 {
                rejected.append(Rejection(en: c.en, reason: .tooFewTokens)); continue
            }
            if tokens.count > maxTokens {
                rejected.append(Rejection(en: c.en, reason: .tooManyTokens(tokens.count))); continue
            }

            // 文法の壁。
            if let g = c.grammar, g.stage > grammarCeiling {
                rejected.append(Rejection(en: c.en, reason: .grammarOverCeiling(g.stage))); continue
            }

            // 不適切語（全トークンを原形でも照合）。
            if let bad = tokens.first(where: { isBlocked($0, blocklist) }) {
                rejected.append(Rejection(en: c.en, reason: .blockedWord(bad.lowercased()))); continue
            }

            // 学年判定に使う内容語は **常に文中の見える語から導く**（機能語を除く）。
            // 著者宣言の lemma に頼らない：壁は「実際に子に見える全語」が対象学年内であることを保証する必要がある。
            // （著者 lemma は不完全/古いことがあり、見えない語が壁をすり抜ける／使われない語が混入するため。）
            let contentWords = tokens
                .map { $0.lowercased() }
                .filter { !functionWords.contains($0) }

            // 各内容語を lemma 化して band 解決。1語でも外れたら不採用。
            // ただし著者が declaredBand を宣言した curated は、level 未収録でも宣言バンドを採用し**警告**に留める。
            var lemmas: [String] = []
            var pendingWarnings: [Warning] = []
            var maxBand = 1
            var failure: RejectionReason?
            for w in contentWords {
                if let (key, b) = resolveBand(w, band) {
                    if b > targetBand { failure = .overTargetBand(key, b); break }
                    lemmas.append(key)
                    maxBand = max(maxBand, b)
                } else if let declared = c.declaredBand {
                    // level 欠落。著者の宣言バンドを信頼して採用（②と同じ＝壊さない）。
                    // 解決できなかった語は確かな原形が無いので、表層トークンをそのまま記録する
                    // （soccer→soc のような lemmatizer 誤変換を出力に持ち込まない）。
                    if declared > targetBand { failure = .overTargetBand(w, declared); break }
                    lemmas.append(w)
                    maxBand = max(maxBand, declared)
                    pendingWarnings.append(Warning(en: c.en, kind: .contentWordNotLeveled(w)))
                } else {
                    failure = .unleveledContentWord(w); break
                }
            }
            if let f = failure {
                rejected.append(Rejection(en: c.en, reason: f)); continue
            }

            // 重複（正規化トークン列が同じ）。
            let key = tokens.map { $0.lowercased() }.joined(separator: " ")
            if seen.contains(key) {
                rejected.append(Rejection(en: c.en, reason: .duplicate)); continue
            }
            seen.insert(key)
            warnings.append(contentsOf: pendingWarnings)

            let id = DeterministicID.uuidV5(namespace: namespace, name: key)
            accepted.append(SentenceItem(
                id: id,
                en: tokens.joined(separator: " "),
                ja: c.ja,
                tokens: tokens,
                gradeBand: maxBand,
                contentLemmas: lemmas,
                grammar: c.grammar,
                sourceID: c.sourceID
            ))
        }

        return Result(accepted: accepted, rejected: rejected, warnings: warnings)
    }

    // MARK: - トークン化

    /// 空白区切り＋各語の前後の句読点を除去（内部のハイフン/アポストロフィは残す）。
    /// 句読点だけの語は落とす。並べ替え/穴埋めの素になるので「語」だけを残す。
    public static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map { stripEdgePunctuation(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:\"'`()[]{}…—–-‚„“”‘’«»")

    private static func stripEdgePunctuation(_ raw: String) -> String {
        var s = Substring(raw)
        while let f = s.unicodeScalars.first, edgePunctuation.contains(f) { s = s.dropFirst() }
        while let l = s.unicodeScalars.last, edgePunctuation.contains(l) { s = s.dropLast() }
        return String(s)
    }

    // MARK: - 学年解決

    /// 原形そのまま → lemma の順で band を引く。当たった key と band を返す。
    private static func resolveBand(_ word: String, _ band: [String: Int]) -> (String, Int)? {
        let w = word.lowercased()
        if let b = band[w] { return (w, b) }
        let lemma = SimpleLemmatizer.lemma(w)
        if lemma != w, let b = band[lemma] { return (lemma, b) }
        return nil
    }

    private static func isBlocked(_ token: String, _ blocklist: Set<String>) -> Bool {
        guard !blocklist.isEmpty else { return false }
        let w = token.lowercased()
        if blocklist.contains(w) { return true }
        return blocklist.contains(SimpleLemmatizer.lemma(w))
    }

    // MARK: - serialize / decode（同梱JSON。SentenceItem は Codable）

    /// 採用文を同梱用 JSON（安定キー順・整形）へ。再実行で差分が安定するよう sortedKeys。
    public static func serialize(_ items: [SentenceItem]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text + "\n"
    }

    /// 同梱 JSON を `SentenceItem` 群へ。アプリ側のバンドル読み込みで使う。
    public static func decode(json text: String) -> [SentenceItem] {
        guard let data = text.data(using: .utf8),
              let items = try? JSONDecoder().decode([SentenceItem].self, from: data) else {
            return []
        }
        return items
    }

    // MARK: - 機能語（学年判定から除外。tokens には残す）

    /// NGSL 学年判定の対象外にする機能語。冠詞・be・助動詞・代名詞・前置詞・接続詞・疑問詞など。
    /// （これらは「語彙の壁」ではなく「文法の壁」で扱う／低頻度ではないため。）
    static let functionWords: Set<String> = [
        // 冠詞
        "a", "an", "the",
        // be
        "be", "is", "am", "are", "was", "were", "been", "being",
        // 助動詞・modal
        "do", "does", "did", "doing", "done",
        "have", "has", "had", "having",
        "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        // 代名詞・限定詞
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their",
        "mine", "yours", "hers", "ours", "theirs",
        "this", "that", "these", "those",
        "myself", "yourself", "himself", "herself", "itself", "ourselves", "themselves",
        // 前置詞
        "to", "of", "in", "on", "at", "for", "with", "from", "by", "as",
        "into", "onto", "over", "under", "above", "below", "up", "down",
        "off", "out", "about", "after", "before", "between", "through",
        // 接続詞・その他機能語
        "and", "or", "but", "so", "if", "because", "when", "while", "than", "then",
        "not", "no", "yes", "there", "here", "too", "very", "just",
        "what", "who", "why", "where", "how", "which", "whose", "whom",
        "please", "let", "let's",
    ]
}
