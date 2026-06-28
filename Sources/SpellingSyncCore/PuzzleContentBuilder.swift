import Foundation

/// ことばパズルの「出題プール」を文バンク（解決済み `SentenceItem` 列）から決定論的に組み立てる。
/// UI(`PuzzleContent`)はこの結果を各 Generator に渡すだけ＝判断ロジックはコアに集約（CLAUDE.md）。
/// source 非依存：静的バンクでもパーソナライズ由来でも同じく扱える。
///
/// 設計: docs/kotoba-puzzle-spec-2026-06-28.md / exercise-formats-and-distractors-2026-06-28.md
public enum PuzzleContentBuilder {

    /// あなうめ系（選択）の1問のもと：文・空所位置・おとり候補。
    public struct ClozeSample: Equatable, Sendable {
        public var item: SentenceItem
        public var blankIndex: Int
        /// おとり候補（順序は決定論。実際の採否・数の上限は Generator が決める）。
        public var distractors: [String]
        public init(item: SentenceItem, blankIndex: Int, distractors: [String]) {
            self.item = item
            self.blankIndex = blankIndex
            self.distractors = distractors
        }
    }

    // MARK: ぶんづくり（並べ替え）

    /// 並べ替え可能な文だけを残す（1語・全同一語は不成立）。
    public static func orderingItems(_ items: [SentenceItem]) -> [SentenceItem] {
        items.filter(\.isScramblable)
    }

    // MARK: あなうめ（選択・読む）

    /// 各文の内容語（最長トークン）を空所にし、おとりは **同じか下の学年** の内容語から決定論的に選ぶ。
    /// おとり候補が1つも無い文（語彙が薄い）は出題にならないので除外する。
    public static func clozeSamples(_ items: [SentenceItem],
                                    seed: UInt64) -> [ClozeSample] {
        // 文ごとの代表内容語（最長トークン）と学年。これがおとりの母集合になる。
        // 1語の断片は文脈が無く、空所にもおとりにもふさわしくないので2語以上だけ使う。
        let reps: [(word: String, band: Int)] = items.compactMap { item in
            guard item.tokens.count >= 2 else { return nil }
            let idx = ClozeChoiceGenerator.defaultBlankIndex(item.tokens)
            return (item.tokens[idx], item.gradeBand)
        }

        var out: [ClozeSample] = []
        for (i, item) in items.enumerated() {
            guard item.tokens.count >= 2 else { continue }
            let idx = ClozeChoiceGenerator.defaultBlankIndex(item.tokens)
            let answer = item.tokens[idx]

            // 同じか下の学年の代表内容語をおとり候補に（正解は除外）。重複は一意化（順序保持）。
            var seen = Set<String>()
            let candidates = reps
                .filter { $0.band <= item.gradeBand && $0.word.lowercased() != answer.lowercased() }
                .map(\.word)
                .filter { seen.insert($0.lowercased()).inserted }

            guard !candidates.isEmpty else { continue }   // おとり0は問題にならない
            let distractors = SeededShuffle.shuffle(candidates, seed: seed &+ UInt64(i))
            out.append(ClozeSample(item: item, blankIndex: idx, distractors: distractors))
        }
        return out
    }

    // MARK: きいて あなうめ

    /// 音類似おとりを持つトークンがある文だけを残し、その語を空所にする。
    /// 空所選択・おとり供給は `ListeningClozeGenerator`（nil 指定で自動選択）に委譲。
    public static func listeningSamples(_ items: [SentenceItem],
                                        confusables: [ConfusableEntry],
                                        seed: UInt64) -> [ClozeSample] {
        items.compactMap { item in
            guard let ex = ListeningClozeGenerator.make(from: item, confusables: confusables,
                                                        blankIndex: nil, optionCount: 4, seed: seed)
            else { return nil }
            return ClozeSample(item: item, blankIndex: ex.blankIndex, distractors: [])
        }
    }

    // MARK: おとを きいて えらぶ（単語リスニング）

    /// 音類似おとりを作れる見出し語だけを返す（重複は一意化・順序保持）。
    public static func listeningWords(_ confusables: [ConfusableEntry]) -> [String] {
        var seen = Set<String>()
        return confusables.compactMap { entry in
            guard !ConfusablesSound.distractors(for: entry.word, in: confusables).isEmpty else { return nil }
            return seen.insert(entry.word.lowercased()).inserted ? entry.word : nil
        }
    }
}
