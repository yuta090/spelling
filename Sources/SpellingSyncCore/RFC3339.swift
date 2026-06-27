import Foundation

/// RFC3339（UTC・ミリ秒は任意）文字列 ⇄ `Date` の共有ヘルパ。
///
/// 送信は常にミリ秒つき UTC（"…Z"）で出し、受信はミリ秒の有無どちらも受ける（LWW 比較の一貫性）。
/// `ISO8601DateFormatter` は Sendable でない（Swift6）ため共有 static には保持せず、呼び出し毎に作る
/// （生成コストは無視できる）。
///
/// 注: `WordWire` は歴史的に同等の private 実装を持つ。新規の wire（reviews/attempts）はこちらを使う。
public enum RFC3339 {
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    /// RFC3339 文字列 → `Date`。解釈できなければ nil。
    public static func date(from string: String) -> Date? {
        makeFormatter(fractional: true).date(from: string)
            ?? makeFormatter(fractional: false).date(from: string)
    }

    /// `Date` → RFC3339（UTC・ミリ秒つき "…Z"）文字列。
    public static func string(from date: Date) -> String {
        makeFormatter(fractional: true).string(from: date)
    }
}
