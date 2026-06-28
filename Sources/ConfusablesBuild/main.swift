import Foundation
import SpellingSyncCore

// confusables_sound 辞書のビルド/検証ツール（開発時のみ・薄い IO）。
// 役割: draft CSV を読み、wordbank から「実在語/band」を取り、Core の検証
//   （ConfusablesValidator）にかけ、レポートを表示し、同梱 CSV を書き出す。
// 検証ルール本体は Core（TDD 済み）。ここはファイル/sqlite の入出力だけ。
//
// 使い方（リポジトリ直下から）:
//   swift run confusables-build [--target-band N] [--write]
//   既定: 読むだけ＋レポート表示。--write で同梱 CSV を書き出す。
//
// 既定パス:
//   draft   : scripts/confusables_sound_draft.csv
//   wordbank: iPadPrototype/Resources/wordbank.sqlite
//   output  : iPadPrototype/Resources/confusables_sound.build.csv

struct Paths {
    var draft = "scripts/confusables_sound_draft.csv"
    var wordbank = "iPadPrototype/Resources/wordbank.sqlite"
    var output = "iPadPrototype/Resources/confusables_sound.build.csv"
}

// MARK: - 引数

let args = CommandLine.arguments
var targetBand: Int?
var doWrite = false
do {
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--target-band":
            i += 1
            guard i < args.count, let b = Int(args[i]) else {
                fail("--target-band には整数を指定してください")
            }
            targetBand = b
        case "--write":
            doWrite = true
        default:
            fail("未知の引数: \(args[i])（--target-band N / --write）")
        }
        i += 1
    }
}

let paths = Paths()

// MARK: - sqlite ヘルパ（外部 sqlite3 を呼ぶ。SQLite3 リンク不要）

func runSQLite(_ db: String, _ query: String) -> [String] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    proc.arguments = ["-noheader", "-separator", "\t", db, query]
    let pipe = Pipe()
    proc.standardOutput = pipe
    do {
        try proc.run()
    } catch {
        fail("sqlite3 を実行できません: \(error). wordbank: \(db)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        fail("sqlite3 がエラー終了（status \(proc.terminationStatus)）。wordbank: \(db)")
    }
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

// MARK: - 入力読み込み

guard let csvText = try? String(contentsOfFile: paths.draft, encoding: .utf8) else {
    fail("draft CSV を読めません: \(paths.draft)（リポジトリ直下から実行してください）")
}
let entries = ConfusablesSound.parse(csv: csvText)

guard FileManager.default.fileExists(atPath: paths.wordbank) else {
    fail("wordbank がありません: \(paths.wordbank)")
}
// 実在語（gloss・広い辞書）と band（level）。
let known = Set(runSQLite(paths.wordbank, "SELECT lower(word) FROM gloss").map { $0.lowercased() })
var band: [String: Int] = [:]
for row in runSQLite(paths.wordbank, "SELECT lower(word), band FROM level WHERE band IS NOT NULL") {
    let cols = row.split(separator: "\t", maxSplits: 1).map(String.init)
    if cols.count == 2, let b = Int(cols[1]) { band[cols[0]] = b }
}

// MARK: - 検証

let result = ConfusablesValidator.validate(entries: entries, known: known,
                                           band: band, targetBand: targetBand)

// MARK: - レポート

print("=== confusables_sound ビルド検証レポート ===")
print("入力行: \(entries.count)  /  wordbank: gloss \(known.count)語・band \(band.count)語"
      + (targetBand.map { "  /  対象band: \($0)" } ?? "  /  対象band: なし(band警告なし)"))
print("採用(approved=1・規則通過): \(result.accepted.count)")
print("未承認で対象外(approved=0): \(result.excludedUnapprovedCount)")
print("却下(要修正): \(result.rejected.count)")

if !result.rejected.isEmpty {
    print("\n--- ❌ 却下（ハード規則違反・直してください） ---")
    for r in result.rejected {
        let why: String
        switch r.reason {
        case .tooFewDistractors:  why = "おとりが2語未満（自己参照/重複の除去後）"
        case .tooManyDistractors: why = "おとりが5語以上（2〜4個にしてください）"
        case .emptyWord:          why = "見出し語が空"
        case .duplicateHeadword:  why = "見出し語が二重登録（先の行を採用済み）"
        case .invalidToken(let t): why = "CSVを壊す文字を含む語: \(t)"
        }
        print("  \(r.word): \(why)")
    }
}

if !result.warnings.isEmpty {
    print("\n--- ⚠ 警告（削除はしません・辞書に足すか/ペアを直すか確認） ---")
    // 種類ごとにまとめる。
    var notInBank: [String: Set<String>] = [:]   // 行語 -> 欠落語
    var bandUnknown: Set<String> = []
    var bandOver: [(String, Int)] = []
    for w in result.warnings {
        switch w.kind {
        case .notInWordbank(let token): notInBank[w.word, default: []].insert(token)
        case .bandUnknown(let token):   bandUnknown.insert(token)
        case .bandOverTarget(let token, let b): bandOver.append((token, b))
        }
    }
    if !notInBank.isEmpty {
        let allMissing = Set(notInBank.values.flatMap { $0 }).sorted()
        print("  ・wordbank(gloss)に無い語: \(allMissing.joined(separator: ", "))")
        for (row, miss) in notInBank.sorted(by: { $0.key < $1.key }) {
            print("      \(row): \(miss.sorted().joined(separator: ", "))")
        }
    }
    if !bandUnknown.isEmpty {
        print("  ・band不明(level未収録): \(bandUnknown.sorted().joined(separator: ", "))")
    }
    if !bandOver.isEmpty {
        let s = bandOver.sorted { $0.0 < $1.0 }.map { "\($0.0)(band\($0.1))" }.joined(separator: ", ")
        print("  ・対象band超過: \(s)")
    }
}

// MARK: - 書き出し

let csvOut = ConfusablesValidator.serialize(result.accepted)
if doWrite {
    // 却下（ハード規則違反）があるうちは書き出さない。部分的な同梱データを作らない。
    guard result.rejected.isEmpty else {
        fail("却下 \(result.rejected.count) 件があるため書き出しません。上の却下を直してから再実行してください。")
    }
    do {
        try csvOut.write(toFile: paths.output, atomically: true, encoding: .utf8)
        print("\n✅ 書き出し: \(paths.output)（\(result.accepted.count)行）")
    } catch {
        fail("出力を書けません: \(paths.output) — \(error)")
    }
} else {
    print("\n(プレビュー。書き出すには --write を付けてください → \(paths.output))")
    if !result.rejected.isEmpty {
        print("  ※ 却下 \(result.rejected.count) 件あり。--write しても書き出されません（先に修正を）。")
    }
}
