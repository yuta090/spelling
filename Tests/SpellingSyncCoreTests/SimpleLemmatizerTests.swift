import XCTest
@testable import SpellingSyncCore

/// SimpleLemmatizer の規則・不規則を固定する。
/// 完璧主義ではなく「level（原形収録）に当たる原形へ寄せられるか」を担保する。
final class SimpleLemmatizerTests: XCTestCase {

    func testPluralAndThirdPersonS() {
        XCTAssertEqual(SimpleLemmatizer.lemma("apples"), "apple")
        XCTAssertEqual(SimpleLemmatizer.lemma("likes"), "like")
        XCTAssertEqual(SimpleLemmatizer.lemma("boys"), "boy")
        XCTAssertEqual(SimpleLemmatizer.lemma("plays"), "play")
    }

    func testDoubleSAndShortSNotStripped() {
        XCTAssertEqual(SimpleLemmatizer.lemma("glass"), "glass")  // ss は触らない
        XCTAssertEqual(SimpleLemmatizer.lemma("bus"), "bus")      // us は触らない
        XCTAssertEqual(SimpleLemmatizer.lemma("cats"), "cat")
    }

    func testIesAndIed() {
        XCTAssertEqual(SimpleLemmatizer.lemma("studies"), "study")
        XCTAssertEqual(SimpleLemmatizer.lemma("flies"), "fly")
        XCTAssertEqual(SimpleLemmatizer.lemma("studied"), "study")
        XCTAssertEqual(SimpleLemmatizer.lemma("tried"), "try")
    }

    func testEsAfterSibilant() {
        XCTAssertEqual(SimpleLemmatizer.lemma("boxes"), "box")
        XCTAssertEqual(SimpleLemmatizer.lemma("wishes"), "wish")
        XCTAssertEqual(SimpleLemmatizer.lemma("watches"), "watch")
    }

    func testEdRegular() {
        XCTAssertEqual(SimpleLemmatizer.lemma("played"), "play")
        XCTAssertEqual(SimpleLemmatizer.lemma("liked"), "like")
        XCTAssertEqual(SimpleLemmatizer.lemma("stopped"), "stop")
        XCTAssertEqual(SimpleLemmatizer.lemma("rained"), "rain")
        XCTAssertEqual(SimpleLemmatizer.lemma("watched"), "watch")
    }

    func testIngRegular() {
        XCTAssertEqual(SimpleLemmatizer.lemma("making"), "make")
        XCTAssertEqual(SimpleLemmatizer.lemma("playing"), "play")
        XCTAssertEqual(SimpleLemmatizer.lemma("reading"), "read")
    }

    func testComparativeSuperlative() {
        XCTAssertEqual(SimpleLemmatizer.lemma("faster"), "fast")
        XCTAssertEqual(SimpleLemmatizer.lemma("bigger"), "big")
        XCTAssertEqual(SimpleLemmatizer.lemma("biggest"), "big")
    }

    func testIrregulars() {
        XCTAssertEqual(SimpleLemmatizer.lemma("is"), "be")
        XCTAssertEqual(SimpleLemmatizer.lemma("are"), "be")
        XCTAssertEqual(SimpleLemmatizer.lemma("went"), "go")
        XCTAssertEqual(SimpleLemmatizer.lemma("ran"), "run")
        XCTAssertEqual(SimpleLemmatizer.lemma("children"), "child")
        XCTAssertEqual(SimpleLemmatizer.lemma("better"), "good")
        XCTAssertEqual(SimpleLemmatizer.lemma("running"), "run")
    }

    func testCaseAndTrim() {
        XCTAssertEqual(SimpleLemmatizer.lemma("  Apples "), "apple")
        XCTAssertEqual(SimpleLemmatizer.lemma("LIKES"), "like")
    }

    func testShortWordsUntouched() {
        XCTAssertEqual(SimpleLemmatizer.lemma("go"), "go")
        XCTAssertEqual(SimpleLemmatizer.lemma("red"), "red")   // -ed だが n<=3 で触らない
        XCTAssertEqual(SimpleLemmatizer.lemma("cat"), "cat")
    }
}
