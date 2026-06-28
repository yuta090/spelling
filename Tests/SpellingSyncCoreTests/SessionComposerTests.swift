import XCTest
@testable import SpellingSyncCore

private func item(_ en: String) -> SentenceItem {
    SentenceItem(en: en, ja: en, tokens: en.split(separator: " ").map(String.init), gradeBand: 1)
}

final class SessionComposerTests: XCTestCase {
    private let items = [item("a b"), item("c d"), item("e f")]
    private let formats: [ExerciseFormat] = [.wordOrdering, .clozeChoice]

    func testEmptyInputsProduceEmpty() {
        XCTAssertTrue(SessionComposer.compose(items: [], formats: formats, length: 5, seed: 1).isEmpty)
        XCTAssertTrue(SessionComposer.compose(items: items, formats: [], length: 5, seed: 1).isEmpty)
        XCTAssertTrue(SessionComposer.compose(items: items, formats: formats, length: 0, seed: 1).isEmpty)
    }

    func testLengthRespected() {
        XCTAssertEqual(SessionComposer.compose(items: items, formats: formats, length: 8, seed: 1).count, 8)
    }

    func testNoConsecutiveSameFormatWhenMultipleFormats() {
        let steps = SessionComposer.compose(items: items, formats: formats, length: 10, seed: 7)
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertNotEqual(a.format, b.format, "連続して同じ形式が出てはいけない")
        }
    }

    func testDeterministicForSameSeed() {
        XCTAssertEqual(
            SessionComposer.compose(items: items, formats: formats, length: 8, seed: 42),
            SessionComposer.compose(items: items, formats: formats, length: 8, seed: 42)
        )
    }

    func testStepsUseOnlyGivenItemsAndFormats() {
        let steps = SessionComposer.compose(items: items, formats: formats, length: 12, seed: 3)
        let itemSet = Set(items.map(\.en))
        for step in steps {
            XCTAssertTrue(itemSet.contains(step.item.en))
            XCTAssertTrue(formats.contains(step.format))
        }
    }

    func testItemsCycleWhenLengthExceedsItemCount() {
        // length > items.count でも全 item が登場する。
        let steps = SessionComposer.compose(items: items, formats: formats, length: 9, seed: 5)
        XCTAssertEqual(Set(steps.map(\.item.en)), Set(items.map(\.en)))
    }

    func testDuplicateFormatsStillNeverConsecutive() {
        // 重複形式を渡しても一意化され、連続同形式は出ない。
        let steps = SessionComposer.compose(
            items: items,
            formats: [.wordOrdering, .wordOrdering, .clozeChoice],
            length: 10, seed: 4)
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertNotEqual(a.format, b.format)
        }
    }

    func testSingleFormatYieldsAllThatFormat() {
        let steps = SessionComposer.compose(items: items, formats: [.clozeChoice], length: 5, seed: 1)
        XCTAssertEqual(steps.count, 5)
        XCTAssertTrue(steps.allSatisfy { $0.format == .clozeChoice })
    }
}
