import Foundation

/// 子がコースを自分で切り替えられるかどうかの「許可ポリシー」（純ロジック）。
///
/// 既定はロック（親が決める）。親が「子にも選ばせる」を ON にしたときだけ、
/// 子は全コースの中から自分で切り替えられる（v1・許可サブセットは未導入）。
/// CLAUDE.md 方針：子に級/学年ラベルは出さないが、ここは「どのコースIDを選べるか」だけを決める。
public enum CourseAccess {
    /// 子が選べるコースID。
    /// - ロック時（`childCanSwitch == false`）：現在のコースだけ（＝切り替え不可）。現在コースが一覧に無ければ空。
    /// - 許可時（`childCanSwitch == true`）：渡された全コース（順序保持）。
    public static func childSelectableCourseIDs(
        allCourseIDs: [String],
        activeCourseID: String,
        childCanSwitch: Bool
    ) -> [String] {
        guard childCanSwitch else {
            return allCourseIDs.contains(activeCourseID) ? [activeCourseID] : []
        }
        return allCourseIDs
    }
}
