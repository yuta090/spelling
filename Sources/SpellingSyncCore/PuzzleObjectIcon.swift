import Foundation

/// ことばパズルの文に出てくる **キャスト以外の名詞**（apple/ball/sun…）を表す絵ヒント1個。
///
/// 常連キャスト（ねこ/いぬ/とり/うさぎ/かめ/きつね/Sora/Mei）は `PuzzleCast` が担当するので、
/// ここはそれ以外の身近な名詞だけを SF Symbol に対応づける。描画は App 側
/// （`Image(systemName:)`）が担当し、ここは「どの名詞が・どのアイコンで・どの順か」だけを
/// 決定論で決める。文字説明をしない子ども向けの“絵ヒント”の素になる。
public struct PuzzleObjectIcon: Sendable, Equatable {
    /// 拾った語（単数形・小文字）。例 "sun" / "book"。
    public let key: String
    /// 対応する SF Symbol 名。例 "sun.max.fill"。
    public let systemImage: String

    public init(key: String, systemImage: String) {
        self.key = key
        self.systemImage = systemImage
    }
}

/// 文の語から絵ヒント（オブジェクト）を拾う純関数群。`PuzzleCastResolver` の名詞版。
public enum PuzzleObjectIconResolver {

    /// 文（トークン列）に登場する身近な名詞を **出現順・アイコン重複なし・最大 `limit` 個** で返す。
    /// - Parameter excluding: すでに別の絵で出している語（キャスト等）。ここに含む `key` は飛ばす。
    public static func icons(in tokens: [String],
                             limit: Int = 3,
                             excluding: Set<String> = []) -> [PuzzleObjectIcon] {
        guard limit > 0 else { return [] }
        var result: [PuzzleObjectIcon] = []
        var seenSymbols = Set<String>()
        for raw in tokens {
            guard let icon = match(raw) else { continue }
            if excluding.contains(icon.key) { continue }
            if seenSymbols.contains(icon.systemImage) { continue }
            seenSymbols.insert(icon.systemImage)
            result.append(icon)
            if result.count >= limit { break }
        }
        return result
    }

    /// `SentenceItem` から直接。
    public static func icons(for item: SentenceItem,
                            limit: Int = 3,
                            excluding: Set<String> = []) -> [PuzzleObjectIcon] {
        icons(in: item.tokens, limit: limit, excluding: excluding)
    }

    /// 1語を絵ヒントに対応づける。小文字化＋英字以外を除去（"Book," → "book"）し、
    /// 簡易単数化（複数 -es / -s を1段だけ）して語彙表と突き合わせる。
    private static func match(_ raw: String) -> PuzzleObjectIcon? {
        let lower = raw.lowercased().filter { $0.isLetter }
        guard !lower.isEmpty else { return nil }
        if let s = lexicon[lower] { return PuzzleObjectIcon(key: lower, systemImage: s) }
        if lower.hasSuffix("es"), let s = lexicon[String(lower.dropLast(2))] {
            return PuzzleObjectIcon(key: String(lower.dropLast(2)), systemImage: s)
        }
        if lower.hasSuffix("s"), let s = lexicon[String(lower.dropLast())] {
            return PuzzleObjectIcon(key: String(lower.dropLast()), systemImage: s)
        }
        return nil
    }

    /// 身近な名詞（単数形）→ SF Symbol。**キャストの動物（cat/dog/bird/rabbit/turtle/fox）は入れない**
    /// （`PuzzleCast` が担当・二重表示を避ける）。iOS 17 で確実に存在するシンボルだけを使う。
    /// 複数形は `match` の単数化で吸収する。新しい名詞が必要になったらここに足す。
    static let lexicon: [String: String] = [
        // しぜん・きせつ・天気
        "sun": "sun.max.fill",
        "cloud": "cloud.fill",
        "rain": "cloud.rain.fill",
        "snow": "snowflake",
        "wind": "wind",
        "star": "star.fill",
        "moon": "moon.fill",
        "leaf": "leaf.fill",
        "tree": "tree.fill",
        "mountain": "mountain.2.fill",
        "fire": "flame.fill",
        "water": "drop.fill",
        "fish": "fish.fill",
        // がっこう・べんきょう
        "book": "book.fill",
        "pencil": "pencil",
        "pen": "pencil",
        "bag": "bag.fill",
        "map": "map.fill",
        "school": "building.2.fill",
        "clock": "clock.fill",
        "time": "clock.fill",
        // あそび・しゅみ
        "ball": "soccerball",
        "soccer": "soccerball",
        "game": "gamecontroller.fill",
        "music": "music.note",
        "song": "music.note",
        "piano": "pianokeys",
        "picture": "photo.fill",
        "photo": "photo.fill",
        "paint": "paintbrush.pointed.fill",
        "camera": "camera.fill",
        "phone": "phone.fill",
        // のりもの
        "car": "car.fill",
        "bus": "bus.fill",
        "train": "tram.fill",
        "bike": "bicycle",
        "bicycle": "bicycle",
        "airplane": "airplane",
        "plane": "airplane",
        "boat": "sailboat.fill",
        "ship": "sailboat.fill",
        // いえ・くらし
        "house": "house.fill",
        "home": "house.fill",
        "bed": "bed.double.fill",
        "cup": "cup.and.saucer.fill",
        "key": "key.fill",
        "bell": "bell.fill",
        "gift": "gift.fill",
        "present": "gift.fill",
        "heart": "heart.fill",
        "hand": "hand.raised.fill",
        "eye": "eye.fill",
    ]
}
