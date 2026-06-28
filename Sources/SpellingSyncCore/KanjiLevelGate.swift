import Foundation

/// 子ども向け和訳 `ja` の漢字を「習った学年以内」に制限する検査（純ロジック・TDD）。
/// 方針: 例文・問題は子の **現在の年齢（学年）に合わせて生成**し、和訳で使う漢字は
///       **1学年前まで**に抑える（入門＝ひらがな主体）。元データは `KyoikuKanji`（現行配当表）。
///
/// 役割分担: ここは「文字列＋許可学年 → 超過漢字」の判定だけ。学年→許可学年の方針（1学年前）も
/// テスト可能なよう `maxGrade(forSchoolGrade:)` に持つ。アプリの `GradeLevel`（小1…中3）からは
/// Int 学年(1…9) に直して渡す（Core はアプリの enum に依存しない）。
public enum KanjiLevelGate {

    /// 子の学年(1=小1 … 6=小6, 7…9=中1…中3) に対し、和訳で許す最大「漢字配当学年」(0…6)。
    /// ルール = **1学年前まで**：小1→0（漢字なし＝ひらがな）／小3→小2／中学→6（教育漢字すべて）。
    public static func maxGrade(forSchoolGrade schoolGrade: Int) -> Int {
        if schoolGrade >= 7 { return 6 }            // 中学以降は教育漢字すべて許可
        return max(0, min(6, schoolGrade - 1))
    }

    /// `text` 中の、許可学年 `maxGrade` を超える漢字を**出現順**に返す。
    /// 超過 = 配当学年 > maxGrade、または **教育漢字外**（中学常用・常用外＝子には未習扱い）。
    /// ひらがな・カタカナ・英数・記号は対象外（漢字だけを見る）。重複はそのまま（位置診断用）。
    public static func offendingKanji(in text: String, maxGrade: Int) -> [Character] {
        text.filter { isKanji($0) }.filter { c in
            guard let g = KyoikuKanji.gradeOf[c] else { return true }   // 教育漢字外＝未習
            return g > maxGrade
        }
    }

    /// `text` の漢字がすべて許可学年以内か（超過漢字ゼロ）。
    public static func isWithin(_ text: String, maxGrade: Int) -> Bool {
        offendingKanji(in: text, maxGrade: maxGrade).isEmpty
    }

    /// CJK 漢字か（ひらがな/カタカナ/記号は除外）。単独スカラの漢字を想定。
    static func isKanji(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x4E00...0x9FFF).contains(s.value) ||   // CJK統合漢字（基本）
            (0x3400...0x4DBF).contains(s.value) ||   // 拡張A
            (0xF900...0xFAFF).contains(s.value)      // 互換漢字
        }
    }
}
