import Foundation

// 承認済みテンプレを「人にもAIにも優しい」オーサリング形式から読み込むローダ。
// 仕様/書式: docs/personalized-sentences-authoring-2026-06-28.md
//
// なぜ別形式か：PersonSentenceTemplate を生 JSON で書かせると UUID や {"kind":...} が冗長で
// AI/人が間違えやすい。そこで簡潔な記法（en は ["{f:name}","likes","apples"]、
// ja は "{f}は りんごが すき"）で書き、ここで決定論的に PersonSentenceTemplate へ変換する。
// 変換は純粋・決定論（fallback の id も template.id から決定論生成）。

/// オーサリング1件（agy/人が書くフラットなレコード）。
public struct AuthoredTemplate: Equatable, Codable, Sendable {
    public var id: String
    public var category: SentenceCategory
    public var grammar: GrammarPoint?      // 省略/null 可
    public var genre: Genre?               // 省略/null 可（既定＝useful 相当）。humor トグルの素
    public var gradeBand: Int
    public var contentLemmas: [String]     // 名前は入れない
    public var slots: [AuthoredSlot]
    public var en: [String]                // ["{f:name}","likes","apples"]
    public var ja: String                  // "{f}は りんごが すき"
    public var fallbackEn: [String]        // ["She","likes","apples"]
    public var fallbackJa: String          // "かのじょは りんごが すき"

    public init(id: String, category: SentenceCategory, grammar: GrammarPoint? = nil,
                genre: Genre? = nil,
                gradeBand: Int, contentLemmas: [String] = [], slots: [AuthoredSlot],
                en: [String], ja: String, fallbackEn: [String], fallbackJa: String) {
        self.id = id; self.category = category; self.grammar = grammar; self.genre = genre
        self.gradeBand = gradeBand; self.contentLemmas = contentLemmas; self.slots = slots
        self.en = en; self.ja = ja; self.fallbackEn = fallbackEn; self.fallbackJa = fallbackJa
    }
}

public struct AuthoredSlot: Equatable, Codable, Sendable {
    public var key: String
    public var role: CastRole
    public var gender: PersonGender?       // .boy/.girl のみ制約。省略=無制約
    public init(key: String, role: CastRole, gender: PersonGender? = nil) {
        self.key = key; self.role = role; self.gender = gender
    }
}

public enum AuthoringError: Error, Equatable {
    case emptyEnglish(id: String)
    case emptyFallback(id: String)
    case badTokenSyntax(id: String, token: String)
    case unknownForm(id: String, form: String)
    case undefinedSlot(id: String, key: String)     // en/ja が宣言外スロットを参照
    case unusedSlot(id: String, key: String)         // 宣言したが en/ja で未使用
    case childMustBeVocative(id: String, key: String) // 本人スロットを英語で呼びかけ以外に使った
    case duplicateID(id: String)
}

public enum PersonTemplateAuthoring {
    /// オーサリング JSON（配列）→ PersonSentenceTemplate 配列。検証付き。
    public static func load(jsonArray data: Data) throws -> [PersonSentenceTemplate] {
        let authored = try JSONDecoder().decode([AuthoredTemplate].self, from: data)
        var seen = Set<String>()
        return try authored.map { a in
            guard seen.insert(a.id).inserted else { throw AuthoringError.duplicateID(id: a.id) }
            return try build(a)
        }
    }

