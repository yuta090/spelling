import Foundation

/// ことばパズルで出せる出題形式。「1つのメニューからランダム出題」するための編成単位。
/// 設計: docs/kotoba-puzzle-spec-2026-06-28.md
///
/// `ExerciseFormat`（SentenceExercise.swift）は **文ベースの採点形式**（並べ替え/穴埋め/手書き/英作文/3択）を表す。
/// ことばパズルは音声・語ベースの形式（リスニング穴埋め・単語リスニング）も同じメニューに混ぜるため、
/// セッション編成専用に別の列挙として持つ（UI 側が `PuzzleFormat` → 各 Generator/Grader に割り当てる）。
public enum PuzzleFormat: String, CaseIterable, Sendable, Codable {
    /// ぶんづくり（並べ替え）。決定的採点。
    case wordOrdering
    /// あなうめ（選択肢から選ぶ）。決定的採点。
    case clozeChoice
    /// きいて あなうめ（リスニング穴埋め・音の近いおとり）。決定的採点。
    case listeningCloze
    /// おとを きいて えらぶ（単語リスニング）。決定的採点。音が本体。
    case wordListening
    /// 手書き穴埋め（AI/OCR 採点）。**未完成 = プール外**。
    case clozeHandwriting
    /// 英作文（AI VLM 採点）。**未完成 = プール外**。
    case composition

    /// いま遊べる（実装＆採点が完成している）形式か。
    /// 手書き・英作文は AI/OCR 採点が未完成のためプールに入れない。
    public var isPlayable: Bool {
        switch self {
        case .wordOrdering, .clozeChoice, .listeningCloze, .wordListening:
            return true
        case .clozeHandwriting, .composition:
            return false
        }
    }

    /// 音声が本体の形式か。`true` の形式は「おとなし」設定では出題できない（やさしく見送る）。
    public var requiresAudio: Bool {
        switch self {
        case .wordListening: return true
        case .wordOrdering, .clozeChoice, .listeningCloze, .clozeHandwriting, .composition:
            return false
        }
    }

    /// ランダム出題プール（いま遊べる形式すべて・宣言順）。
    /// 新形式を完成させたら `isPlayable` を `true` にするだけでプールに入る。
    public static var playablePool: [PuzzleFormat] {
        allCases.filter(\.isPlayable)
    }
}

/// 出題形式の並び（スケジュール）を決定論で組む。
/// 「飽きさせない」ために連続して同じ形式を出さない。内容（どの文/語か）の解決は呼び出し側（UI）の責務。
public enum PuzzleFormatScheduler {
    /// `pool` から `length` 個の出題形式列を返す（seed 決定論）。
    /// ルール:
    /// - **連続して同じ形式を出さない**（pool が2形式以上のとき）。
    /// - pool の重複は出現順で一意化する。
    /// - 形式は決定論シャッフル順で巡回（`SessionComposer` と同じ手法）。
    public static func schedule(pool: [PuzzleFormat], length: Int, seed: UInt64) -> [PuzzleFormat] {
        guard !pool.isEmpty, length > 0 else { return [] }

        var seen = Set<PuzzleFormat>()
        let distinct = pool.filter { seen.insert($0).inserted }
        let shuffled = SeededShuffle.shuffle(distinct, seed: seed)

        var out: [PuzzleFormat] = []
        out.reserveCapacity(length)
        for i in 0..<length {
            // distinct を順に巡回するので i と i+1 は必ず別形式（n>=2 で連続同形式なし）。
            out.append(shuffled[i % shuffled.count])
        }
        return out
    }
}
