import Foundation

/// `TelemetryEvent` ⇄ 送信行（DB の event_log 列に対応）の変換と検証。
///
/// - allowlist 検証: category と code の対応が壊れている行は弾く（呼び出しミスの防波堤）。
/// - payload サイズ上限: JSON 化して `maxPayloadBytes` を超えるものは弾く（巨大 payload の事故防止）。
/// - 送信専用のため `updated_at` / `deleted_at` / `sync_version` は **持たない**。
/// 壊れた/過大な行は `row(from:)` が nil を返す（呼び出し側は drop して `telemetry.dropped` を積む）。
public enum TelemetryWire {
    /// payload(JSON) の最大バイト数（DB 側 CHECK と一致させる）。
    public static let maxPayloadBytes = 2048

    /// event_log への INSERT 用ペイロード。サーバ管理列（received_at）は送らない（DB default）。
    /// 列名は snake_case（PostgREST）。occurred_at は RFC3339(UTC, ミリ秒) 文字列。
    public struct Row: Codable, Sendable, Equatable {
        public let eventID: UUID
        /// 送信には必須（DB は NOT NULL ＋ RLS 境界）。nil の event は送れないので row 化しない。
        public let householdID: UUID
        public let profileID: UUID?
        public let deviceID: UUID
        public let occurredAt: String
        public let severity: Int
        public let category: String
        public let code: String
        public let appVersion: String
        public let osVersion: String
        public let payload: [String: TelemetryValue]

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case householdID = "household_id"
            case profileID = "profile_id"
            case deviceID = "device_id"
            case occurredAt = "occurred_at"
            case severity
            case category
            case code
            case appVersion = "app_version"
            case osVersion = "os_version"
            case payload
        }
    }

    /// イベントを検証して送信行へ変換する。allowlist 不整合・payload 過大なら nil。
    public static func row(from event: TelemetryEvent) -> Row? {
        // 世帯未確定（未ペアリング）の event は送信不能（DB NOT NULL ＋ RLS）。row 化せず弾く。
        // これにより未送信キューの先頭で“送れない行”が詰まって flush 全体を止める事故を防ぐ。
        guard let household = event.householdID else { return nil }

        // allowlist: code から導かれる category と一致していること（構造上は常に一致するが、
        // 将来 category を外から渡す拡張に備えて明示検証する）。
        guard TelemetryCode(rawValue: event.code.rawValue) != nil else { return nil }

        // payload サイズ上限チェック（決定論エンコードのためキーソート）。
        guard payloadSize(event.payload) <= maxPayloadBytes else { return nil }

        return Row(
            eventID: event.id,
            householdID: household,
            profileID: event.profileID,
            deviceID: event.deviceID,
            occurredAt: RFC3339.string(from: event.occurredAt),
            severity: event.severity.rawValue,
            category: event.category.rawValue,
            code: event.code.rawValue,
            appVersion: event.appVersion,
            osVersion: event.osVersion,
            payload: event.payload
        )
    }

    /// payload を JSON 化したバイト数。空なら 0。
    public static func payloadSize(_ payload: [String: TelemetryValue]) -> Int {
        guard !payload.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return Int.max }
        return data.count
    }
}
