import Foundation
import CryptoKit

/// コンテンツ・スキーマv2 の入れ物（authoring 側）。
///
/// 設計の核（`docs/age-tiered-generation-spec-2026-06-29.md` §4/§10）：
/// - authoring は「乗り物(frameTemplate)」「完成文(plain/personTemplate)」を **`kind` で明示分離**する。
/// - 旧 v1（ルート JSON 配列＝`AuthoredTemplate` 互換）は **legacy importer として読めるまま**にし、
///   v2（envelope `{schema:2, records:[...]}`）を新しい正本にする（移行を安全に・差分を小さく保つ）。
/// - 表層 `id`(UUIDv5) とは別に **安定 `sourceID`**（教材ID）を持ち、英文修正で履歴が切れないようにする。
///
/// このファイルはフェーズ① の「入れ物移行」だけを担う純ロジック（TDD）。
/// 出題プール選択・必須問題解決などの seam は後続スライスで足す。

// MARK: - 種別（乗り物 / 完成文）

public enum AuthoringKind: String, Codable, Sendable, Equatable {
    /// 完成文（そのまま露出するプール文）。
    case plain
    /// 名前入れテンプレ（友達/本人をスロットに入れる完成文）。
    case personTemplate
    /// フレーム（語を綴り変えず載せる“乗り物”。必須問題の土台）。
    case frameTemplate
}

// MARK: - 補助（スロット / フレーム）

public struct AuthoringSlot: Codable, Sendable, Equatable {
    public var key: String
    public var role: String
    public var gender: String?
    public init(key: String, role: String, gender: String? = nil) {
        self.key = key; self.role = role; self.gender = gender
    }
}

public struct AuthoringFrame: Codable, Sendable, Equatable {
    public var slot: String
    public var allowedPOS: [String]
    public var semanticClass: String?
    public init(slot: String, allowedPOS: [String], semanticClass: String? = nil) {
        self.slot = slot; self.allowedPOS = allowedPOS; self.semanticClass = semanticClass
    }
}

// MARK: - 統一レコード（v1/v2 共通の取り込み後の形）

/// authoring の1件（v1配列・v2 envelope を読み分けた後の統一表現）。
public struct AuthoringRecord: Sendable, Equatable {
    public var sourceID: String
    public var kind: AuthoringKind
    public var gradeBand: Int
    public var contentLemmas: [String]
    public var en: [String]
    public var ja: String
    public var grammar: GrammarPoint?
    public var slots: [AuthoringSlot]
    public var frame: AuthoringFrame?

    public init(sourceID: String, kind: AuthoringKind, gradeBand: Int,
                contentLemmas: [String], en: [String], ja: String,
                grammar: GrammarPoint? = nil, slots: [AuthoringSlot] = [],
                frame: AuthoringFrame? = nil) {
        self.sourceID = sourceID; self.kind = kind; self.gradeBand = gradeBand
        self.contentLemmas = contentLemmas; self.en = en; self.ja = ja
        self.grammar = grammar; self.slots = slots; self.frame = frame
    }
}

public enum AuthoringSourceError: Error, Equatable {
    case empty
    case unrecognizedRoot
    case duplicateSourceID(String)
    /// v2 envelope の `schema` が想定外（2 以外）。
    case unsupportedSchema(Int)
    /// v2 レコードの `sourceID` が空/前後空白/不正文字（明示の安定キーが必須）。
    case invalidSourceID(String)
}

// MARK: - dual-decode（v1配列 / v2 envelope）

public enum AuthoringSource {

    /// authoring データを v1配列／v2 envelope の**どちらでも**読み、統一レコードへ取り込む。
    /// - ルート先頭の非空白バイトが `[` なら v1配列（legacy importer）、`{` なら v2 envelope。
    /// - v2 は `kind` を明示必須（欠けると decode が throw）。
    /// - sourceID が重複したら弾く（安定IDの一意性）。
    public static func decode(_ data: Data) throws -> [AuthoringRecord] {
        guard let first = firstNonWhitespaceByte(data) else { throw AuthoringSourceError.empty }
        let records: [AuthoringRecord]
        switch first {
        case UInt8(ascii: "["):
            records = try decodeV1Array(data)
        case UInt8(ascii: "{"):
            records = try decodeV2Envelope(data)
        default:
            throw AuthoringSourceError.unrecognizedRoot
        }
        try assertUniqueSourceIDs(records)
        return records
    }

    // v1：ルート配列（AuthoredTemplate 互換のゆるい取り込み）。
    private static func decodeV1Array(_ data: Data) throws -> [AuthoringRecord] {
        let rows = try JSONDecoder().decode([V1Row].self, from: data)
        return rows.map { row in
            let slots = row.slots ?? []
            // kind 推定：slots 有→personTemplate、無→plain（frameTemplate は v2 で明示する）。
            let kind: AuthoringKind = slots.isEmpty ? .plain : .personTemplate
            return AuthoringRecord(
                sourceID: ContentSourceID.derive(authoringID: row.id, en: row.en),
                kind: kind,
                gradeBand: row.gradeBand,
                contentLemmas: row.contentLemmas ?? [],
                en: row.en,
                ja: row.ja,
                grammar: row.grammar,
                slots: slots,
                frame: nil
            )
        }
    }

