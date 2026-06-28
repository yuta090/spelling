import Foundation

/// Tanaka 例文（英日）から子ども向け短文を機械抽出する純ロジック（決定論・TDD）。
/// 設計: `.claude/skills/kotoba-sentence-add/SKILL.md` 手順B / B2「Tanaka 例文から自動抽出」。
///
/// 役割分担（②③と同じ「Core=判定／CLI=IO」）：
///  - sqlite 読み出しは **CLI（薄いIO）** が行い、ここには「すでにパース済みの行 `[Row]`」を渡す。
///  - **学年の壁・未収録語・ブロックリスト・トークン上限・id 採番・重複(バッチ内)** は
///    すべて `SentenceBankBuilder` に委譲する（curated と同一の機械検査を必ず通す）。
///  - 本 Extractor が足すのは Tanaka 固有の **事前フィルタ** と **既存バンク重複除外** と **決定論順** だけ：
///     * 最小トークン（既定3／並べ替え・穴埋めに足る長さ）。
///     * 記号/数字過多（引用符・数字・特殊記号を含む行を落とす＝対話文/見出し/数式を除外）。
///     * 固有名詞だらけ（文中の大文字始まり非機能語が過半なら落とす）。
///     * 二重の子ども安全ブロック（コーパスは除外済みだが組み込み NG 語で backstop）。
///
/// 決定論：入力行の順序に依存しない。事前フィルタ後に **正規化キーでソート**し、
/// バッチ内重複を畳み、`SentenceBankBuilder` に渡す（id は文から UUIDv5）。
/// `limit` は **既存バンクと無関係な**（＝決定論ソート済みの全候補に対する）上位 N で、
/// 既存重複除外はその後に行う。これにより同じ DB・引数なら再実行で出力が一切ぶれない。
public enum TanakaExtractor {

    /// 抽出入力（CLI が sqlite から用意する1行）。
    public struct Row: Equatable, Sendable {
        public var en: String
        public var ja: String
        public init(en: String, ja: String) {
            self.en = en
            self.ja = ja
        }
    }

    /// 事前フィルタの却下理由（Core 検査より前で落ちたもの）。
    public enum PreReject: Equatable, Sendable {
        case tooFewTokens                 // 最小トークン未満
        case tooManyTokens(Int)           // 上限超（Core でも見るが早期に落とす）
        case disallowedCharacters         // 引用符・数字・特殊記号など子ども短文に不要な文字
        case mostlyProperNouns            // 大文字始まり非機能語が過半（人名/地名だらけ）
        case kidUnsafe(String)            // 組み込み NG 語（除外済みコーパスの二重チェック）
        case duplicateInBatch             // バッチ内で正規化キーが既出
    }

    public struct PreRejection: Equatable, Sendable {
        public var en: String
        public var reason: PreReject
        public init(en: String, reason: PreReject) {
            self.en = en
            self.reason = reason
        }
    }

    /// 抽出結果。`accepted` は「既存バンクと重複しない新規採用文（決定論順）」。
    public struct Output: Equatable, Sendable {
        /// 新規採用文（既存バンク重複・limit 打ち切りを除いた最終物）。決定論順（正規化キー昇順）。
        public var accepted: [SentenceItem]
        /// `SentenceBankBuilder` の生結果（学年壁などの却下理由を含む。診断用）。
        public var builderResult: SentenceBankBuilder.Result
        /// 事前フィルタで落ちた行（理由つき）。
        public var preRejected: [PreRejection]
        /// 入力総行数。
        public var totalRows: Int
        /// 事前フィルタ通過行数（Core に渡した数）。
        public var passedPreFilter: Int
        /// Core 採用のうち既存バンク重複で除外した数。
        public var duplicateExisting: Int
        /// limit で打ち切った数（Core 採用 − limit）。
        public var cappedOut: Int

        public init(accepted: [SentenceItem], builderResult: SentenceBankBuilder.Result,
                    preRejected: [PreRejection], totalRows: Int, passedPreFilter: Int,
                    duplicateExisting: Int, cappedOut: Int) {
            self.accepted = accepted
            self.builderResult = builderResult
            self.preRejected = preRejected
            self.totalRows = totalRows
            self.passedPreFilter = passedPreFilter
            self.duplicateExisting = duplicateExisting
            self.cappedOut = cappedOut
        }
    }

