import Foundation

/// 学校テスト語などの **custom 単語**を、保管は personal（うちのれんしゅう）のまま、
/// いま見ているコースのステップ階段に“紐付け”て差し込むための **純ロジック**。
///
/// アプリ型（`SpellingWord`/`WordStep`）に依存しないよう、`WordToken(id, normalized)` の列という
/// 抽象 descriptor 上で計画する。アプリ側はこの計画の `id` を頼りに実モデルへ materialize する。
///
/// 設計方針（codex Architect 助言＋Code Reviewer 指摘反映）:
/// - 合成（synthetic）ステップは編集・同期しない。custom は `linkedCourseID` でコースに、
///   `linkedBeforeStepID` で挿入位置（このステップの手前）に結び付ける。
/// - dedup は **forward-only**: custom と同じ語は「挿入位置以降」の合成からのみ落とす。
///   挿入位置より前（通過/完了し得る）の合成は温存し、履歴・「できた」を壊さない。
/// - 重複判定は **正規化テキスト**で行うが、出力トークンは **id を保持**する。同じ綴りでも
///   別の実語（別id）を取り違えないため（Code Reviewer Critical 2）。
/// - バッチ化（`buildGroups`）は `(storageStepID, beforeStepID)` 単位で分割する。同一保管ステップ内で
///   アンカーが混在しても取りこぼさない（Code Reviewer Rec 1）。custom ステップの一意性のため
///   グループの `storageStepID` は両者を含む合成キーにする。
public enum LinkedStepComposer {

    /// 1語の素性。`id` は実語へ戻すための安定識別子、`normalized` は重複判定キー。
    public struct WordToken: Equatable, Sendable {
        public let id: String
        public let normalized: String
        public init(id: String, normalized: String) {
            self.id = id
            self.normalized = normalized
        }
    }

    /// コースの合成ステップ（読み取り専用・非同期）の最小記述。
    public struct BaseStep: Equatable, Sendable {
        public let stepID: String
        public let words: [WordToken]
        public init(stepID: String, words: [WordToken]) {
            self.stepID = stepID
            self.words = words
        }
    }

    /// personal に保管された custom 語のうち、特定コースへ紐付いた1バッチ分。
    public struct LinkedGroup: Equatable, Sendable {
        /// 表示時の custom ステップの素性キー（custom ステップIDの基。`buildGroups` は合成キーを入れる）。
        public let storageStepID: String
        /// このコースのどのステップ手前に差し込むか。nil または不明なら末尾へ。
        public let beforeStepID: String?
        public let words: [WordToken]
        public init(storageStepID: String, beforeStepID: String?, words: [WordToken]) {
            self.storageStepID = storageStepID
            self.beforeStepID = beforeStepID
            self.words = words
        }
    }

    /// 計画されたステップの素性。
    public enum Origin: Equatable, Sendable {
        case synthetic(stepID: String)
        case custom(storageStepID: String)
    }

    /// マージ後の1ステップ（番号は最終列で 1 始まり振り直し）。
    public struct PlannedStep: Equatable, Sendable {
        public let origin: Origin
        public let number: Int
        public let words: [WordToken]
        public init(origin: Origin, number: Int, words: [WordToken]) {
            self.origin = origin
            self.number = number
            self.words = words
        }
    }

    // MARK: - バッチ化

    /// `buildGroups` の入力：紐付いた1語のフラット記述。
    public struct LinkedWordInput: Equatable, Sendable {
        public let id: String
        public let normalized: String
        /// personal 側の保管ステップID（バッチの基。nil ならフォールバックバケット）。
        public let storageStepID: String?
        public let beforeStepID: String?
        public init(id: String, normalized: String, storageStepID: String?, beforeStepID: String?) {
            self.id = id
            self.normalized = normalized
            self.storageStepID = storageStepID
            self.beforeStepID = beforeStepID
        }
    }

