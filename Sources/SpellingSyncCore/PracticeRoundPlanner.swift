import Foundation

/// 練習の「同じ単語を N 回書く」1回ごとの段階。子ども向けに“意味が見える階段”にするための純ロジック。
///
/// 背景（[[child-ignores-horizontal-text]] / CLAUDE.md 子ども原則）：
/// 3回書く意味を**横並びの文字では説明しない**。代わりに「お手本がだんだん薄くなる」視覚変化と
/// キャラ・音声で伝える。回が進むほどお手本を薄くし、最後は“じぶんで書く”ヒーローの回にする。
public enum PracticeRoundStage: Equatable, Sendable {
    /// 最初の回：お手本くっきり（みてかく）。
    case look
    /// 中間の回：お手本うすい（なぞる/思い出す）。
    case trace
    /// 最後の回：お手本ほぼ無し（じぶんで書く）。
    case memory
}

public struct PracticeRoundProgress: Equatable, Sendable {
    /// この回の開始時のお手本の濃さ（回が進むほど薄い。最後の回はさらに 0 へフェードさせる想定）。
    public let guideStartOpacity: Double
    /// この回の段階（お手本の濃さ・キャラの表情/セリフの選択に使う）。
    public let stage: PracticeRoundStage
    /// この回を終えたら光る⭐️の数（1 始まり）。
    public let starsFilled: Int
    /// ⭐️の総数（＝総回数）。
    public let totalStars: Int
    /// 最後の回か（＝単語完了＝コイン付与のタイミング）。
    public let isFinal: Bool

    public init(guideStartOpacity: Double, stage: PracticeRoundStage,
                starsFilled: Int, totalStars: Int, isFinal: Bool) {
        self.guideStartOpacity = guideStartOpacity
        self.stage = stage
        self.starsFilled = starsFilled
        self.totalStars = totalStars
        self.isFinal = isFinal
    }
}

public enum PracticeRoundPlanner {
    /// - Parameters:
    ///   - round: 0 始まりの回インデックス（`practiceRepeatIndex`）。
    ///   - totalRounds: 総回数（練習は最低3）。
    ///   - baseOpacity: お手本の基準の濃さ（例 0.30）。
    /// - Returns: その回の段階情報。
    public static func progress(round: Int, totalRounds: Int, baseOpacity: Double) -> PracticeRoundProgress {
        let total = max(totalRounds, 1)
        let r = min(max(round, 0), total - 1)
        let isFinal = r == total - 1
        // 段階フェード：最初 = base、以降 (total-r)/total で線形に薄く。最後の回でも >0 で始め、
        // UI 側でそこから 0 へゆっくり消す（一瞬見てから思い出して書ける）。
        let opacity = baseOpacity * Double(total - r) / Double(total)
        let stage: PracticeRoundStage = (r == 0) ? .look : (isFinal ? .memory : .trace)
        return PracticeRoundProgress(
            guideStartOpacity: opacity,
            stage: stage,
            starsFilled: r + 1,
            totalStars: total,
            isFinal: isFinal)
    }
}
