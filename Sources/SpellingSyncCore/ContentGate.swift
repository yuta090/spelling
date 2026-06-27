import Foundation

/// Dolch 学年（US 学年制のサイトワード）。rawValue は WordBank の `level.dolch` 値に対応。
public enum DolchGrade: String, Equatable, Sendable, CaseIterable {
    case preK = "pre-K"
    case k = "K"
    case g1 = "1"
    case g2 = "2"
    case g3 = "3"
    case noun
}

/// レベル生成で扱うコンテンツのレベル（学年軸 or 難易度軸）。
/// 生フィールド（`dolch: String?`, `band: Int?`）を**型付き**に閉じ込めるための値。
public enum ContentLevel: Equatable, Sendable {
    case dolch(DolchGrade)
    case ngsl(band: Int)

    /// 有効な NGSL バンドの範囲（頻度バンド 1〜5）。
    public static let ngslBandRange = 1...5

    /// WordBank/UI の生パラメータからのブリッジ。
    /// - UI 上は学年軸/難易度軸が排他だが、両方来たら **band（難易度軸）を優先**する。
    /// - `band` は 1〜5 のみ有効。範囲外なら（grade が来ていても）誤入力として `nil`。
    /// - どちらも解釈できなければ `nil`。
    public init?(dolch: String?, band: Int?) {
        if let band {
            guard ContentLevel.ngslBandRange.contains(band) else { return nil }
            self = .ngsl(band: band)
        } else if let dolch, let grade = DolchGrade(rawValue: dolch) {
            self = .dolch(grade)
        } else {
            return nil
        }
    }
}

/// コンテンツゲート（レベル生成のロック判定）の**純粋ロジック**。
///
/// 無料＝Dolch pre-K / K のみ。Grade1/2/3・noun・全 NGSL バンドは有料。
/// 判定は**生成時のみ**使う（練習時には使わない＝解約後も既存語は練習可能）。
/// 手打ち登録はこの経路を通らないため常に無料・無制限。
public enum ContentGate {
    /// 無料で解放されるレベルか。
    public static func isFree(_ level: ContentLevel) -> Bool {
        switch level {
        case .dolch(.preK), .dolch(.k):
            return true
        default:
            return false
        }
    }

    /// このレベルが解放済みか（購読中なら全解放、未購読は無料のみ）。
    public static func isUnlocked(_ level: ContentLevel, isSubscribed: Bool) -> Bool {
        isSubscribed || isFree(level)
    }
}
