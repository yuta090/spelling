import Foundation

/// 永続化キーの名前空間化。子ども別キーは `profiles/<profileID>/<key>` に prefix し、
/// 世帯/端末グローバルなキー（サブスク・デバッグ・同期簿記・台帳）は素通しする。
///
/// このリストは **移行のコピー対象**・**`ProfileScopedStore` の分類**・**テスト**で共有する
/// 単一のソース（キー分類の二重管理ズレを防ぐ）。設計 §3。
/// 未分類キーは安全側で prefix する（プロファイル間のデータ漏れを防ぐ）。
public enum ProfileKeyScope {
    /// 子ども別（プロファイルごとに分ける＝移行時に `profiles/<id1>/` へコピーする）キー。
    public static let childScopedKeys: Set<String> = [
        "spellingTrainer.words",
        "spellingTrainer.attempts",
        "spellingTrainer.practiceSamples",
        "spellingTrainer.schoolTestResults",
        "spellingTrainer.settings",
        "spellingTrainer.selectedWordStepID",      // 旧 single-track（移行元）
        "spellingTrainer.selectedCourseID",
        "spellingTrainer.selectedStepIDByCourse",
        "spellingTrainer.childCanSwitchCourses",
        "spellingTrainer.allowedCourseIDs",
        "spellingTrainer.requiredCompletion",
        "spellingTrainer.rewardCoins",             // 旧コイン単位（移行元・不変）
        "spellingTrainer.rewardCoins.v2",
        "spellingTrainer.loginStreak",
        "spellingTrainer.lastLoginDay",
        "spellingTrainer.lastPerfectBonusDay",
        "spellingTrainer.puzzleLastPlayedDay",
        "spellingTrainer.puzzlePlaysToday",
        "spellingTrainer.selectedCharacterID",
        "spellingTrainer.unlockedCharacterIDs",
        "spellingTrainer.selectedBackgroundID",
        "spellingTrainer.unlockedBackgroundIDs",
        "spellingTrainer.homeReviewWordIDs",
        "spellingTrainer.usageLog",
        "spellingTrainer.grammarReviewStates",
        "spellingTrainer.grammarReviewStep",
        "spellingTrainer.spellingReviewStates",
        "spellingTrainer.spellingReviewStep",
        "spellingTrainer.spellingReviewSeeded",
        "spellingTrainer.hasCompletedOnboarding",  // 新しい子は名前/学年のミニ設定を通す
        "spellingTrainer.hasShownHomeCharacterHint",
        "spellingTrainer.stepUnlockCelebration",
        "spellingTrainer.childName",               // → ChildProfile.displayName へ移行（§4）
        "spellingTrainer.selectedGrade",
        "spellingTrainer.cast",                     // 本人実名＝プロファイル別・ローカルのみ
        "spellingTrainer.aiJudgments",              // DEBUG のみ。子のテスト答案のAI採点記録＝子ども別
        "spellingTrainer.aiJudgeConfig",            // DEBUG のみ。AI判定の実行パラメータ（子ども別に持つ）
        "spellingTrainer.sync.wordSidecar",         // 同期簿記はプロファイル別（Phase 5：子ごとに独立した dirty 基準/tombstone 台帳）
        "spellingTrainer.sync.cursors"              // 同上：pull/push カーソルも子ごとに独立
    ]

    /// 世帯/端末グローバル（prefix しない）キー。
    public static let globalKeys: Set<String> = [
        "spellingTrainer.cachedEntitlement",        // サブスクは家族＝世帯単位（§7）
        "spellingTrainer.debugUnlockAll",
        "spellingTrainer.debugDisableDailyLimit",
        "spellingTrainer.debugAIJudgeOnTest",       // DEBUG のみ。端末のデバッグトグル（他 debug フラグと同じく端末単位）
        "spellingTrainer.migratedFromSwiftData.v1", // 端末の移行フラグ
        "spellingTrainer.sync.activeHouseholdID",   // 「今どの世帯か」は端末単位（子で分けない）
        "spellingTrainer.sync.wordRemoteOwnerProfileID", // 世帯NULLストリームのオーナー（元の単一子）。端末単位・再割当なし（Phase 5）
        "spellingTrainer.profiles",                 // 台帳そのもの（端末）
        "spellingTrainer.activeProfileID",
        "spellingTrainer.migratedToProfiles.v1"     // プロファイル移行フラグ
    ]

    /// 与えたキーを、アクティブプロファイルのスコープへ写像する。
    /// グローバルキーは素通し、それ以外（未分類含む）は `profiles/<profileID>/<key>`。
    public static func scopedKey(_ key: String, profileID: UUID) -> String {
        guard !globalKeys.contains(key) else { return key }
        return "profiles/\(profileID.uuidString)/\(key)"
    }
}
