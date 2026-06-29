import Foundation

/// 送信前イベントを端末内に溜める **capped ring buffer**（純粋な値型）。
///
/// - 容量超過は **drop-oldest**（古いものから捨てる）。捨てた件数を呼び出し側へ返し、
///   `telemetry.dropped` メタイベントで可観測化できるようにする（暗黙の取りこぼしを作らない）。
/// - 重複（同一 `event_id`）は無視（決定論UUIDの再生成や多重 record を吸収）。
/// - FIFO。`batch(limit:)` で古い順に送信対象を取り、成功した id を `acknowledge` で外す。
/// I/O（ファイル永続化・ネットワーク送信）はアプリ側の薄い層が担い、ここは選択ロジックに専念する。
public struct EventOutbox: Codable, Sendable, Equatable {
    /// 保持できる最大件数。超えた分は古い順に落とす。
    public let capacity: Int
    /// 送信待ちイベント（古い順＝FIFO）。
    public private(set) var events: [TelemetryEvent]

    public init(capacity: Int = 500, events: [TelemetryEvent] = []) {
        precondition(capacity > 0, "capacity must be > 0")
        self.capacity = capacity
        // 既存配列が容量を超える場合は古い側を切り捨てて整合させる。
        self.events = events.suffix(capacity).map { $0 }
    }

    /// イベントを末尾に追加する。
    /// - Returns: 容量超過で **落としたイベント数**（0 なら無損失）。重複で無視した場合も 0。
    @discardableResult
    public mutating func append(_ event: TelemetryEvent) -> Int {
        // 重複 id は無視（冪等）。
        if events.contains(where: { $0.id == event.id }) { return 0 }
        events.append(event)
        guard events.count > capacity else { return 0 }
        let overflow = events.count - capacity
        events.removeFirst(overflow)
        return overflow
    }

    /// 送信対象を古い順に最大 `limit` 件返す（buffer は変更しない）。
    public func batch(limit: Int) -> [TelemetryEvent] {
        guard limit > 0 else { return [] }
        return Array(events.prefix(limit))
    }

    /// 送信に成功した id を取り除く。
    public mutating func acknowledge<S: Sequence>(_ ids: S) where S.Element == UUID {
        let set = Set(ids)
        guard !set.isEmpty else { return }
        events.removeAll { set.contains($0.id) }
    }

    public var count: Int { events.count }
    public var isEmpty: Bool { events.isEmpty }
}