    /// - rows: 抽出入力（sqlite 由来・順不同でよい）。
    /// - band: 語（小文字・原形）→ NGSL band。`level` 由来。
    /// - targetBand: 語彙の壁（この band 以下のみ採用）。
    /// - existingKeys: 既存 `sentence_bank.json` の正規化キー集合（重複除外用）。
    /// - blocklist: 外部の不適切語（小文字・原形）。Core に渡す。
    /// - extraUnsafeWords: 組み込み NG 語に追加する語（任意）。
    /// - minTokens: 事前フィルタの最小トークン（既定3）。
    /// - maxTokens: 子ども向け短文の上限トークン数（Core にも渡す）。
    /// - limit: 採用上限（決定論ソート済み全候補の上位 N）。nil で無制限。
    public static func extract(rows: [Row],
                               band: [String: Int],
                               targetBand: Int,
                               existingKeys: Set<String>,
                               blocklist: Set<String> = [],
                               extraUnsafeWords: Set<String> = [],
                               minTokens: Int = 3,
                               maxTokens: Int = 10,
                               limit: Int? = nil) -> Output {
        var preRejected: [PreRejection] = []
        let unsafeWords = builtinUnsafeWords.union(extraUnsafeWords)

        // 1) 事前フィルタ（行ごとに独立・決定論）。
        struct Surviving { var en: String; var ja: String; var key: String }
        var survivors: [Surviving] = []
        for r in rows {
            if let reason = preFilter(r.en, minTokens: minTokens, maxTokens: maxTokens, unsafeWords: unsafeWords) {
                preRejected.append(PreRejection(en: r.en, reason: reason)); continue
            }
            survivors.append(Surviving(en: r.en, ja: r.ja, key: normalizedKey(r.en)))
        }

        // 2) 正規化キーで決定論ソート（入力順に依存しない）。同点は en で安定化。
        survivors.sort { ($0.key, $0.en) < ($1.key, $1.en) }

        // 3) バッチ内重複（同一正規化キー）を畳む。ソート済みなので隣接比較で十分。
        var deduped: [Surviving] = []
        var lastKey: String? = nil
        for s in survivors {
            if s.key == lastKey {
                preRejected.append(PreRejection(en: s.en, reason: .duplicateInBatch)); continue
            }
            deduped.append(s)
            lastKey = s.key
        }
        let passedPreFilter = deduped.count

        // 4) Core(SentenceBankBuilder) で機械検査（学年壁・未収録・ブロック・トークン・id 採番）。
        //    Tanaka は grammar 無し・宣言バンド無し。grammarCeiling は最上位（nil grammar は常に通過）。
        let candidates = deduped.map {
            SentenceBankBuilder.Candidate(en: $0.en, ja: $0.ja, grammar: nil,
                                          declaredBand: nil, source: "tanaka")
        }
        let builderResult = SentenceBankBuilder.build(
            candidates: candidates, band: band, targetBand: targetBand,
            grammarCeiling: .applied, blocklist: blocklist, maxTokens: maxTokens)

        // 5) limit（既存バンクと無関係＝決定論。Core 採用は入力＝ソート順を保つ）。
        var selected = builderResult.accepted
        var cappedOut = 0
        if let limit = limit, selected.count > limit {
            cappedOut = selected.count - limit
            selected = Array(selected.prefix(limit))
        }

        // 6) 既存バンク重複除外（limit の後＝再実行で追加が増えない）。
        var accepted: [SentenceItem] = []
        var duplicateExisting = 0
        for item in selected {
            if existingKeys.contains(keyOf(item)) { duplicateExisting += 1; continue }
            accepted.append(item)
        }

        return Output(accepted: accepted, builderResult: builderResult, preRejected: preRejected,
                      totalRows: rows.count, passedPreFilter: passedPreFilter,
                      duplicateExisting: duplicateExisting, cappedOut: cappedOut)
    }

    // MARK: - 正規化キー（重複判定・ソート）

