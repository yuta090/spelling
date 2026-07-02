import Foundation

/// 世帯の `words` リモートストリーム（当面 `profile_id = NULL` ＝世帯スコープ）の **オーナー** 解決。
///
/// Phase 5a では **サーバがまだプロファイル別でない**（`words.profile_id` に対応する `profiles` 行の
/// provisioning は Phase 5b）。そのため wire は `profile_id = NULL` の世帯スコープで push/pull する。
/// この世帯 NULL ストリームは「元の単一子（＝ブートストラップ #1）」のデータであり、そのオーナー
/// **1 人だけ** がリモート同期してよい。別の子がこのストリームを pull すると他児の単語を取り込み、
/// push すると他児の行を墓石化しうる（＝データ破壊）。
///
/// したがってオーナーは **一度決めたら再割り当てしない**。オーナーが削除されたら、別の子へ移さず
/// リモート同期は停止したままにする（安全側）。複数子の同時リモート同期は Phase 5b（サーバ側
/// プロファイル別化＋既存 NULL 行の移行）で解禁する。
public enum WordRemoteOwner {
    /// 世帯 NULL ストリームのオーナーを解決する。
    /// - `current` が既に記録済みならそのまま返す（**再割り当てしない**）。オーナーが台帳から消えて
    ///   いても、別の子へ移さない（消えた id を返す＝どの子もアクティブ一致せず同期は停止）。
    /// - 未記録なら、**最古（`createdAt` 最小・同時刻は id で安定）＝ブートストラップ #1** を初期オーナーにする。
    ///   新規/単一子インストールではこれが唯一の子＝正しいオーナー。並べ替え（`sortIndex`）に依存しないよう
    ///   表示順ではなく生成時刻で選ぶ（世帯 NULL ストリームを書いた「元の子」を安定に指す）。
    public static func resolve(current: UUID?, registry: ProfileRegistry) -> UUID? {
        if let current { return current }
        return registry.profiles.min {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }?.id
    }
}
