import XCTest
@testable import SpellingSyncCore

/// 着せ替えアバターの純ロジック（manifest 解釈・z-order 合成・選択解決）。
/// UI を一切持たない。SwiftUI 側はここが返すレイヤー列をそのまま ZStack で描くだけ。
final class AvatarDressUpTests: XCTestCase {

    /// テスト用の最小 manifest（spec.json の placement モデルに対応）。
    private func sampleManifest() -> AvatarManifest {
        AvatarManifest(
            canvas: [1024, 1536],
            zOrder: ["back_hair", "base_body", "bottom", "shoes", "top", "outer", "face", "front_hair", "accessory"],
            bases: [
                AvatarBase(id: "female", labelJa: "おんなのこ", file: "base_female.png"),
                AvatarBase(id: "male", labelJa: "おとこのこ", file: "base_male.png")
            ],
            parts: [
                // 髪は 1 髪型が back_hair / front_hair の 2 レイヤーに分かれる
                AvatarPart(id: "hair_twin", slot: .hair, labelJa: "ツインテール", base: "female", layers: [
                    AvatarLayer(file: "hair_twin_back.png", z: "back_hair", offsetX: 0, offsetY: 0, scale: 1),
                    AvatarLayer(file: "hair_twin_front.png", z: "front_hair", offsetX: 0, offsetY: 0, scale: 1)
                ]),
                AvatarPart(id: "hair_short", slot: .hair, labelJa: "ショート", base: "female", layers: [
                    AvatarLayer(file: "hair_short_front.png", z: "front_hair", offsetX: 0, offsetY: 0, scale: 1)
                ]),
                AvatarPart(id: "top_red", slot: .top, labelJa: "あかいシャツ", base: "*", layers: [
                    AvatarLayer(file: "top_red.png", z: "top", offsetX: 0, offsetY: 0, scale: 1)
                ]),
                AvatarPart(id: "bottom_blue", slot: .bottom, labelJa: "あおいパンツ", base: "female", layers: [
                    AvatarLayer(file: "bottom_blue.png", z: "bottom", offsetX: 0, offsetY: 0, scale: 1)
                ]),
                AvatarPart(id: "shoes_white", slot: .shoes, labelJa: "しろいくつ", base: "*", layers: [
                    AvatarLayer(file: "shoes_white.png", z: "shoes", offsetX: 0, offsetY: 0, scale: 1)
                ]),
                // male 専用パーツ（female の候補に出てはいけない）
                AvatarPart(id: "hair_buzz_male", slot: .hair, labelJa: "ぼうず", base: "male", layers: [
                    AvatarLayer(file: "hair_buzz.png", z: "front_hair", offsetX: 0, offsetY: 0, scale: 1)
                ])
            ]
        )
    }

    // MARK: - Codable

