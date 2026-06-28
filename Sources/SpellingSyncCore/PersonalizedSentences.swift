import Foundation

// 例文パーソナライズ（キャスト＋役スロット）の純粋ロジック。
// 設計/仕様: docs/personalized-sentences-spec-2026-06-28.md
//
// 中心思想（codex Architect）：**生の文を後から書き換えない。**
// スロット付きで“最初から正しく書かれた”テンプレ(PersonSentenceTemplate)だけを
// 決定論的にレンダリングして既存の SentenceItem を生成する。
// → 動詞活用(like→likes)・代名詞(he/she)・日本語助詞は作成時に確定済みなので、
//   実行時は名前を流し込むだけ。主語動詞一致・性別の崩れが原理的に起きない。
//
// 決定論：Date()/乱数/String.hashValue を使わない。seed から再現可能（SpellingSyncCore 方針）。

// MARK: - キャスト（その子の登場人物。親がローカル登録）

public enum CastRole: String, Codable, Sendable {
    case child
    case friend
}

public enum PersonGender: String, Codable, Sendable {
    case boy
    case girl
    case unspecified
}

public struct CastPerson: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var role: CastRole
    public var gender: PersonGender
    public var displayNameJa: String   // "ゆうた"（親一覧・日本語文用）
    public var romaji: String          // "Yuta"（英文に出す綴り。英1トークン）
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        role: CastRole,
        gender: PersonGender,
        displayNameJa: String,
        romaji: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.role = role
        self.gender = gender
        self.displayNameJa = displayNameJa
        self.romaji = romaji
        self.isActive = isActive
    }
}

public struct Cast: Equatable, Codable, Sendable {
    public var people: [CastPerson]   // 配列順＝登録順（選択の安定ソート基準）
    public init(people: [CastPerson] = []) {
        self.people = people
    }
}

// MARK: - 役スロット付きテンプレ（承認済みを同梱する想定）

/// 英語トークン1個分のテンプレ。リテラル or 人物参照（参照形＋接尾）。
/// JSON 形: {"kind":"literal","text":"…"} / {"kind":"person","slot":"f","form":"name","suffix":","}
/// suffix は省略可（既定 ""）。承認済みデータ生成側の記述ミスに強くする。
public enum EnglishTokenTemplate: Equatable, Codable, Sendable {
    case literal(String)
    /// suffix は名前/代名詞に続けて1トークンに含める文字（呼びかけの "," など）。
    case person(slot: String, form: PersonReferenceForm, suffix: String)

    public static func person(slot: String, form: PersonReferenceForm) -> EnglishTokenTemplate {
        .person(slot: slot, form: form, suffix: "")
    }

    private enum Kind: String, Codable { case literal, person }
    private enum CodingKeys: String, CodingKey { case kind, text, slot, form, suffix }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .literal:
            self = .literal(try c.decode(String.self, forKey: .text))
        case .person:
            let slot = try c.decode(String.self, forKey: .slot)
            let form = try c.decode(PersonReferenceForm.self, forKey: .form)
            let suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
            self = .person(slot: slot, form: form, suffix: suffix)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let text):
            try c.encode(Kind.literal, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .person(let slot, let form, let suffix):
            try c.encode(Kind.person, forKey: .kind)
            try c.encode(slot, forKey: .slot)
            try c.encode(form, forKey: .form)
            try c.encode(suffix, forKey: .suffix)
        }
    }
}

/// 日本語文の1パーツ。日本語は活用問題が無いので名前差し込みだけ。
/// JSON 形: {"kind":"literal","text":"…"} / {"kind":"person","slot":"f","suffix":"は"}
/// suffix は省略可（既定 ""）。
public enum JapaneseTextPart: Equatable, Codable, Sendable {
    case literal(String)
    case person(slot: String, suffix: String)

    public static func person(slot: String) -> JapaneseTextPart {
        .person(slot: slot, suffix: "")
    }

    private enum Kind: String, Codable { case literal, person }
    private enum CodingKeys: String, CodingKey { case kind, text, slot, suffix }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .literal:
            self = .literal(try c.decode(String.self, forKey: .text))
        case .person:
            let slot = try c.decode(String.self, forKey: .slot)
            let suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
            self = .person(slot: slot, suffix: suffix)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let text):
            try c.encode(Kind.literal, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .person(let slot, let suffix):
            try c.encode(Kind.person, forKey: .kind)
            try c.encode(slot, forKey: .slot)
            try c.encode(suffix, forKey: .suffix)
        }
    }
}

