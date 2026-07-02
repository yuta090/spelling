import Foundation

// かな名 → ヘボン式（パスポート風）ローマ字の決定論変換。
// 用途：「なかま」登録シートで、既知のかな名からローマ字欄をプリフィルする（親が修正できる下書き）。
// 方針：
// - 決定論（辞書・OS API 非依存の固定テーブル）。同入力→同出力。
// - 1語の名前だけ扱う。変換できない文字（漢字・英字・スペース等）が混ざったら空文字を返し、
//   呼び出し側は空欄のまま親に入力してもらう（誤変換を出すより空の方が安全）。
// - 長音はパスポート表記に合わせて省く（ゆうた→Yuta、こうた→Kota、おおた→Ota。えい=ei は残す）。
// - ん は b/m/p の前で m（しんぺい→Shimpei）。ん+母音の区切り記号（Ken'ichi の '）は
//   ローマ字欄が英字のみ（1語）の制約のため省き Kenichi とする。
public enum KanaRomaji {

    /// かな1語の名前をローマ字（先頭大文字）へ。変換不能なら "" を返す。
    public static func romanize(_ kanaName: String) -> String {
        let trimmed = kanaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // カタカナ→ひらがな正規化（ー は直前の母音の繰り返しとして扱う）。
        var kana: [Character] = []
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x30A1...0x30F6:   // ァ..ヶ → ぁ..ゖ
                guard let shifted = Unicode.Scalar(scalar.value - 0x60) else { return "" }
                kana.append(Character(shifted))
            case 0x30FC:            // ー（長音記号）
                kana.append("ー")
            default:
                kana.append(Character(scalar))
            }
        }

        // かな列 → 音節ローマ字列。
        var syllables: [String] = []
        var pendingSokuon = false
        var index = 0
        while index < kana.count {
            // 拗音（2文字）を先に引く。
            if index + 1 < kana.count,
               let digraph = Self.digraphs[String([kana[index], kana[index + 1]])] {
                syllables.append(applySokuon(digraph, pending: &pendingSokuon))
                index += 2
                continue
            }
            let ch = kana[index]
            index += 1
            if ch == "っ" {
                pendingSokuon = true
                continue
            }
            if ch == "ー" {
                // 直前音節の母音を繰り返す（後段の長音省きで自然に縮む）。
                guard let last = syllables.last?.last else { return "" }
                syllables.append(String(last))
                continue
            }
            guard let romaji = Self.monographs[ch] else { return "" }
            syllables.append(applySokuon(romaji, pending: &pendingSokuon))
        }
        if pendingSokuon { return "" }   // 末尾の「っ」は名前として不正

        // ん（n）は b/m/p の前で m（パスポート式：しんぺい→Shimpei）。
        for i in syllables.indices {
            if syllables[i] == "n", i + 1 < syllables.count,
               let head = syllables[i + 1].first, head == "b" || head == "m" || head == "p" {
                syllables[i] = "m"
            }
        }

        // 長音省き（音節境界で判定：直前が o で終わり次が "u"、または同母音 o/u の連続）。
        var flattened = ""
        for syllable in syllables {
            if let lastVowel = flattened.last,
               (lastVowel == "o" && (syllable == "u" || syllable == "o")) ||
               (lastVowel == "u" && syllable == "u") {
                continue
            }
            flattened += syllable
        }

        guard let first = flattened.first else { return "" }
        return first.uppercased() + flattened.dropFirst()
    }

    /// 促音（っ）を次音節の頭子音の重ねとして反映する（ち系は t を前置：まっちゃ→matcha）。
    private static func applySokuon(_ syllable: String, pending: inout Bool) -> String {
        guard pending else { return syllable }
        pending = false
        guard let head = syllable.first, head != "a", head != "i", head != "u", head != "e", head != "o" else {
            return syllable   // 母音の前の促音は名前として不自然 → 重ねずそのまま
        }
        return syllable.hasPrefix("ch") ? "t" + syllable : String(head) + syllable
    }

    // MARK: テーブル（ヘボン式）

    private static let monographs: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "o", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu",
    ]

    private static let digraphs: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
        "てぃ": "ti", "でぃ": "di",
        "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
    ]
}
