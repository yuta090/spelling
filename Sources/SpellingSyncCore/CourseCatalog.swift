import Foundation

/// コース（学年×英検の2軸）のカタログ生成と練習抑制の純ロジック。
///
/// 設計: `docs/step-map-and-courses-spec-2026-06-29.md` §5 / `docs/eiken-level-mapping.md` §2 / 実装プラン。
/// - コースの単語は**永続化しない**（仮想カタログ）。アプリが wordbank の頻度順行(`LeveledRow`)を渡し、
///   ここで決定論的にステップ階段へ組む。語彙の難易度軸＝NGSL頻度（採用済み基準）。
/// - 英検帯は eiken-level-mapping のバンド範囲、学年帯はそのバンドを学年数で等分割して入れ子化。
/// - セッション/採点/満点は単語テキスト基準なので、合成語に**決定論ID**を与えれば既存ロジックがそのまま動く。

// MARK: - コース種別

/// 英検級（コース軸その1）。子には級ラベルを出さない（表示名はアプリ側 `Course.childTitle`）。
public enum EikenLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case g5   // 英検5級
    case g4   // 英検4級
    case g3   // 英検3級
    case p2   // 英検準2級

    /// NGSL rank 範囲（`docs/eiken-level-mapping.md` §2）。
    public var rankRange: ClosedRange<Int> {
        switch self {
        case .g5: return 1...500
        case .g4: return 501...1500
        case .g3: return 1501...2200
        case .p2: return 2201...2816
        }
    }

    public var courseID: String { "eiken-\(rawValue)" }
}

/// コース種別。`.eiken` は spec §5 の拡張軸。`.grade` は学年軸。`.personal` は既存の自分の単語トラック。
/// `.dolch` は Dolch サイトワード（よく出る基礎語）の土台コース（順序・フィルタは `DolchCourse.swift`）。
public enum CourseKind: Codable, Hashable, Sendable {
    case personal
    case grade(schoolGrade: Int)   // 1...9（小1…中3）
    case eiken(EikenLevel)
    case dolch                     // サイトワード（基礎語）コース
}

// MARK: - 学年帯（英検バンドの学年等分割）

/// 学年（小1〜中3）→ NGSL rank 範囲。英検バンドを、その tier に属する学年数で等分割して入れ子化する。
/// （公式の学年別語彙リストは無いため、採用済みの英検バンド＋段階対応を頻度で近似する。）
public enum GradeBand {
    /// tier ごとの (学年集合, 対応する英検バンド)。`StarterWords.GradeLevel.tier` の段階対応に一致。
    private static let tiers: [(grades: [Int], band: ClosedRange<Int>)] = [
        (grades: [1, 2],    band: EikenLevel.g5.rankRange),   // 入門
        (grades: [3, 4],    band: EikenLevel.g4.rankRange),
        (grades: [5, 6, 7], band: EikenLevel.g3.rankRange),
        (grades: [8, 9],    band: EikenLevel.p2.rankRange),
    ]

    public static func courseID(schoolGrade g: Int) -> String { "grade-\(g)" }

    /// 学年の rank 範囲（その tier のバンドを学年位置で等分割した連続区間）。
    public static func rankRange(schoolGrade g: Int) -> ClosedRange<Int> {
        guard let tier = tiers.first(where: { $0.grades.contains(g) }),
              let i = tier.grades.firstIndex(of: g) else {
            // 想定外の学年はフォールバック（5級帯先頭）。
            return EikenLevel.g5.rankRange
        }
        let n = tier.grades.count
        let lo = tier.band.lowerBound
        let total = tier.band.count
        // [lo, hi] を n 等分し、i 番目の連続区間を返す（整数分割・端は元バンドに一致）。
        let partLo = lo + (i * total) / n
        let partHiExclusive = lo + ((i + 1) * total) / n
        return partLo...(partHiExclusive - 1)
    }
}

// MARK: - 入出力

/// アプリが wordbank から供給する1行（頻度順の語＋訳）。
public struct LeveledRow: Equatable, Sendable {
    public let word: String
    public let gloss: String
    public let ngslRank: Int
    public init(word: String, gloss: String, ngslRank: Int) {
        self.word = word
        self.gloss = gloss
        self.ngslRank = ngslRank
    }
}

public struct CourseWord: Equatable, Sendable {
    public let text: String
    public let gloss: String
    public let ngslRank: Int
    public init(text: String, gloss: String, ngslRank: Int) {
        self.text = text
        self.gloss = gloss
        self.ngslRank = ngslRank
    }
}

public struct CourseStep: Equatable, Sendable {
    public let stepID: String
    public let index: Int            // コース内 0始まり
    public let words: [CourseWord]
    public init(stepID: String, index: Int, words: [CourseWord]) {
        self.stepID = stepID
        self.index = index
        self.words = words
    }
}

// MARK: - カタログ生成

public enum CourseCatalog {
    public static let defaultStepSize = 10

    /// 合成語の安定IDの名前空間（他の決定論IDと混ざらない専用値）。
    private static let wordNamespace = UUID(uuidString: "7E2C1B44-9A03-5C61-8D2E-3F4A5B6C7D80")!

