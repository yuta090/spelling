import Foundation

/// 単語リスニング（音を聞いて正しい綴りを選ぶ）の純ロジック。
/// 設計: docs/exercise-formats-and-distractors-2026-06-28.md
///
/// 音声で `word` を再生 → 候補（正解＋おとり）から綴りを選ばせる。
/// おとりは confusables_sound（[[ConfusablesSound]]）など呼び出し側が用意。ここは決定論で組むだけ。

/// 単語リスニング 1問。
public struct WordListeningExercise: Equatable, Sendable {
    /// 読み上げ＝正解語。
    public var word: String
    /// 選択肢（正解＋おとり・決定論シャッフル済み）。
    public var options: [String]
    /// 正解（= word）。
    public var answer: String

    public init(word: String, options: [String], answer: String) {
        self.word = word
        self.options = options
        self.answer = answer
    }
}

public enum WordListeningGenerator {
    /// 単語リスニングを生成する。
    /// - distractors: 正解以外の候補（呼び出し側が用意）。正解と同じ/重複は除外。
    /// - optionCount: 選択肢の最大数（正解込み）。最低2（正解＋おとり1）。
    /// 使えるおとりが0で選択肢が1つしか作れない場合は nil。
    public static func make(word: String,
                            distractors: [String],
                            optionCount: Int = 4,
                            seed: UInt64) -> WordListeningExercise? {
        guard !word.isEmpty else { return nil }
        let cap = max(2, optionCount)
        var options = [word]
        for d in distractors {
            if options.count >= cap { break }
            if d != word && !options.contains(d) {
                options.append(d)
            }
        }
        guard options.count >= 2 else { return nil }   // 正解だけでは問題にならない

        return WordListeningExercise(
            word: word,
            options: SeededShuffle.shuffle(options, seed: seed),
            answer: word
        )
    }
}

/// 単語リスニングの採点（決定的）。
public enum WordListeningGrader {
    public static func grade(selected: String, answer: String) -> ClozeGrade {
        ClozeGrade(isCorrect: selected == answer)
    }
}
