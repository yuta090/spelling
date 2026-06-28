import Foundation
import SpellingSyncCore

/// 同梱 confusables_sound.build.csv（ビルド検証ツール `confusables-build` が生成・approved=1 のみ）を
/// 読み、おとり辞書 `ConfusableEntry` 群へ。単語リスニング／リスニング穴埋めのおとりプール。
///
/// 生成元: `swift run confusables-build --write`（draft CSV ＋ wordbank → 検証 → この CSV）。
/// 設計: docs/confusables-sound-authoring-DRAFT-2026-06-28.md §5。失敗時は空（呼び出し側が空ガード）。
enum ConfusablesBundle {
    /// 一度だけ読み込みキャッシュ（語ごとに参照するため再パースを避ける）。
    static let entries: [ConfusableEntry] = load()

    static func load() -> [ConfusableEntry] {
        guard let url = Bundle.main.url(forResource: "confusables_sound.build", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("confusables_sound.build.csv をバンドルから読めません（Resources 同梱を確認）")
            return []
        }
        return ConfusablesSound.parse(csv: text)
    }
}
