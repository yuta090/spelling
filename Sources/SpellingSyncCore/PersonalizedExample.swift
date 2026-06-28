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

        // 名前が入り得る（スロットあり）かつ対象語を扱うテンプレだけを候補に。
        let matches = templates.filter { template in
            !template.slots.isEmpty && teaches(template, word: target)
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

    // MARK: - 対象語の照合（決定論・純粋）

    /// テンプレが練習語 `word`（小文字化済み）を扱うか。
    /// (a) 教える基本語 `contentLemmas` に一致、または
    /// (b) 例文中に**実際に現れる英単語**（`enTokens` の literal の表層形）に一致、なら真。
    ///
    /// 「その文に実在する綴り」だけを当てるのがミソ。apple は (a)、apples / likes は (b) で当たり、
    /// 一方 "seed" は "see" の文に存在しないので当たらない＝形態素を機械生成しないため
    /// 実在語どうしの誤マッチ（see→seed, good→goods 等）が原理的に起きない。
    static func teaches(_ template: PersonSentenceTemplate, word: String) -> Bool {
        if template.contentLemmas.contains(where: { $0.lowercased() == word }) { return true }
        for token in template.enTokens {
            guard case let .literal(text) = token else { continue }   // 人物（名前/代名詞）は対象外
            for piece in text.split(whereSeparator: { $0 == " " }) where surfaceWord(String(piece)) == word {
                return true
            }
        }
        return false
    }

    /// 英語トークンの表層形を比較用に正規化：小文字化し、前後の句読点/空白を除く。
    private static func surfaceWord(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: trimSet)
    }
    private static let trimSet = CharacterSet(charactersIn: " ,.!?;:'\"")
}
