import Foundation

/// 表層ID（surfaceID = UUIDv5）の別名解決。旧→新を1ホップだけ引いて履歴をつなぐ。
///
/// 設計（[[content-schema-v2-architecture]] §3 ID分離）：
/// - 英文を直すと表層IDが変わる → `content_id_aliases.json`（旧→新）で進捗/ReviewQueue を旧IDから引き継ぐ。
/// - **1ホップで完結させる**＝alias の値はさらに alias のキーになってはいけない（鎖禁止）。
///   多段リネームは「旧→最新」を直接書き直すことで、取りこぼし無く1ホップに保つ。

public enum ContentIDResolverError: Error, Equatable {
    /// alias の値がさらにキーになっている（鎖）。旧→最新へ畳んでから渡す。
    case chainedAlias(String)
}

public struct ContentIDResolver: Sendable {
    private let aliases: [String: String]

    /// 鎖が無いことを保証して初期化する（不変条件を入口で固定）。
    public init(aliases: [String: String]) throws {
        let keys = Set(aliases.keys)
        for (_, value) in aliases where keys.contains(value) {
            // 自己参照（x→x）も「値がキー」に当たるためここで弾かれる。
            throw ContentIDResolverError.chainedAlias(value)
        }
        self.aliases = aliases
    }

    /// 旧IDなら新IDへ1ホップ。別名に無ければそのまま返す。
    public func resolve(_ id: String) -> String {
        aliases[id] ?? id
    }
}
