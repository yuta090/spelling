import XCTest
@testable import SpellingSyncCore

/// 手書きの「ていねいさ」報酬の純粋ロジックのテスト。
///
/// 設計ガード（このアプリの哲学）を機械的に守れているか確認する:
/// - 罰しない（最低ティアも加点 > 0・ボーナスは決して負にならない）
/// - 本筋スペルを邪魔しない（丁寧さは「加点のみ」・基礎コインには触れない）
/// - ティアの出所（VLM neatness 1〜4）が変わってもこの層は不変（入力は 1〜4 の score）
final class NeatnessRewardTests: XCTestCase {

    // MARK: - VLM neatness score(1〜4) → ティア

    func testScoreMapsToTier() {
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 1), .nice)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 2), .good)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 3), .great)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 4), .perfect)
    }

    func testScoreOutOfRangeClampsIntoTier() {
        // 防御的にクランプ（bench 側で正規化済みだが、欠損・範囲外でも壊れない）
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 0), .nice)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: -5), .nice)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 5), .perfect)
        XCTAssertEqual(NeatnessReward.tier(neatnessScore: 99), .perfect)
    }

    // MARK: - ティアの順序（最低でもポジティブ・上下関係）

    func testTierOrdering() {
        XCTAssertLessThan(NeatnessTier.nice, NeatnessTier.good)
        XCTAssertLessThan(NeatnessTier.good, NeatnessTier.great)
        XCTAssertLessThan(NeatnessTier.great, NeatnessTier.perfect)
        XCTAssertEqual(NeatnessTier.allCases, [.nice, .good, .great, .perfect])
    }

    // MARK: - 1ティアあたりのボーナス（加点のみ・最低でも > 0）

    func testBonusPerTierIsAlwaysPositiveAndMonotonic() {
        let nice = NeatnessReward.bonusCoins(for: .nice)
        let good = NeatnessReward.bonusCoins(for: .good)
        let great = NeatnessReward.bonusCoins(for: .great)
        let perfect = NeatnessReward.bonusCoins(for: .perfect)
        // 最低ティアでも罰さない＝必ず正
        XCTAssertGreaterThan(nice, 0)
        // 丁寧なほど多い（単調増加）
        XCTAssertLessThan(nice, good)
        XCTAssertLessThan(good, great)
        XCTAssertLessThan(great, perfect)
    }

    func testBonusPerTierStableValues() {
        // 既定値の固定（チューニング時はここが意図的に変わる）
        XCTAssertEqual(NeatnessReward.bonusCoins(for: .nice), 2)
        XCTAssertEqual(NeatnessReward.bonusCoins(for: .good), 4)
        XCTAssertEqual(NeatnessReward.bonusCoins(for: .great), 6)
        XCTAssertEqual(NeatnessReward.bonusCoins(for: .perfect), 10)
    }

    // MARK: - セッション合算ボーナス（加点のみ・上限つき）

    func testSessionBonusSumsPerTier() {
        // nice(2) + great(6) + perfect(10) = 18
        let coins = NeatnessReward.sessionBonusCoins(tiers: [.nice, .great, .perfect])
        XCTAssertEqual(coins, 18)
    }

    func testSessionBonusEmptyIsZero() {
        XCTAssertEqual(NeatnessReward.sessionBonusCoins(tiers: []), 0)
    }

    func testSessionBonusNeverNegative() {
        // 最低ティアだけを大量に積んでも負にならない・必ず加点
        let coins = NeatnessReward.sessionBonusCoins(tiers: Array(repeating: .nice, count: 5))
        XCTAssertGreaterThan(coins, 0)
        XCTAssertEqual(coins, 10) // 2 * 5
    }

    func testSessionBonusIsCapped() {
        // 全部 perfect(10) を大量に積んでも上限で頭打ち（基礎コインを食わない topping）
        let many = Array(repeating: NeatnessTier.perfect, count: 100) // 素なら 1000
        let coins = NeatnessReward.sessionBonusCoins(tiers: many)
        XCTAssertEqual(coins, NeatnessReward.sessionBonusCap)
        XCTAssertLessThanOrEqual(coins, NeatnessReward.sessionBonusCap)
    }

    // MARK: - セッション総合ティア（「きょうのていねい度」の星）

    func testSessionTierIsRoundedAverageLeaningPositive() {
        // [great(3), perfect(4)] 平均 3.5 → 四捨五入で perfect（ポジティブ寄り）
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.great, .perfect]), .perfect)
        // [nice(1), good(2)] 平均 1.5 → good
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.nice, .good]), .good)
        // 全部 nice → nice
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.nice, .nice, .nice]), .nice)
        // 単独
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.great]), .great)
    }

    func testSessionTierRoundingTableNonTies() {
        // 非タイの四捨五入（半分=切り上げ）を端まで固定
        // [nice,nice,good] 平均 4/3 ≈ 1.33 → nice
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.nice, .nice, .good]), .nice)
        // [nice,good,good] 平均 5/3 ≈ 1.67 → good
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.nice, .good, .good]), .good)
        // [good,good,perfect] 平均 8/3 ≈ 2.67 → great
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.good, .good, .perfect]), .great)
        // [great,great,great,perfect] 平均 13/4 = 3.25 → great
        XCTAssertEqual(NeatnessReward.sessionTier(tiers: [.great, .great, .great, .perfect]), .great)
    }

    func testSessionTierEmptyIsNil() {
        // 1語も書いていなければ星は出さない
        XCTAssertNil(NeatnessReward.sessionTier(tiers: []))
    }
}
