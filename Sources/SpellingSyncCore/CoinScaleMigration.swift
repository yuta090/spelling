import Foundation

/// コイン単位を一桁上げた（×10）リリースで、既存ユーザーの残高を**一度だけ**スケールするための
/// 純粋ロジック。
///
/// 設計（クラッシュ安全・冪等）:
/// - 移行後の残高は **新キー(v2)** に保存し、以後の入出金も v2 に書く。
/// - 旧キー(legacy) は**二度と書き換えない**。よって「v2 未保存なら legacy×factor」を毎回再計算しても
///   常に同じ値になり、保存途中でプロセスが落ちても再倍化（×100）しない。
/// - つまり「v2 が存在するか」だけが移行済みの単一の判定で、フラグ別管理は不要。
public enum CoinScaleMigration {
    /// 旧単位から新単位への倍率（×10）。
    public static let factor = 10

    /// 表示・保存に使う現在の残高を決める。
    /// - Parameters:
    ///   - storedV2: 新キーに保存済みの残高（無ければ nil）。
    ///   - legacy: 旧キーに保存された残高（無ければ nil）。
    /// - Returns: v2 があればそれ（0未満は0補正）、無ければ legacy×factor（0未満は0補正）。
    public static func resolveBalance(storedV2: Int?, legacy: Int?) -> Int {
        if let storedV2 {
            return max(storedV2, 0)
        }
        return max(legacy ?? 0, 0) * factor
    }

    /// 解決した残高を新キーへ保存（＝移行を確定）する必要があるか。
    /// v2 が未保存のときだけ true。保存は冪等なので、複数回呼ばれても安全。
    public static func needsPersist(storedV2: Int?) -> Bool {
        storedV2 == nil
    }
}
