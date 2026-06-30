import Foundation
import SpellingSyncCore

/// コース（学年軸／英検軸／自分のトラック）。`CourseKind` は Core 由来。
/// - 親には `parentTitle`（"小3コース"/"英検5級コース"）を出してよい。
/// - 子には**級・学年ラベルを出さない**（`childTitle`＝やさしい世界名）。CLAUDE.md の非ラベリング方針。
struct Course: Identifiable, Equatable, Sendable {
    let id: String            // == courseID（"personal" / "grade-3" / "eiken-g5"）
    let kind: CourseKind
    let parentTitle: String
    let childTitle: String
    let emoji: String
    let accent: String        // hex（マップ/チップのアクセント）
}

/// 利用可能なコース一覧（固定）。personal ＋ 学年9 ＋ 英検4。
enum CourseDirectory {
    static let personal = Course(
        id: "personal", kind: .personal,
        parentTitle: "うちのれんしゅう", childTitle: "おうちのたんご",
        emoji: "🏠", accent: "#7C9CF5"
    )

    /// Dolch サイトワード（基礎語）コース。最初に固める一番やさしい土台。
    /// 子には級/学年ラベルを出さない＝childTitle はやさしい名前。
    static let dolch = Course(
        id: CourseCatalog.dolchCourseID, kind: .dolch,
        parentTitle: "きほんコース（サイトワード）", childTitle: "きほんのことば",
        emoji: "🔤", accent: "#F2994A"
    )

    static let grades: [Course] = (1...9).map { g in
        let w = gradeWorld(g)
        return Course(
            id: GradeBand.courseID(schoolGrade: g),
            kind: .grade(schoolGrade: g),
            parentTitle: "\(gradeLabel(g))コース",
            childTitle: w.name, emoji: w.emoji, accent: w.accent
        )
    }

    static let eiken: [Course] = EikenLevel.allCases.map { lv in
        let w = eikenWorld(lv)
        return Course(
            id: lv.courseID, kind: .eiken(lv),
            parentTitle: "英検\(eikenLabel(lv))コース",
            childTitle: w.name, emoji: w.emoji, accent: w.accent
        )
    }

    static let all: [Course] = [personal, dolch] + grades + eiken

    static func course(id: String) -> Course? { all.first { $0.id == id } }

    // MARK: 親向けラベル（子には出さない）

    static func gradeLabel(_ g: Int) -> String {
        switch g {
        case 1...6: return "小\(g)"
        default: return "中\(g - 6)"   // 7→中1, 8→中2, 9→中3
        }
    }

    static func eikenLabel(_ lv: EikenLevel) -> String {
        switch lv {
        case .g5: return "5級"
        case .g4: return "4級"
        case .g3: return "3級"
        case .p2: return "準2級"
        }
    }

    // MARK: 子向け世界名（級/学年を出さない・spec §3.5 の世界観を簡略採用）

    private struct World { let name: String; let emoji: String; let accent: String }

    private static func gradeWorld(_ g: Int) -> World {
        switch g {
        case 1: return World(name: "そうげん", emoji: "🌱", accent: "#9BD27A")
        case 2: return World(name: "うみべ",   emoji: "🏝️", accent: "#5EC8D8")
        case 3: return World(name: "もり",     emoji: "🌲", accent: "#4CAF7D")
        case 4: return World(name: "やま",     emoji: "🏔️", accent: "#8DA9C4")
        case 5: return World(name: "そら",     emoji: "☁️", accent: "#7FB6F5")
        case 6: return World(name: "ゆうやけ", emoji: "🌇", accent: "#F2A45C")
        case 7: return World(name: "ほし",     emoji: "⭐", accent: "#F2C94C")
        case 8: return World(name: "にじ",     emoji: "🌈", accent: "#C78AF0")
        default: return World(name: "うちゅう", emoji: "🚀", accent: "#6C7BF0")
        }
    }

    private static func eikenWorld(_ lv: EikenLevel) -> World {
        switch lv {
        case .g5: return World(name: "たいよう", emoji: "☀️", accent: "#F6C026")
        case .g4: return World(name: "みずうみ", emoji: "💧", accent: "#46B5E6")
        case .g3: return World(name: "だいち",   emoji: "🏕️", accent: "#7BA05B")
        case .p2: return World(name: "おおぞら", emoji: "🪂", accent: "#8E7CF0")
        }
    }
}
