import XCTest
@testable import SpellingSyncCore

private struct StubItem: ReviewableItem {
    var requiresParentReview: Bool
    var parentReviewState: ParentReviewState
}

final class ReviewProgressTests: XCTestCase {
    func testPendingCountsOnlyReviewNeededAndUnreviewed() {
        let items = [
            StubItem(requiresParentReview: true, parentReviewState: .unreviewed),   // pending
            StubItem(requiresParentReview: true, parentReviewState: .unreviewed),   // pending
            StubItem(requiresParentReview: true, parentReviewState: .approved),     // done
            StubItem(requiresParentReview: true, parentReviewState: .needsPractice),// done
            StubItem(requiresParentReview: false, parentReviewState: .unreviewed)   // auto, not pending
        ]
        XCTAssertEqual(ReviewProgress.pendingCount(items), 2)
    }

    func testAutoDecidedItemsAreNeverPending() {
        let items = [
            StubItem(requiresParentReview: false, parentReviewState: .unreviewed),
            StubItem(requiresParentReview: false, parentReviewState: .unreviewed)
        ]
        XCTAssertEqual(ReviewProgress.pendingCount(items), 0)
    }

    func testEmptyIsFullyReviewed() {
        let items: [StubItem] = []
        XCTAssertEqual(ReviewProgress.pendingCount(items), 0)
        XCTAssertTrue(ReviewProgress.isFullyReviewed(items))
    }

    func testIsFullyReviewedFalseWhenPendingExists() {
        let items = [StubItem(requiresParentReview: true, parentReviewState: .unreviewed)]
        XCTAssertFalse(ReviewProgress.isFullyReviewed(items))
    }

    func testIsFullyReviewedTrueWhenAllResolvedOrAuto() {
        let items = [
            StubItem(requiresParentReview: true, parentReviewState: .approved),
            StubItem(requiresParentReview: false, parentReviewState: .unreviewed)
        ]
        XCTAssertTrue(ReviewProgress.isFullyReviewed(items))
    }
}