    /// 1件をビルド（公開・テスト/部分利用用）。
    public static func build(_ a: AuthoredTemplate) throws -> PersonSentenceTemplate {
        guard !a.en.isEmpty else { throw AuthoringError.emptyEnglish(id: a.id) }
        guard !a.fallbackEn.isEmpty else { throw AuthoringError.emptyFallback(id: a.id) }

        let declared = Dictionary(uniqueKeysWithValues: a.slots.map { ($0.key, $0) })
        var referenced = Set<String>()

        // 英語トークン
        let enTokens: [EnglishTokenTemplate] = try a.en.map { tok in
            guard let parsed = try parseEnToken(tok, id: a.id) else { return .literal(tok) }
            referenced.insert(parsed.slot)
            // 本人スロットは英語では呼びかけ専用（"I"主語の一致崩れを禁止）。
            if declared[parsed.slot]?.role == .child, parsed.form != .vocativeName {
                throw AuthoringError.childMustBeVocative(id: a.id, key: parsed.slot)
            }
            return .person(slot: parsed.slot, form: parsed.form, suffix: parsed.suffix)
        }

        // 日本語パーツ
        let jaParts = parseJa(a.ja)
        for case let .person(slot, _) in jaParts { referenced.insert(slot) }

        // 参照整合性
        for key in referenced where declared[key] == nil {
            throw AuthoringError.undefinedSlot(id: a.id, key: key)
        }
        for slot in a.slots where !referenced.contains(slot.key) {
            throw AuthoringError.unusedSlot(id: a.id, key: slot.key)
        }

        let slots = a.slots.map { PersonSlotSpec(key: $0.key, role: $0.role, requiredGender: $0.gender) }

        // fallback の id は template.id から決定論生成（オーサリングでは UUID を書かせない）。
        let fallback = SentenceItem(
            id: DeterministicHash.uuid("fallback\u{1f}" + a.id),
            en: a.fallbackEn.joined(separator: " "),
            ja: a.fallbackJa,
            tokens: a.fallbackEn,
            gradeBand: a.gradeBand,
            contentLemmas: a.contentLemmas,
            grammar: a.grammar,
            genre: a.genre
        )

        return PersonSentenceTemplate(
            id: a.id, category: a.category, fallback: fallback,
            enTokens: enTokens, jaParts: jaParts, slots: slots,
            gradeBand: a.gradeBand, contentLemmas: a.contentLemmas, grammar: a.grammar,
            genre: a.genre
        )
    }

    // MARK: パース

    private struct ParsedRef { let slot: String; let form: PersonReferenceForm; let suffix: String }

    /// "{f:name}" / "{me:vocative}," → 人物参照。"{...}" で始まらなければ nil（＝リテラル扱い）。
    private static func parseEnToken(_ s: String, id: String) throws -> ParsedRef? {
        guard s.hasPrefix("{") else { return nil }
        guard let close = s.firstIndex(of: "}") else { throw AuthoringError.badTokenSyntax(id: id, token: s) }
        let inner = s[s.index(after: s.startIndex)..<close]   // "f:name"
        let suffix = String(s[s.index(after: close)...])       // "}" の後ろ（"," 等）
        let parts = inner.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else { throw AuthoringError.badTokenSyntax(id: id, token: s) }
        guard let form = formMap[parts[1]] else { throw AuthoringError.unknownForm(id: id, form: parts[1]) }
        return ParsedRef(slot: parts[0], form: form, suffix: suffix)
    }

    /// "{f}は …" のように {slot} を抜き出して [literal|person] に分解。日本語の助詞はリテラル。
    private static func parseJa(_ s: String) -> [JapaneseTextPart] {
        var parts: [JapaneseTextPart] = []
        var lit = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                if !lit.isEmpty { parts.append(.literal(lit)); lit = "" }
                let slot = String(s[s.index(after: i)..<close])
                parts.append(.person(slot: slot, suffix: ""))
                i = s.index(after: close)
            } else {
                lit.append(s[i])
                i = s.index(after: i)
            }
        }
        if !lit.isEmpty { parts.append(.literal(lit)) }
        return parts
    }

    /// オーサリングの短い form 名 → PersonReferenceForm。
    private static let formMap: [String: PersonReferenceForm] = [
        "name": .name,
        "possessive": .namePossessive,
        "subject": .subjectPronoun,
        "object": .objectPronoun,
        "posdet": .possessiveDeterminer,
        "vocative": .vocativeName
    ]
}
