import Foundation

/// ペアリング6桁コードの **入力正規化**（子端末でコードを打ち込む UI の純ロジック）。
///
/// 貼り付け・区切り・記号混じり・打ちすぎに強くするため、入力から ASCII 数字だけを抜き出し、
/// 先頭 `length` 桁に丸める。UI は本ヘルパの結果を `TextField` にバインドし、`isComplete` で
/// 送信ボタンの活性を決める。I/O を持たない純関数なので `swift test` で検証できる（CLAUDE.md: テスト可能な
/// ロジックはコアに置く）。
public enum PairingCodeEntry {
    /// コードの桁数（サーバ `create_pairing_code` の発行仕様に一致）。
    public static let length = 6

    /// 入力から ASCII 数字だけを取り出し、最大 `length` 桁に丸める。
    /// 例: `"12 34-56"` → `"123456"`, `"abc1234567"` → `"123456"`。
    public static func normalize(_ raw: String) -> String {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        return String(digits.prefix(length))
    }

    /// 正規化後にちょうど `length` 桁そろっているか（送信可否）。
    public static func isComplete(_ raw: String) -> Bool {
        normalize(raw).count == length
    }
}
