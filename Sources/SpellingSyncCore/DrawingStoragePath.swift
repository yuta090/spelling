import Foundation

/// 手書き/見本画像の Supabase Storage 上の**決定論パス**を組み立てる純ロジック。
///
/// バケット `drawings`（非公開）内のパス規約は migration の RLS と厳密に一致させる:
///   {household_id}/{profile_id}/attempts/{attempt_id}.png
///   {household_id}/{profile_id}/reviews/{attempt_id}.png
/// `storage.objects` の RLS は `foldername(name)[1]=household_id, [2]=profile_id, [3]=種別` を
/// `app.has_access(hid,pid)`（attempts）/ `is_household_member`（reviews 書込み）で判定する。
///
/// UUID は Postgres の `uuid` キャストが大文字小文字を無視するため round-trip 上は不問だが、
/// `ReviewIdentity` 等と揃えて **全小文字**で出力する（差分の決定性・可読性のため）。
public enum DrawingStoragePath {
    /// 非公開バケット名（migration と一致）。
    public static let bucket = "drawings"

    /// 種別フォルダ。RLS が `foldername[3]` で分岐するのに使う。
    public enum Kind: String, Sendable {
        case attempts
        case reviews
    }

    /// 子の手書き（attempt）画像のパス。
    public static func attempt(householdID: UUID, profileID: UUID, attemptID: UUID) -> String {
        path(kind: .attempts, householdID: householdID, profileID: profileID, attemptID: attemptID)
    }

    /// 親の見本（review）画像のパス。
    public static func review(householdID: UUID, profileID: UUID, attemptID: UUID) -> String {
        path(kind: .reviews, householdID: householdID, profileID: profileID, attemptID: attemptID)
    }

    /// 汎用ビルダ。`{hid}/{pid}/{kind}/{attemptID}.png`（全小文字）。
    public static func path(kind: Kind, householdID: UUID, profileID: UUID, attemptID: UUID) -> String {
        let hid = householdID.uuidString.lowercased()
        let pid = profileID.uuidString.lowercased()
        let aid = attemptID.uuidString.lowercased()
        return "\(hid)/\(pid)/\(kind.rawValue)/\(aid).png"
    }
}
