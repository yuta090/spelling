import Foundation

/// 単語の **同期対象ペイロード**（`SyncMetadata` を除いた本体フィールド）。
///
/// アプリの `SpellingWord`（UI モデル・同期列を持たない）と、サーバーの `words` 行の橋渡し。
/// `Equatable` を **dirty 検出の指紋**として使う（前回同期時と内容が変われば送信対象）。
/// `stepID` は当面ローカルの String のまま保持する（サーバーの UUID `step_id` への対応は別管理。
/// 設計: docs/supabase-adapter-design.md §7.5）。
public struct WordPayload: Equatable, Codable, Sendable {
    public var text: String
    public var promptText: String
    /// `WordSource` の raw 値（"parent" / "child"）。コアは enum を知らないので String で持つ。
    public var source: String
    /// ローカルの派生ステップ ID（String）。サーバー `step_id`(UUID) とは別管理（→ `storage_step_id` text 列で往復）。
    public var stepID: String?
    public var displayOrder: Int
    /// 表示先コースID（`Course.id`。合成コースへ「表示だけ」紐付ける。nil＝紐付け無し）。Ph4 で同期。
    public var linkedCourseID: String?
    /// 表示先コースのどの合成ステップ手前に差し込むか（nil＝末尾）。Ph4 で同期。
    public var linkedBeforeStepID: String?

    public init(text: String, promptText: String, source: String, stepID: String?, displayOrder: Int,
                linkedCourseID: String? = nil, linkedBeforeStepID: String? = nil) {
        self.text = text
        self.promptText = promptText
        self.source = source
        self.stepID = stepID
        self.displayOrder = displayOrder
        self.linkedCourseID = linkedCourseID
        self.linkedBeforeStepID = linkedBeforeStepID
    }
}

/// 単語の正準同期レコード（`SyncMetadata` ＋ `WordPayload`）。
/// プル/プッシュ両方で `LastWriteWins` / `OutboundSync` に渡せる `SyncableRecord`。
public struct WordSyncRecord: SyncableRecord, Codable, Equatable, Sendable {
    public var sync: SyncMetadata
    public var payload: WordPayload

    public init(sync: SyncMetadata, payload: WordPayload) {
        self.sync = sync
        self.payload = payload
    }
}

/// ローカル UI 側の単語入力（射影の素材）。`SpellingWord` から id/payload/createdAt を写したもの。
public struct LocalWord: Equatable, Sendable {
    public var id: UUID
    public var payload: WordPayload
    /// 新規採番時に `SyncMetadata.createdAt` に使う（`SpellingWord.registeredAt` 相当）。
    public var createdAt: Date

    public init(id: UUID, payload: WordPayload, createdAt: Date) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// 世帯（＋任意でプロファイル）スコープのフィルタ（プル取得分の隔離・プッシュ前の自衛）。
public enum SyncScope {
    /// `householdID`（と、指定時は `profileID`）が一致するレコードだけを残す。
    /// アクティブ世帯が `nil`（未選択）なら **空**（スコープ無し＝同期対象なし）。
    ///
    /// `profileID` を渡すと **プロファイル一致も要求** する（Phase 5b の防御的スコープ）。pull は
    /// クエリ側で `profile_id` を絞る（`SyncEngine`）が、親認証は世帯の全子行にアクセスできるため、
    /// 万一クエリを跨いだ行が混ざっても reducer が他児レコードを取り込まない belt になる。
    /// `nil` はプロファイル絞りなし（後方互換：レビュー/アテンプト等・単一プロファイル文脈）。
    public static func scoped<R: SyncableRecord>(_ records: [R], householdID: UUID?, profileID: UUID? = nil) -> [R] {
        guard let householdID else { return [] }
        return records.filter { record in
            record.sync.householdID == householdID
                && (profileID == nil || record.sync.profileID == profileID)
        }
    }
}

/// 単語の **サイドカー同期ストア**。
///
/// `SpellingWord`（巨大な View 層が依存する UI モデル）を改変せず、`id → (SyncMetadata, 指紋)`
/// を別管理する。`project` がローカル単語に同期メタデータを射影し、内容変化・論理削除を検出して
/// `WordSyncRecord` 群を返す（プル時の `LastWriteWins.reconcile` 入力にも、プッシュ時の
/// `OutboundSync.pending` 入力にもなる）。`ingest` で「同期済み/取得済みの真実」を取り込み、
/// 次回 `project` の dirty 判定基準を前進させる。永続化のため `Codable`。
/// 設計: docs/supabase-adapter-design.md §7.5。
public struct WordSidecarStore: Equatable, Codable, Sendable {
    /// 直近に同期/取得した状態（メタデータ＋指紋）。`project` の dirty 検出の基準。
    private struct Entry: Equatable, Codable, Sendable {
        var metadata: SyncMetadata
        var payload: WordPayload
    }

