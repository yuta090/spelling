import Foundation

/// 1つの子どもプロファイル（1台の iPad を兄弟で共有するための単位）。
/// `id` はローカル生成し、サーバ `profiles.id` と対応づける（設計 §6）。
/// 表示名・アバターは「切り替え画面で自分を選ぶ手掛かり」（字が読めなくても顔で選べる）。
/// 設計: docs/multi-child-profiles-design-2026-07-01.md §2.1
public struct ChildProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    /// 子のニックネーム（旧 `childName` の移設先）。
    public var displayName: String
    /// ランチャーの顔＝既存のなかま/アバター資産の ID を流用。
    public var avatarID: String
    /// カード色（見た目言語の再利用）。
    public var colorHex: String
    public var createdAt: Date
    /// 並び順（親が並べ替え）。
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        avatarID: String = "",
        colorHex: String = "#7C9CF5",
        createdAt: Date,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarID = avatarID
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}

/// プロファイル台帳。一覧と「今アクティブな子」を保持する純データ＋操作（I/O は持たない）。
///
/// 不変条件:
/// - `profiles.count >= 1`（`removing` は最後の1人を消さない）
/// - `activeProfile` は常に解決可能（保存が壊れて `activeProfileID` が見つからない場合は先頭へフォールバック）
///
/// 全操作は新しい `ProfileRegistry` を返す（決定論・値型）。`profiles` は常に正準順序で保持する。
/// 設計: docs/multi-child-profiles-design-2026-07-01.md §2.2
public struct ProfileRegistry: Equatable, Codable, Sendable {
    /// 正準順序（sortIndex → createdAt → id）で正規化済みの一覧。
    public private(set) var profiles: [ChildProfile]
    public private(set) var activeProfileID: UUID

    /// 正規化（重複ID除去・正準順序）した上で不変条件を強制する。
    /// `activeProfileID` が実在しなければ先頭へ修復する（`>=1` は precondition で保証）。
    public init(profiles: [ChildProfile], activeProfileID: UUID) {
        let normalized = Self.normalized(profiles)
        precondition(!normalized.isEmpty, "ProfileRegistry は最低1人のプロファイルが必要")
        self.profiles = normalized
        self.activeProfileID = normalized.contains { $0.id == activeProfileID }
            ? activeProfileID
            : normalized[0].id
    }

    /// 移行/初回セットアップ用：1人から台帳を起こす（その子をアクティブに）。
    public init(bootstrapping profile: ChildProfile) {
        self.init(profiles: [profile], activeProfileID: profile.id)
    }

    // MARK: Codable（合成をバイパスさせず、デコードでも不変条件を守る）

    private enum CodingKeys: String, CodingKey { case profiles, activeProfileID }

    /// 壊れた/古い保存からの復旧：順序を正規化し、`activeProfileID` が無ければ先頭へ修復する。
    /// プロファイルが空なら**デコード失敗**にする（上位は `load` が nil を受け取り bootstrap する設計 §4）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProfiles = try container.decode([ChildProfile].self, forKey: .profiles)
        let decodedActive = try container.decode(UUID.self, forKey: .activeProfileID)
        let normalized = Self.normalized(decodedProfiles)
        guard !normalized.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles, in: container,
                debugDescription: "ProfileRegistry は最低1人のプロファイルが必要"
            )
        }
        self.profiles = normalized
        self.activeProfileID = normalized.contains { $0.id == decodedActive }
            ? decodedActive
            : normalized[0].id
    }

    // MARK: 参照

    /// 表示・切り替え用の並び（正準順序）。
    public var orderedProfiles: [ChildProfile] { profiles }

    /// 今アクティブな子。不変条件（`>=1`・`activeProfileID` は実在に修復済み）により常に存在する。
    public var activeProfile: ChildProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    // MARK: 操作（新しい台帳を返す）

    /// 追加。アクティブは変えない。id が既にあれば no-op（重複を作らない）。
    /// 追加した子は **末尾** に来るよう `sortIndex` を既存の最大+1 にする。
    /// （呼び出し側は既定 `sortIndex=0` の `ChildProfile` を渡すため、そのまま入れると reorder 後の
    ///  正準順序（sortIndex→createdAt→id）で先頭付近へ割り込んでしまう。ここで末尾採番に正規化する。）
    public func adding(_ profile: ChildProfile) -> ProfileRegistry {
        guard !profiles.contains(where: { $0.id == profile.id }) else { return self }
        var appended = profile
        appended.sortIndex = (profiles.map(\.sortIndex).max() ?? -1) + 1
        return ProfileRegistry(profiles: profiles + [appended], activeProfileID: activeProfileID)
    }

    /// 削除。最後の1人は消せない／未知IDは無視。アクティブを消したら残りの先頭へ移す。
    public func removing(_ id: UUID) -> ProfileRegistry {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return self }
        let remaining = profiles.filter { $0.id != id }
        let newActive = (id == activeProfileID) ? Self.normalized(remaining).first!.id : activeProfileID
        return ProfileRegistry(profiles: remaining, activeProfileID: newActive)
    }

    /// 改名。未知IDは無視。
    public func renaming(_ id: UUID, to newName: String) -> ProfileRegistry {
        mutatingProfile(id) { $0.displayName = newName }
    }

    /// プロファイル丸ごと差し替え（アバター/色の更新など）。未知IDは無視。
    public func updating(_ profile: ChildProfile) -> ProfileRegistry {
        mutatingProfile(profile.id) { $0 = profile }
    }

    /// アクティブ切り替え。未知IDは無視。
    public func activating(_ id: UUID) -> ProfileRegistry {
        guard profiles.contains(where: { $0.id == id }) else { return self }
        return ProfileRegistry(profiles: profiles, activeProfileID: id)
    }

    /// 並べ替え。`orderedIDs` の順に `sortIndex` を振り直す。未指定IDは末尾に既存順で。アクティブは変えない。
    public func reordering(_ orderedIDs: [UUID]) -> ProfileRegistry {
        var indexByID: [UUID: Int] = [:]
        for (i, id) in orderedIDs.enumerated() { indexByID[id] = i }
        let base = orderedIDs.count
        let renumbered = profiles.enumerated().map { offset, profile -> ChildProfile in
            var next = profile
            next.sortIndex = indexByID[profile.id] ?? (base + offset)
            return next
        }
        return ProfileRegistry(profiles: renumbered, activeProfileID: activeProfileID)
    }

    // MARK: 内部

    private func mutatingProfile(_ id: UUID, _ transform: (inout ChildProfile) -> Void) -> ProfileRegistry {
        guard profiles.contains(where: { $0.id == id }) else { return self }
        var next = profiles
        for i in next.indices where next[i].id == id { transform(&next[i]) }
        return ProfileRegistry(profiles: next, activeProfileID: activeProfileID)
    }

    /// 正準順序（sortIndex → createdAt → id）に並べ、id 重複は先勝ちで除去する。
    /// 重複除去は `removing` 後の `first!` などクラッシュ源を根で断つための保険。
    private static func normalized(_ profiles: [ChildProfile]) -> [ChildProfile] {
        let sorted = profiles.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var seen = Set<UUID>()
        return sorted.filter { seen.insert($0.id).inserted }
    }
}
