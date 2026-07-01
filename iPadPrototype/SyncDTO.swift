import Foundation

/// Supabase の行に対応する DTO（同期の wire 型）。
///
/// 差分プルのカーソルは **`sync_version`（サーバー採番の単調増加 bigint）**。
/// timestamptz の同時刻タイ・文字列比較の問題を避けるため、`server_changed_at` ではなくこれを使う。
/// `updated_at` はクライアントのLWW時刻（String保持）。`deleted_at` は tombstone。
/// 設計: docs/supabase-adapter-design.md
protocol SyncedRow: Decodable, Identifiable, Sendable {
    static var table: String { get }
    var id: UUID { get }
    /// 同期カーソル（サーバー採番・単調増加）。差分プルの基準。
    var syncVersion: Int { get }
    /// 論理削除（tombstone）。nil でなければ削除済み。
    var deletedAt: String? { get }
}

extension SyncedRow {
    var isDeleted: Bool { deletedAt != nil }
}

// MARK: - 子プロファイル
struct ProfileDTO: SyncedRow {
    static let table = "profiles"
    let id: UUID
    let householdId: UUID
    let displayName: String
    let appLanguage: String
    let activeStepId: UUID?
    let updatedAt: String
    let deletedAt: String?
    let syncVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case displayName = "display_name"
        case appLanguage = "app_language"
        case activeStepId = "active_step_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }
}

// MARK: - 単語
struct WordDTO: SyncedRow {
    static let table = "words"
    let id: UUID
    let householdId: UUID
    let profileId: UUID?
    let stepId: UUID?
    let text: String
    let promptText: String
    let source: String
    let displayOrder: Int
    let updatedAt: String
    let deletedAt: String?
    let syncVersion: Int
    // Ph4: ローカル String の保管ステップ／コース紐付け（text 列。サーバー UUID step_id とは別管理＝§7.5）。
    let storageStepId: String?
    let linkedCourseId: String?
    let linkedBeforeStepId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case profileId = "profile_id"
        case stepId = "step_id"
        case text
        case promptText = "prompt_text"
        case source
        case displayOrder = "display_order"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case storageStepId = "storage_step_id"
        case linkedCourseId = "linked_course_id"
        case linkedBeforeStepId = "linked_before_step_id"
    }
}

// MARK: - プッシュ用ペイロード（upsert）
//
// サーバー管理列（sync_version / server_changed_at / created_at）は **送らない**（トリガが採番）。
// `updated_at` はクライアントのLWW時刻（ISO8601文字列）。削除は `deleted_at` を立てて送る（論理削除）。

/// upsert 可能な行（Encodable）。`table` は対象テーブル名。
protocol UpsertRow: Encodable {
    static var table: String { get }
}

struct ProfileUpsert: UpsertRow {
    static let table = "profiles"
    let id: UUID
    let householdId: UUID
    let displayName: String
    let appLanguage: String
    let activeStepId: UUID?
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case displayName = "display_name"
        case appLanguage = "app_language"
        case activeStepId = "active_step_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct WordUpsert: UpsertRow {
    static let table = "words"
    let id: UUID
    let householdId: UUID
    let profileId: UUID?
    let stepId: UUID?
    let text: String
    let promptText: String
    let source: String
    let displayOrder: Int
    let updatedAt: String
    let deletedAt: String?
    // Ph4: ローカル String の保管ステップ／コース紐付け（text 列。サーバー UUID step_id とは別管理＝§7.5）。
    let storageStepId: String?
    let linkedCourseId: String?
    let linkedBeforeStepId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case profileId = "profile_id"
        case stepId = "step_id"
        case text
        case promptText = "prompt_text"
        case source
        case displayOrder = "display_order"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case storageStepId = "storage_step_id"
        case linkedCourseId = "linked_course_id"
        case linkedBeforeStepId = "linked_before_step_id"
    }
}