    private var entries: [UUID: Entry]

    /// 変更時刻を「過去版より厳密に後」に保つための最小刻み（1ms）。
    /// 端末クロックの逆行（別端末が未来の `updatedAt` を書いた／ローカル時計が巻き戻った）でも
    /// 編集・削除が前の版に **タイ/敗北しない** ことを保証する。RFC3339(ms 精度)で往復しても消えない幅。
    private static let minimumTick: TimeInterval = 0.001

    /// `floor`（既知の最終 updatedAt）より厳密に後の変更時刻を返す。
    /// `now` が十分に新しければそのまま、クロック逆行時のみ `floor + 1ms` に押し上げる。
    private static func bump(after floor: Date, now: Date) -> Date {
        now > floor ? now : floor.addingTimeInterval(minimumTick)
    }

    public init() {
        entries = [:]
    }

    /// id に対する直近の同期メタデータ（無ければ nil）。
    public func metadata(for id: UUID) -> SyncMetadata? {
        entries[id]?.metadata
    }

    /// 既知の id 数（テスト/デバッグ用）。
    public var count: Int { entries.count }

    /// 「同期済み/取得済みの真実」を取り込み、dirty 判定の基準を前進させる。
    /// - プル＋reconcile 後の確定版、プッシュ成功後の送信版、いずれもここに通す。
    /// - 同 id が複数来た場合は `LastWriteWins` で勝者を採り、順序非依存にする。
    public mutating func ingest(_ records: [WordSyncRecord]) {
        for record in records {
            if let existing = entries[record.id] {
                let winner = LastWriteWins.resolve(
                    WordSyncRecord(sync: existing.metadata, payload: existing.payload),
                    record
                )
                entries[record.id] = Entry(metadata: winner.sync, payload: winner.payload)
            } else {
                entries[record.id] = Entry(metadata: record.sync, payload: record.payload)
            }
        }
    }

