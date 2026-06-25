import XCTest
@testable import SpellingSyncCore

private struct Rec: SyncableRecord, Equatable {
    var sync: SyncMetadata
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func rec(_ id: UUID = UUID(), updated: TimeInterval, deleted: Bool = false) -> Rec {
    Rec(sync: SyncMetadata(
        id: id,
        createdAt: t0,
        updatedAt: t0.addingTimeInterval(updated),
        deletedAt: deleted ? t0.addingTimeInterval(updated) : nil
    ))
}

final class OutboundSyncPendingTests: XCTestCase {
    func testNilPushedThroughReturnsAllAscending() {
        let a = rec(updated: 30), b = rec(updated: 10), c = rec(updated: 20)
        let result = OutboundSync.pending([a, b, c], pushedThrough: nil)
        XCTAssertEqual(result.map { $0.sync.updatedAt },
                       [b, c, a].map { $0.sync.updatedAt })  // 昇順
    }

    func testExcludesAtOrBeforeHighWater() {
        let old = rec(updated: 10)
        let boundary = rec(updated: 50)              // == pushedThrough → 除外
        let fresh = rec(updated: 60)
        let result = OutboundSync.pending([old, boundary, fresh],
                                          pushedThrough: t0.addingTimeInterval(50))
        XCTAssertEqual(result.map(\.id), [fresh.id])
    }

    func testIncludesTombstones() {
        let deleted = rec(updated: 70, deleted: true)
        let result = OutboundSync.pending([deleted], pushedThrough: t0.addingTimeInterval(50))
        XCTAssertEqual(result.map(\.id), [deleted.id])
        XCTAssertTrue(result.first?.sync.isDeleted ?? false)
    }

    func testEmptyWhenNothingNewer() {
        let r = rec(updated: 10)
        XCTAssertTrue(OutboundSync.pending([r], pushedThrough: t0.addingTimeInterval(50)).isEmpty)
    }
}

final class OutboundSyncHighWaterTests: XCTestCase {
    func testMaxOfPushedWhenNoCurrent() {
        let pushed = [rec(updated: 10), rec(updated: 40), rec(updated: 25)]
        XCTAssertEqual(OutboundSync.highWater(pushed, current: nil), t0.addingTimeInterval(40))
    }

    func testKeepsCurrentWhenLarger() {
        let pushed = [rec(updated: 10)]
        let current = t0.addingTimeInterval(99)
        XCTAssertEqual(OutboundSync.highWater(pushed, current: current), current)
    }

    func testEmptyPushedKeepsCurrent() {
        let current = t0.addingTimeInterval(5)
        XCTAssertEqual(OutboundSync.highWater([Rec](), current: current), current)
        XCTAssertNil(OutboundSync.highWater([Rec](), current: nil))
    }
}
