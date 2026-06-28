import Foundation

/// 穴埋め・選択（読む）の純ロジック。
/// 設計: docs/exercise-formats-and-distractors-2026-06-28.md
///
/// 文の1トークンを空所にし、正解＋おとりから選ばせる。おとり（distractors）は
/// アプリ/データ層が用意（語形変化・同band語・confusables）。ここは決定論で組むだけ。

/// 穴埋め選択 1問（提示＋正解）。
public struct ClozeChoiceExercise: Equatable, Sendable {
    public var itemID: UUID
    /// 子に見せる和訳プロンプト。
    public var prompt: String
    /// 空所にするトークンの位置。
    public var blankIndex: Int
    /// 文のトークン列（空所位置は `blankIndex`）。
    public var displayTokens: [String]
    /// 選択肢（正解＋おとり・決定論シャッフル済み）。
    public var options: [String]
    /// 正解トークン。
    public var answer: String

    public init(itemID: UUID, prompt: String, blankIndex: Int,
                displayTokens: [String], options: [String], answer: String) {
        self.itemID = itemID
        self.prompt = prompt
        self.blankIndex = blankIndex
        self.displayTokens = displayTokens
        self.options = options
        self.answer = answer
    }
}

public enum ClozeChoiceGenerator {
    /// 穴埋め選択を生成する。
    /// - distractors: 正解以外の候補（呼び出し側が用意）。正解と同じ/重複は除外。
    /// - blankIndex: 空所位置。nil なら既定（最長トークン＝内容語に当たりやすい）。
    /// - optionCount: 選択肢の最大数（正解込み）。最低2（正解＋おとり1）。
    /// 使えるおとりが0で選択肢が1つしか作れない場合や、トークン空/範囲外は nil。
    public static func make(from item: SentenceItem,
                            distractors: [String],
                            blankIndex: Int? = nil,
                            optionCount: Int = 4,
                            seed: UInt64) -> ClozeChoiceExercise? {
        guard !item.tokens.isEmpty else { return nil }
        let idx = blankIndex ?? defaultBlankIndex(item.tokens)
        guard item.tokens.indices.contains(idx) else { return nil }

        let answer = item.tokens[idx]
        let cap = max(2, optionCount)
        var options = [answer]
        for d in distractors {
            if options.count >= cap { break }
            if d != answer && !options.contains(d) {
                options.append(d)
            }
        }
        guard options.count >= 2 else { return nil }   // 正解だけでは問題にならない

        return ClozeChoiceExercise(
            itemID: item.id,
            prompt: item.ja,
            blankIndex: idx,
            displayTokens: item.tokens,
            options: SeededShuffle.shuffle(options, seed: seed),
            answer: answer
        )
    }

    /// 既定の空所＝最長トークン（内容語に当たりやすい）。同長は最小 index。
    static func defaultBlankIndex(_ tokens: [String]) -> Int {
        var best = 0
        for (i, token) in tokens.enumerated() where token.count > tokens[best].count {
            best = i
        }
        return best
    }
}

/// 穴埋め選択の採点（決定的）。
public struct ClozeGrade: Equatable, Sendable {
    public var isCorrect: Bool
    public init(isCorrect: Bool) { self.isCorrect = isCorrect }
}

public enum ClozeChoiceGrader {
    public static func grade(selected: String, answer: String) -> ClozeGrade {
        ClozeGrade(isCorrect: selected == answer)
    }
}
