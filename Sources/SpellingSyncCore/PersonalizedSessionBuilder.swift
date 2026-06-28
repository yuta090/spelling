import Foundation

// パーソナライズ例文の「1セッション分」を組む純粋ロジック。
// 仕様: docs/personalized-sentences-spec-2026-06-28.md（§3-§5）。
//
// 役割：承認済みテンプレ集（同梱）＋ その世帯の Cast から、
//   - カテゴリで絞り（nil=全部）
//   - 決定論シャッフルで seed 依存に選び（飽きないよう毎回ちがう並び）
//   - 件数上限まで取り出し
//   - 各テンプレを `SentencePersonalizer.resolve` で解決済み `SentenceItem` に
// する。以降は既存の `WordOrderingGenerator` / `SentenceFeedback` がそのまま食う。
//
// 決定論：Date()/乱数/hashValue を使わない。同 seed → 同じ並び・選択（再現可能）。

public enum PersonalizedSessionBuilder {

    /// テンプレ集＋Cast から解決済み `SentenceItem` 列を組む。
    /// - Parameters:
    ///   - templates: 承認済みテンプレ（同梱 JSON 由来）。
    ///   - cast: その世帯の登場人物（本人＋友達）。空でもフォールバック文で成立。
    ///   - category: 絞り込むカテゴリ。`nil` で全カテゴリ。
    ///   - count: セッションに入れる最大問題数（プールが小さければプール数）。
    ///   - seed: 決定論シード（同値→同結果）。
    public static func build(
        templates: [PersonSentenceTemplate],
        cast: Cast,
        category: SentenceCategory? = nil,
        count: Int,
        seed: UInt64
    ) -> [SentenceItem] {
        guard count > 0 else { return [] }

        // カテゴリ絞り込み（nil=全部）。
        let pool = templates.filter { category == nil || $0.category == category }
        guard !pool.isEmpty else { return [] }

        // seed 依存の決定論シャッフル。同 seed→同順、別 seed→別順。
        // 同ハッシュ衝突時も id を tiebreaker にして全順序を保証（sort 安定性に依存しない）。
        let ordered = pool.sorted { lhs, rhs in
            let hl = DeterministicHash.mix(lhs.id, seed)
            let hr = DeterministicHash.mix(rhs.id, seed)
            if hl != hr { return hl < hr }
            return lhs.id < rhs.id
        }

        let picked = ordered.prefix(count)
        return picked.enumerated().map { offset, template in
            // 問題ごとに seed を変える＝同一セッション内でも友達選択が問題ごとに変わる。
            let itemSeed = DeterministicHash.splitmix(seed &+ UInt64(offset))
            return SentencePersonalizer.resolve(template, cast: cast, seed: itemSeed)
        }
    }

    /// テンプレ集をカテゴリ別に数える。親UIの「カテゴリ選択」で
    /// 空カテゴリを隠す／件数バッジを出すために使う（純粋・決定論）。
    /// テンプレが1件も無いカテゴリはキーに現れない（合計＝テンプレ総数）。
    public static func categoryCounts(templates: [PersonSentenceTemplate]) -> [SentenceCategory: Int] {
        var counts: [SentenceCategory: Int] = [:]
        for template in templates {
            counts[template.category, default: 0] += 1
        }
        return counts
    }
}
