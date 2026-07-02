import Foundation

/// テスト直後の「その場採点 → そのまま復習」で使う純ロジック。
///
/// 芯: **親が『直そう』にした単語だけ**を、出題順のまま・重複なしで子の復習（かき）に渡す。
/// - 未採点（デフォルトOK扱い）は復習に回さない＝親が明示的に「直そう」にした語だけ。
/// - 同じ単語が複数回出た場合はまとめて1回（どれか1つでも `needsPractice` なら対象）。
/// - 表示綴りは最初に現れたものを保つ（大文字小文字の違いは同じ単語として扱う）。
public enum SessionGrading {

    /// 採点対象の1項目（子の答案）。同じ単語が複数回出ても順序・重複排除できるよう word を持つ。
    public struct GradedItem: Equatable, Sendable {
        public var word: String
        public var decision: ParentReviewState

        public init(word: String, decision: ParentReviewState) {
            self.word = word
            self.decision = decision
        }
    }

    /// 採点後に子へ見せる結果サマリ（「何問中何問せいかい」＋復習に回す単語）。
    /// - `total`: 出題した**異なる単語数**（同じ単語が複数回出ても1問）。
    /// - `correctCount`: 直そうにならなかった単語数（＝ `total - needsPractice.count`）。
    /// - `needsPractice`: 「直そう」の単語（出題順・重複なし）。
    /// 不変条件: `correctCount + needsPractice.count == total`。
    public struct ResultSummary: Equatable, Sendable {
        public var total: Int
        public var correctCount: Int
        public var needsPractice: [String]

        public init(total: Int, correctCount: Int, needsPractice: [String]) {
            self.total = total
            self.correctCount = correctCount
            self.needsPractice = needsPractice
        }
    }

    /// 採点済み項目から結果サマリを作る（純粋・重複は単語単位で排除）。
    /// 「1つでも直そう」の単語だけを不正解（復習対象）とし、残りは正解（未採点はOK扱い）。
    public static func summarize(_ items: [GradedItem]) -> ResultSummary {
        var distinctKeys = Set<String>()
        for item in items { distinctKeys.insert(item.word.lowercased()) }
        let needs = wordsNeedingPractice(items)
        let total = distinctKeys.count
        return ResultSummary(total: total, correctCount: total - needs.count, needsPractice: needs)
    }

    /// 「直そう（needsPractice）」になった単語を、出題順のまま・重複なしで返す。
    public static func wordsNeedingPractice(_ items: [GradedItem]) -> [String] {
        var orderedFirstSpelling: [String] = []
        var seenKeys = Set<String>()
        var needsKeys = Set<String>()

        for item in items {
            let key = item.word.lowercased()
            if seenKeys.insert(key).inserted {
                orderedFirstSpelling.append(item.word)
            }
            if item.decision == .needsPractice {
                needsKeys.insert(key)
            }
        }

        return orderedFirstSpelling.filter { needsKeys.contains($0.lowercased()) }
    }
}
