import XCTest
@testable import SpellingSyncCore

final class CourseAccessTests: XCTestCase {
    private let all = ["personal", "grade-1", "grade-3", "eiken-g5", "eiken-p2"]

    func testLockedReturnsOnlyActiveCourse() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "grade-3",
            childCanSwitch: false
        )
        XCTAssertEqual(result, ["grade-3"])
    }

    func testUnlockedReturnsAllCoursesInOrder() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "grade-3",
            childCanSwitch: true
        )
        XCTAssertEqual(result, all)
    }

    func testLockedWithActiveCourseMissingReturnsEmpty() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "eiken-g3",   // 一覧に無い
            childCanSwitch: false
        )
        XCTAssertEqual(result, [])
    }

    func testLockedPersonalActiveReturnsPersonalOnly() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "personal",
            childCanSwitch: false
        )
        XCTAssertEqual(result, ["personal"])
    }

    func testUnlockedEmptyDirectoryReturnsEmpty() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: [],
            activeCourseID: "personal",
            childCanSwitch: true
        )
        XCTAssertEqual(result, [])
    }
}
