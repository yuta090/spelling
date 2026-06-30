import XCTest
@testable import SpellingSyncCore

final class WorldThemeTests: XCTestCase {

    // 既知コースID（学年9＋英検4＋personal）。
    private let knownGrades = (1...9).map { "grade-\($0)" }
    private let knownEiken = ["eiken-g5", "eiken-g4", "eiken-g3", "eiken-p2"]
    private var allKnown: [String] { knownGrades + knownEiken + ["personal"] }

    // MARK: - 既知コースは固有テーマ

    func testKnownCoursesReturnDistinctThemes() {
        let themes = allKnown.map { WorldTheme.theme(forCourseID: $0) }
        // 全部ユニーク（丸ごと差し替わっている）。
        for i in themes.indices {
            for j in themes.indices where j > i {
                XCTAssertNotEqual(themes[i], themes[j],
                    "\(allKnown[i]) と \(allKnown[j]) のテーマが同一です")
            }
        }
    }

    func testGradesAscendToHigherWorlds() {
        // 学年が上がると別世界（goalEmoji が学年順に固有）。
        let goals = knownGrades.map { WorldTheme.theme(forCourseID: $0).goalEmoji }
        XCTAssertEqual(Set(goals).count, goals.count, "学年ごとのゴール絵文字が重複しています")
        XCTAssertEqual(goals.first, "🎈")   // grade-1 草原
        XCTAssertEqual(goals.last, "🚀")    // grade-9 宇宙
    }

    // MARK: - 未知IDのフォールバック

    func testUnknownCourseFallsBackToDefault() {
        XCTAssertEqual(WorldTheme.theme(forCourseID: "grade-99"), WorldTheme.fallback)
        XCTAssertEqual(WorldTheme.theme(forCourseID: "dolch-pp"), WorldTheme.fallback)
        XCTAssertEqual(WorldTheme.theme(forCourseID: ""), WorldTheme.fallback)
        // 既定は草原。
        XCTAssertEqual(WorldTheme.fallback, WorldTheme.grassland)
    }

    // MARK: - 決定論

    func testDeterministic() {
        for id in allKnown + ["unknown-x"] {
            XCTAssertEqual(WorldTheme.theme(forCourseID: id), WorldTheme.theme(forCourseID: id))
        }
    }

    // MARK: - 構造の健全性（全テーマ）

    func testAllThemesHaveValidStopsAndProps() {
        for id in allKnown + ["unknown-x"] {
            let theme = WorldTheme.theme(forCourseID: id)

            // 空ストップ：最低2点。location は 0..1 かつ昇順、端は 0 と 1。
            XCTAssertGreaterThanOrEqual(theme.skyStops.count, 2, "\(id): stops が少なすぎます")
            let locs = theme.skyStops.map(\.location)
            XCTAssertEqual(locs.first, 0.0, "\(id): 先頭 location が 0 でない")
            XCTAssertEqual(locs.last, 1.0, "\(id): 末尾 location が 1 でない")
            for k in 1..<locs.count {
                XCTAssertGreaterThan(locs[k], locs[k - 1], "\(id): location が昇順でない")
            }
            for l in locs {
                XCTAssertGreaterThanOrEqual(l, 0.0)
                XCTAssertLessThanOrEqual(l, 1.0)
            }

            // 色成分は 0..1。
            for stop in theme.skyStops { assertRGBInRange(stop.color, id: id) }
            assertRGBInRange(theme.ground, id: id)
            assertRGBInRange(theme.path, id: id)
            assertRGBInRange(theme.accent, id: id)

            // 飾り：非空・xFrac/yFrac/opacity は 0..1・size 正。
            XCTAssertFalse(theme.props.isEmpty, "\(id): props が空")
            XCTAssertFalse(theme.goalEmoji.isEmpty, "\(id): goalEmoji が空")
            for p in theme.props {
                XCTAssertFalse(p.emoji.isEmpty, "\(id): prop emoji が空")
                XCTAssertGreaterThanOrEqual(p.xFrac, 0.0); XCTAssertLessThanOrEqual(p.xFrac, 1.0)
                XCTAssertGreaterThanOrEqual(p.yFrac, 0.0); XCTAssertLessThanOrEqual(p.yFrac, 1.0)
                XCTAssertGreaterThanOrEqual(p.opacity, 0.0); XCTAssertLessThanOrEqual(p.opacity, 1.0)
                XCTAssertGreaterThan(p.size, 0.0)
            }
        }
    }

    // MARK: - アクセント前景のコントラスト（白文字が読めない淡色アクセントを避ける）

    func testAccentForegroundIsReadableOnEveryTheme() {
        // アクセント上に乗るのは大きい星アイコン(46pt)と太字バッジ(15pt heavy=大きめ文字)。
        // 大きめ文字／グラフィック要素の WCAG 基準は 3:1。どのテーマでもそれ以上を満たす。
        for id in allKnown + ["unknown-x"] {
            let theme = WorldTheme.theme(forCourseID: id)
            let ratio = theme.accent.contrastRatio(against: theme.accentForeground)
            XCTAssertGreaterThanOrEqual(ratio, 3.0, "\(id): accent 上の前景コントラストが不足 (\(ratio))")
        }
    }

    func testAccentForegroundPicksHigherContrastOption() {
        // 前景は必ず {白, ダークネイビー} のどちらか。
        let white = ThemeRGB(1, 1, 1)
        let dark = ThemeRGB(0.10, 0.14, 0.24)
        for id in allKnown {
            let theme = WorldTheme.theme(forCourseID: id)
            XCTAssertTrue(theme.accentForeground == white || theme.accentForeground == dark, "\(id)")
            // 選んだ方が他方以上のコントラストであること。
            let chosen = theme.accent.contrastRatio(against: theme.accentForeground)
            let other = theme.accentForeground == white
                ? theme.accent.contrastRatio(against: dark)
                : theme.accent.contrastRatio(against: white)
            XCTAssertGreaterThanOrEqual(chosen, other, "\(id): 低コントラスト側を選んでいる")
        }
    }

    func testLightAndGoldAccentsGetDarkForeground() {
        // 草原（淡い緑）・星空（金）は白だと読めない → ダーク前景になる。
        XCTAssertEqual(WorldTheme.grassland.accentForeground, ThemeRGB(0.10, 0.14, 0.24))
        XCTAssertEqual(WorldTheme.starryNight.accentForeground, ThemeRGB(0.10, 0.14, 0.24))
    }

    private func assertRGBInRange(_ c: ThemeRGB, id: String) {
        for v in [c.r, c.g, c.b] {
            XCTAssertGreaterThanOrEqual(v, 0.0, "\(id): RGB が範囲外")
            XCTAssertLessThanOrEqual(v, 1.0, "\(id): RGB が範囲外")
        }
    }
}