    /// ローカル単語へ同期メタデータを射影し、`WordSyncRecord` 群を返す。
    ///
    /// 規則:
    /// - **新規 id**（サイドカー未知）: `createdAt`=word の registeredAt、`updatedAt`=now、世帯/プロファイルを付与。
    /// - **既知・内容不変・生存中**: メタデータ据え置き（dirty にしない）。
    /// - **既知・内容変化** または **復活**（墓石だった id を再追加）: `updatedAt`=now、`deletedAt` はクリア。
    /// - **サイドカーにあるがローカルに無い id**: 論理削除（`deletedAt`=`updatedAt`=now）。
    ///   既に墓石なら据え置き（churn 防止）。最後に見たペイロードを保持する。
    ///
    /// `now` は呼び出し側から渡す（純粋・決定的）。戻り値は id 昇順で安定ソート。
    ///
    /// スコープ: `householdID` が `nil`（未サインイン/世帯未選択）なら **空**を返す（同期対象なし）。
    /// 「ローカルに無い → 墓石化」は **アクティブ世帯のエントリのみ** に限定する。これにより
    /// 1 つのストアが複数世帯のエントリを持っていても、別世帯の単語を誤って削除しない。
    ///
    /// クロック: 変更/復活/削除の `updatedAt` は `bump(after:now:)` で過去版より厳密に後にする
    /// （クロック逆行でも `OutboundSync.pending` の strict `>` や LWW から取りこぼさない）。
    ///
    /// 契約: `project` は非破壊（dirty を確定しない）。プッシュ/プル成功後に勝者を `ingest` して
    /// 基準を前進させること。`ingest` 前に再 `project` すると、変更中レコードは渡した `now` で
    /// 再スタンプされる（収束する：最終的に push+ingest した版が真実になる）。
    public func project(
        localWords: [LocalWord],
        now: Date,
        householdID: UUID?,
        profileID: UUID?
    ) -> [WordSyncRecord] {
        // 未スコープ（世帯未選択）なら同期対象なし。
        guard let householdID else { return [] }

        // 同一 id の重複入力は最後の版を採る（重複レコード生成を防ぐ）。
        var byID: [UUID: LocalWord] = [:]
        for word in localWords { byID[word.id] = word }

        var result: [WordSyncRecord] = []

        for (id, word) in byID {
            if let entry = entries[id] {
                let unchanged = entry.payload == word.payload && !entry.metadata.isDeleted
                if unchanged {
                    result.append(WordSyncRecord(sync: entry.metadata, payload: entry.payload))
                } else {
                    var meta = entry.metadata
                    meta.updatedAt = Self.bump(after: entry.metadata.updatedAt, now: now)
                    meta.deletedAt = nil          // 内容変更/復活はいずれも生存版
                    result.append(WordSyncRecord(sync: meta, payload: word.payload))
                }
            } else {
                let meta = SyncMetadata(
                    id: id,
                    householdID: householdID,
                    profileID: profileID,
                    createdAt: word.createdAt,
                    updatedAt: now
                )
                result.append(WordSyncRecord(sync: meta, payload: word.payload))
            }
        }

        // ローカルから消えた既知レコード → 論理削除（墓石）。アクティブ世帯のみが対象。
        for (id, entry) in entries
        where byID[id] == nil && entry.metadata.householdID == householdID {
            if entry.metadata.isDeleted {
                result.append(WordSyncRecord(sync: entry.metadata, payload: entry.payload))
            } else {
                var meta = entry.metadata
                let stamp = Self.bump(after: entry.metadata.updatedAt, now: now)
                meta.updatedAt = stamp
                meta.deletedAt = stamp
                result.append(WordSyncRecord(sync: meta, payload: entry.payload))
            }
        }

        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// テーブル別の同期カーソルと送信 high-water mark の永続化値。
///
/// - **プルカーソル**: `sync_version`（サーバー採番の単調増加 bigint）。テーブル毎に最大値を保持。
/// - **プッシュ high-water**: 送信済みの最大 `updatedAt`（`OutboundSync.highWater` と同義）。
///
/// I/O（UserDefaults/ファイル）はアプリ側。ここは前進ロジックと `Codable` のみ。
public struct SyncCursors: Equatable, Codable, Sendable {
    private var pull: [String: Int]
    private var push: [String: Date]

    public init() {
        pull = [:]
        push = [:]
    }

    /// テーブルのプルカーソル（未設定なら 0＝初回から全件）。
    public func pullCursor(for table: String) -> Int {
        pull[table] ?? 0
    }

    /// プルカーソルを前進（後退はしない）。
    public mutating func advancePull(table: String, to cursor: Int) {
        pull[table] = Swift.max(pull[table] ?? 0, cursor)
    }

    /// テーブルの送信済み high-water（未送信なら nil）。
    public func pushedThrough(for table: String) -> Date? {
        push[table]
    }

    /// 送信 high-water を前進（後退はしない）。
    public mutating func advancePush(table: String, to highWater: Date) {
        if let current = push[table] {
            push[table] = Swift.max(current, highWater)
        } else {
            push[table] = highWater
        }
    }
}
