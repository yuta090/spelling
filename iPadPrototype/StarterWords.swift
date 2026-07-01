import Foundation
import SpellingSyncCore

/// 学年（小1〜中3）。初回オンボーディングで聞き、その学年のコース選択・出題ティア・漢字ゲートに使う。
/// ⚠️ 子に「レベル/順位」を見せる意図はない。聞くのは「なんねんせい？」という事実だけで、
/// 生成された難易度は子に見せない（CLAUDE.md の方針）。
enum GradeLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case e1, e2, e3, e4, e5, e6   // 小1〜小6
    case j1, j2, j3               // 中1〜中3

    var id: String { rawValue }

    /// 子ども向け表示（ふりがな前提のやさしい表記）。
    var label: String {
        switch self {
        case .e1: return "小1"
        case .e2: return "小2"
        case .e3: return "小3"
        case .e4: return "小4"
        case .e5: return "小5"
        case .e6: return "小6"
        case .j1: return "中1"
        case .j2: return "中2"
        case .j3: return "中3"
        }
    }

    var isElementary: Bool {
        switch self {
        case .e1, .e2, .e3, .e4, .e5, .e6: return true
        case .j1, .j2, .j3: return false
        }
    }

    /// 学年を 1…9 の整数に直す（小1=1…小6=6／中1=7…中3=9）。
    /// `KanjiLevelGate.maxGrade(forSchoolGrade:)` に渡して和訳で許す漢字配当学年を決める。
    var schoolGrade: Int {
        switch self {
        case .e1: return 1
        case .e2: return 2
        case .e3: return 3
        case .e4: return 4
        case .e5: return 5
        case .e6: return 6
        case .j1: return 7
        case .j2: return 8
        case .j3: return 9
        }
    }

    /// 難易度ティア。日本の学年は英語頻度バンドと 1:1 で対応しないため、
    /// 「無理なく成功できる」ことを優先したゆるいマップにしている（あとで調整可）。
    var tier: StarterTier {
        switch self {
        case .e1, .e2: return .a
        case .e3, .e4: return .b
        case .e5, .e6, .j1: return .c
        case .j2, .j3: return .d
        }
    }
}

/// 出題の難易度ティア（`GradeLevel.tier` が返す）。例文・問題生成の制約段階（`ContentTier`）へ橋渡しする。
enum StarterTier {
    case a, b, c, d

    /// 出題制約の段階（Core）へ写像。値は 1:1（StarterTier はアプリ専用なので Core 用に橋渡しする）。
    var contentTier: ContentTier {
        switch self {
        case .a: return .a
        case .b: return .b
        case .c: return .c
        case .d: return .d
        }
    }
}

// NOTE: 旧 `StarterWords`（学年→初期単語シード表）は方針A で撤去。
// オンボーディングでは personal へシードせず、選んだ学年のコースをアクティブにする
// （`AppModel.applyOnboardingGrade`）。`GradeLevel` / `StarterTier` は出題ティア判定で継続使用。
