import Foundation

/// ステップの今の焦点。
///
/// 設計（`docs/age-tiered-generation-spec-2026-06-29.md` §2 自動フロー）：
/// 「必須（登録語を手書きで練習→満点）を先にクリア → 満点後にことばパズル（プール/自由）がアンロック」。
/// 理由＝**①必ず覚えてほしい構文/単語を先に確実に通す ②一つをしっかり定着**、の両立。
/// - `.required`＝まだ満点でない＝必須をやる段階（ホームは練習を主役にする）。
/// - `.freePlayUnlocked`＝満点クリア済み＝パズル（自由）が解放された段階。
///
/// **パズルはクリア条件にしない**。満点が唯一のクリア条件で、その判定は呼び出し側の満点ゲート
/// （既存 `childStepIsMastered` / `hasPerfectRun`）に委譲する＝ここでは二重管理しない（§3.6）。
public enum StepFocus: Equatable, Sendable {
    case required
    case freePlayUnlocked
}

/// 「あたらしいクイズがでた！」のアンロック演出を**1回だけ**出すための記録。
///
/// - これは演出を見せたかどうかだけの記録で、**満点クリアの判定そのものではない**
///   （クリア＝満点ゲートが唯一の基準）。毎回起動で再演出しないための印（[[control-repeating-animated-ui]] と同じ方針）。
/// - キーは `StepSignature` なので、**単語を入れ替えて新しいセットを満点にすれば新しい署名＝また祝える**
///   （`RequiredCompletion` と同じ署名機構を再利用）。
public struct StepUnlockCelebration: Equatable, Sendable, Codable {
    public private(set) var celebrated: Set<StepSignature>

    public init(celebrated: Set<StepSignature> = []) {
        self.celebrated = celebrated
    }

    /// この署名（単語セット）のアンロック演出は既に出したか。
    public func wasCelebrated(_ signature: StepSignature) -> Bool {
        celebrated.contains(signature)
    }

    /// この署名のアンロック演出を出した、と記録する。
    public mutating func markCelebrated(_ signature: StepSignature) {
        celebrated.insert(signature)
    }
}

public enum StepFocusResolver {
    /// 満点なら自由（パズル解放）、まだなら必須。クリア判定は呼び出し側の満点ゲートに委譲する。
    public static func focus(isMastered: Bool) -> StepFocus {
        isMastered ? .freePlayUnlocked : .required
    }

    /// 今「あたらしいクイズがでた！」のアンロック演出を出すべきか。
    /// 満点になっていて（＝今クリア）、その署名でまだ演出していなければ true
    /// ＝**満点になった“瞬間”を1回だけ祝う**。演出後は `markCelebrated` で false に落ちる。
    public static func shouldCelebrateUnlock(signature: StepSignature,
                                             isMastered: Bool,
                                             celebration: StepUnlockCelebration) -> Bool {
        isMastered && !celebration.wasCelebrated(signature)
    }
}