    // v2：envelope。kind は非 optional ＝欠けると throw（明示必須を型で強制）。
    private static func decodeV2Envelope(_ data: Data) throws -> [AuthoringRecord] {
        let env = try JSONDecoder().decode(V2Envelope.self, from: data)
        // schema の値を実際に検証する（{"schema":1} 等の取り違えを弾く）。
        guard env.schema == 2 else { throw AuthoringSourceError.unsupportedSchema(env.schema) }
        return try env.records.map { r in
            // v2 は安定キーが明示前提＝英文由来フォールバックに頼らない（空/前後空白/不正文字は弾く）。
            let sourceID = try ContentSourceID.requireExplicit(r.sourceID)
            return AuthoringRecord(
                sourceID: sourceID,
                kind: r.kind,
                gradeBand: r.gradeBand,
                contentLemmas: r.contentLemmas ?? [],
                en: r.en,
                ja: r.ja,
                grammar: r.grammar,
                slots: r.slots ?? [],
                frame: r.frame
            )
        }
    }

    private static func assertUniqueSourceIDs(_ records: [AuthoringRecord]) throws {
        var seen = Set<String>()
        for r in records {
            if seen.contains(r.sourceID) { throw AuthoringSourceError.duplicateSourceID(r.sourceID) }
            seen.insert(r.sourceID)
        }
    }

    /// ルート種別判定用の先頭バイト。UTF-8 BOM(EF BB BF)と空白は読み飛ばす
    /// （BOM 付きで保存するエディタ由来でも素直に読めるように）。
    private static func firstNonWhitespaceByte(_ data: Data) -> UInt8? {
        let bytes = Array(data)
        var i = 0
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { i = 3 }
        while i < bytes.count {
            let b = bytes[i]
            if b != 0x20 && b != 0x09 && b != 0x0A && b != 0x0D { return b }
            i += 1
        }
        return nil
    }

    // MARK: - 生 Codable（ファイル形そのまま）

    private struct V1Row: Decodable {
        var id: String?
        var gradeBand: Int
        var contentLemmas: [String]?
        var slots: [AuthoringSlot]?
        var en: [String]
        var ja: String
        var grammar: GrammarPoint?
    }

    private struct V2Envelope: Decodable {
        var schema: Int
        var records: [V2Row]
    }

    private struct V2Row: Decodable {
        var kind: AuthoringKind          // 非 optional＝明示必須
        var sourceID: String?
        var gradeBand: Int
        var contentLemmas: [String]?
        var slots: [AuthoringSlot]?
        var en: [String]
        var ja: String
        var grammar: GrammarPoint?
        var frame: AuthoringFrame?
    }
}

// MARK: - 安定 sourceID 導出

public enum ContentSourceID {
    /// sourceID 用の決定論名前空間（surfaceID の名前空間とは別系統）。
    private static let namespace = UUID(uuidString: "2D7A1E60-9B44-5C2E-8F1D-3A6B0C4E7D90")!

    /// v2 で許可する安定キーの文字種＝英数と `-` `_` `.` のみ（空白・制御文字を排除）。
    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

    /// authoring の id があればそれを安定IDとして**再利用**する（v1/legacy 用・寛容）。
    /// 無い legacy 行は `legacy-<slug>-<短ハッシュ>` を英文から決定論で付与（同入力＝同出力）。
    public static func derive(authoringID: String?, en: [String]) -> String {
        if let id = authoringID, !id.trimmingCharacters(in: .whitespaces).isEmpty {
            return id
        }
        let text = en.joined(separator: " ")
        return "legacy-\(slug(text))-\(shortHash(text))"
    }

    /// v2 の明示 sourceID を検証して返す（英文フォールバックに頼らない厳格版）。
    /// nil/空/前後空白/許可外文字は `invalidSourceID` を投げる。
    public static func requireExplicit(_ raw: String?) throws -> String {
        guard let id = raw, !id.isEmpty else { throw AuthoringSourceError.invalidSourceID(raw ?? "") }
        // 前後空白を持たない（== トリム結果）かつ許可文字のみ。
        guard id == id.trimmingCharacters(in: .whitespacesAndNewlines),
              id.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { throw AuthoringSourceError.invalidSourceID(id) }
        return id
    }

    /// 英数小文字の slug（非英数の連続は1つの `-`、最大24文字、前後 `-` を除去）。
    private static func slug(_ text: String) -> String {
        var out = ""
        var lastDash = false
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(24))
    }

    /// 英文からの 12 桁 16 進ハッシュ（決定論・衝突回避の補助。長命キー向けに 48bit を確保）。
    private static func shortHash(_ text: String) -> String {
        let uuid = DeterministicID.uuidV5(namespace: namespace, name: text)
        return String(uuid.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    }
}
