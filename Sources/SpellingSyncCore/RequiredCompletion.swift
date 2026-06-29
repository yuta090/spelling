import Foundation

/// 必須クリア状態（このステップの登録語セットの必須を一通り済ませた印）。
///
/// 設計（`docs/age-tiered-generation-spec-2026-06-29.md` §3-6/§3-7）：
/// - 完了キーは文字列でなく **(stepID, 単語構成 signature)**。
/// - 単語の追加/置換で signature が変わり、自動で「未完了」に戻る（再ロック）。
/// - これは「必須を一通り済ませたか」だけを表す。**満点クリアの mastery ゲートは既存アプリ側の責務**で、
///   ここでは二重管理しない（順番・進級は既存 WordStep 順＋満点ゲートに一本化）。

/// (stepID, 単語構成) の安定署名。永続化するので Codable/Hashable。
public struct StepSignature: Equatable, Hashable, Sendable, Codable {
    public var stepID: String
    /// 登録語の安定ID集合（ソート・重複排除後）のハッシュ。
    public var wordSetHash: String
    /// 署名アルゴリズムの版（将来ロジックを変えても旧データと区別できる）。
    public var version: Int

    public init(stepID: String, wordSetHash: String, version: Int) {
        self.stepID = stepID
        self.wordSetHash = wordSetHash
        self.version = version
    }
}

public enum RequiredCompletionSignature {
    /// 署名アルゴリズムの版。集合ハッシュの作り方を変えるときに増やす。
    public static let version = 1

    /// 名前空間（他の決定論IDと混ざらないよう専用値）。
    private static let namespace = UUID(uuidString: "5C1F8A22-7E63-5B49-9D0A-1B2C3D4E5F60")!

    /// 単語の安定ID集合（順序・重複に依存しない）から署名を作る。
    public static func make(stepID: String, wordStableIDs: [String]) -> StepSignature {
        let normalized = Set(wordStableIDs).sorted()
        // ステップIDも署名材料に含め、ハッシュ自体を stepID とは独立に算出する。
        let hash = DeterministicID.uuidV5(namespace: namespace, components: normalized)
            .uuidString.lowercased()
        return StepSignature(stepID: stepID, wordSetHash: hash, version: version)
    }
}

/// 済んだ必須署名の集合。
public struct RequiredCompletion: Equatable, Sendable, Codable {
    public private(set) var completed: Set<StepSignature>

    public init(completed: Set<StepSignature> = []) {
        self.completed = completed
    }

    /// この単語セットの必須が完了済みか。
    public func isCleared(_ signature: StepSignature) -> Bool {
        completed.contains(signature)
    }

    /// この単語セットの必須を完了として記録する。
    public mutating func markCleared(_ signature: StepSignature) {
        completed.insert(signature)
    }
}
