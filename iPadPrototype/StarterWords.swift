import Foundation

/// 学年（小1〜中3）。初回オンボーディングで聞き、レベルに合う初期単語のシードに使う。
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

/// 初期単語の難易度ティア。
enum StarterTier {
    case a, b, c, d
}

/// 学年に応じた「初期単語の厳選セット」。
///
/// wordbank の頻度バンドをそのまま使うと band=1 が the/of/and… の機能語になり、
/// 訳語も一部壊れているため、**低学年に文法語を出さない**よう手で厳選したセットを使う。
/// これは“たたき台”で、保護者があとから本物の宿題単語に置き換える前提。
enum StarterWords {
    struct Seed: Equatable, Sendable {
        let text: String
        /// 子ども向けの意味（ひらがな中心）。`SpellingWord.promptText` に入る。
        let promptText: String
    }

    static func seeds(for grade: GradeLevel) -> [Seed] {
        tier(grade.tier)
    }

    private static func tier(_ tier: StarterTier) -> [Seed] {
        switch tier {
        case .a:
            return [
                Seed(text: "cat", promptText: "ねこ"),
                Seed(text: "dog", promptText: "いぬ"),
                Seed(text: "sun", promptText: "たいよう"),
                Seed(text: "fish", promptText: "さかな"),
                Seed(text: "book", promptText: "ほん"),
                Seed(text: "red", promptText: "あか"),
                Seed(text: "blue", promptText: "あお"),
                Seed(text: "cake", promptText: "ケーキ"),
                Seed(text: "star", promptText: "ほし"),
                Seed(text: "milk", promptText: "ぎゅうにゅう"),
            ]
        case .b:
            return [
                Seed(text: "apple", promptText: "りんご"),
                Seed(text: "water", promptText: "みず"),
                Seed(text: "friend", promptText: "ともだち"),
                Seed(text: "school", promptText: "がっこう"),
                Seed(text: "music", promptText: "おんがく"),
                Seed(text: "bird", promptText: "とり"),
                Seed(text: "rain", promptText: "あめ"),
                Seed(text: "snow", promptText: "ゆき"),
                Seed(text: "hand", promptText: "て"),
                Seed(text: "jump", promptText: "とぶ"),
            ]
        case .c:
            return [
                Seed(text: "family", promptText: "かぞく"),
                Seed(text: "animal", promptText: "どうぶつ"),
                Seed(text: "science", promptText: "りか"),
                Seed(text: "dinner", promptText: "ゆうしょく"),
                Seed(text: "winter", promptText: "ふゆ"),
                Seed(text: "doctor", promptText: "おいしゃさん"),
                Seed(text: "garden", promptText: "にわ"),
                Seed(text: "future", promptText: "みらい"),
                Seed(text: "travel", promptText: "りょこう"),
                Seed(text: "letter", promptText: "てがみ"),
            ]
        case .d:
            return [
                Seed(text: "important", promptText: "たいせつ"),
                Seed(text: "different", promptText: "ちがう"),
                Seed(text: "machine", promptText: "きかい"),
                Seed(text: "language", promptText: "ことば"),
                Seed(text: "foreign", promptText: "がいこく"),
                Seed(text: "breakfast", promptText: "あさごはん"),
                Seed(text: "weather", promptText: "てんき"),
                Seed(text: "opinion", promptText: "いけん"),
                Seed(text: "experience", promptText: "けいけん"),
                Seed(text: "environment", promptText: "かんきょう"),
            ]
        }
    }
}