/// 英語での人物の出方。表層形は決定論的に決まる（活用は作成時確定）。
public enum PersonReferenceForm: String, Codable, Sendable {
    case name                  // Yuki
    case namePossessive        // Yuki's
    case subjectPronoun        // he / she / they（※小文字。文頭で使うなら .name か literal を使う）
    case objectPronoun         // him / her / them
    case possessiveDeterminer  // his / her / their
    case vocativeName          // 呼びかけ（本人専用想定）。Yuki（"," 等は suffix で）
}

public enum SentenceCategory: String, Codable, Sendable {
    case school     // 学校での会話
    case play       // あそび・さそい
    case greeting   // あいさつ
    case home       // 家
    case daily      // 日常
    case other
}

public struct PersonSlotSpec: Equatable, Codable, Sendable {
    public var key: String                  // "friendA" / "friendB" / "child"
    public var role: CastRole
    public var requiredGender: PersonGender? // .boy/.girl のみ制約。nil/.unspecified は無制約

    public init(key: String, role: CastRole, requiredGender: PersonGender? = nil) {
        self.key = key
        self.role = role
        self.requiredGender = requiredGender
    }
}

/// 文のもと。英語トークン列・日本語パーツ・スロット要件・正常なフォールバック文を一緒に持つ。
public struct PersonSentenceTemplate: Equatable, Codable, Sendable {
    public var id: String
    public var category: SentenceCategory
    public var fallback: SentenceItem          // Cast不足時に出す“正常な”既定文
    public var enTokens: [EnglishTokenTemplate]
    public var jaParts: [JapaneseTextPart]
    public var slots: [PersonSlotSpec]
    // 解決後 SentenceItem へコピー（名前は contentLemmas に含めない）
    public var gradeBand: Int
    public var contentLemmas: [String]
    public var grammar: GrammarPoint?

    public init(
        id: String,
        category: SentenceCategory,
        fallback: SentenceItem,
        enTokens: [EnglishTokenTemplate],
        jaParts: [JapaneseTextPart],
        slots: [PersonSlotSpec],
        gradeBand: Int,
        contentLemmas: [String] = [],
        grammar: GrammarPoint? = nil
    ) {
        self.id = id
        self.category = category
        self.fallback = fallback
        self.enTokens = enTokens
        self.jaParts = jaParts
        self.slots = slots
        self.gradeBand = gradeBand
        self.contentLemmas = contentLemmas
        self.grammar = grammar
    }
}

// MARK: - 解決（純粋・決定論）

public enum SentencePersonalizer {
    /// テンプレ＋Cast＋seed → 解決済み SentenceItem。
    /// 必要スロットを埋められなければ template.fallback をそのまま返す（＝機能オフ/未登録と同じ体験）。
    public static func resolve(_ template: PersonSentenceTemplate, cast: Cast, seed: UInt64) -> SentenceItem {
        guard !template.slots.isEmpty else { return template.fallback }

        // 各スロットへ「別人」を決定論的に割り当てる（3人会話で同一人物を避ける）。
        // 貪欲だと「制約ゆるいスロットが、後段の厳しいスロットの唯一の候補を先取り」して
        // 解が在るのに fallback してしまう。→ seed順に並べた候補を DFS バックトラックで割り当てる。
        guard let assigned = assignSlots(template: template, cast: cast, seed: seed) else {
            return template.fallback
        }

        // 英語トークン列を描画。
        var tokens: [String] = []
        tokens.reserveCapacity(template.enTokens.count)
        for token in template.enTokens {
            switch token {
            case .literal(let s):
                tokens.append(s)
            case .person(let slotKey, let form, let suffix):
                guard let person = assigned[slotKey] else { return template.fallback }
                tokens.append(englishReference(person, form: form) + suffix)
            }
        }

        // 日本語文を描画（スペースなしで連結）。
        var ja = ""
        for part in template.jaParts {
            switch part {
            case .literal(let s):
                ja += s
            case .person(let slotKey, let suffix):
                guard let person = assigned[slotKey] else { return template.fallback }
                ja += person.displayNameJa + suffix
            }
        }

        let en = tokens.joined(separator: " ")
        let id = deterministicID(template: template, assigned: assigned, seed: seed)

        return SentenceItem(
            id: id,
            en: en,
            ja: ja,
            tokens: tokens,
            gradeBand: template.gradeBand,
            contentLemmas: template.contentLemmas,   // 名前は含めない（作成側の責務）
            grammar: template.grammar
        )
    }

