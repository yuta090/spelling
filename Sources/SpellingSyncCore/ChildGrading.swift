import Foundation

/// 子ども向けのやさしい判定。
///
/// 芯: **「機械が字を読めたか（＝綺麗さ・読みやすさ）」を「綴りの正誤」と混同しない**。
/// 低学年はまだ字が整わないのが当たり前で、端末OCRが読めないことは頻繁に起きる。
/// これを「間違い（✕）」として子どもに見せると「点が取れない＝自分はダメ」とモチベが下がる。
/// そこで、機械が読めなかっただけの答案は `pending`（中立）として扱い、達成を邪魔しない。
///
/// - `correct`   : はっきり正しい（自動正解 or 親OK）。褒める。
/// - `pending`   : 機械が読めなかっただけ（needsReview/rewrite/timeExpired・親未採点）。罰しない・中立。
/// - `tryAgain`  : はっきり綴りが違う（autoIncorrect or 親「直そう」）。やさしく「もう いちど」。
public enum ChildOutcome: String, Sendable, Equatable {
    case correct
    case pending
    case tryAgain
}

public enum ChildGrading {

    /// 1答案の子ども向け判定。親採点があれば自動採点を上書きする（親が最終権威）。
    public static func outcome(decision: GradeDecisionState,
                               parentReview: ParentReviewState) -> ChildOutcome {
        switch parentReview {
        case .approved:
            return .correct
        case .needsPractice:
            return .tryAgain
        case .unreviewed:
            switch decision {
            case .autoCorrect:
                return .correct
            case .autoIncorrect:
                return .tryAgain
            case .needsReview, .rewrite, .timeExpired:
                // 機械が読めなかっただけ。間違いにしない（親があとで確認する）。
                return .pending
            }
        }
    }

    /// 達成ゲートで、この1答案が達成を「満たす」か。
    ///
    /// 表示（`outcome`）とは別軸。芯は「**はっきりした綴りミスが無く、かつ本人が実際に手書きした**」こと。
    /// - `tryAgain` : 満たさない（はっきりした綴りミス）
    /// - `correct` / `pending` : `genuineAttempt`（実際に書いたか）のときだけ満たす。
    ///
    /// `correct` にも `genuineAttempt` を要求するのが重要:
    /// 通常の自動正解は必ずインクがある（書かずにOCR正解にはならない）ので実害は無いが、
    /// **親採点の一括承認（未採点はデフォルトOK）で空答案が `autoCorrect` に化けても、
    /// インクが無ければ達成にしない**＝パス連打/時間切れを親のデフォルト承認ですり抜けさせない。
    public static func achievementSatisfied(outcome: ChildOutcome, genuineAttempt: Bool) -> Bool {
        switch outcome {
        case .tryAgain:
            return false
        case .correct, .pending:
            return genuineAttempt
        }
    }

    /// 子どもの達成（クラウン／ごほうび／ことばパズル解放）ゲート。
    /// 対象語がすべて `achievementSatisfied` を満たせば達成（空は未達成）。
    public static func isAchieved(satisfied: [Bool]) -> Bool {
        !satisfied.isEmpty && satisfied.allSatisfy { $0 }
    }
}