    func testManifestRoundTripsThroughJSON() throws {
        let manifest = sampleManifest()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(AvatarManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }

    func testManifestDecodesFromHandWrittenJSON() throws {
        let json = """
        {
          "canvas": [1024, 1536],
          "zOrder": ["base_body", "top", "front_hair"],
          "bases": [{ "id": "female", "labelJa": "おんなのこ", "file": "base_female.png" }],
          "parts": [
            { "id": "top_red", "slot": "top", "labelJa": "あかいシャツ", "base": "*",
              "layers": [{ "file": "top_red.png", "z": "top", "offsetX": 0, "offsetY": 0, "scale": 1 }] }
          ]
        }
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(AvatarManifest.self, from: json)
        XCTAssertEqual(m.bases.first?.id, "female")
        XCTAssertEqual(m.parts.first?.slot, .top)
        XCTAssertEqual(m.parts.first?.layers.first?.file, "top_red.png")
    }

    // MARK: - compose

    func testComposeAlwaysIncludesBaseBody() {
        let m = sampleManifest()
        let layers = AvatarComposer.compose(manifest: m, selection: DressUpSelection(baseID: "female", parts: [:]))
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers.first?.file, "base_female.png")
        XCTAssertEqual(layers.first?.z, "base_body")
        XCTAssertNil(layers.first?.sourcePartID)
    }

    func testComposeSortsLayersByZOrder() {
        let m = sampleManifest()
        // ツインテール（back+front）＋赤シャツ＋青パンツを選ぶ
        let sel = DressUpSelection(baseID: "female", parts: [
            .hair: "hair_twin", .top: "top_red", .bottom: "bottom_blue"
        ])
        let layers = AvatarComposer.compose(manifest: m, selection: sel)
        let order = layers.map(\.z)
        // 期待 z 順: back_hair → base_body → bottom → top → front_hair
        XCTAssertEqual(order, ["back_hair", "base_body", "bottom", "top", "front_hair"])
        // zIndex は昇順に単調増加
        XCTAssertEqual(layers.map(\.zIndex), layers.map(\.zIndex).sorted())
    }

    func testComposeSkipsUnknownPartIDsSafely() {
        let m = sampleManifest()
        let sel = DressUpSelection(baseID: "female", parts: [.top: "does_not_exist"])
        let layers = AvatarComposer.compose(manifest: m, selection: sel)
        XCTAssertEqual(layers.map(\.file), ["base_female.png"]) // base のみ
    }

    func testComposePreservesOffsetAndScale() {
        var m = sampleManifest()
        m.parts.append(AvatarPart(id: "acc_cap", slot: .accessory, labelJa: "ぼうし", base: "*", layers: [
            AvatarLayer(file: "cap.png", z: "accessory", offsetX: 12, offsetY: -8, scale: 1.05)
        ]))
        let sel = DressUpSelection(baseID: "female", parts: [.accessory: "acc_cap"])
        let layers = AvatarComposer.compose(manifest: m, selection: sel)
        let cap = layers.first { $0.sourcePartID == "acc_cap" }
        XCTAssertEqual(cap?.offsetX, 12)
        XCTAssertEqual(cap?.offsetY, -8)
        XCTAssertEqual(cap?.scale, 1.05)
    }

    func testComposeSkipsPartWhoseBaseDoesNotMatchSelection() {
        let m = sampleManifest()
        // male 専用 hair_buzz_male を誤って female の選択に入れても描かない
        let sel = DressUpSelection(baseID: "female", parts: [.hair: "hair_buzz_male"])
        let layers = AvatarComposer.compose(manifest: m, selection: sel)
        XCTAssertEqual(layers.map(\.file), ["base_female.png"]) // base のみ
    }

    func testComposeUnknownZSortsToEnd() {
        var m = sampleManifest()
        m.parts.append(AvatarPart(id: "weird", slot: .accessory, labelJa: "?", base: "*", layers: [
            AvatarLayer(file: "weird.png", z: "not_in_zorder", offsetX: 0, offsetY: 0, scale: 1)
        ]))
        let sel = DressUpSelection(baseID: "female", parts: [.accessory: "weird", .top: "top_red"])
        let layers = AvatarComposer.compose(manifest: m, selection: sel)
        XCTAssertEqual(layers.last?.file, "weird.png")
    }

    // MARK: - parts(for:) / defaultSelection

    func testPartsForSlotFiltersByBaseIncludingWildcard() {
        let m = sampleManifest()
        let femaleHair = AvatarComposer.parts(manifest: m, slot: .hair, baseID: "female").map(\.id)
        XCTAssertEqual(femaleHair, ["hair_twin", "hair_short"]) // male 専用 hair_buzz は除外
        let femaleTops = AvatarComposer.parts(manifest: m, slot: .top, baseID: "female").map(\.id)
        XCTAssertEqual(femaleTops, ["top_red"]) // "*" は全 base に出る
        let maleHair = AvatarComposer.parts(manifest: m, slot: .hair, baseID: "male").map(\.id)
        XCTAssertEqual(maleHair, ["hair_buzz_male"])
    }

    func testDefaultSelectionPicksFirstPartPerSlotForBase() {
        let m = sampleManifest()
        let sel = AvatarComposer.defaultSelection(manifest: m, baseID: "female")
        XCTAssertEqual(sel.baseID, "female")
        XCTAssertEqual(sel.parts[.hair], "hair_twin")
        XCTAssertEqual(sel.parts[.top], "top_red")
        XCTAssertEqual(sel.parts[.bottom], "bottom_blue")
        XCTAssertEqual(sel.parts[.shoes], "shoes_white")
        // face / accessory は候補が無いので未設定
        XCTAssertNil(sel.parts[.face])
        XCTAssertNil(sel.parts[.accessory])
    }
}
