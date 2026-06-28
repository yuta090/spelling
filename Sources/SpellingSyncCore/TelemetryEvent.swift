import Foundation

// =============================================================================
// 運用テレメトリ（送信専用イベント）の純粋モデル。
//
// event_log は「同期テーブルではなく送信専用テーブル」: pull/LWW/tombstone/sync_version
// を持たない（更新も削除もしない・読み返さない＝append-only）。
// 値はすべて **低カーディナリティ**（バケット・フラグ・列挙）に限る。
// 氏名・なかま名・手書き画像/ストローク・自由入力・生の数値や時刻は **載せない**（児童プライバシー）。
// 設計: docs/telemetry-design.md
// =============================================================================

/// 重大度（syslog 風の段階値。サーバ index・絞り込みに使う）。
public enum TelemetrySeverity: Int, Codable, Sendable, CaseIterable {
    case info = 20
    case warning = 30
    case error = 40
    case fatal = 50
}

/// 送信を許可するカテゴリ（allowlist）。これ以外は wire で弾く。
public enum TelemetryCategory: String, Codable, Sendable, CaseIterable {
    case sync       // 同期（プル/プッシュ）の失敗
    case ocr        // 手書きOCRの失敗
    case crash      // MetricKit クラッシュ/診断
    case telemetry  // テレメトリ自身の健全性（drop 等）
    case session    // 練習セッション要約（低頻度・1セッション1件）
}

/// 送信を許可するイベントコード（allowlist）。v1 はこの6種のみ。
/// 追加は「数えると意思決定が変わるか？」と「児童の学習履歴そのものではないか？」を満たす時だけ。
public enum TelemetryCode: String, Codable, Sendable, CaseIterable {
    case syncPullFailed         = "sync.pull_failed"
    case syncPushFailed         = "sync.push_failed"
    case ocrFailed              = "ocr.failed"
    case crashDiagnostic        = "crash.mx_diagnostic"
    case telemetryDropped       = "telemetry.dropped"
    case practiceSessionSummary = "session.practice_summary"

    /// このコードが属するカテゴリ（DB の category 列と一致させる）。
    public var category: TelemetryCategory {
        switch self {
        case .syncPullFailed, .syncPushFailed: return .sync
        case .ocrFailed: return .ocr
        case .crashDiagnostic: return .crash
        case .telemetryDropped: return .telemetry
        case .practiceSessionSummary: return .session
        }
    }

    /// 既定の重大度（呼び出し側が明示しなければこれを使う）。
    public var defaultSeverity: TelemetrySeverity {
        switch self {
        case .syncPullFailed, .syncPushFailed, .ocrFailed: return .warning
        case .crashDiagnostic: return .fatal
        case .telemetryDropped, .practiceSessionSummary: return .info
        }
    }
}

/// payload に載せられる値（低カーディナリティのスカラのみ）。
/// JSON のスカラ（string/number/bool）として素直にエンコードする（jsonb 列にそのまま入る）。
public enum TelemetryValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // bool を Int より先に試す（JSON では true/false が Int にデコードされ得ないが順序を明示）。
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .bool(let b):   try c.encode(b)
        }
    }
}

/// 送信専用イベント1件。`id` は端末生成の決定論UUID（再送時の冪等キー）。
public struct TelemetryEvent: Codable, Sendable, Equatable, Identifiable {
    /// event_id（決定論UUID推奨。再送・多重 flush でも DB 側 ON CONFLICT DO NOTHING で吸収）。
    public let id: UUID
    /// RLS 境界。未ペアリング端末では nil もあり得る（その場合は送信を見送る運用）。
    public let householdID: UUID?
    /// 子プロファイル。**既定 nil**。行動分析目的で安易に付けない（障害切り分けに要る時のみ）。
    public let profileID: UUID?
    /// 端末識別（非秘密）。
    public let deviceID: UUID
    /// 端末でのイベント発生時刻（UTC）。
    public let occurredAt: Date
    public let severity: TelemetrySeverity
    public let code: TelemetryCode
    public let appVersion: String
    public let osVersion: String
    /// 低カーディナリティ値のみ。氏名・自由入力・生データ禁止。
    public let payload: [String: TelemetryValue]

    public var category: TelemetryCategory { code.category }

    public init(
        id: UUID,
        householdID: UUID?,
        profileID: UUID? = nil,
        deviceID: UUID,
        occurredAt: Date,
        code: TelemetryCode,
        severity: TelemetrySeverity? = nil,
        appVersion: String,
        osVersion: String,
        payload: [String: TelemetryValue] = [:]
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.deviceID = deviceID
        self.occurredAt = occurredAt
        self.code = code
        self.severity = severity ?? code.defaultSeverity
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.payload = payload
    }
}

/// 数値・期間を「区間（バケット）」に丸める。生値を送らずにヒストグラムが描ける。
public enum TelemetryBucket {
    /// 回数 → 区間文字列（単語数・採点数・なかま数など）。
    public static func count(_ n: Int) -> String {
        switch n {
        case ..<0:    return "neg"   // 異常系（負数）。配線ミスの可視化用。
        case 0:       return "0"
        case 1:       return "1"
        case 2...3:   return "2-3"
        case 4...5:   return "4-5"
        case 6...10:  return "6-10"
        case 11...20: return "11-20"
        default:      return "21+"
        }
    }

    /// 経過秒 → 区間文字列（セッション長など）。
    public static func duration(seconds: Double) -> String {
        switch seconds {
        case ..<0:     return "neg"
        case ..<30:    return "0-30s"
        case ..<60:    return "30-60s"
        case ..<120:   return "1-2m"
        case ..<300:   return "2-5m"
        case ..<600:   return "5-10m"
        default:       return "10m+"
        }
    }
}
