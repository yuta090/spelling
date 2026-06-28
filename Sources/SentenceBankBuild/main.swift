import Foundation
import SpellingSyncCore

// 文バンク前処理ツール（開発時のみ・薄い IO）。
// 役割: curated 素（person_templates の承認済みフォールバック文）を読み、wordbank から
//   band（NGSL）を取り、Core（SentenceBankBuilder）で学年タグ付け検証し、レポートを出し、
//   同梱 sentence_bank.json を書き出す。判定本体は Core（TDD 済み）。ここは入出力だけ。
//
// 使い方（リポジトリ直下から）:
//   swift run sentence-bank-build [--target-band N] [--grammar-ceiling STAGE] [--max-tokens N] [--write]
//   既定: 全 band・全文法段階を許容（=同梱バンクは“素材は全部入れる”。子ごとの絞り込みは実行時）。
//   読むだけ＋レポート表示。--write で同梱 JSON を書き出す。
//
// 既定パス:
//   curated : scripts/person_templates.authoring.json（fallbackEn/Ja/grammar/contentLemmas を使用）
//   wordbank: iPadPrototype/Resources/wordbank.sqlite
//   blocklist(任意): scripts/sentence_blocklist.txt（1行1語・# でコメント）
//   output  : iPadPrototype/Resources/sentence_bank.json

struct Paths {
    var curated = "scripts/person_templates.authoring.json"
    var wordbank = "iPadPrototype/Resources/wordbank.sqlite"
    var blocklist = "scripts/sentence_blocklist.txt"
    var output = "iPadPrototype/Resources/sentence_bank.json"
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

// MARK: - 引数

let args = CommandLine.arguments
var targetBand = 5                       // 既定: 全 band（同梱は素材を全部入れる）
var grammarCeiling: GrammarStage = .applied  // 既定: 全文法段階
var maxTokens = 10
var doWrite = false
do {
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--target-band":
            i += 1
            guard i < args.count, let b = Int(args[i]) else { fail("--target-band には整数を指定してください") }
            targetBand = b
        case "--grammar-ceiling":
            i += 1
            guard i < args.count, let s = parseStage(args[i]) else {
                fail("--grammar-ceiling は intro1/intro2/basic1/basic2/applied のいずれか")
            }
            grammarCeiling = s
        case "--max-tokens":
            i += 1
            guard i < args.count, let n = Int(args[i]), n >= 2 else { fail("--max-tokens には2以上の整数を") }
            maxTokens = n
        case "--write":
            doWrite = true
        default:
            fail("未知の引数: \(args[i])（--target-band N / --grammar-ceiling STAGE / --max-tokens N / --write）")
        }
        i += 1
    }
}

func parseStage(_ s: String) -> GrammarStage? {
    switch s.lowercased() {
    case "intro1": return .intro1
    case "intro2": return .intro2
    case "basic1": return .basic1
    case "basic2": return .basic2
    case "applied": return .applied
    default: return nil
    }
}

let paths = Paths()

// MARK: - sqlite ヘルパ（外部 sqlite3。SQLite3 リンク不要）