    /// 範囲＋コースIDからステップ階段を決定論的に組む。
    /// フィルタ（機能語/短語/非英字/訳無し）→ 範囲抽出 →`(rank,word)`再ソート → `stepSize`分割。
    public static func buildSteps(rows: [LeveledRow],
                                  courseID: String,
                                  rankRange: ClosedRange<Int>,
                                  stepSize: Int = defaultStepSize) -> [CourseStep] {
        let size = stepSize > 0 ? stepSize : defaultStepSize
        let admissible = rows.filter { isAdmissible($0) && rankRange.contains($0.ngslRank) }
        let sorted = admissible.sorted { a, b in
            a.ngslRank != b.ngslRank ? a.ngslRank < b.ngslRank : a.word < b.word
        }
        let words = sorted.map { CourseWord(text: $0.word, gloss: $0.gloss, ngslRank: $0.ngslRank) }

        var steps: [CourseStep] = []
        var start = 0
        var idx = 0
        while start < words.count {
            let end = min(start + size, words.count)
            let stepID = "\(courseID).s\(String(format: "%02d", idx + 1))"
            steps.append(CourseStep(stepID: stepID, index: idx, words: Array(words[start..<end])))
            start = end
            idx += 1
        }
        return steps
    }

    public static func buildSteps(rows: [LeveledRow], eiken: EikenLevel,
                                  stepSize: Int = defaultStepSize) -> [CourseStep] {
        buildSteps(rows: rows, courseID: eiken.courseID, rankRange: eiken.rankRange, stepSize: stepSize)
    }

    public static func buildSteps(rows: [LeveledRow], schoolGrade g: Int,
                                  stepSize: Int = defaultStepSize) -> [CourseStep] {
        buildSteps(rows: rows, courseID: GradeBand.courseID(schoolGrade: g),
                   rankRange: GradeBand.rankRange(schoolGrade: g), stepSize: stepSize)
    }

    /// 合成語の安定ID（同コース・同綴りなら常に同一）。`ForEach(id:)`/`StepSignature` の安定化に使う。
    public static func wordStableID(courseID: String, text: String) -> UUID {
        DeterministicID.uuidV5(namespace: wordNamespace, components: [courseID, text.lowercased()])
    }

    /// 出題に適する語か（子の綴り練習に不向きなものを決定論的に除外）。
    static func isAdmissible(_ row: LeveledRow) -> Bool {
        let w = row.word
        guard w.count >= 3 else { return false }                       // 短すぎ（a/an/of/to…）
        guard w.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false } // 英字のみ
        guard !functionWords.contains(w.lowercased()) else { return false }     // 機能語
        guard !row.gloss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false } // 訳無し
        return true
    }

    /// 機能語ストップリスト（長さ≥3で残る冠詞/接続詞/代名詞/助動詞/限定詞/be・do・have 等）。
    /// 前置詞や一般副詞は綴り練習に使えるので原則残す。崩壊を防ぐ最小限に留める（後で調整可）。
    static let functionWords: Set<String> = [
        "the", "and", "but", "for", "nor", "yet", "not", "because", "while", "until",
        "unless", "although", "though", "however", "therefore", "whether",
        "are", "was", "were", "been", "being", "has", "had", "have", "does", "did",
        "can", "could", "will", "would", "shall", "should", "may", "might", "must", "ought",
        "you", "your", "yours", "his", "her", "hers", "its", "our", "ours", "their", "theirs",
        "them", "they", "she", "who", "whom", "whose", "which", "what",
        "this", "that", "these", "those", "there", "here",
        "than", "then", "too", "very", "just", "only", "also", "such",
        "some", "any", "all", "both", "each", "every", "other", "another",
        "more", "most", "much", "many", "few", "own", "same",
    ]
}

// MARK: - 練習抑制（マスター済みは練習で出さない／テストには出す）

public enum PracticeSelection {
    /// 練習ドリル用：抑制集合の語を除く。**テスト側は呼ばない**＝全語のまま。
    public static func practiceWords<W>(_ stepWords: [W],
                                        suppressed: Set<String>,
                                        keyOf: (W) -> String) -> [W] {
        stepWords.filter { !suppressed.contains(keyOf($0)) }
    }

    /// 練習ドリル用（既定選択向け）：抑制集合の語を除く。ただし**全部抑制されて空になる場合は
    /// 元の集合をそのまま返す**＝ステップ全語が既習（マスター済み）でも練習を“できなく”しない。
    /// （ホームのメイン大ボタンは常に練習。全抑制で空→無効化＝「練習できない」を防ぐ再ドリル許可。）
    /// 元が空（ステップに語が無い）なら空のまま返す。
    public static func practiceWordsAllowingRedrill<W>(_ stepWords: [W],
                                                       suppressed: Set<String>,
                                                       keyOf: (W) -> String) -> [W] {
        let filtered = stepWords.filter { !suppressed.contains(keyOf($0)) }
        return filtered.isEmpty ? stepWords : filtered
    }

    /// 練習から外す語キー（正規化テキスト）を**既存シグナルだけ**から決定論的に算出する。
    /// 新しい永続ストアは作らず、既存の missed/review 基盤（`ReviewQueue`）と二重管理しない。
    ///
    /// 抑制する＝「最新クリア」かつ「未解決でない」かつ「復習アクティブ（未マスター）でない」。
    /// - `latestClearedTexts`：各語の最新 attempt がクリア（ノーミス正解）の語。
    /// - `unresolvedTexts`：`unresolvedReviewWords` 由来（最新ミス／学校ミス）＝練習に戻す。
    /// - `activeReviewTexts`：`spellingReviewStates` で未マスターの語（復習中）＝卒業まで練習に残す。
    public static func suppressedPracticeKeys(latestClearedTexts: Set<String>,
                                              unresolvedTexts: Set<String>,
                                              activeReviewTexts: Set<String>) -> Set<String> {
        latestClearedTexts.subtracting(unresolvedTexts).subtracting(activeReviewTexts)
    }
}
