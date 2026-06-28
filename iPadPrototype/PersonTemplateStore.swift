import Foundation
import SpellingSyncCore

// 同梱の承認済みパーソナライズ・テンプレ（`Resources/person_templates.authoring.json`）を
// 起動時に1度だけ読み込む薄い app 層ストア。純粋ロジックは `SpellingSyncCore` 側。
// 仕様: docs/personalized-sentences-spec-2026-06-28.md（§6 同梱）。
//
// v1 は JSON 直同梱（承認済みセット＝ファイルそのもの）。将来 sqlite の
// `sentence_templates(approved=1)` に寄せる場合もこの境界（[PersonSentenceTemplate] を返す）は不変。
enum PersonTemplateStore {

    /// バンドルから承認済みテンプレを読み込む。失敗時は空（＝フォールバックで今日と同じ体験）。
    static func loadBundled() -> [PersonSentenceTemplate] {
        guard let url = Bundle.main.url(forResource: "person_templates.authoring", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try PersonTemplateAuthoring.load(jsonArray: data)
        } catch {
            // 同梱データの破損はフォールバックに退避（クラッシュさせない）。
            return []
        }
    }
}
