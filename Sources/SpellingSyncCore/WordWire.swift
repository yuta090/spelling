import Foundation

/// 単語の **wire 表現**（Supabase `words` 行のフィールドを SDK 非依存のプリミティブで持つ箱）。
///
/// アプリ側 DTO（`WordDTO` / `WordUpsert`）⇄ コアの変換は、**単純なフィールドの写し替えだけ**を
/// アプリに残し、判断を要するロジック（RFC3339 日付のパース/整形・`stepID` の取り扱い・
/// `createdAt` 欠落の補完）は**すべてここ（コア）に集約してテスト**する。
/// 設計: docs/supabase-adapter-design.md §7.5
public struct WordRow: Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var profileID: UUID?
    public var text: String
    public var promptText: String
    /// `WordSource` の raw 値（"parent" / "child"）。
    public var source: String
    public var displayOrder: Int
    /// クライアント LWW 時刻（RFC3339 文字列, UTC）。
    public var updatedAt: String
    /// 論理削除（RFC3339 文字列、未削除なら nil）。
    public var deletedAt: String?
    /// ローカルの保管ステップ ID（`storage_step_id` text 列）。サーバー UUID `step_id` とは別管理（§7.5）。
    public var storageStepID: String?
    /// 表示先コースID（`linked_course_id` text 列）。
    public var linkedCourseID: String?
    /// 表示先コースの挿入位置ステップ ID（`linked_before_step_id` text 列）。
    public var linkedBeforeStepID: String?

    public init(
        id: UUID,
        householdID: UUID,
        profileID: UUID?,
        text: String,
        promptText: String,
        source: String,
        displayOrder: Int,
        updatedAt: String,
        deletedAt: String?,
        storageStepID: String? = nil,
        linkedCourseID: String? = nil,
        linkedBeforeStepID: String? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.text = text
        self.promptText = promptText
        self.source = source
        self.displayOrder = displayOrder
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.storageStepID = storageStepID
        self.linkedCourseID = linkedCourseID
        self.linkedBeforeStepID = linkedBeforeStepID
    }
}

/// wire 行 ⇄ 正準同期レコード（`WordSyncRecord`）の純粋変換と RFC3339 日付ヘルパ。
public enum WordWire {
    // 送信は常にミリ秒つき UTC（"…Z"）で出す（LWW 比較の一貫性のため）。
    // ISO8601DateFormatter は Sendable でないため共有 static にはできない（Swift6）。
    // 生成コストは無視できる規模なので呼び出し毎に作る。
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    /// RFC3339（UTC, ミリ秒は任意）文字列を `Date` に。解釈できなければ nil。
    /// ミリ秒の無い "…Z" / "+00:00" 形式も受け付ける（受信側の保険）。
    public static func date(fromRFC3339 string: String) -> Date? {
        makeFormatter(fractional: true).date(from: string)
            ?? makeFormatter(fractional: false).date(from: string)
    }

    /// `Date` を RFC3339（UTC, ミリ秒つき "…Z"）文字列に。
    public static func rfc3339(from date: Date) -> String {
        makeFormatter(fractional: true).string(from: date)
    }

    /// サーバー行 → 正準同期レコード。
    /// - `createdAt` はサーバー DTO に無いため `updatedAt` を流用する（情報用途のみ）。
    /// - `payload.stepID` は `storage_step_id`(text) を写す（サーバー UUID `step_id` は依然 nil 扱い＝§7.5）。
    ///   Ph4: `linked_course_id` / `linked_before_step_id`(text) も payload へ写し、多端末で紐付けを伝搬する。
    /// - `updatedAt`、または非 nil の `deletedAt` が解釈できなければ nil（壊れた行は取り込まない）。
    ///   ⚠️ 解釈不能な `deletedAt` を黙って nil にすると**削除済み行が復活**するため、行ごと落とす。
    public static func record(from row: WordRow) -> WordSyncRecord? {
        guard let updated = date(fromRFC3339: row.updatedAt) else { return nil }
        let deleted: Date?
        if let deletedString = row.deletedAt {
            guard let parsed = date(fromRFC3339: deletedString) else { return nil }
            deleted = parsed
        } else {
            deleted = nil
        }
        let meta = SyncMetadata(
            id: row.id,
            householdID: row.householdID,
            profileID: row.profileID,
            createdAt: updated,
            updatedAt: updated,
            deletedAt: deleted
        )
        let payload = WordPayload(
            text: row.text,
            promptText: row.promptText,
            source: row.source,
            stepID: row.storageStepID,
            displayOrder: row.displayOrder,
            linkedCourseID: row.linkedCourseID,
            linkedBeforeStepID: row.linkedBeforeStepID
        )
        return WordSyncRecord(sync: meta, payload: payload)
    }

    /// 正準同期レコード → 送信用 wire 行。
    /// - `stepID`(ローカル String) は `storage_step_id`(text) として送る（サーバー UUID `step_id` は別管理＝§7.5）。
    ///   Ph4: `linkedCourseID` / `linkedBeforeStepID`(text) も送り、多端末で紐付けを伝搬する。
    /// - 日付は RFC3339（UTC, ミリ秒）文字列へ。
    /// - `householdID` が無いレコードは送れないため **nil** を返す（呼び出し側で除外）。
    public static func wire(from record: WordSyncRecord) -> WordRow? {
        guard let householdID = record.sync.householdID else { return nil }
        return WordRow(
            id: record.sync.id,
            householdID: householdID,
            profileID: record.sync.profileID,
            text: record.payload.text,
            promptText: record.payload.promptText,
            source: record.payload.source,
            displayOrder: record.payload.displayOrder,
            updatedAt: rfc3339(from: record.sync.updatedAt),
            deletedAt: record.sync.deletedAt.map(rfc3339(from:)),
            storageStepID: record.payload.stepID,
            linkedCourseID: record.payload.linkedCourseID,
            linkedBeforeStepID: record.payload.linkedBeforeStepID
        )
    }
}
