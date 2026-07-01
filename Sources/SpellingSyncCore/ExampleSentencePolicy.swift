import Foundation

/// スペル練習の「英語例文」を出すかどうかの純ロジック。
///
/// 同梱の例文（田中コーパス由来）は大人向けの自然文で語彙を制御していないため、
/// 低学年（小1・小2＝`ContentTier.a`）ではコースでまだ習っていない語が混ざり負担になる。
/// この段階では英語例文（とその和訳）を出さず、単語＋意味（訳）だけに割り切る。
/// 中学年以降（b/c/d）は読める前提で従来どおり例文を出す。
///
/// 判定は子の学年段階（tier）だけに依存する純関数。意味（gloss）の表示可否は別軸（常に出す）。
public enum ExampleSentencePolicy {
    /// その段階で英語例文を表示してよいか。低学年（a）だけ false。
    public static func showsEnglishExample(tier: ContentTier) -> Bool {
        switch tier {
        case .a:
            return false
        case .b, .c, .d:
            return true
        }
    }
}
