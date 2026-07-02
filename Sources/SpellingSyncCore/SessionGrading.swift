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
