import Foundation

/// 練習の1回ごとの「お祝いプラン」を決める純ロジック。
///
/// ねらい（飽き防止）：
/// - **文脈フレーズ**：あと1回なら「あといっかい！」、単語完了なら完了のことば＝ランダムより“見てくれてる感”。
/// - **レア（大当たり）**：単語完了時に低確率（1/8）で特別演出＋コイン2倍。毎回同じ強度だと3日で慣れる。
/// - **直前重複回避**：同じほめ言葉が連続で出ない。
///
/// [[child-ignores-horizontal-text]]：フレーズは短く・ひらがな/カタカナのみ（声と中央大表示で使う）。
/// ランダム性は `RandomNumberGenerator` を注入＝シードすればテスト可能。
public enum PracticeCheer {

    public struct Plan: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// 中間の回（一般のほめ言葉）。
            case midRound
            /// つぎが最後の回（カウントダウンで期待を作る）。
            case oneMoreToGo
            /// 最後の回＝単語完了（コイン付与のタイミング。レアはここでだけ起こる）。
            case wordCompleted
        }

        public let kind: Kind
        /// 大当たりか（wordCompleted のみ true になりうる）。
        public let isRare: Bool
        /// 表示＆読み上げるフレーズ（言語解決済み）。
        public let phrase: String
        /// コイン倍率（レア＝2、通常＝1）。
        public let coinMultiplier: Int
    }

    /// レアの発生率＝ 1/rareChanceDenominator。
    public static let rareChanceDenominator = 8

    /// 「つぎで最後」の回のフレーズ。
    public static let oneMoreJapanese: [String] = [
        "あと いっかい！",
        "つぎで さいご！",
        "もう すこし！"
    ]

    public static let oneMoreEnglish: [String] = [
        "One more!",
        "Last one next!",
        "Almost there!"
    ]

    /// 単語完了（通常）のフレーズ。
    public static let completedJapanese: [String] = [
        "ぜんぶ かけた！",
        "かんぺき！",
        "マスターしたね！",
        "できたー！",
        "はくしゅー！",
        "すごすぎる！"
    ]

    public static let completedEnglish: [String] = [
        "You did it!",
        "Perfect!",
        "Mastered it!",
        "All done!",
        "High five!",
        "So good!"
    ]

    /// レア（大当たり）専用のフレーズ。レアの時にしか聞けない特別語彙。
    public static let rareJapanese: [String] = [
        "スーパーすごい！",
        "キラキラ だいばくはつ！",
        "ミラクル！",
        "でんせつだ！"
    ]

    public static let rareEnglish: [String] = [
        "SUPER amazing!",
        "MEGA wow!",
        "Miracle!",
        "Legendary!"
    ]

    /// この回のお祝いプランを決める。
    /// - Parameters:
    ///   - round: 0 始まりの回インデックス（`practiceRepeatIndex`）。
    ///   - totalRounds: 総回数。
    ///   - japanese: 日本語なら true。
    ///   - previousPhrase: 直前に出したフレーズ（同じものを連続で出さない）。
    ///   - rng: 乱数源（テストではシード済みを注入）。
    public static func plan(round: Int, totalRounds: Int, japanese: Bool,
                            previousPhrase: String?,
                            using rng: inout some RandomNumberGenerator) -> Plan {
        let total = max(totalRounds, 1)
        let r = min(max(round, 0), total - 1)

        let kind: Plan.Kind
        if r == total - 1 {
            kind = .wordCompleted
        } else if r == total - 2 {
            kind = .oneMoreToGo
        } else {
            kind = .midRound
        }

        let isRare = kind == .wordCompleted
            && Int.random(in: 0..<rareChanceDenominator, using: &rng) == 0

        let pool: [String]
        switch kind {
        case .midRound:
            pool = japanese ? PracticePraise.japanese : PracticePraise.english
        case .oneMoreToGo:
            pool = japanese ? oneMoreJapanese : oneMoreEnglish
        case .wordCompleted:
            if isRare {
                pool = japanese ? rareJapanese : rareEnglish
            } else {
                pool = japanese ? completedJapanese : completedEnglish
            }
        }

        return Plan(
            kind: kind,
            isRare: isRare,
            phrase: pick(from: pool, excluding: previousPhrase, using: &rng),
            coinMultiplier: isRare ? 2 : 1)
    }

    /// プールからランダムに1つ選ぶ。直前のフレーズは（プールに2つ以上あれば）除外する。
    private static func pick(from pool: [String], excluding previous: String?,
                             using rng: inout some RandomNumberGenerator) -> String {
        guard !pool.isEmpty else { return "" }
        let candidates: [String]
        if let previous, pool.count > 1 {
            let filtered = pool.filter { $0 != previous }
            candidates = filtered.isEmpty ? pool : filtered
        } else {
            candidates = pool
        }
        let i = Int.random(in: 0..<candidates.count, using: &rng)
        return candidates[i]
    }
}
