import XCTest
@testable import SpellingSyncCore

/// 世帯 NULL ストリームのオーナー解決の不変条件を固定する。
/// 肝は **一度決めたオーナーを再割り当てしない**（＝オーナー削除後に別の子へ移して他児のリモート行を
/// 取り込む事故を防ぐ）こと。
final class WordRemoteOwnerTests: XCTestCase {
    private func profile(_ n: Int, sortIndex: Int) -> ChildProfile {
        var p = ChildProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
            displayName: "child\(n)",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n))
        )
        p.sortIndex = sortIndex
        return p
    }

    func testUnrecordedInitializesToFirstProfile() {
        let a = profile(1, sortIndex: 0)
        let b = profile(2, sortIndex: 1)
        let registry = ProfileRegistry(profiles: [a, b], activeProfileID: b.id)
        XCTAssertEqual(WordRemoteOwner.resolve(current: nil, registry: registry), a.id,
                       "未記録なら先頭（最古＝#1）を初期オーナーにする")
    }

    func testUnrecordedUsesOldestNotSortOrder() {
        // 並べ替えで先頭が入れ替わっても、初期オーナーは「最古（createdAt 最小）＝元の子」を指す。
        let old = profile(1, sortIndex: 5)   // 生成は古いが末尾へ並べ替え済み
        let new = profile(2, sortIndex: 0)   // 生成は新しいが先頭へ
        let registry = ProfileRegistry(profiles: [old, new], activeProfileID: new.id)
        XCTAssertEqual(registry.orderedProfiles.first?.id, new.id, "表示順の先頭は new（前提確認）")
        XCTAssertEqual(WordRemoteOwner.resolve(current: nil, registry: registry), old.id,
                       "初期オーナーは表示順でなく最古を指す")
    }

    func testRecordedOwnerIsNeverReassigned() {
        let a = profile(1, sortIndex: 0)
        let b = profile(2, sortIndex: 1)
        // 記録済みオーナー b。台帳の先頭が a でも、b のまま維持する。
        let registry = ProfileRegistry(profiles: [a, b], activeProfileID: a.id)
        XCTAssertEqual(WordRemoteOwner.resolve(current: b.id, registry: registry), b.id)
    }

    func testDeletedOwnerIsNotReassignedToRemaining() {
        // オーナー a が台帳から消えても、残った b へは移さない（消えた a を返す＝どの子も一致せず同期停止）。
        let a = profile(1, sortIndex: 0)
        let b = profile(2, sortIndex: 1)
        let registryWithoutA = ProfileRegistry(profiles: [b], activeProfileID: b.id)
        XCTAssertEqual(WordRemoteOwner.resolve(current: a.id, registry: registryWithoutA), a.id,
                       "オーナー削除後も別の子へ移さない（安全側で同期停止）")
    }

    func testSingleProfileIsOwner() {
        let a = profile(1, sortIndex: 0)
        let registry = ProfileRegistry(bootstrapping: a)
        XCTAssertEqual(WordRemoteOwner.resolve(current: nil, registry: registry), a.id)
    }
}
