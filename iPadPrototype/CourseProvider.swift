import Foundation
import SpellingSyncCore

/// 学年/英検コースの仮想ステップを wordbank から合成する（**読み取り専用・非永続**）。
/// 合成 `SpellingWord` は `words` 配列に入れない＝同期しない。決定論ID（`CourseCatalog.wordStableID`）で
/// `ForEach(id:)`/`StepSignature` を安定させる。`.personal` は既存 `makeWordSteps` が担うのでここでは扱わない。
@MainActor
final class CourseProvider {
    private let wordBank: WordBank
    private var rowsCache: [LeveledRow]?
    private var stepsCache: [String: [WordStep]] = [:]

    /// 合成語の登録日時（固定＝決定論。順序は `WordStep.number` で制御するので実値は表示用のみ）。
    private static let epoch = Date(timeIntervalSince1970: 0)

    init(wordBank: WordBank = .shared) { self.wordBank = wordBank }

    private func rows() -> [LeveledRow] {
        if let rowsCache { return rowsCache }
        let r = wordBank.rankedLeveledRows()
        rowsCache = r
        return r
    }

    /// コースのステップ（合成）。`.personal` は空（呼び出し側が `makeWordSteps` を使う）。
    func steps(for course: Course) -> [WordStep] {
        if let cached = stepsCache[course.id] { return cached }
        let built: [CourseStep]
        switch course.kind {
        case .personal:
            return []
        case .grade(let g):
            built = CourseCatalog.buildSteps(rows: rows(), schoolGrade: g)
        case .eiken(let lv):
            built = CourseCatalog.buildSteps(rows: rows(), eiken: lv)
        }
        let steps = built.map { cs in
            let words = cs.words.map { cw in
                SpellingWord(
                    id: CourseCatalog.wordStableID(courseID: course.id, text: cw.text),
                    text: cw.text,
                    promptText: cw.gloss,
                    registeredAt: Self.epoch,
                    stepID: cs.stepID,
                    source: .parent
                )
            }
            return WordStep(id: cs.stepID, number: cs.index + 1,
                            registeredDate: Self.epoch, words: words,
                            isChildStep: false, childNumber: nil)
        }
        stepsCache[course.id] = steps
        return steps
    }
}
