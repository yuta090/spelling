import XCTest
@testable import SpellingSyncCore

/// おぼえる練習用フレームのスターターセットを「正しく作れているか」毎回チェックする検証テスト。
/// well-formed / 綴り不変 / tier 安全（漢字なし）/ POS カバレッジ / 決定論カナリア。
final class StarterSpellingFramesTests: XCTestCase {

    private var frames: [SpellingInvariantFrame] { StarterSpellingFrames.all }

    func testCountIsStable() {
        // 件数カナリア（増減したら意図的か確認する）。
        XCTAssertEqual(frames.count, 9)
    }

    /// 名詞フレームは冠詞 a/an や数（two/many/one…）を固定しない＝`a foxes`/`two apple` を作らない。
    func testNounFramesAvoidArticleAndNumberAgreement() {
        let forbidden: Set<String> = ["a", "an", "one", "two", "three", "many", "some"]
        for f in frames where f.allowedPOS.contains("noun") {
            for token in f.tokens {
                XCTAssertFalse(forbidden.contains(token.lowercased()),
                               "\(f.id): 名詞フレームに冠詞/数 '\(token)' があり一致誤りを生む")
            }
        }
    }

    func testIDsAreUnique() {
        let ids = frames.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "フレーム id が重複している")
    }

    func testAllWellFormed() {
        for f in frames {
            XCTAssertTrue(f.isWellFormed, "\(f.id): スロットがトークン範囲外")
            XCTAssertEqual(f.tokens[f.answerSlotIndex], StarterSpellingFrames.slotToken,
                           "\(f.id): スロット位置にプレースホルダが無い")
            XCTAssertFalse(f.allowedPOS.isEmpty, "\(f.id): POS 制約が空（どの語でも載ってしまう）")
            XCTAssertFalse(f.ja.isEmpty, "\(f.id): 和訳テンプレが空")
        }
    }

    func testGradeBandInRange() {
        for f in frames {
            guard let band = f.gradeBand else { return XCTFail("\(f.id): band 未設定") }
            XCTAssertTrue((1...5).contains(band), "\(f.id): band=\(band) が範囲外")
        }
    }

    func testJaHasNoKanjiAboveGrade1() {
        // 仮名のみ＝どの学年でも tier 安全（最も厳しい grade1 で通ること）。
        for f in frames {
            XCTAssertTrue(KanjiLevelGate.isWithin(f.ja, maxGrade: 1),
                          "\(f.id): 和訳テンプレに学年外の漢字がある: \(f.ja)")
        }
    }

    func testCoversNounVerbAdjective() {
        let pos = Set(frames.flatMap { $0.allowedPOS })
        XCTAssertTrue(pos.contains("noun"), "名詞フレームが無い")
        XCTAssertTrue(pos.contains("verb"), "動詞フレームが無い")
        XCTAssertTrue(pos.contains("adjective"), "形容詞フレームが無い")
    }

    // MARK: - Resolver と組み合わせ（必須問題化）

    func testResolverPicksFrameForNoun() {
        let apple = RegisteredWord(stableID: "w-apple", text: "apple", partOfSpeech: "noun")
        let problem = CoreProblemResolver.resolve(word: apple, frames: frames)
        guard case let .spellingInvariantFrame(frame, word) = problem else {
            return XCTFail("名詞はフレームに載るはず: \(problem)")
        }
        // 綴り不変：スロットは登録語の綴りそのもの。
        let (tokens, idx) = frame.filled(with: word)
        XCTAssertEqual(tokens[idx], "apple")
    }

    func testResolverPicksFrameForVerb() {
        let play = RegisteredWord(stableID: "w-play", text: "play", partOfSpeech: "verb")
        let problem = CoreProblemResolver.resolve(word: play, frames: frames)
        guard case .spellingInvariantFrame = problem else {
            return XCTFail("動詞はフレームに載るはず: \(problem)")
        }
    }

    func testFilledKeepsSpellingExact() {
        // どのフレームに載せても綴りは一切変えない（活用/複数化しない）。
        let word = RegisteredWord(stableID: "w-foxes", text: "foxes", partOfSpeech: "noun")
        for f in frames where f.accepts(word) {
            let (tokens, idx) = f.filled(with: word)
            XCTAssertEqual(tokens[idx], "foxes", "\(f.id): 綴りが変わった")
        }
    }
}