func runSQLite(_ db: String, _ query: String) -> [String] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    proc.arguments = ["-noheader", "-separator", "\t", db, query]
    let pipe = Pipe()
    proc.standardOutput = pipe
    do { try proc.run() } catch { fail("sqlite3 を実行できません: \(error). wordbank: \(db)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { fail("sqlite3 がエラー終了（status \(proc.terminationStatus)）") }
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

// MARK: - curated 素（person_templates の承認済みフォールバック文）

/// person_templates.authoring.json の必要フィールドだけ拾う。
struct PersonTemplateRow: Decodable {
    var id: String?
    var grammar: String?
    var gradeBand: Int?
    var fallbackEn: [String]?
    var fallbackJa: String?
}

guard let curatedData = FileManager.default.contents(atPath: paths.curated) else {
    fail("curated 素を読めません: \(paths.curated)（リポジトリ直下から実行してください）")
}
let rows: [PersonTemplateRow]
do {
    rows = try JSONDecoder().decode([PersonTemplateRow].self, from: curatedData)
} catch {
    fail("curated 素の JSON 解析に失敗: \(error)")
}

var candidates: [SentenceBankBuilder.Candidate] = []
for row in rows {
    guard let en = row.fallbackEn, !en.isEmpty, let ja = row.fallbackJa else { continue }
    let rowID = row.id ?? "(id不明)"
    // 文法タグは打ち間違いを黙って無効化しない（nil=制約なしと typo を区別する）。
    var grammar: GrammarPoint?
    if let g = row.grammar {
        guard let parsed = GrammarPoint(rawValue: g) else {
            fail("未知の grammar タグ: \"\(g)\"（row \(rowID)）。GrammarPoint の rawValue を確認してください")
        }
        grammar = parsed
    }
    // 宣言バンドは 1...5 の範囲のみ信頼する（typo を弾く）。
    if let b = row.gradeBand, !(1...5).contains(b) {
        fail("gradeBand は 1...5 で指定してください（row \(rowID) の \(b)）")
    }
    candidates.append(.init(
        en: en.joined(separator: " "),
        ja: ja,
        grammar: grammar,
        declaredBand: row.gradeBand,
        source: "curated"
    ))
}
guard !candidates.isEmpty else { fail("curated 候補が0件（fallbackEn/Ja を確認）") }

// MARK: - wordbank band / blocklist

guard FileManager.default.fileExists(atPath: paths.wordbank) else {
    fail("wordbank がありません: \(paths.wordbank)")
}
var band: [String: Int] = [:]
for r in runSQLite(paths.wordbank, "SELECT lower(word), band FROM level WHERE band IS NOT NULL") {
    let cols = r.split(separator: "\t", maxSplits: 1).map(String.init)
    if cols.count == 2, let b = Int(cols[1]) { band[cols[0]] = b }
}

var blocklist: Set<String> = []
if let text = try? String(contentsOfFile: paths.blocklist, encoding: .utf8) {
    for line in text.split(separator: "\n") {
        let w = line.trimmingCharacters(in: .whitespaces).lowercased()
        if !w.isEmpty && !w.hasPrefix("#") { blocklist.insert(w) }
    }
}

// MARK: - 検証

let result = SentenceBankBuilder.build(
    candidates: candidates,
    band: band,
    targetBand: targetBand,
    grammarCeiling: grammarCeiling,
    blocklist: blocklist,
    maxTokens: maxTokens
)

// MARK: - レポート

print("=== 文バンク前処理レポート ===")
print("curated 候補: \(candidates.count)  /  wordbank band: \(band.count)語  /  blocklist: \(blocklist.count)語")
print("対象band ≤ \(targetBand)  /  文法上限 ≤ \(grammarCeiling.cefrJ)(\(grammarCeiling.gradeLabelJa))  /  最大トークン \(maxTokens)")
print("採用: \(result.accepted.count)  /  不採用: \(result.rejected.count)  /  警告: \(result.warnings.count)")

// band 分布。
var dist: [Int: Int] = [:]
for it in result.accepted { dist[it.gradeBand, default: 0] += 1 }
if !dist.isEmpty {
    let s = dist.sorted { $0.key < $1.key }.map { "band\($0.key):\($0.value)" }.joined(separator: " ")
    print("採用の学年分布: \(s)")
}

if !result.rejected.isEmpty {
    print("\n--- ⚠ 不採用（理由つき・素を直すか辞書整備を検討） ---")
    for r in result.rejected {
        let why: String
        switch r.reason {
        case .emptyText:                   why = "英文が空"
        case .tooFewTokens:                why = "2語未満"
        case .tooManyTokens(let n):        why = "長すぎ（\(n)語 > \(maxTokens)）"
        case .unleveledContentWord(let w): why = "level未収録の内容語: \(w)"
        case .overTargetBand(let w, let b):why = "対象band超: \(w)(band\(b))"
        case .grammarOverCeiling(let s):   why = "文法が上限超: \(s.cefrJ)"
        case .blockedWord(let w):          why = "不適切語: \(w)"
        case .duplicate:                   why = "重複"
        }
        print("  \(r.en) — \(why)")
    }
}

if !result.warnings.isEmpty {
    print("\n--- ⚠ 警告（採用は維持・level 整備の検討用） ---")
    var missing: Set<String> = []
    for w in result.warnings {
        switch w.kind {
        case .contentWordNotLeveled(let token): missing.insert(token)
        }
    }
    print("  ・level 未収録だが著者バンドで採用した内容語: \(missing.sorted().joined(separator: ", "))")
}

// MARK: - 書き出し

let jsonOut = SentenceBankBuilder.serialize(result.accepted)
if doWrite {
    do {
        try jsonOut.write(toFile: paths.output, atomically: true, encoding: .utf8)
        let excluded = result.rejected.isEmpty ? "" : "・\(result.rejected.count)文を除外（上の不採用一覧を確認）"
        print("\n✅ 書き出し: \(paths.output)（\(result.accepted.count)文\(excluded)）")
    } catch {
        fail("出力を書けません: \(paths.output) — \(error)")
    }
} else {
    print("\n(プレビュー。書き出すには --write を付けてください → \(paths.output))")
}