    // MARK: 内部

    /// requiredGender が .boy/.girl のときだけ一致を要求。nil/.unspecified は無制約。
    private static func genderMatches(_ gender: PersonGender, required: PersonGender?) -> Bool {
        switch required {
        case .some(.boy): return gender == .boy
        case .some(.girl): return gender == .girl
        case .some(.unspecified), .none: return true
        }
    }

    /// 全スロットに「別人」を割り当てる。解が在れば必ず見つける（DFS バックトラック）。
    /// 各スロットの候補は seed で安定ソートし、その順に試す（どの解を採るかは seed で決定論かつ多様）。
    /// 解なし（埋められない）なら nil → 呼び出し側で fallback。
    private static func assignSlots(template: PersonSentenceTemplate, cast: Cast, seed: UInt64) -> [String: CastPerson]? {
        let slots = template.slots
        // スロットごとの候補列を seed 順に整列（タイブレークは登録順＝cast index）。
        let orderedCandidates: [[CastPerson]] = slots.map { slot in
            cast.people.enumerated()
                .filter { (_, p) in
                    p.isActive
                        && p.role == slot.role
                        && !p.romaji.isEmpty              // 英文に出せない人は除外
                        && genderMatches(p.gender, required: slot.requiredGender)
                }
                .sorted { lhs, rhs in
                    let lh = selectionHash(templateID: template.id, slotKey: slot.key + "\u{1f}" + lhs.element.id.uuidString, seed: seed)
                    let rh = selectionHash(templateID: template.id, slotKey: slot.key + "\u{1f}" + rhs.element.id.uuidString, seed: seed)
                    return lh != rh ? lh < rh : lhs.offset < rhs.offset
                }
                .map { $0.element }
        }

        var used = Set<UUID>()
        var result: [String: CastPerson] = [:]
        func dfs(_ i: Int) -> Bool {
            if i == slots.count { return true }
            for person in orderedCandidates[i] where !used.contains(person.id) {
                used.insert(person.id)
                result[slots[i].key] = person
                if dfs(i + 1) { return true }
                used.remove(person.id)
                result[slots[i].key] = nil
            }
            return false
        }
        return dfs(0) ? result : nil
    }

    /// 英語での人物表層形（小文字の代名詞。文頭で大文字が要る場合は .name/literal を使う）。
    private static func englishReference(_ person: CastPerson, form: PersonReferenceForm) -> String {
        switch form {
        case .name, .vocativeName:
            return person.romaji
        case .namePossessive:
            return person.romaji + "'s"
        case .subjectPronoun:
            switch person.gender {
            case .boy: return "he"
            case .girl: return "she"
            case .unspecified: return "they"
            }
        case .objectPronoun:
            switch person.gender {
            case .boy: return "him"
            case .girl: return "her"
            case .unspecified: return "them"
            }
        case .possessiveDeterminer:
            switch person.gender {
            case .boy: return "his"
            case .girl: return "her"
            case .unspecified: return "their"
            }
        }
    }

    // MARK: 決定論ハッシュ（Date/Random/String.hashValue 非依存）

    /// FNV-1a(64) で文字列を畳み、SplitMix64 で1段撹拌。同入力→同出力。
    private static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func splitmix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// スロット選択用ハッシュ（template.id・slot.key・seed から決定論）。
    private static func selectionHash(templateID: String, slotKey: String, seed: UInt64) -> UInt64 {
        splitmix(fnv1a(templateID + "\u{1f}" + slotKey) ^ seed)
    }

    /// 解決済み文の決定論 UUID（template.id・選んだ人・seed から128bit を作る）。
    private static func deterministicID(template: PersonSentenceTemplate, assigned: [String: CastPerson], seed: UInt64) -> UUID {
        // 割り当てを安定文字列化（slot.key 昇順）。
        let assignment = assigned.keys.sorted().map { "\($0)=\(assigned[$0]!.id.uuidString)" }.joined(separator: ",")
        let base = fnv1a(template.id + "\u{1f}" + assignment) ^ seed
        let hi = splitmix(base)
        let lo = splitmix(base ^ 0xD1B5_4A32_D192_ED03)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: hi >> (8 * (7 - i))) }
        for i in 0..<8 { bytes[8 + i] = UInt8(truncatingIfNeeded: lo >> (8 * (7 - i))) }
        // RFC4122 風に version/variant ビットを整える（衝突回避とは無関係だが体裁）。
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: t)
    }
}
