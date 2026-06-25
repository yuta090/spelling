import Foundation

/// 親採点（レビュー）の状態。アプリの `ParentReviewDecision` に対応する同期コア側の表現。
public enum ParentReviewState: String, Codable, Sendable {
    case unreviewed
    case approved
    case needsPractice
}

/// 親レビューの対象になりうる項目（子の答案 = Attempt など）。
/// 同期コアをアプリのドメイン型に依存させないため、必要な性質だけを抽象化する。
public protocol ReviewableItem {
    /// 自動採点で「親の確認が必要」と判定されたか（例: GradeDecision.needsReview）。
    var requiresParentReview: Bool { get }
    /// 親採点の現在の状態。
    var parentReviewState: ParentReviewState { get }
}

/// セッションの親採点進捗。CloudKit 設計の `ReviewRequest.pendingCount` 算出に使う。
///
/// 「採点待ち」 = 親の確認が必要 かつ まだ未採点（`unreviewed`）。
/// 自動で正誤が確定した項目（確認不要）は採点待ちに含めない。
public enum ReviewProgress {
    /// 親の採点待ち件数。
    public static func pendingCount<I: ReviewableItem>(_ items: [I]) -> Int {
        items.filter { $0.requiresParentReview && $0.parentReviewState == .unreviewed }.count
    }

    /// すべて採点済みか（採点待ちが 0 件）。
    public static func isFullyReviewed<I: ReviewableItem>(_ items: [I]) -> Bool {
        pendingCount(items) == 0
    }
}
