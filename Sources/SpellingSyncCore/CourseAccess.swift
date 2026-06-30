import Foundation

/// 子がコースを自分で切り替えられるかどうかの「許可ポリシー」（純ロジック）。
///
/// 既定はロック（親が決める）。親が「子にも選ばせる」を ON にしたときだけ、
/// 子は自分でコースを切り替えられる。さらに親が「許可サブセット」を指定すると、
/// その集合に含まれるコースだけ（＋現在コース）に絞り込める。
/// CLAUDE.md 方針：子に級/学年ラベルは出さないが、ここは「どのコースIDを選べるか」だけを決める。
public enum CourseAccess {
    /// 子が選べるコースID。
    /// - ロック時（`childCanSwitch == false`）：現在のコースだけ（＝切り替え不可）。現在コースが一覧に無ければ空。
    /// - 許可時（`childCanSwitch == true`）：
    ///   - `allowedCourseIDs` が空 = 制限なし＝渡された全コース（順序保持・後方互換の既定）。
    ///   - `allowedCourseIDs` が非空 = その集合に含まれるコースのみ（`allCourseIDs` の順序を保持）。
    ///     ただし**現在アクティブなコースは許可外でも常に含める**（子が今いるコースから締め出されないため）。
    ///     許可集合に存在しないID（ディレクトリ外）は無視される。
    public static func childSelectableCourseIDs(
        allCourseIDs: [String],
        activeCourseID: String,
        childCanSwitch: Bool,
        allowedCourseIDs: Set<String> = []
    ) -> [String] {
        guard childCanSwitch else {
            return allCourseIDs.contains(activeCourseID) ? [activeCourseID] : []
        }
        guard !allowedCourseIDs.isEmpty else {
            return allCourseIDs
        }
        // 許可集合 ∪ {現在コース} を allCourseIDs の順序で抽出（重複なし）。
        return allCourseIDs.filter { allowedCourseIDs.contains($0) || $0 == activeCourseID }
    }
}
