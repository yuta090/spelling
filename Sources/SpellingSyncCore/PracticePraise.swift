import Foundation

/// 練習の1回ごとに出す「ランダムなほめ言葉」。声（TTS）と中央の大きな表示に使う。
///
/// [[child-ignores-horizontal-text]]：子どもは横の説明文を読まないので、ほめ言葉は**短く・中央に大きく・声で**。
/// 選択は純関数（index → 文言）にしておき、ランダム性は呼び出し側（アプリ）が index で与える＝テスト可能。
public enum PracticePraise {
    public static let japanese: [String] = [
        "すごい！",
        "じょうずだね！",
        "がんばってるね！",
        "その ちょうし！",
        "いいね！",
        "やったね！",
        "かっこいい！",
        "てんさい！",
        "がんばったね！",
        "はなまる！",
        "パーフェクト！",
        "だいせいこう！",
        "よくできました！",
        "さいこう！"
    ]

    public static let english: [String] = [
        "Great!",
        "Nice!",
        "Awesome!",
        "Keep going!",
        "You got it!",
        "Wonderful!",
        "Cool!",
        "Superstar!",
        "Well done!",
        "Fantastic!",
        "Perfect!",
        "Amazing!",
        "Brilliant!",
        "You rock!"
    ]

    /// index に対応するほめ言葉（範囲外は剰余で巡回）。空配列でも安全に空文字を返す。
    public static func phrase(index: Int, japanese isJapanese: Bool) -> String {
        let pool = isJapanese ? japanese : english
        guard !pool.isEmpty else { return "" }
        let i = ((index % pool.count) + pool.count) % pool.count
        return pool[i]
    }
}
