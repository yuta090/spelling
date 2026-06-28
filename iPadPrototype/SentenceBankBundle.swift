import Foundation
import SpellingSyncCore

/// 同梱 sentence_bank.json（前処理ツール `sentence-bank-build` が生成・学年タグ/トークン済み）を
/// 読み、文バンク `SentenceItem` 群へ。並べ替え/穴埋め等の出題はこのプールから引く。
///
/// 生成元: `swift run sentence-bank-build --write`（curated 素 ＋ wordbank → 学年タグ付け検証 → この JSON）。
/// 設計: docs/sentence-builder-design-2026-06-27.md §3。失敗時は空（呼び出し側が空ガード）。
enum SentenceBankBundle {
    /// 一度だけ読み込みキャッシュ。
    static let items: [SentenceItem] = load()

    static func load() -> [SentenceItem] {
        guard let url = Bundle.main.url(forResource: "sentence_bank", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("sentence_bank.json をバンドルから読めません（Resources 同梱を確認）")
            return []
        }
        return SentenceBankBuilder.decode(json: text)
    }
}
