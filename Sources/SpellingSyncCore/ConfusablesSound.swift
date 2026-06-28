import Foundation

/// リスニングおとり辞書（音が紛らわしい語）の純ロジック。
/// データ: scripts/confusables_sound_draft.csv（`word,sounds_like,approved,source`）。
/// 仕様: docs/confusables-sound-authoring-DRAFT-2026-06-28.md
///
/// 用途: ①単語リスニング（音→綴り選択）②リスニング穴埋め のおとりプール。
/// 音の近さは人が承認済み（approved=1）の行だけを既定で使う。

/// 辞書1件。
public struct ConfusableEntry: Equatable, Sendable {
    /// 見出し語（小文字想定）。
    public var word: String
    /// 音が近い語（おとり候補）。
    public var soundsLike: [String]
    /// 人が承認済みか（AI生成のまま=未承認は false）。
    public var approved: Bool

    public init(word: String, soundsLike: [String], approved: Bool) {
        self.word = word
        self.soundsLike = soundsLike
        self.approved = approved
    }
}

public enum ConfusablesSound {
    /// CSV テキスト → エントリ配列。ヘッダ行・空行・列不足の不正行はスキップ。
    /// 形式: `word,sounds_like,approved,source`（sounds_like は `|` 区切り）。
    public static func parse(csv: String) -> [ConfusableEntry] {
        var result: [ConfusableEntry] = []
        // 改行は CRLF("\r\n") が単一グラフェムになるため、Character.isNewline で分割する
        // （"\n" 固定だと CRLF を分割できない）。
        for rawLine in csv.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            // フィールドは前後空白/改行をトリム（"1 " / "right " などに強くする）。
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // ヘッダ行は位置に依らずシグネチャで判定（先頭に空行があっても誤って取り込まない）。
            if fields.count >= 2, fields[0] == "word", fields[1] == "sounds_like" { continue }
            guard fields.count >= 4, !fields[0].isEmpty else { continue }   // 不正行スキップ
            let sounds = fields[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !sounds.isEmpty else { continue }
            result.append(ConfusableEntry(word: fields[0],
                                          soundsLike: sounds,
                                          approved: fields[2] == "1"))
        }
        return result
    }

    /// 見出し語に対するおとり候補を返す（大文字小文字無視）。
    /// - approvedOnly: true(既定) なら承認済み行のみ採用。未承認/未登録は空配列。
    public static func distractors(for word: String,
                                   in entries: [ConfusableEntry],
                                   approvedOnly: Bool = true) -> [String] {
        let key = word.lowercased()
        for entry in entries where entry.word.lowercased() == key {
            // approvedOnly のとき、未承認の重複が承認済み行を隠さないよう読み飛ばす。
            if approvedOnly && !entry.approved { continue }
            return entry.soundsLike
        }
        return []
    }
}
