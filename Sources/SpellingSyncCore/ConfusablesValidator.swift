import Foundation

/// confusables_sound 辞書のビルド検証（純ロジック・TDD）。
/// 設計: docs/confusables-sound-authoring-DRAFT-2026-06-28.md §5（ビルド検証チェックリスト）
///
/// 方針（ユーザー決定 2026-06-28）：
///  - **ハード規則**（守れなければ却下）はデータだけで判定する：
///    承認済み・見出し語と別・重複なし・個数2〜4・正規化（小文字/トリム）。
///  - **wordbank 実在/band** は **警告**（レポートに出すだけ・自動削除しない）。
///    この wordbank の `gloss` には gray/math のような実在語の欠落があり、
///    機械削除すると良い手承認データを壊すため。警告を見て人が
///    「辞書に足す」か「ペアを直す」かを判断する。
///
/// IO（CSV/wordbank 読み込み・ファイル出力）は本 Core では行わない。呼び出し側（ビルドツール）が用意する。
public enum ConfusablesValidator {

    /// 却下理由（ハード規則違反）。
    public enum RejectionReason: Equatable, Sendable {
        case tooFewDistractors      // 正規化後に2語未満
        case tooManyDistractors     // 5語以上
        case emptyWord              // 見出し語が空
        case duplicateHeadword      // 同じ見出し語が既に採用済み（distractors は先頭一致なので後勝ちを防ぐ）
        case invalidToken(String)   // CSV を壊す文字（, | 改行 タブ）を含む語
    }

    public struct Rejection: Equatable, Sendable {
        public var word: String
        public var reason: RejectionReason
        public init(word: String, reason: RejectionReason) {
            self.word = word
            self.reason = reason
        }
    }

    /// 警告の種類（採用は維持・人が確認する）。
    public enum WarningKind: Equatable, Sendable {
        case notInWordbank(String)          // 見出し語/おとりが wordbank に無い（語）
        case bandUnknown(String)            // band 不明（targetBand 指定時のみ）
        case bandOverTarget(String, Int)    // band が対象学年を超える（語, band）
    }

    public struct Warning: Equatable, Sendable {
        public var word: String             // 対象の見出し語（どの行の警告か）
        public var kind: WarningKind
        public init(word: String, kind: WarningKind) {
            self.word = word
            self.kind = kind
        }
    }

    public struct Result: Equatable, Sendable {
        public var accepted: [ConfusableEntry]      // 同梱対象（approved=1・ハード規則通過・正規化/整理済み）
        public var rejected: [Rejection]            // ハード規則違反（要修正）
        public var warnings: [Warning]              // 実在/band の確認事項（削除しない）
        public var excludedUnapprovedCount: Int     // approved=0 で同梱対象外（問題ではない）
    }

    /// - entries: パース済みエントリ（approved フラグ含む）。
    /// - known: wordbank に存在する語（小文字）の集合。空なら実在チェックの警告は出るが採用は維持。
    /// - band: 語（小文字）→ band。無い語は band 不明。
    /// - targetBand: 指定時のみ band 警告（不明/超過）を出す。nil なら band 警告なし。
    public static func validate(entries: [ConfusableEntry],
                                known: Set<String>,
                                band: [String: Int],
                                targetBand: Int?) -> Result {
        var accepted: [ConfusableEntry] = []
        var rejected: [Rejection] = []
        var warnings: [Warning] = []
        var excludedUnapproved = 0
        var acceptedHeadwords: Set<String> = []

        for entry in entries {
            let word = normalize(entry.word)
            guard !word.isEmpty else {
                rejected.append(Rejection(word: entry.word, reason: .emptyWord))
                continue
            }
            guard entry.approved else {
                excludedUnapproved += 1
                continue
            }
            // 同じ見出し語の二重登録を弾く（ConfusablesSound.distractors は先頭一致＝後の行が隠れる）。
            if acceptedHeadwords.contains(word) {
                rejected.append(Rejection(word: word, reason: .duplicateHeadword))
                continue
            }

            // 正規化＋自己参照/重複除去（順序維持）。
            var cleaned: [String] = []
            for raw in entry.soundsLike {
                let s = normalize(raw)
                if s.isEmpty || s == word || cleaned.contains(s) { continue }
                cleaned.append(s)
            }

            // ハード規則：CSV を壊す文字を含む語は弾く（serialize→parse の往復不変条件を守る）。
            if let bad = ([word] + cleaned).first(where: hasUnsafeChar) {
                rejected.append(Rejection(word: word, reason: .invalidToken(bad)))
                continue
            }

            // ハード規則：個数2〜4。
            if cleaned.count < 2 {
                rejected.append(Rejection(word: word, reason: .tooFewDistractors))
                continue
            }
            if cleaned.count > 4 {
                rejected.append(Rejection(word: word, reason: .tooManyDistractors))
                continue
            }

            // 採用は確定。実在/band は警告として積む（削除しない）。
            if !known.isEmpty && !known.contains(word) {
                warnings.append(Warning(word: word, kind: .notInWordbank(word)))
            }
            for s in cleaned {
                if !known.isEmpty && !known.contains(s) {
                    warnings.append(Warning(word: word, kind: .notInWordbank(s)))
                }
            }
            if let target = targetBand {
                for token in [word] + cleaned {
                    if let b = band[token] {
                        if b > target { warnings.append(Warning(word: word, kind: .bandOverTarget(token, b))) }
                    } else {
                        warnings.append(Warning(word: word, kind: .bandUnknown(token)))
                    }
                }
            }

            accepted.append(ConfusableEntry(word: word, soundsLike: cleaned, approved: true))
            acceptedHeadwords.insert(word)
        }

        return Result(accepted: accepted, rejected: rejected,
                      warnings: warnings, excludedUnapprovedCount: excludedUnapproved)
    }

    /// 採用エントリを再パース可能な CSV（`word,sounds_like,approved,source`）へ。
    /// 同梱は approved=1 のみ・source は `build`。`ConfusablesSound.parse` で読み戻せる。
    public static func serialize(_ entries: [ConfusableEntry]) -> String {
        var lines = ["word,sounds_like,approved,source"]
        for e in entries {
            lines.append("\(e.word),\(e.soundsLike.joined(separator: "|")),1,build")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// CSV（`,` 区切り・`|` で sounds_like 分割）と行を壊す文字。
    private static func hasUnsafeChar(_ s: String) -> Bool {
        s.contains { $0 == "," || $0 == "|" || $0 == "\n" || $0 == "\r" || $0 == "\t" }
    }
}
