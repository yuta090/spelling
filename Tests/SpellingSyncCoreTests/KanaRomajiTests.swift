import XCTest
@testable import SpellingSyncCore

/// `KanaRomaji.romanize` — かな名 → ヘボン式（パスポート風）ローマ字の決定論変換。
/// 用途は「なかま」登録シートのローマ字プリフィル（1語の名前想定・親が修正可能）。
final class KanaRomajiTests: XCTestCase {

    func testBasicNames() {
        XCTAssertEqual(KanaRomaji.romanize("ゆうた"), "Yuta")     // 長音 uu → u
        XCTAssertEqual(KanaRomaji.romanize("さくら"), "Sakura")
        XCTAssertEqual(KanaRomaji.romanize("ゆき"), "Yuki")
        XCTAssertEqual(KanaRomaji.romanize("ひなた"), "Hinata")
    }

    func testHepburnSpecials() {
        XCTAssertEqual(KanaRomaji.romanize("しんじ"), "Shinji")   // し=shi・じ=ji
        XCTAssertEqual(KanaRomaji.romanize("ちひろ"), "Chihiro")  // ち=chi
        XCTAssertEqual(KanaRomaji.romanize("つばさ"), "Tsubasa")  // つ=tsu
        XCTAssertEqual(KanaRomaji.romanize("ふみか"), "Fumika")   // ふ=fu
    }

    func testYouon() {
        XCTAssertEqual(KanaRomaji.romanize("きょうこ"), "Kyoko")  // きょ=kyo・長音 ou → o
        XCTAssertEqual(KanaRomaji.romanize("しょうた"), "Shota")  // しょ=sho
        XCTAssertEqual(KanaRomaji.romanize("じゅん"), "Jun")      // じゅ=ju
        XCTAssertEqual(KanaRomaji.romanize("りょう"), "Ryo")      // りょ=ryo
        XCTAssertEqual(KanaRomaji.romanize("ちゃこ"), "Chako")    // ちゃ=cha
    }

    func testLongVowelCollapse() {
        XCTAssertEqual(KanaRomaji.romanize("こうた"), "Kota")     // ou → o
        XCTAssertEqual(KanaRomaji.romanize("おおた"), "Ota")      // oo → o
        XCTAssertEqual(KanaRomaji.romanize("けい"), "Kei")        // ei はそのまま
    }

    func testSokuonAndN() {
        XCTAssertEqual(KanaRomaji.romanize("はっとり"), "Hattori") // っ=次の子音重ね
        XCTAssertEqual(KanaRomaji.romanize("けん"), "Ken")
        // ん+母音は厳密ヘボンなら Ken'ichi だが、ローマ字欄は英字のみ（1語）の制約なので ' は省く。
        XCTAssertEqual(KanaRomaji.romanize("けんいち"), "Kenichi")
        // ん は b/m/p の前では m（パスポート式：しんぺい→Shimpei、なんば→Namba）。
        XCTAssertEqual(KanaRomaji.romanize("しんぺい"), "Shimpei")
        XCTAssertEqual(KanaRomaji.romanize("なんば"), "Namba")
        XCTAssertEqual(KanaRomaji.romanize("じゅんぺい"), "Jumpei")
    }

    func testKatakanaNames() {
        XCTAssertEqual(KanaRomaji.romanize("カレン"), "Karen")
        XCTAssertEqual(KanaRomaji.romanize("メイ"), "Mei")
    }

    func testUnsupportedInputReturnsEmpty() {
        // 変換できない文字（漢字・英字・記号）が混ざったら空を返し、呼び出し側は空欄のまま親に入力してもらう。
        XCTAssertEqual(KanaRomaji.romanize("優太"), "")
        XCTAssertEqual(KanaRomaji.romanize("Yuta"), "")
        XCTAssertEqual(KanaRomaji.romanize(""), "")
    }

    func testWhitespaceTrimmedAndSpacesUnsupported() {
        XCTAssertEqual(KanaRomaji.romanize(" ゆき "), "Yuki")
        // 2語（スペース入り）は1語の名前ではないので変換しない。
        XCTAssertEqual(KanaRomaji.romanize("ゆき ちゃん"), "")
    }
}
