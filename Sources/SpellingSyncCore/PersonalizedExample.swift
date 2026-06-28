import Foundation

// 練習中の例文ヒントを「Cast で名前入りに差し替える」純粋ロジック。
// 設計: docs/personalized-sentences-spec-2026-06-28.md（練習ヒントへの適用）
//
// 使い方（アプリ層）：いま練習している単語 `word` を渡すと、
//   - その語を教えるテンプレ（contentLemmas に語を含む・スロットあり）を
//   - seed で決定論的に1件選び、
//   - その世帯の Cast で SentencePersonalizer.resolve して
// 名前入り SentenceItem を返す。名前を埋められない（＝fallback になる）場合は
// nil を返し、呼び出し側は既存の静的例文（WordBank）にフォールバックする。
//
// なぜ fallback を返さないか：fallback は名前の入らない汎用文で、静的例文と価値が
// 変わらない。むしろ良質な同梱例文を別の汎用文に置き換えてしまう。名前が入った
// ときだけ差し替える＝「あ、さくらが出てきた」の体験だけを足す、が本機能の趣旨。

public enum PersonalizedExample {
    /// 指定語を教える名前入り例文を1件返す。名前が入らない/該当なしは nil。
    /// - Parameters:
    ///   - word: いま練習している単語（大文字小文字は無視して照合）。
    ///   - templates: 承認済みテンプレ群（同梱 JSON 由来）。
    ///   - cast: その世帯の登場人物（親がローカル登録）。
    ///   - seed: 決定論シード（同じ語では安定して同じ人/文が出るよう固定値を渡す）。
    public static func sentence(
        for word: String,
        templates: [PersonSentenceTemplate],
        cast: Cast,
        seed: UInt64
    ) -> SentenceItem? {
        let target = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }

        // 照合は contentLemmas との完全一致（小文字化）。練習語は基本形が大半なので
        // 「apple」「book」「run」等はそのまま当たる。屈折形（apples / went / studies）は
        // v1 では当てない＝該当なしとして静的例文にフォールバックする（誤マッチより安全側）。
        // 屈折形まで当てたくなったら、ここに決定論的な正規化/別名層をテスト付きで足す。
        // 名前が入り得る（スロットあり）かつ対象語を教えるテンプレだけを候補に。
        let matches = templates.filter { template in
            !template.slots.isEmpty
                && template.contentLemmas.contains { $0.lowercased() == target }
        }
        guard !matches.isEmpty else { return nil }

        // seed で安定した順に並べ（タイブレークは id 昇順）、先頭から
        // 「名前が実際に入った（fallback でない）」最初の解を採る。
        let ordered = matches.sorted { lhs, rhs in
            let lh = DeterministicHash.mix(lhs.id, seed)
            let rh = DeterministicHash.mix(rhs.id, seed)
            return lh != rh ? lh < rh : lhs.id < rhs.id
        }
        for template in ordered {
            let resolved = SentencePersonalizer.resolve(template, cast: cast, seed: seed)
            // resolve はスロットを埋められないと template.fallback をそのまま返す。
            // その場合は名前が入っていない＝採用しない（既存の静的例文に任せる）。
            if resolved.id != template.fallback.id {
                return resolved
            }
        }
        return nil
    }
}
