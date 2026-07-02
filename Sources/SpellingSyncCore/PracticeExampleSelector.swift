import Foundation

/// スペル練習（書き問題）のヒント例文を、生成バンク（学年タグ付き `SentenceItem`）から選ぶ純ロジック。
///
/// 従来は同梱 `wordbank.sqlite` の `examples` 表（田中コーパス由来の大人向け自然文）を語彙制御せず
/// そのまま出しており、低学年で未習語が混ざっていた。ここでは
/// **「その練習語を含み・子の段階（`ContentPolicy`）で読める生成文」**だけを候補にする。
/// 制約（band / 文法天井 / 漢字の壁 / ジャンル / i+1）は既存の `ContentPolicy.admissiblePool` に委譲し、
/// この層は **「練習語を含むか」の見出し語照合** と **決定論的な並び/選択** だけを足す薄いラッパ。
///
/// 候補が無ければ `nil`（呼び出し側は例文を出さないフォールバックに落とす）。
public enum PracticeExampleSelector {
    /// 練習語 `word` を含み、段階 `policy` で見せてよい生成文を**決定論順**で返す（順序は `order` 参照）。
    public static func candidates(
        for word: String,
        in items: [SentenceItem],
        policy: ContentPolicy,
        knownLemmas: Set<String> = [],
        exemptRegisteredLemmas: Set<String> = [],
        bandOf: [String: Int] = [:]
    ) -> [SentenceItem] {
        let target = SimpleLemmatizer.lemma(word)
        guard !target.isEmpty else { return [] }
        let matching = items.filter { contains($0, lemma: target) }
        let admissible = ContentPolicy.admissiblePool(
            matching, policy: policy, knownLemmas: knownLemmas,
            exemptRegisteredLemmas: exemptRegisteredLemmas, bandOf: bandOf
        )
        return admissible.sorted(by: order)
    }

    /// 候補から1つ選ぶ。`seed` で決定論的に回転させる（繰り返し表示で多様性を出す）。候補ゼロは `nil`。
    public static func example(
        for word: String,
        in items: [SentenceItem],
        policy: ContentPolicy,
        knownLemmas: Set<String> = [],
        exemptRegisteredLemmas: Set<String> = [],
        bandOf: [String: Int] = [:],
        seed: UInt64 = 0
    ) -> SentenceItem? {
        let cands = candidates(for: word, in: items, policy: policy, knownLemmas: knownLemmas,
                               exemptRegisteredLemmas: exemptRegisteredLemmas, bandOf: bandOf)
        guard !cands.isEmpty else { return nil }
        return cands[Int(seed % UInt64(cands.count))]
    }

    /// 文がその見出し語を内容語（`contentLemmas`）またはトークンとして含むか（両側を見出し語化して比較）。
    static func contains(_ item: SentenceItem, lemma target: String) -> Bool {
        if item.contentLemmas.contains(where: { SimpleLemmatizer.lemma($0) == target }) { return true }
        return item.tokens.contains(where: { SimpleLemmatizer.lemma($0) == target })
    }

    /// 決定論的な優先順位：学年band低い → 短い（token数） → 英文アルファベット順 → id。
    /// 低学年ほどやさしく短い例文を優先し、同点は安定に並べる（同入力＝同出力）。
    static func order(_ a: SentenceItem, _ b: SentenceItem) -> Bool {
        if a.gradeBand != b.gradeBand { return a.gradeBand < b.gradeBand }
        if a.tokens.count != b.tokens.count { return a.tokens.count < b.tokens.count }
        if a.en != b.en { return a.en < b.en }
        return a.id.uuidString < b.id.uuidString
    }
}
