import XCTest
@testable import SpellingSyncCore

final class DeterministicIDTests: XCTestCase {
    // RFC 4122 の標準名前空間 DNS
    private let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!

    func testKnownVector() {
        // RFC/標準実装で広く知られた v5 ベクトル
        let id = DeterministicID.uuidV5(namespace: dns, name: "www.example.com")
        XCTAssertEqual(id.uuidString.lowercased(), "2ed6657d-e927-568b-95e1-2665a8aea6a2")
    }

    func testDeterministic() {
        let a = DeterministicID.uuidV5(namespace: dns, name: "profile-1|word-9")
        let b = DeterministicID.uuidV5(namespace: dns, name: "profile-1|word-9")
        XCTAssertEqual(a, b)
    }

    func testDifferentNameDiffers() {
        let a = DeterministicID.uuidV5(namespace: dns, name: "x")
        let b = DeterministicID.uuidV5(namespace: dns, name: "y")
        XCTAssertNotEqual(a, b)
    }

    func testVersionAndVariantBits() {
        let id = DeterministicID.uuidV5(namespace: dns, name: "anything")
        // version nibble = 5（uuidString の 15文字目: xxxxxxxx-xxxx-5xxx-...）
        let chars = Array(id.uuidString.lowercased())
        XCTAssertEqual(chars[14], "5")
        // variant: 20文字目が 8/9/a/b のいずれか（RFC 4122）
        XCTAssertTrue(["8", "9", "a", "b"].contains(String(chars[19])))
    }

    func testComponentsOrderMatters() {
        let ab = DeterministicID.uuidV5(namespace: dns, components: ["a", "b"])
        let ba = DeterministicID.uuidV5(namespace: dns, components: ["b", "a"])
        XCTAssertNotEqual(ab, ba)
        // 区切り子により "a","b" と "ab" は衝突しない
        let joined = DeterministicID.uuidV5(namespace: dns, components: ["ab"])
        XCTAssertNotEqual(ab, joined)
    }
}
