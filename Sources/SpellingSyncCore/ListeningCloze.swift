import Foundation

/// リスニング穴埋めの純ロジック。
/// 設計: docs/kotoba-puzzle-spec-2026-06-28.md（形式カタログ「リスニング穴埋め」）
///
/// 穴埋め選択（`ClozeChoiceGenerator`）を流用しつつ、おとりを **音が近い語**
/// （`ConfusablesSound`）に固定する。設問中は無音・回答後に文を読み上げる体験用で、
/// 音そのものは View 側（`SpeechPlayer`）が鳴らす。ここは「どの語を空所にし、
/// どの音類似語をおとりにするか」を決定論で決めるだけ。
///
/// この形式は「音が紛らわしい綴り」を選ばせるのが肝なので、空所語に承認済みの
/// 音類似おとりが無ければ問題を作らない（= nil）。
public enum ListeningClozeGenerator {
    /// リスニング穴埋めを1問生成する。
    /// - confusables: 音類似おとり辞書（既定で承認済み行のみ採用）。
    /// - blankIndex: 空所位置。nil なら音類似おとりを持つトークンから自動選択
    ///   （内容語に当たりやすい最長を優先、同長は最小 index）。
    /// - optionCount: 選択肢の最大数（正解込み・最低2）。
    /// 空所語に使えるおとりが無い／トークン空／範囲外は nil。
    public static func make(from item: SentenceItem,
                            confusables: [ConfusableEntry],
                            blankIndex: Int? = nil,
                            optionCount: Int = 4,
                            seed: UInt64) -> ClozeChoiceExercise? {
        guard !item.tokens.isEmpty else { return nil }

        if let explicit = blankIndex {
            guard item.tokens.indices.contains(explicit) else { return nil }
            return makeAt(explicit, from: item, confusables: confusables,
                          optionCount: optionCount, seed: seed)
        }

        // 空所未指定：おとりを持つ候補を優先順（内容語に当たりやすい最長→同長は最小index）に並べ、
        // 最初に「問題として成立する（選択肢が2つ以上できる）」ものを採用する。
        // 最長候補のおとりが自分自身/重複だけで成立しない場合も、次の候補へフォールバックできる。
        for idx in candidateBlankIndices(item.tokens, confusables: confusables) {
            if let ex = makeAt(idx, from: item, confusables: confusables,
                               optionCount: optionCount, seed: seed) {
                return ex
            }
        }
        return nil
    }

    /// 指定 index を空所にして1問作る。おとり0／成立しなければ nil。
    private static func makeAt(_ idx: Int, from item: SentenceItem,
                               confusables: [ConfusableEntry],
                               optionCount: Int, seed: UInt64) -> ClozeChoiceExercise? {
        let distractors = ConfusablesSound.distractors(for: item.tokens[idx], in: confusables)
        guard !distractors.isEmpty else { return nil }   // 音の近いおとりが無ければ作らない
        return ClozeChoiceGenerator.make(from: item, distractors: distractors,
                                         blankIndex: idx, optionCount: optionCount, seed: seed)
    }

    /// 音類似おとりを持つトークンの index を優先順に並べる。
    /// 内容語に当たりやすい最長を優先、同長は最小 index。
    static func candidateBlankIndices(_ tokens: [String], confusables: [ConfusableEntry]) -> [Int] {
        tokens.indices
            .filter { !ConfusablesSound.distractors(for: tokens[$0], in: confusables).isEmpty }
            .sorted { a, b in
                tokens[a].count != tokens[b].count ? tokens[a].count > tokens[b].count : a < b
            }
    }
}
