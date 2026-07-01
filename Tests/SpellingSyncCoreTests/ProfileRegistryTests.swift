import XCTest
@testable import SpellingSyncCore

/// 複数子プロファイル台帳 `ProfileRegistry` の純ロジック。
/// 不変条件（最低1人・active∈profiles・決定論順序）と add/remove/rename/activate/reorder を固定する。
/// 設計: docs/multi-child-profiles-design-2026-07-01.md §2.2
final class ProfileRegistryTests: XCTestCase {

    // 決定論のため now/id は明示的に与える。
    private func profile(_ n: Int, sort: Int, name: String? = nil) -> ChildProfile {
        ChildProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!,
            displayName: name ?? "child\(n)",
            avatarID: "a\(n)",
            colorHex: "#111111",
            createdAt: Date(timeIntervalSince1970: TimeInterval(n)),
            sortIndex: sort
        )
    }

    func testBootstrapHasOneActiveProfile() {
        let p = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: p)
        XCTAssertEqual(reg.orderedProfiles, [p])
        XCTAssertEqual(reg.activeProfileID, p.id)
        XCTAssertEqual(reg.activeProfile, p)
    }

    func testOrderedProfilesAreSortedBySortIndexThenCreatedThenID() {
        let a = profile(1, sort: 2)
        let b = profile(2, sort: 1)
        let c = profile(3, sort: 1) // b と同 sort → createdAt(=2) < (=3) で b が先
        let reg = ProfileRegistry(profiles: [a, b, c], activeProfileID: a.id)
        XCTAssertEqual(reg.orderedProfiles.map(\.id), [b.id, c.id, a.id])
    }

    func testInitRepairsMissingActiveIDToFirst() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        // active が存在しない ID → init が先頭へ修復（activeProfileID 自体も直す）。
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: UUID())
        XCTAssertEqual(reg.activeProfile, a)
        XCTAssertEqual(reg.activeProfileID, a.id)
    }

    func testInitDeduplicatesByID() {
        let a = profile(1, sort: 0)
        let dup = ChildProfile(id: a.id, displayName: "dup", avatarID: "x",
                               colorHex: "#000000", createdAt: Date(timeIntervalSince1970: 9), sortIndex: 5)
        let reg = ProfileRegistry(profiles: [a, dup], activeProfileID: a.id)
        XCTAssertEqual(reg.orderedProfiles.count, 1, "同一IDは1つに畳む")
    }

    func testAddingAppendsAndKeepsActive() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        let b = profile(2, sort: 1)
        let next = reg.adding(b)
        XCTAssertEqual(next.orderedProfiles.map(\.id), [a.id, b.id])
        XCTAssertEqual(next.activeProfileID, a.id, "追加はアクティブを変えない")
    }

    func testRemovingNonActiveKeepsActive() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        let next = reg.removing(b.id)
        XCTAssertEqual(next.orderedProfiles.map(\.id), [a.id])
        XCTAssertEqual(next.activeProfileID, a.id)
    }

    func testRemovingActiveMovesActiveToNewFirst() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        let next = reg.removing(a.id)
        XCTAssertEqual(next.orderedProfiles.map(\.id), [b.id])
        XCTAssertEqual(next.activeProfileID, b.id, "アクティブを消したら残りの先頭へ")
    }

    func testCannotRemoveLastProfile() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        let next = reg.removing(a.id)
        XCTAssertEqual(next, reg, "最後の1人は消せない（不変条件）")
    }

    func testRemovingUnknownIDIsNoOp() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        XCTAssertEqual(reg.removing(UUID()), reg)
    }

    func testRenaming() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        let next = reg.renaming(a.id, to: "ゆうた")
        XCTAssertEqual(next.activeProfile.displayName, "ゆうた")
    }

    func testAddingDuplicateIDIsNoOp() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        let sameID = ChildProfile(id: a.id, displayName: "別名", avatarID: "z",
                                  colorHex: "#000000", createdAt: Date(timeIntervalSince1970: 9), sortIndex: 9)
        XCTAssertEqual(reg.adding(sameID), reg, "同一IDの追加は no-op")
    }

    func testReorderingWithPartialAndUnknownIDsKeepsAllProfiles() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let c = profile(3, sort: 2)
        let reg = ProfileRegistry(profiles: [a, b, c], activeProfileID: a.id)
        // 一部だけ指定＋未知IDを混ぜても、全プロファイルが保たれ指定分が先頭に来る。
        let next = reg.reordering([c.id, UUID()])
        XCTAssertEqual(next.orderedProfiles.count, 3)
        XCTAssertEqual(next.orderedProfiles.first?.id, c.id)
        XCTAssertEqual(Set(next.orderedProfiles.map(\.id)), [a.id, b.id, c.id])
    }

    func testDecodingEmptyProfilesFails() {
        let json = Data(#"{"profiles":[],"activeProfileID":"\#(UUID().uuidString)"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileRegistry.self, from: json),
                             "空プロファイルはデコード失敗（上位で bootstrap）")
    }

    func testDecodingRepairsOrderAndMissingActive() throws {
        // 非正規順＋実在しない active を持つ JSON を、正規化＋先頭修復で受ける。
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let unsorted = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        // わざと壊す：activeProfileID を実在しないUUIDにした生JSONを作る。
        var dict: [String: Any] = [:]
        dict["profiles"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([b, a]))
        dict["activeProfileID"] = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: data)
        XCTAssertEqual(decoded.orderedProfiles.map(\.id), [a.id, b.id], "順序は正規化される")
        XCTAssertEqual(decoded.activeProfileID, a.id, "実在しない active は先頭へ修復")
        _ = unsorted
    }

    func testRenamingUnknownIDIsNoOp() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        XCTAssertEqual(reg.renaming(UUID(), to: "x"), reg)
    }

    func testActivating() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        XCTAssertEqual(reg.activating(b.id).activeProfileID, b.id)
    }

    func testActivatingUnknownIDIsNoOp() {
        let a = profile(1, sort: 0)
        let reg = ProfileRegistry(bootstrapping: a)
        XCTAssertEqual(reg.activating(UUID()), reg)
    }

    func testReordering() {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let c = profile(3, sort: 2)
        let reg = ProfileRegistry(profiles: [a, b, c], activeProfileID: a.id)
        let next = reg.reordering([c.id, a.id, b.id])
        XCTAssertEqual(next.orderedProfiles.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(next.activeProfileID, a.id, "並べ替えはアクティブを変えない")
    }

    func testCodableRoundTrip() throws {
        let a = profile(1, sort: 0)
        let b = profile(2, sort: 1)
        let reg = ProfileRegistry(profiles: [a, b], activeProfileID: b.id)
        let data = try JSONEncoder().encode(reg)
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: data)
        XCTAssertEqual(decoded, reg)
    }
}
