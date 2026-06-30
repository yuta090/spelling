import Foundation

/// Dolch サイトワード（よく出る基礎語）コースのカタログ生成（仮想・読み取り専用）。
///
/// 設計の核心（既存の学年/英検コースと違う点）:
/// - **難易度軸が NGSL 頻度ではなく Dolch 帯**（pre-K → K → 1 → 2 → 3 → noun）。名詞リストは最後。
/// - **機能語(the/and/you/this 等)を除外しない**。Dolch サイトワードはそれら自体が教材の中心なので、
///   `CourseCatalog.isAdmissible` の `functionWords` 除外や「長さ≥3」をそのまま適用すると教材が壊れる。
///   よって専用フィルタ（機能語を残す／長さ≥2／英字のみ／訳ありのみ／未知の帯は除外）を使う。
/// - 同梱 wordbank の `level.dolch` 列に値がある語（315語想定）をアプリが `DolchRow` で供給し、
///   ここで決定論的にステップ階段へ組む（入力順非依存）。

// MARK: - Dolch 帯（出題順）

/// Dolch 難易度帯。`rawValue` は wordbank `level.dolch` の値に一致する。
public enum DolchBand: String, CaseIterable, Codable, Hashable, Sendable {
    case preK = "pre-K"
    case k    = "K"
    case g1   = "1"
    case g2   = "2"
    case g3   = "3"
    case noun = "noun"   // Dolch 名詞リスト（学年帯ではない・最後に回す）

    /// 出題順（小さいほど先）。pre-K → K → 1 → 2 → 3 → noun。
    public var order: Int {
        switch self {
        case .preK: return 0
        case .k:    return 1
        case .g1:   return 2
        case .g2:   return 3
        case .g3:   return 4
        case .noun: return 5
        }
    }
}

// MARK: - 入力行

/// アプリが wordbank から供給する Dolch 1行（語＋訳＋Dolch帯生値）。
public struct DolchRow: Equatable, Sendable {
    public let word: String
    public let gloss: String
    public let dolch: String   // 生値（"pre-K"/"K"/"1"/.../"noun"）。未知値は除外される。
    public init(word: String, gloss: String, dolch: String) {
        self.word = word
        self.gloss = gloss
        self.dolch = dolch
    }
}

// MARK: - カタログ生成（CourseCatalog 拡張）

public extension CourseCatalog {
    /// Dolch コースの固定 courseID（合成語の安定IDの名前空間にも使う）。
    static let dolchCourseID = "dolch"

    /// Dolch 行からステップ階段を決定論的に組む。
    /// フィルタ（未知帯/短語/非英字/訳無しを除外・機能語は**残す**）→ `(帯順, 語)` ソート → `stepSize` 分割。
    static func buildDolchSteps(rows: [DolchRow], stepSize: Int = defaultStepSize) -> [CourseStep] {
        let size = stepSize > 0 ? stepSize : defaultStepSize

        // (band, row) に解決しつつフィルタ。未知の dolch 帯はここで落ちる。
        let resolved: [(band: DolchBand, row: DolchRow)] = rows.compactMap { row in
            guard let band = DolchBand(rawValue: row.dolch), isDolchAdmissible(row) else { return nil }
            return (band, row)
        }
        let sorted = resolved.sorted { a, b in
            a.band.order != b.band.order ? a.band.order < b.band.order : a.row.word < b.row.word
        }
        // 帯は ngslRank の表示に流用しない（順序は WordStep.number が握る）。表示用に帯順を入れておく。
        let words = sorted.map { CourseWord(text: $0.row.word, gloss: $0.row.gloss, ngslRank: $0.band.order) }

        var steps: [CourseStep] = []
        var start = 0
        var idx = 0
        while start < words.count {
            let end = min(start + size, words.count)
            let stepID = "\(dolchCourseID).s\(String(format: "%02d", idx + 1))"
            steps.append(CourseStep(stepID: stepID, index: idx, words: Array(words[start..<end])))
            start = end
            idx += 1
        }
        return steps
    }

    /// Dolch 出題に適する語か（機能語は**残す**専用フィルタ）。
    /// 長さ≥2（"a"/"I" 等の1文字は外す）・英字のみ・訳あり。`functionWords` 除外は**しない**。
    static func isDolchAdmissible(_ row: DolchRow) -> Bool {
        let w = row.word
        guard w.count >= 2 else { return false }                               // 1文字（a/I）は外す
        guard w.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false } // 英字のみ
        guard !row.gloss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false } // 訳無し
        return true
    }
}
