import Foundation

/// 親の単語“管理”で、あるステップを **その場で編集できるか** を判定する純ロジック。
///
/// 背景（`docs/multi-user-cloudkit-sync-design.md` / CLAUDE.md 親側方針）：
/// 親がコースを選ぶと、子と同じ「コース連動のステップ（`wordSteps`）」を見せる。ただしその中身は
/// - **合成コースの読み取り専用ステップ**（wordbank から生成・非永続）
/// - **`linked.` 差し込みステップ**（表示用に `stepID` を振り直した合成ラダー上の見せかけ）
/// - **自分の登録語（personal）のステップ**（保管とID が1:1で対応＝安全に編集できる）
/// が混在する。前2者は保管（`words`）と `stepID` が1:1で対応しないため、その表示ステップを
/// そのまま `replaceWords(in:)` に渡すと**別IDの語を新規作成して保管を壊す**。よって編集は
/// **personal トラックに実在するステップだけ**に限定する（他は読み取り表示）。
///
/// 判定基準は明快に「そのステップID が自分の単語トラックのステップID集合に含まれるか」。
public enum StepEditability {
    /// - Parameters:
    ///   - stepID: 表示中ステップの ID（`WordStep.id`）。
    ///   - personalStepIDs: 自分の登録語から導出した personal ステップの ID 集合。
    /// - Returns: personal トラックに実在すれば true（＝安全に編集可）。合成/紐付け表示ステップは false。
    public static func isEditable(stepID: String, personalStepIDs: Set<String>) -> Bool {
        personalStepIDs.contains(stepID)
    }
}
