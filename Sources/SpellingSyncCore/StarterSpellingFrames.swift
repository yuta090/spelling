import Foundation

/// おぼえる練習（手書きの前・タップで選ぶ）で使う「綴り不変フレーム」のスターターセット。
///
/// - 登録語を**綴り変えずに**スロットへ載せる“乗り物”。`CoreProblemResolver` が POS で選ぶ。
/// - `ja` はテンプレ（語の和訳が入る位置を `slotToken` で示す）。漢字は使わず仮名で書く
///   （どの学年でも `KanjiLevelGate` を通る＝tier 安全。和訳語は UI 側で差し込む想定）。
/// - 中身（件数・id・POS・band）が変わると `StarterSpellingFramesTests` のカナリアで検知する。
///
/// 設計上の注意（冠詞・数の不一致を避ける）：
/// - 名詞フレームは**冠詞 a/an や数（two/many）を固定しない**中立文にする。POS だけでは
///   その語が単数可算か複数か母音始まりかを判定できないため、`a foxes` / `two apple` /
///   `a apple` のような誤った英文を作らないよう除外する。
/// - さらに裸の名詞が最も自然に読める動詞（like / Do you like）に限定する
///   （`I see apple.` のような不自然さも避ける）。`I like apple(s).` は日本の小学英語で定番。
/// - 動詞は原形スロット、形容詞は be 動詞スロット＝どちらも冠詞/数の一致問題が起きない。
/// - **残る制限**: POS だけでは可算/不可算・母音始まりまでは保証できない。完全な一致には
///   語ごとの「単数可算/複数/母音始まり」メタデータが要る（別タスク＝age-tiered generation）。
///
/// ※ これは“最初の少数”。本格量産（題材×学年）は別タスク（age-tiered generation）。
public enum StarterSpellingFrames {

    /// スロットのプレースホルダ。`SpellingInvariantFrame.filled(with:)` で登録語に置換される。
    public static let slotToken = "___"

    public static let all: [SpellingInvariantFrame] = [
        // 名詞（裸の名詞が自然に読める like 系のみ。冠詞/数は固定しない）
        frame("starter-noun-like",  ["I", "like", slotToken, "."],          ja: "___が すきだよ。",          pos: ["noun"], band: 1, grammar: .presentSimple),
        frame("starter-noun-doyou", ["Do", "you", "like", slotToken, "?"],  ja: "___は すき？",              pos: ["noun"], band: 2, grammar: .yesNoQuestion),

        // 動詞（原形スロット）
        frame("starter-verb-can",    ["I", "can", slotToken, "."],          ja: "___ できるよ。",            pos: ["verb"], band: 1, grammar: .canModal),
        frame("starter-verb-daily",  ["I", slotToken, "every", "day", "."], ja: "まいにち ___ するよ。",      pos: ["verb"], band: 2, grammar: .frequencyAdverb),
        frame("starter-verb-lets",   ["Let's", slotToken, "together", "."], ja: "いっしょに ___ しよう。",    pos: ["verb"], band: 2, grammar: .imperative),
        frame("starter-verb-wantto", ["I", "want", "to", slotToken, "."],   ja: "___ したいな。",            pos: ["verb"], band: 3, grammar: .infinitive),

        // 形容詞（be 動詞スロット）
        frame("starter-adj-it",     ["It", "is", slotToken, "."],           ja: "それは ___ だよ。",          pos: ["adjective"], band: 1, grammar: .beVerb),
        frame("starter-adj-iam",    ["I", "am", slotToken, "."],            ja: "わたしは ___ だよ。",        pos: ["adjective"], band: 1, grammar: .beVerb),
        frame("starter-adj-youare", ["You", "are", slotToken, "."],         ja: "きみは ___ だよ。",          pos: ["adjective"], band: 1, grammar: .beVerb),
    ]

    /// スロット位置はトークン列から求める（手で index を打ち間違えない）。
    private static func frame(_ id: String, _ tokens: [String], ja: String,
                              pos: [String], band: Int, grammar: GrammarPoint) -> SpellingInvariantFrame {
        let slot = tokens.firstIndex(of: slotToken) ?? 0
        return SpellingInvariantFrame(id: id, tokens: tokens, answerSlotIndex: slot,
                                      ja: ja, allowedPOS: pos, gradeBand: band, grammar: grammar)
    }
}
