import XCTest
@testable import SpellingSyncCore

/// テスト用の決定論RNG（SplitMix64）。シードが同じなら列も同じ。
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class PracticeCheerTests: XCTestCase {

    private func plan(round: Int, total: Int, japanese: Bool = true,
                      previous: String? = nil, seed: UInt64 = 1) -> PracticeCheer.Plan {
        var rng = SeededRNG(seed: seed)
        return PracticeCheer.plan(round: round, totalRounds: total, japanese: japanese,
                                  previousPhrase: previous, using: &rng)
    }

    // MARK: - 回→種類のマッピング

    func testKindMapping() {
        XCTAssertEqual(plan(round: 0, total: 3).kind, .midRound)
        XCTAssertEqual(plan(round: 1, total: 3).kind, .oneMoreToGo)
        XCTAssertEqual(plan(round: 2, total: 3).kind, .wordCompleted)
        XCTAssertEqual(plan(round: 0, total: 2).kind, .oneMoreToGo)
        XCTAssertEqual(plan(round: 1, total: 2).kind, .wordCompleted)
        XCTAssertEqual(plan(round: 0, total: 1).kind, .wordCompleted)
    }

    func testKindMappingClampsOutOfRange() {
        XCTAssertEqual(plan(round: 99, total: 3).kind, .wordCompleted)
        XCTAssertEqual(plan(round: -1, total: 3).kind, .midRound)
        XCTAssertEqual(plan(round: 0, total: 0).kind, .wordCompleted)
    }

    // MARK: - フレーズはその種類のプールから出る

    func testPhraseComesFromMatchingPool() {
        for seed: UInt64 in 1...50 {
            let mid = plan(round: 0, total: 4, seed: seed)
            XCTAssertTrue(PracticePraise.japanese.contains(mid.phrase))

            let oneMore = plan(round: 2, total: 4, seed: seed)
            XCTAssertTrue(PracticeCheer.oneMoreJapanese.contains(oneMore.phrase))

            let done = plan(round: 3, total: 4, seed: seed)
            if done.isRare {
                XCTAssertTrue(PracticeCheer.rareJapanese.contains(done.phrase))
            } else {
                XCTAssertTrue(PracticeCheer.completedJapanese.contains(done.phrase))
            }
        }
    }

    func testEnglishPhraseComesFromEnglishPool() {
        for seed: UInt64 in 1...50 {
            let mid = plan(round: 0, total: 4, japanese: false, seed: seed)
            XCTAssertTrue(PracticePraise.english.contains(mid.phrase))

            let done = plan(round: 3, total: 4, japanese: false, seed: seed)
            if done.isRare {
                XCTAssertTrue(PracticeCheer.rareEnglish.contains(done.phrase))
            } else {
                XCTAssertTrue(PracticeCheer.completedEnglish.contains(done.phrase))
            }
        }
    }

    // MARK: - レア（大当たり）

    func testRareOnlyOnWordCompleted() {
        for seed: UInt64 in 1...300 {
            XCTAssertFalse(plan(round: 0, total: 3, seed: seed).isRare)
            XCTAssertFalse(plan(round: 1, total: 3, seed: seed).isRare)
        }
    }

    func testRareFrequencyIsAboutOneInEight() {
        var rareCount = 0
        let trials = 10_000
        for seed in 1...trials {
            if plan(round: 2, total: 3, seed: UInt64(seed)).isRare {
                rareCount += 1
            }
        }
        let ratio = Double(rareCount) / Double(trials)
        XCTAssertGreaterThan(ratio, 0.09, "レアが少なすぎる: \(ratio)")
        XCTAssertLessThan(ratio, 0.16, "レアが多すぎる: \(ratio)")
    }

    func testCoinMultiplierIsTwoOnRareElseOne() {
        var sawRare = false
        var sawNormal = false
        for seed: UInt64 in 1...500 {
            let p = plan(round: 2, total: 3, seed: seed)
            XCTAssertEqual(p.coinMultiplier, p.isRare ? 2 : 1)
            sawRare = sawRare || p.isRare
            sawNormal = sawNormal || !p.isRare
        }
        XCTAssertTrue(sawRare)
        XCTAssertTrue(sawNormal)
        XCTAssertEqual(plan(round: 0, total: 3).coinMultiplier, 1)
    }

    // MARK: - 決定論と直前重複回避

    func testSameSeedGivesSamePlan() {
        for seed: UInt64 in 1...20 {
            XCTAssertEqual(plan(round: 2, total: 3, seed: seed), plan(round: 2, total: 3, seed: seed))
        }
    }

    func testNeverRepeatsPreviousPhrase() {
        // どのプールでも、直前と同じフレーズは連続で出ない。
        for previous in PracticePraise.japanese {
            for seed: UInt64 in 1...40 {
                XCTAssertNotEqual(plan(round: 0, total: 4, previous: previous, seed: seed).phrase, previous)
            }
        }
        for previous in PracticeCheer.completedJapanese {
            for seed: UInt64 in 1...40 {
                let p = plan(round: 3, total: 4, previous: previous, seed: seed)
                if !p.isRare {
                    XCTAssertNotEqual(p.phrase, previous)
                }
            }
        }
    }

    // MARK: - プールの中身の健全性

    func testPoolsAreNonEmptyUniqueAndBigEnough() {
        for pool in [PracticeCheer.oneMoreJapanese, PracticeCheer.oneMoreEnglish,
                     PracticeCheer.completedJapanese, PracticeCheer.completedEnglish,
                     PracticeCheer.rareJapanese, PracticeCheer.rareEnglish] {
            XCTAssertGreaterThanOrEqual(pool.count, 3)
            XCTAssertEqual(Set(pool).count, pool.count, "重複あり: \(pool)")
            XCTAssertFalse(pool.contains(where: \.isEmpty))
        }
    }

    func testJapanesePhrasesContainNoKanji() {
        // 子ども向け表示なので漢字を使わない（ひらがな・カタカナ・記号のみ）。
        let kanji = Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!
        for pool in [PracticeCheer.oneMoreJapanese, PracticeCheer.completedJapanese, PracticeCheer.rareJapanese] {
            for phrase in pool {
                XCTAssertFalse(phrase.unicodeScalars.contains(where: { kanji.contains($0) }),
                               "漢字が含まれる: \(phrase)")
            }
        }
    }
}
