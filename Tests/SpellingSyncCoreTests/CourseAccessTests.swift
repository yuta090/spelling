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

    // MARK: - allowedCourseIDs（許可サブセット）

    /// 許可集合が空 = 制限なし＝全コース（後方互換の既定）。
    func testUnlockedEmptyAllowedReturnsAllCourses() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "grade-3",
            childCanSwitch: true,
            allowedCourseIDs: []
        )
        XCTAssertEqual(result, all)
    }

    /// 部分許可 = その集合のみ（allCourseIDs の順序を保持）。
    func testUnlockedAllowedSubsetReturnsOnlyAllowedInOrder() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "grade-3",          // 許可集合にも含まれる
            childCanSwitch: true,
            allowedCourseIDs: ["eiken-g5", "grade-3", "personal"]
        )
        // allCourseIDs 準拠の順序：personal, grade-3, eiken-g5
        XCTAssertEqual(result, ["personal", "grade-3", "eiken-g5"])
    }

    /// 現在コースが許可外でも必ず含める（子が今いるコースから締め出されない）。
    func testUnlockedActiveCourseAlwaysIncludedEvenIfNotAllowed() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "eiken-p2",         // 許可集合に無い
            childCanSwitch: true,
            allowedCourseIDs: ["grade-1"]
        )
        // grade-1 ＋ 現在の eiken-p2。順序は allCourseIDs 準拠。
        XCTAssertEqual(result, ["grade-1", "eiken-p2"])
    }

    /// 許可集合に存在しないID（ディレクトリ外）が混ざっても無害。
    func testUnlockedAllowedWithUnknownIDsIsHarmless() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "personal",
            childCanSwitch: true,
            allowedCourseIDs: ["grade-1", "does-not-exist", "ghost-course"]
        )
        // 存在する grade-1 ＋ 現在の personal のみ。未知IDは無視。
        XCTAssertEqual(result, ["personal", "grade-1"])
    }

    /// ロック時は allowedCourseIDs に関係なく現在コースのみ。
    func testLockedIgnoresAllowedSet() {
        let result = CourseAccess.childSelectableCourseIDs(
            allCourseIDs: all,
            activeCourseID: "grade-3",
            childCanSwitch: false,
            allowedCourseIDs: ["personal", "eiken-g5"]
        )
        XCTAssertEqual(result, ["grade-3"])
    }
}