    /// 文を重複判定キーへ：トークン化 → 小文字 → 空白結合（句読点/大小無視）。
    /// `SentenceBankBuilder` のバッチ内重複キーと一致させる（既存バンクとも揃う）。
    public static func normalizedKey(_ en: String) -> String {
        SentenceBankBuilder.tokenize(en).map { $0.lowercased() }.joined(separator: " ")
    }

    /// 採用済み `SentenceItem` の正規化キー（tokens から・en 由来と一致）。
    static func keyOf(_ item: SentenceItem) -> String {
        item.tokens.map { $0.lowercased() }.joined(separator: " ")
    }

    // MARK: - 事前フィルタ

    /// 1行を事前フィルタする。落ちる理由があれば返す（nil なら通過）。
    static func preFilter(_ en: String, minTokens: Int, maxTokens: Int,
                          unsafeWords: Set<String>) -> PreReject? {
        // 記号/数字過多：許可文字（英字・空白・基本句読点）以外を含む行は落とす。
        // 引用符 " “ ” / 数字 / カッコ / セミコロン / & % $ などの対話文・見出し・数式を除外。
        if en.unicodeScalars.contains(where: { !allowedScalars.contains($0) }) {
            return .disallowedCharacters
        }

        let tokens = SentenceBankBuilder.tokenize(en)
        if tokens.count < minTokens { return .tooFewTokens }
        if tokens.count > maxTokens { return .tooManyTokens(tokens.count) }

        // 子ども安全 backstop（原形でも照合）。コーパスは除外済みだが二重に弾く。
        if let bad = tokens.first(where: { isUnsafe($0, unsafeWords) }) {
            return .kidUnsafe(bad.lowercased())
        }

        // 固有名詞だらけ：文頭以外で大文字始まりの非機能語が、判定可能語（文頭を除く）の過半なら落とす。
        // （人名/地名の羅列。文頭語は常に大文字始まりで判定不能なので分母から除く。
        //   単独の固有名詞は未収録語として Core が弾くのでここでは「過半」のみ。）
        if tokens.count >= 2 {
            let judgeable = tokens.count - 1   // 文頭を除く
            var proper = 0
            for (i, t) in tokens.enumerated() where i > 0 && isLikelyProperNoun(t) { proper += 1 }
            if proper * 2 > judgeable { return .mostlyProperNouns }
        }

        return nil
    }

    /// 許可するスカラー集合：英字 a-zA-Z・空白・基本句読点（. , ! ? と内部の ' -）。
    private static let allowedScalars: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: " .,!?'-")
        return set
    }()

    /// 文頭以外で大文字始まり、かつ機能語でも "I" でもない語＝固有名詞候補。
    static func isLikelyProperNoun(_ token: String) -> Bool {
        guard let first = token.unicodeScalars.first else { return false }
        guard CharacterSet.uppercaseLetters.contains(first) else { return false }
        let lower = token.lowercased()
        if lower == "i" { return false }
        if SentenceBankBuilder.functionWords.contains(lower) { return false }
        return true
    }

    private static func isUnsafe(_ token: String, _ words: Set<String>) -> Bool {
        guard !words.isEmpty else { return false }
        let w = token.lowercased()
        if words.contains(w) { return true }
        return words.contains(SimpleLemmatizer.lemma(w))
    }

    /// 組み込みの子ども安全 backstop 語（最小限・原形）。外部 `sentence_blocklist.txt` とは別レイヤ。
    /// コーパスは既に子ども不適切を除外済みのため、ここは「念のため」の固定セット。
    /// 飲酒・喫煙・賭博・暴力/武器・露骨な語など、子ども向け短文に出したくない題材を弾く。
    static let builtinUnsafeWords: Set<String> = [
        // 飲酒・喫煙・薬物
        "wine", "whisky", "whiskey", "vodka", "brandy", "liquor", "alcohol", "drunk",
        "cigarette", "cigar", "tobacco", "smoke", "smoking", "drug", "cocaine", "heroin",
        // 賭博
        "casino", "gamble", "gambling", "bet", "betting",
        // 暴力・武器
        "gun", "pistol", "rifle", "knife", "sword", "bomb", "kill", "killed", "murder",
        "blood", "wound", "corpse", "suicide",
        // 露骨・成人向け
        "sex", "sexy", "nude", "naked", "porn", "rape", "damn", "hell",
    ]
}
