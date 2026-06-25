import Foundation
import CryptoKit

/// 決定論的な UUID 生成（RFC 4122 v5 / 名前ベース SHA-1）。
///
/// 論理的に一意な行（例: srs_cards = profile+word、wallet = profile）に対し、
/// 別端末がオフラインで作っても **同じ id に収束**させ、サーバーの unique 制約と整合させる。
/// （ランダムUUIDだと別idの論理重複が unique 違反になるため。push の前提条件。）
public enum DeterministicID {
    /// 名前空間 UUID と名前文字列から UUIDv5 を生成する（同入力なら常に同一）。
    public static func uuidV5(namespace: UUID, name: String) -> UUID {
        // data = namespace(16 bytes, big-endian) + name(UTF-8)
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(contentsOf: Array(name.utf8))

        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// 複数要素から UUIDv5 を生成する。要素は区切り子(U+001F)で連結する（順序・境界が意味を持つ）。
    ///
    /// ⚠️ 前提: 各 component は **U+001F を含まない固定形の内部ID/正規化済み値**であること
    /// （区切り子を含むとマッピングが一意でなくなる）。ユーザー/OCR 由来の任意文字列は直接渡さない。
    public static func uuidV5(namespace: UUID, components: [String]) -> UUID {
        uuidV5(namespace: namespace, name: components.joined(separator: "\u{1F}"))
    }
}
