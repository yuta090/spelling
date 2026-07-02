import XCTest
@testable import SpellingSyncCore

final class DrawingStoragePathTests: XCTestCase {
    private let hid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let pid = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let aid = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    func testBucketName() {
        XCTAssertEqual(DrawingStoragePath.bucket, "drawings")
    }

    func testAttemptPathShape() {
        XCTAssertEqual(
            DrawingStoragePath.attempt(householdID: hid, profileID: pid, attemptID: aid),
            "11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/attempts/33333333-3333-3333-3333-333333333333.png"
        )
    }

    func testReviewPathShape() {
        XCTAssertEqual(
            DrawingStoragePath.review(householdID: hid, profileID: pid, attemptID: aid),
            "11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/reviews/33333333-3333-3333-3333-333333333333.png"
        )
    }

    func testLowercasedEvenIfInputsUppercase() {
        // Swift の UUID.uuidString は大文字。パスは全小文字で決定的に出す。
        let path = DrawingStoragePath.attempt(householdID: hid, profileID: pid, attemptID: aid)
        XCTAssertEqual(path, path.lowercased())
    }

    func testSegmentsMatchRLSExpectations() {
        // RLS は foldername(name)[1]=hid, [2]=pid, [3]=種別 を見る。
        let parts = DrawingStoragePath.attempt(householdID: hid, profileID: pid, attemptID: aid)
            .split(separator: "/").map(String.init)
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], hid.uuidString.lowercased())
        XCTAssertEqual(parts[1], pid.uuidString.lowercased())
        XCTAssertEqual(parts[2], "attempts")
        XCTAssertEqual(parts[3], "\(aid.uuidString.lowercased()).png")
    }

    func testAttemptAndReviewDifferOnlyByKind() {
        let a = DrawingStoragePath.attempt(householdID: hid, profileID: pid, attemptID: aid)
        let r = DrawingStoragePath.review(householdID: hid, profileID: pid, attemptID: aid)
        XCTAssertNotEqual(a, r)
        XCTAssertEqual(a.replacingOccurrences(of: "/attempts/", with: "/reviews/"), r)
    }
}
