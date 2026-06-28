import Foundation

/// 英単語を「もとの形（見出し語 / lemma）」へ寄せる簡易ルール（純ロジック・TDD）。
/// 設計: docs/sentence-builder-design-2026-06-27.md §3.1（内容語を lemma 化して level に当てる）
///
/// 用途は **文バンク前処理での学年解決**。`level`（約2,866語）は原形で収録されているため、
/// `plays`/`liked`/`running`/`boxes` などをまず原形へ寄せてから band を引く。
///
/// 方針：
///  - 完璧な形態素解析はしない（純Swift・辞書同梱なし）。**最頻パターン＋不規則語の小辞書**で十分。
///  - 最終判定は呼び出し側（`SentenceBankBuilder`）が「原形そのまま → lemma の順で level を引く」。
///    ここはあくまで**当てに行く候補**を返すだけ（外しても level に無ければ未収録として弾かれる）。
///  - 決定論（`Date()`/乱数/`hashValue` 不使用）。
public enum SimpleLemmatizer {

    /// 不規則変化（規則では戻せない語）。be動詞・代表的な不規則動詞・不規則複数・比較級など。
    static let irregular: [String: String] = [
        // be / 助動詞
        "is": "be", "am": "be", "are": "be", "was": "be", "were": "be", "been": "be", "being": "be",
        "has": "have", "had": "have", "having": "have",
        "does": "do", "did": "do", "done": "do", "doing": "do",
        // 不規則動詞（よく出るもの）
        "went": "go", "gone": "go", "goes": "go", "going": "go",
        "ate": "eat", "eaten": "eat", "eating": "eat",
        "came": "come", "coming": "come",
        "got": "get", "gotten": "get", "getting": "get",
        "gave": "give", "given": "give", "giving": "give",
        "made": "make", "making": "make",
        "said": "say", "saw": "see", "seen": "see", "seeing": "see",
        "took": "take", "taken": "take", "taking": "take",
        "knew": "know", "known": "know",
        "grew": "grow", "grown": "grow",
        "wrote": "write", "written": "write", "writing": "write",
        "bought": "buy", "caught": "catch", "taught": "teach", "thought": "think",
        "brought": "bring", "felt": "feel", "kept": "keep", "slept": "sleep",
        "left": "leave", "met": "meet", "told": "tell", "sold": "sell",
        "found": "find", "held": "hold", "stood": "stand", "understood": "understand",
        "swam": "swim", "swum": "swim", "sang": "sing", "sung": "sing",
        "drank": "drink", "drunk": "drink", "drove": "drive", "driven": "drive",
        "flew": "fly", "flown": "fly", "threw": "throw", "thrown": "throw",
        "began": "begin", "begun": "begin", "won": "win", "ran": "run", "running": "run",
        "sat": "sit", "sitting": "sit", "put": "put", "putting": "put",
        "read": "read", "let": "let", "cut": "cut", "hit": "hit",
        // 不規則複数
        "children": "child", "men": "man", "women": "woman",
        "feet": "foot", "teeth": "tooth", "mice": "mouse",
        "people": "person", "geese": "goose", "lice": "louse",
        // 比較級・最上級（不規則）
        "better": "good", "best": "good", "worse": "bad", "worst": "bad",
        "more": "much", "most": "much",
    ]

    /// 母音判定（y は文末以外で母音扱いだがここでは単純化）。
    private static func isVowel(_ c: Character) -> Bool {
        "aeiou".contains(c)
    }

    /// 語を原形候補に寄せる（小文字・トリム後にルール適用）。
    public static func lemma(_ raw: String) -> String {
        let w = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return w }
        if let m = irregular[w] { return m }
        return applyRules(w)
    }

    /// 規則ベースの語尾処理。短すぎる語は触らない（mangling 防止）。
    private static func applyRules(_ w: String) -> String {
        let chars = Array(w)
        let n = chars.count

        // -ies → -y（studies→study, flies→fly）。
        if n > 4, w.hasSuffix("ies") {
            return String(chars[..<(n - 3)]) + "y"
        }
        // -ied → -y（studied→study, tried→try）。
        if n > 4, w.hasSuffix("ied") {
            return String(chars[..<(n - 3)]) + "y"
        }
        // -es（sibilant のあと）→ 語幹（boxes→box, wishes→wish, watches→watch, buzzes→buzz, kisses→kiss）。
        if n > 3 {
            for sib in ["sses", "shes", "ches", "xes", "zes"] where w.hasSuffix(sib) {
                return String(chars[..<(n - 2)])
            }
        }
        // -ing → 語幹。doubled consonant（running→run）と e 復元（making→make）。
        if n > 4, w.hasSuffix("ing") {
            let stem = Array(chars[..<(n - 3)])
            return restoreStem(stem)
        }
        // -ed → 語幹。doubled consonant（stopped→stop）と e 復元（liked→like）。
        if n > 3, w.hasSuffix("ed") {
            let stem = Array(chars[..<(n - 2)])
            return restoreStem(stem)
        }
        // -est / -er（比較級・最上級）→ 語幹（faster→fast, biggest→big, nicer→nice）。
        if n > 4, w.hasSuffix("est") {
            return restoreStem(Array(chars[..<(n - 3)]))
        }
        if n > 4, w.hasSuffix("er") {
            return restoreStem(Array(chars[..<(n - 2)]))
        }
        // -s（複数・三単現）→ 語幹（apples→apple, likes→like, runs→run）。
        // ss/us/is で終わる語（glass, bus, this）は触らない。
        if n > 3, w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") {
            return String(chars[..<(n - 1)])
        }
        return w
    }

    /// -ing/-ed/-er 除去後の語幹を補正する。
    ///  - 末尾が同子音の重なり（runn, stopp）→ 1つ落とす（run, stop）。
    ///  - 子音終わりで母音が直前にある等は、e を足した形も妥当（lik→like, mak→make）が、
    ///    level 照合は「原形そのまま→lemma」の二段なので、ここでは **e 復元を優先**しすぎず
    ///    “重なり落とし”のみ確実に行い、e 形は候補として返す。
    private static func restoreStem(_ stem: [Character]) -> String {
        let n = stem.count
        guard n >= 2 else { return String(stem) }
        // 末尾が y の語幹はそのまま（played→play, stayed→stay）。y を子音扱いして e を足さない。
        if stem[n - 1] == "y" { return String(stem) }
        // 末尾同子音の重なり（vowel+C+C）→ 1つ落とす。
        if stem[n - 1] == stem[n - 2], !isVowel(stem[n - 1]) {
            return String(stem[..<(n - 1)])
        }
        // CVC でなく、母音で終わらない短語幹は e を補う（lik→like, mak→make, us→use の類）。
        // ただし誤補正を避けるため「語幹末が子音 かつ 直前が母音 かつ 長さ>=3」に限定。
        if n >= 3, !isVowel(stem[n - 1]), isVowel(stem[n - 2]), !isVowel(stem[n - 3]) {
            return String(stem) + "e"
        }
        return String(stem)
    }
}
