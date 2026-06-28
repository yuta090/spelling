import Foundation
import SpellingSyncCore

// Tanaka 例文抽出ツール（開発時のみ・薄い IO）。
// 役割: wordbank の examples（Tanaka 英日6万・子ども不適切除外済）から条件に合う短文を
//   機械抽出し、判定本体（TanakaExtractor → SentenceBankBuilder）で検査して、既存の
//   sentence_bank.json（curated 47 文）に **決定論で追記マージ** する。判定は Core（TDD済）。ここは入出力だけ。
//
// 使い方（リポジトリ直下から）:
//   swift run tanaka-extract-build [--target-band N] [--min-tokens N] [--max-tokens N] [--limit N] [--write]
//   読むだけ＋レポート表示。--write で sentence_bank.json に追記マージ。
//   再実行で git 差分が増えないこと（決定論・既存重複は除外）。
//
// 既定パス:
//   wordbank : iPadPrototype/Resources/wordbank.sqlite（examples / level）
//   blocklist(任意): scripts/sentence_blocklist.txt（1行1語・# でコメント）
//   output(マージ先): iPadPrototype/Resources/sentence_bank.json（既存 curated を保持して追記）

struct Paths {
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
var targetBand = 5
var minTokens = 3
var maxTokens = 10
var limit: Int? = nil
var doWrite = false
do {
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--target-band":
            i += 1
            guard i < args.count, let b = Int(args[i]) else { fail("--target-band には整数を指定してください") }
            targetBand = b
        case "--min-tokens":
            i += 1
            guard i < args.count, let n = Int(args[i]), n >= 2 else { fail("--min-tokens には2以上の整数を") }
            minTokens = n
        case "--max-tokens":
            i += 1
            guard i < args.count, let n = Int(args[i]), n >= 2 else { fail("--max-tokens には2以上の整数を") }
            maxTokens = n
        case "--limit":
            i += 1
            guard i < args.count, let n = Int(args[i]), n >= 1 else { fail("--limit には1以上の整数を") }
            limit = n
        case "--write":
            doWrite = true
        default:
            fail("未知の引数: \(args[i])（--target-band N / --min-tokens N / --max-tokens N / --limit N / --write）")
        }
        i += 1
    }
}
guard minTokens <= maxTokens else { fail("--min-tokens は --max-tokens 以下にしてください") }

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

// MARK: - band / blocklist / 既存バンク

guard FileManager.default.fileExists(atPath: paths.wordbank) else {
    fail("wordbank がありません: \(paths.wordbank)（リポジトリ直下から実行してください）")
}
var band: [String: Int] = [:]
for r in runSQLite(paths.wordbank, "SELECT lower(word), band FROM level WHERE band IS NOT NULL") {
    let cols = r.split(separator: "\t", maxSplits: 1).map(String.init)
    if cols.count == 2, let b = Int(cols[1]) { band[cols[0]] = b }
}
guard !band.isEmpty else { fail("level バンドが0件（wordbank を確認）") }

var blocklist: Set<String> = []
if let text = try? String(contentsOfFile: paths.blocklist, encoding: .utf8) {
    for line in text.split(separator: "\n") {
        let w = line.trimmingCharacters(in: .whitespaces).lowercased()
        if !w.isEmpty && !w.hasPrefix("#") { blocklist.insert(w) }
    }
}

// 既存 sentence_bank.json（curated 47 文）。これがマージのベース。重複除外キーも取る。
guard let existingData = FileManager.default.contents(atPath: paths.output),
      let existingText = String(data: existingData, encoding: .utf8) else {
    fail("既存バンクを読めません: \(paths.output)（先に sentence-bank-build で生成してください）")
}
let existingItems = SentenceBankBuilder.decode(json: existingText)
guard !existingItems.isEmpty else { fail("既存バンクが0件（\(paths.output) を確認）") }
// 既存の正規化キー（curated は en==tokens 結合なので normalizedKey(en) で一致する）。
let existingKeys = Set(existingItems.map { TanakaExtractor.normalizedKey($0.en) })

// MARK: - Tanaka 行（distinct en・ja は決定論に MIN・制御文字は空白化）

