import Foundation

/// ことばパズルの文に登場する「常連キャスト」。
///
/// 文の語（`SentenceItem.tokens`）から**決定論**で判定し、出題画面に最大3体まで
/// 絵を出すために使う。描画自体は App 側（`RewardCharacterAvatar`）が担当し、
/// ここは「どのキャストが・どの順で出るか」だけを純ロジックで決める。
public enum PuzzleCast: String, CaseIterable, Sendable, Equatable {
    case sora, mei, cat, dog, bird, rabbit, turtle, fox

    /// 子どもキャラ（人）か動物か。レイアウト/描画の出し分け用。
    public var isChild: Bool { self == .sora || self == .mei }
}

/// 文の語からキャストを拾う純関数群。
public enum PuzzleCastResolver {

    /// 文（トークン列）に登場するキャストを **出現順・重複なし・最大 `limit` 体** で返す。
    public static func cast(in tokens: [String], limit: Int = 3) -> [PuzzleCast] {
        guard limit > 0 else { return [] }
        var result: [PuzzleCast] = []
        for raw in tokens {
            guard let c = match(raw) else { continue }
            if !result.contains(c) { result.append(c) }
            if result.count >= limit { break }
        }
        return result
    }

    /// `SentenceItem` から直接。
    public static func cast(for item: SentenceItem, limit: Int = 3) -> [PuzzleCast] {
        cast(in: item.tokens, limit: limit)
    }

    /// 1語をキャストに対応づける。小文字化＋英字以外を除去（"Sora," → "sora" / "dogs?" → "dogs"）し、
    /// 簡易単数化（複数 -es / -s を1段だけ）して語彙表と突き合わせる。
    private static func match(_ raw: String) -> PuzzleCast? {
        let lower = raw.lowercased().filter { $0.isLetter }
        guard !lower.isEmpty else { return nil }
        if let c = lexicon[lower] { return c }
        if lower.hasSuffix("es"), let c = lexicon[String(lower.dropLast(2))] { return c }
        if lower.hasSuffix("s"), let c = lexicon[String(lower.dropLast())] { return c }
        return nil
    }

    /// 単数形（と素直な別名）→ キャスト。複数形は `match` の単数化で吸収する。
    private static let lexicon: [String: PuzzleCast] = [
        "sora": .sora, "mei": .mei,
        "cat": .cat, "kitten": .cat,
        "dog": .dog, "puppy": .dog,
        "bird": .bird,
        "rabbit": .rabbit, "bunny": .rabbit,
        "turtle": .turtle, "tortoise": .turtle,
        "fox": .fox,
    ]
}
