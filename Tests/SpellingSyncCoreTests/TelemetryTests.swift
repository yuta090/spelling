import XCTest
@testable import SpellingSyncCore

final class TelemetryTests: XCTestCase {
    private let dev = UUID(uuidString: "00000000-0000-0000-0000-0000000000DE")!
    private let hh = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private func makeEvent(
        id: UUID = UUID(),
        code: TelemetryCode = .ocrFailed,
        at seconds: TimeInterval = 0,
        payload: [String: TelemetryValue] = [:]
    ) -> TelemetryEvent {
        TelemetryEvent(
            id: id,
            householdID: hh,
            deviceID: dev,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds),
            code: code,
            appVersion: "1.0.0",
            osVersion: "17.0",
            payload: payload
        )
    }

    // MARK: - TelemetryCode / category / severity

    func testCodeCategoryMapping() {
        XCTAssertEqual(TelemetryCode.syncPullFailed.category, .sync)
        XCTAssertEqual(TelemetryCode.syncPushFailed.category, .sync)
        XCTAssertEqual(TelemetryCode.ocrFailed.category, .ocr)
        XCTAssertEqual(TelemetryCode.crashDiagnostic.category, .crash)
        XCTAssertEqual(TelemetryCode.telemetryDropped.category, .telemetry)
        XCTAssertEqual(TelemetryCode.practiceSessionSummary.category, .session)
    }

    func testDefaultSeverityAppliedWhenOmitted() {
        XCTAssertEqual(makeEvent(code: .crashDiagnostic).severity, .fatal)
        XCTAssertEqual(makeEvent(code: .ocrFailed).severity, .warning)
        XCTAssertEqual(makeEvent(code: .telemetryDropped).severity, .info)
    }

    func testV1AllowlistIsExactlySixCodes() {
        XCTAssertEqual(TelemetryCode.allCases.count, 6)
    }

    // MARK: - Bucketing

    func testCountBuckets() {
        XCTAssertEqual(TelemetryBucket.count(-1), "neg")
        XCTAssertEqual(TelemetryBucket.count(0), "0")
        XCTAssertEqual(TelemetryBucket.count(1), "1")
        XCTAssertEqual(TelemetryBucket.count(3), "2-3")
        XCTAssertEqual(TelemetryBucket.count(7), "6-10")
        XCTAssertEqual(TelemetryBucket.count(50), "21+")
    }

    func testDurationBuckets() {
        XCTAssertEqual(TelemetryBucket.duration(seconds: -5), "neg")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 10), "0-30s")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 45), "30-60s")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 90), "1-2m")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 250), "2-5m")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 9999), "10m+")
    }

    // MARK: - TelemetryValue Codable round-trip

    func testValueRoundTripScalars() throws {
        let payload: [String: TelemetryValue] = [
            "s": .string("completed"),
            "i": .int(7),
            "b": .bool(true)
        ]
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode([String: TelemetryValue].self, from: data)
        XCTAssertEqual(back, payload)
    }

    func testValueEncodesAsJSONScalarsNotWrapped() throws {
        let data = try JSONEncoder().encode(["n": TelemetryValue.int(5)])
        let json = String(decoding: data, as: UTF8.self)
        // jsonb 列にそのまま入るよう、{"n":5} の形（オブジェクト包みでない）。
        XCTAssertEqual(json, "{\"n\":5}")
    }

    // MARK: - EventOutbox

    func testOutboxAppendNoDrop() {
        var box = EventOutbox(capacity: 3)
        XCTAssertEqual(box.append(makeEvent()), 0)
        XCTAssertEqual(box.append(makeEvent()), 0)
        XCTAssertEqual(box.count, 2)
    }

    func testOutboxDropsOldestWhenOverCapacity() {
        var box = EventOutbox(capacity: 2)
        let a = makeEvent(at: 0), b = makeEvent(at: 1), c = makeEvent(at: 2)
        _ = box.append(a)
        _ = box.append(b)
        XCTAssertEqual(box.append(c), 1, "1件落ちる")
        XCTAssertEqual(box.events.map { $0.id }, [b.id, c.id], "古い a が落ちる(FIFO)")
    }

    func testOutboxIgnoresDuplicateID() {
        var box = EventOutbox(capacity: 5)
        let id = UUID()
        XCTAssertEqual(box.append(makeEvent(id: id)), 0)
        XCTAssertEqual(box.append(makeEvent(id: id)), 0)
        XCTAssertEqual(box.count, 1, "同一 id は無視（冪等）")
    }

    func testOutboxBatchAndAcknowledge() {
        var box = EventOutbox(capacity: 10)
        let ids = (0..<5).map { _ in UUID() }
        ids.forEach { _ = box.append(makeEvent(id: $0)) }
        let batch = box.batch(limit: 3)
        XCTAssertEqual(batch.map { $0.id }, Array(ids.prefix(3)))
        box.acknowledge(batch.map { $0.id })
        XCTAssertEqual(box.events.map { $0.id }, Array(ids.suffix(2)), "送信成功分だけ外れる")
    }

    func testOutboxInitTruncatesOversizedSeed() {
        let seed = (0..<5).map { makeEvent(at: TimeInterval($0)) }
        let box = EventOutbox(capacity: 3, events: seed)
        XCTAssertEqual(box.count, 3)
        XCTAssertEqual(box.events.map { $0.id }, seed.suffix(3).map { $0.id })
    }

    func testOutboxCodableRoundTrip() throws {
        var box = EventOutbox(capacity: 4)
        _ = box.append(makeEvent(payload: ["k": .string("v")]))
        let data = try JSONEncoder().encode(box)
        let back = try JSONDecoder().decode(EventOutbox.self, from: data)
        XCTAssertEqual(back, box)
    }

    // MARK: - MonotonicStamper

    func testStamperStrictlyIncreasingOnSameInstant() {
        var clock = MonotonicStamper(step: 0.001)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let a = clock.stamp(t)
        let b = clock.stamp(t)
        let c = clock.stamp(t)
        XCTAssertEqual(a, t)
        XCTAssertGreaterThan(b, a)
        XCTAssertGreaterThan(c, b)
    }

    func testStamperPassesThroughLaterTimes() {
        var clock = MonotonicStamper()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = clock.stamp(t0)
        let later = t0.addingTimeInterval(60)
        XCTAssertEqual(clock.stamp(later), later)
        XCTAssertEqual(clock.lastIssued, later)
    }

    func testStamperResumesFromPersistedLast() {
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = MonotonicStamper(last: last)
        let next = clock.stamp(last) // 同時刻 → +step
        XCTAssertGreaterThan(next, last)
    }

    // MARK: - TelemetryWire

    func testWireRowMapsColumns() throws {
        let event = makeEvent(code: .practiceSessionSummary, payload: [
            "result": .string("completed"),
            "word_count_bucket": .string("6-10")
        ])
        let row = try XCTUnwrap(TelemetryWire.row(from: event))
        XCTAssertEqual(row.eventID, event.id)
        XCTAssertEqual(row.category, "session")
        XCTAssertEqual(row.code, "session.practice_summary")
        XCTAssertEqual(row.severity, TelemetrySeverity.info.rawValue)
        XCTAssertEqual(row.householdID, hh)
        XCTAssertNil(row.profileID, "profile_id は既定 nil")
        XCTAssertTrue(row.occurredAt.hasSuffix("Z"), "RFC3339 UTC")
    }

    func testWireRejectsOversizedPayload() {
        let big = String(repeating: "x", count: TelemetryWire.maxPayloadBytes + 100)
        let event = makeEvent(payload: ["blob": .string(big)])
        XCTAssertNil(TelemetryWire.row(from: event), "上限超え payload は弾く")
    }

    func testWireRejectsNilHousehold() {
        let e = TelemetryEvent(
            id: UUID(), householdID: nil, deviceID: dev,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            code: .ocrFailed, appVersion: "1.0.0", osVersion: "17.0"
        )
        XCTAssertNil(TelemetryWire.row(from: e), "世帯未確定の event は送信不能なので row 化しない")
    }

    func testWireAcceptsEmptyPayload() {
        XCTAssertEqual(TelemetryWire.payloadSize([:]), 0)
        XCTAssertNotNil(TelemetryWire.row(from: makeEvent()))
    }

    func testWireRowEncodesSnakeCaseKeys() throws {
        let row = try XCTUnwrap(TelemetryWire.row(from: makeEvent()))
        let data = try JSONEncoder().encode(row)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"event_id\""))
        XCTAssertTrue(json.contains("\"occurred_at\""))
        XCTAssertTrue(json.contains("\"app_version\""))
        XCTAssertFalse(json.contains("\"received_at\""), "received_at は送らない（DB default）")
    }
}