    /// フラットな紐付け語を `(storageStepID, beforeStepID)` 単位のバッチへまとめる。
    /// 同一保管ステップでもアンカーが違えば別バッチに割る（取りこぼし防止）。
    /// 出現順を保ち、custom ステップが衝突しないよう `storageStepID` を合成キーにする。
    public static func buildGroups(from inputs: [LinkedWordInput]) -> [LinkedGroup] {
        struct Key: Hashable { let storage: String; let before: String? }
        var order: [Key] = []
        var wordsByKey: [Key: [WordToken]] = [:]
        for w in inputs {
            let key = Key(storage: w.storageStepID ?? "$loose", before: w.beforeStepID)
            if wordsByKey[key] == nil { order.append(key) }
            wordsByKey[key, default: []].append(WordToken(id: w.id, normalized: w.normalized))
        }
        return order.map { key in
            LinkedGroup(storageStepID: compositeStorageID(storage: key.storage, before: key.before),
                        beforeStepID: key.before,
                        words: wordsByKey[key] ?? [])
        }
    }

    /// custom ステップの一意・決定論キー（保管ステップ＋アンカーを含む）。
    public static func compositeStorageID(storage: String, before: String?) -> String {
        "\(storage)@\(before ?? "$end")"
    }

    // MARK: - 計画

    /// 合成ステップ列に紐付き custom バッチを差し込み、forward dedup と空ステップ除去を施して
    /// 1 始まりで番号を振り直した最終列を返す。
    public static func plan(base: [BaseStep], linked: [LinkedGroup]) -> [PlannedStep] {
        // アンカー stepID → base 内の最初の位置。
        var anchorIndex: [String: Int] = [:]
        for (i, step) in base.enumerated() where anchorIndex[step.stepID] == nil {
            anchorIndex[step.stepID] = i
        }

        // 各バッチを「挿入位置（= その base index の手前）」へ解決し、バッチ内 dedup 済み語を持つ。
        struct Resolved {
            let storageStepID: String
            let insertionIndex: Int
            let words: [WordToken]
            /// 「以降の合成から落とす」判定に使う正規化テキスト集合。
            let normalizedSet: Set<String>
        }
        let resolved: [Resolved] = linked.compactMap { group in
            let words = dedup(group.words)
            guard !words.isEmpty else { return nil }   // 空バッチは出さない
            let index: Int
            if let before = group.beforeStepID, let anchored = anchorIndex[before] {
                index = anchored
            } else {
                index = base.count   // nil / 不明 → 末尾フォールバック
            }
            return Resolved(storageStepID: group.storageStepID, insertionIndex: index,
                            words: words, normalizedSet: Set(words.map(\.normalized)))
        }

        var ordered: [(origin: Origin, words: [WordToken])] = []

        // insertionIndex == i のバッチを storageStepID 昇順で決定論的に出す。
        func emitCustom(at i: Int) {
            let groups = resolved
                .filter { $0.insertionIndex == i }
                .sorted { $0.storageStepID < $1.storageStepID }
            for g in groups {
                ordered.append((.custom(storageStepID: g.storageStepID), g.words))
            }
        }

        for i in 0..<base.count {
            emitCustom(at: i)
            // 挿入位置 <= i のバッチ語は「以降」の合成から落とす（前は温存）。
            var active = Set<String>()
            for r in resolved where r.insertionIndex <= i { active.formUnion(r.normalizedSet) }
            let words = base[i].words.filter { !active.contains($0.normalized) }
            if !words.isEmpty {
                ordered.append((.synthetic(stepID: base[i].stepID), words))
            }
        }
        emitCustom(at: base.count)   // 末尾フォールバック分

        return ordered.enumerated().map { idx, item in
            PlannedStep(origin: item.origin, number: idx + 1, words: item.words)
        }
    }

    /// 正規化テキスト先勝ちで重複を畳む（順序・id維持）。
    private static func dedup(_ words: [WordToken]) -> [WordToken] {
        var seen = Set<String>()
        var out: [WordToken] = []
        for w in words where !seen.contains(w.normalized) {
            seen.insert(w.normalized)
            out.append(w)
        }
        return out
    }
}