let san = "replace(replace(replace(%@, char(9),' '), char(10),' '), char(13),' ')"
let enExpr = san.replacingOccurrences(of: "%@", with: "en")
let jaExpr = san.replacingOccurrences(of: "%@", with: "ja")
let query = """
SELECT \(enExpr) AS e, MIN(\(jaExpr)) AS j
FROM examples
WHERE en IS NOT NULL AND trim(en) <> ''
GROUP BY en
"""
var rows: [TanakaExtractor.Row] = []
for line in runSQLite(paths.wordbank, query) {
    let cols = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    guard cols.count == 2 else { continue }
    let en = cols[0].trimmingCharacters(in: .whitespaces)
    let ja = cols[1].trimmingCharacters(in: .whitespaces)
    if en.isEmpty || ja.isEmpty { continue }
    rows.append(.init(en: en, ja: ja))
}
guard !rows.isEmpty else { fail("examples から行を取得できませんでした") }

// MARK: - 抽出（判定本体は Core）

let out = TanakaExtractor.extract(
    rows: rows, band: band, targetBand: targetBand,
    existingKeys: existingKeys, blocklist: blocklist,
    minTokens: minTokens, maxTokens: maxTokens, limit: limit)

// MARK: - レポート

// 事前却下を理由ごとに集計。
var preCounts: [String: Int] = [:]
for pr in out.preRejected {
    let k: String
    switch pr.reason {
    case .tooFewTokens:        k = "短すぎ(<\(minTokens))"
    case .tooManyTokens:       k = "長すぎ(>\(maxTokens))"
    case .disallowedCharacters: k = "記号/数字過多"
    case .mostlyProperNouns:   k = "固有名詞だらけ"
    case .kidUnsafe:           k = "子ども安全ブロック"
    case .duplicateInBatch:    k = "バッチ内重複"
    }
    preCounts[k, default: 0] += 1
}
// Core 却下を理由ごとに集計。
var coreCounts: [String: Int] = [:]
for r in out.builderResult.rejected {
    let k: String
    switch r.reason {
    case .emptyText:            k = "空文"
    case .tooFewTokens:         k = "2語未満"
    case .tooManyTokens:        k = "長すぎ"
    case .unleveledContentWord: k = "level未収録語"
    case .overTargetBand:       k = "対象band超"
    case .grammarOverCeiling:   k = "文法上限超"
    case .blockedWord:          k = "ブロック語"
    case .duplicate:            k = "重複"
    }
    coreCounts[k, default: 0] += 1
}

print("=== Tanaka 例文抽出レポート ===")
print("examples distinct en: \(out.totalRows)  /  level band: \(band.count)語  /  blocklist: \(blocklist.count)語  /  既存バンク: \(existingItems.count)文")
print("対象band ≤ \(targetBand)  /  トークン \(minTokens)..\(maxTokens)  /  limit: \(limit.map(String.init) ?? "なし")")
print("事前フィルタ: 通過 \(out.passedPreFilter)  /  却下 \(out.preRejected.count)")
if !preCounts.isEmpty {
    print("  事前却下内訳: " + preCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " / "))
}
print("Core検査: 採用 \(out.builderResult.accepted.count)  /  却下 \(out.builderResult.rejected.count)")
if !coreCounts.isEmpty {
    print("  Core却下内訳: " + coreCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " / "))
}
// サンプリング/打ち切りは黙らない（skill 手順B2）。
print("採用集計: \(out.totalRows)候補中 \(out.accepted.count)件採用・既存重複 \(out.duplicateExisting)件除外・limit打ち切り \(out.cappedOut)件")

// 新規採用の band 分布。
var dist: [Int: Int] = [:]
for it in out.accepted { dist[it.gradeBand, default: 0] += 1 }
if !dist.isEmpty {
    let s = dist.sorted { $0.key < $1.key }.map { "band\($0.key):\($0.value)" }.joined(separator: " ")
    print("新規採用の学年分布: \(s)")
}
print("マージ後の総文数: \(existingItems.count + out.accepted.count)（既存 \(existingItems.count) + 新規 \(out.accepted.count)）")

// MARK: - 書き出し（既存を保持して追記マージ）

let merged = existingItems + out.accepted
let jsonOut = SentenceBankBuilder.serialize(merged)
if doWrite {
    do {
        try jsonOut.write(toFile: paths.output, atomically: true, encoding: .utf8)
        print("\n✅ 書き出し: \(paths.output)（\(merged.count)文）")
        print("   ※ もう一度 --write して git diff が増えなければ決定論OK（既存重複は除外されます）。")
    } catch {
        fail("出力を書けません: \(paths.output) — \(error)")
    }
} else {
    print("\n(プレビュー。書き出すには --write を付けてください → \(paths.output))")
}
