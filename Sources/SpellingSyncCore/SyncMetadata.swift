import Foundation

/// すべての同期対象レコードに共通する同期メタデータ。
///
/// CloudKit（`NSPersistentCloudKitContainer`）の競合解決は **レコード単位の last-write-wins**。
/// アプリ側でもこのメタデータを使って、複数端末から来た同一レコードの版を決定論的に解決し、
/// 論理削除（tombstone）を表現する。
///
/// 設計の全体像: docs/multi-user-cloudkit-sync-design.md
public struct SyncMetadata: Equatable, Codable, Sendable {
    /// 端末をまたいで一意な安定 ID。オフラインでも採番できる。
    public var id: UUID
    /// 世帯スコープ。共有ゾーン内のデータ隔離に使う。
    public var householdID: UUID?
    /// 子プロファイルスコープ。
    public var profileID: UUID?
    public var createdAt: Date
    /// 競合解決の基準となる最終更新時刻。
    public var updatedAt: Date
    /// 論理削除の時刻。`nil` でなければ削除済み（tombstone）。
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        householdID: UUID? = nil,
        profileID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// 論理削除済みか。
    public var isDeleted: Bool {
        deletedAt != nil
    }
}

/// 同期メタデータを持つレコード。
public protocol SyncableRecord: Identifiable, Sendable {
    var sync: SyncMetadata { get set }
}

public extension SyncableRecord {
    /// `Identifiable` の id は同期メタデータの id に揃える。
    var id: UUID { sync.id }
}

/// レコード単位 last-write-wins による競合解決と論理削除の取り扱い。
///
/// 解決は **順序非依存（対称）** であること。つまり `resolve(a, b) == resolve(b, a)`。
/// 複数端末から任意順で同期が届いても、収束先が一意になる。
public enum LastWriteWins {
    /// 同一 id の 2 版から採用する版を決める。
    ///
    /// 規則（上から順に評価）:
    /// 1. `updatedAt` が新しい方を採用。
    /// 2. 同時刻なら、**削除（tombstone）を優先**（消えたものを復活させない）。
    /// 3. それも同じなら、`id.uuidString` が大きい方を採用（決定論的なタイブレーク）。
    public static func resolve<R: SyncableRecord>(_ lhs: R, _ rhs: R) -> R {
        let l = lhs.sync
        let r = rhs.sync
        if l.updatedAt != r.updatedAt {
            return l.updatedAt > r.updatedAt ? lhs : rhs
        }
        if l.isDeleted != r.isDeleted {
            return l.isDeleted ? lhs : rhs
        }
        return l.id.uuidString >= r.id.uuidString ? lhs : rhs
    }

    /// ローカルとリモートのレコード集合を id ごとに LWW で統合する。
    /// 戻り値には tombstone も含む（同期状態として保持する必要があるため）。
    /// `resolve` は全順序の最大値選択なので、統合は畳み込み順序に依存しない。
    /// 戻り値は id 昇順で安定ソートして決定論的にする。
    public static func reconcile<R: SyncableRecord>(local: [R], remote: [R]) -> [R] {
        var byID: [UUID: R] = [:]
        for record in local + remote {
            if let existing = byID[record.id] {
                byID[record.id] = resolve(existing, record)
            } else {
                byID[record.id] = record
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// tombstone を除いた「生きている」レコードだけを返す（UI 表示用）。
    public static func live<R: SyncableRecord>(_ records: [R]) -> [R] {
        records.filter { !$0.sync.isDeleted }
    }
}
