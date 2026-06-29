import Foundation

/// 子ども向けに辞書訳（EJDict の `gloss`）を整える純ロジック（バンドルI/O無し＝テスト可能）。
///
/// EJDict の和訳は「猫、ねこ」「走る、駆ける、運営する」のように複数語義を区切り記号で
/// 並べた大人向けの形をしている。練習中のヒントでは情報を絞るため **最初の語義だけ** を見せる。
/// 学年に応じた漢字/かなの出し分けは別レイヤー（`KanjiLevelGate`）が担当する。
public enum GlossFormatter {

    /// 語義の区切りに使われる記号。先頭からこの記号の手前までを「最初の語義」とみなす。
    private static let separators: Set<Character> = [
        "、", "，", ",", "；", ";", "・", "/", "／", "|", "｜", "\n", "\r",
    ]

    /// 辞書訳から子に見せる「最初の語義」を取り出す。
    /// - 先頭の空白・区切り記号は読み飛ばす。
    /// - 取り出せる語義が無ければ、元の文字列（前後空白を除く）をそのまま返す。
    public static func primarySense(_ raw: String) -> String {
        var result = ""
        for ch in raw {
            if separators.contains(ch) {
                // すでに語義を拾っていれば、そこで打ち切る。まだ空なら先頭区切りとして読み飛ばす。
                if result.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                break
            }
            result.append(ch)
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
