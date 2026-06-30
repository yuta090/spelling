import Foundation

/// 手書きの「ていねいさ」称賛ティア。**最低でもポジティブ**な4段。
///
/// 主目的は「ていねいに書こう」という意識づけで、報酬はその手段。
/// 表示の文言（「よく書けたね」等）はアプリ側（UI）の責務。ここは順序と段だけを持つ。
/// rawValue は VLM の neatness(1〜4) と一致させてある（[[ai-ocr-and-age-ceiling]] の採点に相乗り）。
public enum NeatnessTier: Int, CaseIterable, Sendable, Comparable {
    case nice = 1     // 例: よく書けたね（最低ティアでも罰さない）
    case good = 2     // 例: 上手に書けたね
    case great = 3    // 例: すごく上手！
    case perfect = 4  // 例: 完璧！

    public static func < (lhs: NeatnessTier, rhs: NeatnessTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ていねいさ報酬の**純粋ロジック**（ティア判定・加点コイン・セッション合算）。
///
/// I/O（VLM 採点呼び出し・永続化・UI 演出）はアプリ側。ここは「VLM が返した
/// neatness(1〜4) を ティアと加点に変換する」決定的計算だけを行い、テストする。
///
/// 設計ガード（`docs`／spec ドラフト）:
/// - **罰しない**：最低ティアでも加点は必ず > 0。合算は決して負にならない。
/// - **本筋スペルを邪魔しない**：丁寧さは「加点のみ」。基礎コイン(練習30/語・満点ボーナス)には触れない。
///   正解なら字が雑でも正解＆基礎コイン満額。丁寧さで合否は分けない。
/// - **出所非依存**：ティアの元が confidence→VLM neatness に変わっても、この層は入力 score(1〜4)
///   だけを見るので不変。
public enum NeatnessReward {

    /// 1ティアあたりの加点コイン（既定値・チューニング可）。
    /// 基礎コイン（練習 30/語）を食わない控えめな topping。×10 スケールに揃えてある。
    public static func bonusCoins(for tier: NeatnessTier) -> Int {
        switch tier {
        case .nice: return 2
        case .good: return 4
        case .great: return 6
        case .perfect: return 10
        }
    }

    /// セッション合算ボーナスの上限。これ以上は頭打ち（基礎/満点ボーナスを上回らせない）。
    public static let sessionBonusCap = 50

    /// VLM の neatness スコア(1〜4) を ティアに変換。範囲外・欠損は端にクランプ（壊れない）。
    public static func tier(neatnessScore: Int) -> NeatnessTier {
        let clamped = min(NeatnessTier.perfect.rawValue, max(NeatnessTier.nice.rawValue, neatnessScore))
        return NeatnessTier(rawValue: clamped) ?? .nice
    }

    /// セッション中の各語ティアを合算し、上限つきの加点コインを返す（**加点のみ・0以上**）。
    public static func sessionBonusCoins(tiers: [NeatnessTier]) -> Int {
        let raw = tiers.reduce(0) { $0 + bonusCoins(for: $1) }
        return min(sessionBonusCap, raw)
    }

    /// セッション総合ティア（「きょうのていねい度」の星表示用）。
    /// 各語ティアの平均を四捨五入（0.5 は上＝ポジティブ寄り）。1語も無ければ nil。
    public static func sessionTier(tiers: [NeatnessTier]) -> NeatnessTier? {
        guard !tiers.isEmpty else { return nil }
        let sum = tiers.reduce(0) { $0 + $1.rawValue }
        // 四捨五入（半分は切り上げ）を整数演算で: (sum*2 + n) / (2n)
        let rounded = (sum * 2 + tiers.count) / (2 * tiers.count)
        return tier(neatnessScore: rounded)
    }
}
