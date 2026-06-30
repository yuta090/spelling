import Foundation

/// ステップ選択「冒険マップ」(StepMapView) の **世界観テーマ**（空グラデ／地面／小道／飾り／ゴール／アクセント）。
///
/// SwiftUI 非依存（色は 0..1 の `Double` RGB）。描画側（iPadPrototype/StepMapView）で `Color` / `Gradient.Stop`
/// に変換する。コースごとに丸ごと差し替えられるよう **courseID 文字列で引く**（`CourseKind` を switch しない）。
/// 学年が上がるほど高い世界へ：草原→海辺→森→山→空→夕焼け→星→虹→宇宙。英検は太陽／湖／大地／大空。personal は家。
///
/// 未知の courseID（後で Dolch 等のコースが増えても）には **無難な既定（草原）** をフォールバックで返す＝落ちない。

// MARK: - 色（SwiftUI 非依存）

public struct ThemeRGB: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// WCAG 相対輝度（0=黒〜1=白）。前景色の自動選択に使う。
    public var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// 自分（背景）に対する `other`（前景）の WCAG コントラスト比（1〜21）。
    public func contrastRatio(against other: ThemeRGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        let hi = max(a, b), lo = min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// 空グラデの 1 ストップ（色＋位置 0..1）。
public struct ThemeStop: Equatable, Sendable {
    public let color: ThemeRGB
    public let location: Double
    public init(color: ThemeRGB, location: Double) {
        self.color = color
        self.location = location
    }
}

/// 背景に点在する飾り。`xFrac`/`yFrac` は 0..1（yFrac 0=上＝空の高い所, 1=下＝スタート）。
public struct ThemeProp: Equatable, Sendable {
    public let emoji: String
    public let xFrac: Double
    public let yFrac: Double
    public let size: Double
    public let opacity: Double
    public init(emoji: String, xFrac: Double, yFrac: Double, size: Double, opacity: Double = 1) {
        self.emoji = emoji
        self.xFrac = xFrac
        self.yFrac = yFrac
        self.size = size
        self.opacity = opacity
    }
}

// MARK: - テーマ本体

public struct WorldTheme: Equatable, Sendable {
    /// 空のグラデ（上＝location 0 → 下＝location 1）。location は昇順。
    public let skyStops: [ThemeStop]
    /// 地面（下端の丘）の色。
    public let ground: ThemeRGB
    /// 小道（点線）の色。
    public let path: ThemeRGB
    /// 「いまここ」ノード等のアクセント色（コース world accent 由来）。
    public let accent: ThemeRGB
    /// ゴール（つづく…）の絵文字。
    public let goalEmoji: String
    /// 飾り（emoji の点在）。
    public let props: [ThemeProp]

    public init(
        skyStops: [ThemeStop],
        ground: ThemeRGB,
        path: ThemeRGB,
        accent: ThemeRGB,
        goalEmoji: String,
        props: [ThemeProp]
    ) {
        self.skyStops = skyStops
        self.ground = ground
        self.path = path
        self.accent = accent
        self.goalEmoji = goalEmoji
        self.props = props
    }

    /// アクセント色の上に乗せる文字／アイコンの前景色。
    /// 白とダークネイビーのうち、アクセントに対してコントラスト比が高い方を選ぶ
    /// （明るい/淡いアクセント＝草原の緑・星空の金などで白文字が読めなくなるのを防ぐ）。
    public var accentForeground: ThemeRGB {
        let white = ThemeRGB(1, 1, 1)
        let darkInk = ThemeRGB(0.10, 0.14, 0.24)
        return accent.contrastRatio(against: white) >= accent.contrastRatio(against: darkInk) ? white : darkInk
    }
}

// MARK: - 飾りの配置テンプレ（全テーマ共通の座標。emoji だけ差し替える）

extension WorldTheme {
    /// 飾り 9 個の標準配置（meadow と同じ）。各テーマは emoji 9 個を渡すだけ。
    /// (xFrac, yFrac, size, opacity)
    static let propSlots: [(Double, Double, Double, Double)] = [
        (0.78, 0.10, 60, 0.95),
        (0.30, 0.08, 56, 1.00),
        (0.42, 0.22, 30, 1.00),
        (0.20, 0.30, 52, 0.90),
        (0.72, 0.40, 26, 1.00),
        (0.30, 0.55, 30, 1.00),
        (0.84, 0.72, 46, 1.00),
        (0.16, 0.80, 34, 1.00),
        (0.78, 0.90, 30, 1.00),
    ]

    /// emoji 配列を標準配置にあてはめて props を作る（足りなければそのぶんは省く）。
    static func props(_ emojis: [String]) -> [ThemeProp] {
        zip(emojis, propSlots).map { emoji, slot in
            ThemeProp(emoji: emoji, xFrac: slot.0, yFrac: slot.1, size: slot.2, opacity: slot.3)
        }
    }

    private static func stops(_ list: [(ThemeRGB, Double)]) -> [ThemeStop] {
        list.map { ThemeStop(color: $0.0, location: $0.1) }
    }
}

// MARK: - コースID → テーマ

extension WorldTheme {

    /// `courseID`（"grade-1".."grade-9" / "eiken-g5".."eiken-p2" / "personal"）でテーマを引く。
    /// 未知の ID は **既定（草原）** にフォールバックする（後で Dolch 等が増えても落ちない）。
    public static func theme(forCourseID courseID: String) -> WorldTheme {
        switch courseID {
        case "grade-1": return grassland
        case "grade-2": return seaside
        case "grade-3": return forest
        case "grade-4": return mountain
        case "grade-5": return sky
        case "grade-6": return sunset
        case "grade-7": return starryNight
        case "grade-8": return rainbow
        case "grade-9": return space
        case "eiken-g5": return sun
        case "eiken-g4": return lake
        case "eiken-g3": return land
        case "eiken-p2": return bigSky
        case "personal": return home
        default: return fallback
        }
    }

    /// 未知コース用の無難な既定。
    public static let fallback = grassland

    // MARK: 学年（低→高い世界へ）

    /// 草原（grade-1・既定）。
    public static let grassland = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.66, 0.85, 0.98), 0.00),
            (ThemeRGB(0.80, 0.92, 1.00), 0.40),
            (ThemeRGB(0.86, 0.96, 0.84), 0.80),
            (ThemeRGB(0.74, 0.90, 0.66), 1.00),
        ]),
        ground: ThemeRGB(0.62, 0.85, 0.58),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.608, 0.824, 0.478),
        goalEmoji: "🎈",
        props: props(["☁️", "🌈", "🦋", "☁️", "🐝", "🐤", "🌳", "🌻", "🌷"])
    )

    /// 海辺（grade-2）。
    public static let seaside = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.55, 0.82, 0.97), 0.00),
            (ThemeRGB(0.70, 0.90, 0.98), 0.45),
            (ThemeRGB(0.85, 0.93, 0.85), 0.82),
            (ThemeRGB(0.95, 0.90, 0.70), 1.00),
        ]),
        ground: ThemeRGB(0.93, 0.86, 0.62),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.369, 0.784, 0.847),
        goalEmoji: "⛵",
        props: props(["☀️", "🐚", "🐬", "🏖️", "🦀", "🐠", "🌴", "🏝️", "🌊"])
    )

    /// 森（grade-3）。
    public static let forest = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.62, 0.84, 0.92), 0.00),
            (ThemeRGB(0.74, 0.88, 0.80), 0.45),
            (ThemeRGB(0.60, 0.80, 0.58), 0.80),
            (ThemeRGB(0.42, 0.66, 0.42), 1.00),
        ]),
        ground: ThemeRGB(0.40, 0.62, 0.36),
        path: ThemeRGB(0.96, 0.93, 0.80),
        accent: ThemeRGB(0.298, 0.686, 0.490),
        goalEmoji: "🦉",
        props: props(["🌲", "🍄", "🦌", "🐿️", "🍃", "🦋", "🌳", "🐸", "🌿"])
    )

    /// 山（grade-4）。
    public static let mountain = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.58, 0.74, 0.90), 0.00),
            (ThemeRGB(0.74, 0.84, 0.94), 0.45),
            (ThemeRGB(0.82, 0.86, 0.90), 0.82),
            (ThemeRGB(0.70, 0.74, 0.78), 1.00),
        ]),
        ground: ThemeRGB(0.62, 0.66, 0.70),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.553, 0.663, 0.769),
        goalEmoji: "🏔️",
        props: props(["☁️", "🦅", "🏔️", "🌲", "🪨", "🐐", "🌲", "❄️", "🪨"])
    )

    /// 空（grade-5）。
    public static let sky = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.40, 0.64, 0.92), 0.00),
            (ThemeRGB(0.56, 0.76, 0.96), 0.45),
            (ThemeRGB(0.76, 0.88, 0.99), 0.82),
            (ThemeRGB(0.90, 0.95, 1.00), 1.00),
        ]),
        ground: ThemeRGB(0.86, 0.92, 0.99),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.498, 0.714, 0.961),
        goalEmoji: "🪁",
        props: props(["☁️", "🌤️", "🐦", "🪁", "☁️", "🎈", "🌈", "☁️", "🦅"])
    )

    /// 夕焼け（grade-6）。
    public static let sunset = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.36, 0.40, 0.66), 0.00),
            (ThemeRGB(0.78, 0.50, 0.56), 0.45),
            (ThemeRGB(0.97, 0.66, 0.42), 0.80),
            (ThemeRGB(0.99, 0.82, 0.52), 1.00),
        ]),
        ground: ThemeRGB(0.85, 0.55, 0.40),
        path: ThemeRGB(1.00, 0.95, 0.85),
        accent: ThemeRGB(0.949, 0.643, 0.361),
        goalEmoji: "🌇",
        props: props(["🌅", "🦩", "☁️", "🌇", "🕊️", "⛅", "🌴", "🌺", "🌄"])
    )

    /// 星空（grade-7）。
    public static let starryNight = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.05, 0.07, 0.22), 0.00),
            (ThemeRGB(0.10, 0.13, 0.34), 0.45),
            (ThemeRGB(0.18, 0.22, 0.48), 0.82),
            (ThemeRGB(0.28, 0.30, 0.56), 1.00),
        ]),
        ground: ThemeRGB(0.16, 0.18, 0.40),
        path: ThemeRGB(0.95, 0.92, 0.70),
        accent: ThemeRGB(0.949, 0.788, 0.298),
        goalEmoji: "🌟",
        props: props(["⭐", "✨", "🌙", "⭐", "💫", "🌠", "✨", "⭐", "🪐"])
    )

    /// 虹（grade-8）。
    public static let rainbow = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.74, 0.86, 0.98), 0.00),
            (ThemeRGB(0.86, 0.82, 0.98), 0.40),
            (ThemeRGB(0.98, 0.84, 0.92), 0.78),
            (ThemeRGB(0.99, 0.92, 0.80), 1.00),
        ]),
        ground: ThemeRGB(0.80, 0.90, 0.70),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.780, 0.541, 0.941),
        goalEmoji: "🌈",
        props: props(["🌈", "☁️", "🦄", "✨", "🎈", "🌸", "🦋", "🌟", "🍭"])
    )

    /// 宇宙（grade-9・最高世界）。
    public static let space = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.03, 0.02, 0.12), 0.00),
            (ThemeRGB(0.08, 0.05, 0.22), 0.45),
            (ThemeRGB(0.14, 0.10, 0.32), 0.82),
            (ThemeRGB(0.20, 0.14, 0.40), 1.00),
        ]),
        ground: ThemeRGB(0.18, 0.16, 0.36),
        path: ThemeRGB(0.85, 0.88, 0.98),
        accent: ThemeRGB(0.424, 0.482, 0.941),
        goalEmoji: "🚀",
        props: props(["🌌", "🪐", "⭐", "🛸", "✨", "🌟", "☄️", "🌙", "🚀"])
    )

    // MARK: 英検（太陽／湖／大地／大空）

    /// 太陽（eiken-g5）。
    public static let sun = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.40, 0.70, 0.96), 0.00),
            (ThemeRGB(0.62, 0.82, 0.98), 0.45),
            (ThemeRGB(0.90, 0.90, 0.70), 0.82),
            (ThemeRGB(1.00, 0.86, 0.46), 1.00),
        ]),
        ground: ThemeRGB(0.55, 0.80, 0.45),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.965, 0.753, 0.149),
        goalEmoji: "☀️",
        props: props(["☀️", "🌻", "☁️", "🐝", "🦋", "🌼", "🌾", "🏵️", "🌻"])
    )

    /// 湖（eiken-g4）。
    public static let lake = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.52, 0.78, 0.92), 0.00),
            (ThemeRGB(0.66, 0.86, 0.94), 0.45),
            (ThemeRGB(0.60, 0.82, 0.88), 0.82),
            (ThemeRGB(0.40, 0.66, 0.80), 1.00),
        ]),
        ground: ThemeRGB(0.36, 0.62, 0.74),
        path: ThemeRGB(0.95, 0.97, 1.00),
        accent: ThemeRGB(0.275, 0.710, 0.902),
        goalEmoji: "🦆",
        props: props(["💧", "🦆", "🐟", "🌊", "🪷", "🐸", "🦢", "🍃", "💦"])
    )

    /// 大地（eiken-g3）。
    public static let land = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.66, 0.82, 0.92), 0.00),
            (ThemeRGB(0.80, 0.86, 0.78), 0.45),
            (ThemeRGB(0.74, 0.74, 0.56), 0.82),
            (ThemeRGB(0.60, 0.52, 0.38), 1.00),
        ]),
        ground: ThemeRGB(0.58, 0.48, 0.34),
        path: ThemeRGB(0.96, 0.92, 0.78),
        accent: ThemeRGB(0.482, 0.627, 0.357),
        goalEmoji: "🏕️",
        props: props(["⛰️", "🌾", "🐎", "🌳", "🪨", "🦌", "🏕️", "🌻", "🍂"])
    )

    /// 大空（eiken-p2）。
    public static let bigSky = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.30, 0.56, 0.90), 0.00),
            (ThemeRGB(0.48, 0.70, 0.95), 0.45),
            (ThemeRGB(0.70, 0.84, 0.98), 0.82),
            (ThemeRGB(0.88, 0.94, 1.00), 1.00),
        ]),
        ground: ThemeRGB(0.82, 0.90, 0.98),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.557, 0.486, 0.941),
        goalEmoji: "🪂",
        props: props(["🪂", "☁️", "🦅", "🎈", "✈️", "🌤️", "🕊️", "☁️", "🌈"])
    )

    // MARK: 自分のトラック（家）

    /// おうち（personal）。
    public static let home = WorldTheme(
        skyStops: stops([
            (ThemeRGB(0.74, 0.82, 0.96), 0.00),
            (ThemeRGB(0.84, 0.88, 0.97), 0.45),
            (ThemeRGB(0.92, 0.90, 0.86), 0.82),
            (ThemeRGB(0.96, 0.90, 0.78), 1.00),
        ]),
        ground: ThemeRGB(0.72, 0.84, 0.62),
        path: ThemeRGB(1.00, 1.00, 1.00),
        accent: ThemeRGB(0.486, 0.612, 0.961),
        goalEmoji: "🏠",
        props: props(["🏠", "☁️", "🌳", "🐱", "🌷", "🐶", "🪴", "🌻", "🚲"])
    )
}
