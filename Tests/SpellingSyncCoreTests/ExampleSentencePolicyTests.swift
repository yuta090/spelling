import XCTest
@testable import SpellingSyncCore

final class ExampleSentencePolicyTests: XCTestCase {
    /// 低学年（小1・小2＝tier a）は、コースでまだ習っていない語が英語例文に混ざるため出さない。
    func testHidesEnglishExampleForLowerGrades() {
        XCTAssertFalse(ExampleSentencePolicy.showsEnglishExample(tier: .a))
    }

    /// 中学年以降（b/c/d）は読める前提で英語例文を出す。
    func testShowsEnglishExampleForMiddleAndUpperGrades() {
        XCTAssertTrue(ExampleSentencePolicy.showsEnglishExample(tier: .b))
        XCTAssertTrue(ExampleSentencePolicy.showsEnglishExample(tier: .c))
        XCTAssertTrue(ExampleSentencePolicy.showsEnglishExample(tier: .d))
    }
}
