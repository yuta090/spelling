import SwiftUI
import SpellingSyncCore

// 本物のテンプレ（承認済み34件）を実ループに流し込む試遊画面。
// 流れ: バンドルの person_templates.authoring.json を読む
//      → PersonTemplateAuthoring.load で PersonSentenceTemplate 群に変換
//      → デモ Cast（友達/本人）で SentencePersonalizer.resolve → 実 SentenceItem
//      → 既存の WordOrderingDemoView（答え合わせカード・音声・未習語マーカー配線済み）で再生。
//
// アプリ本体は薄く：純粋ロジック（load/resolve）は SpellingSyncCore に委譲し、
// ここは「バンドル I/O ＋ デモ Cast の組み立て ＋ 画面提示」だけを担う。
// v1 はおとり不要の **並べ替え** 専用（テンプレに穴埋めおとりを持たせていないため）。

enum RealContentTemplates {
    /// バンドル同梱の承認済みオーサリング JSON（person_templates.authoring.json）。
    static let resourceName = "person_templates.authoring"
    static let resourceExtension = "json"

    /// 試遊用のデモ Cast。親が友達/本人を登録した状態を再現する。
    /// id は固定（決定論：実行ごとに割り当てがブレないように）。
    static func demoCast() -> Cast {
        Cast(people: [
            CastPerson(id: uuid(1), role: .friend, gender: .girl,
                       displayNameJa: "さくら", romaji: "Sakura", avatarCharacterID: "rabbit"),
            CastPerson(id: uuid(2), role: .friend, gender: .boy,
                       displayNameJa: "けんた", romaji: "Kenta", avatarCharacterID: "bear"),
            CastPerson(id: uuid(3), role: .child, gender: .unspecified,
                       displayNameJa: "ゆうた", romaji: "Yuta", avatarCharacterID: "fox")
        ])
    }

    /// 同梱テンプレを一度だけ読み込みキャッシュする。練習画面の例文ヒントは単語ごとに
    /// 参照するため、語が変わるたびに JSON を再パースしないようここで保持する。失敗時は空。
    static let cachedTemplates: [PersonSentenceTemplate] = loadTemplates() ?? []

    /// バンドルからオーサリング JSON を読み、PersonSentenceTemplate 群へ変換。
    static func loadTemplates() -> [PersonSentenceTemplate]? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("person_templates.json をバンドルから読めません（Resources 同梱を確認）")
            return nil
        }
        do {
            return try PersonTemplateAuthoring.load(jsonArray: data)
        } catch {
            assertionFailure("テンプレの検証/変換に失敗: \(error)")
            return nil
        }
    }

    private static func uuid(_ n: UInt8) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = n
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - 本物コンテンツのセッション（並べ替え）

struct RealContentSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// プレビュー/テスト用の明示アイテム（指定時は Cast 解決を行わない）。
    private let explicitItems: [SentenceItem]?

    init() { self.explicitItems = nil }
    init(items: [SentenceItem]) { self.explicitItems = items }

    /// 親が登録した Cast を使う。未登録（在席者ゼロ）ならデモ Cast で試遊できる。
    private var effectiveCast: Cast {
        model.cast.people.contains { $0.isActive } ? model.cast : RealContentTemplates.demoCast()
    }

    /// 出題アイテムと、復習チップから除外する名前（同期流出防止）。
    private var session: (items: [SentenceItem], hidden: Set<String>) {
        if let explicitItems { return (explicitItems, []) }
        let cast = effectiveCast
        let templates = RealContentTemplates.loadTemplates() ?? []
        let items = PersonalizedSessionBuilder.build(templates: templates, cast: cast,
                                                     count: 12, seed: 20_260_628)
            .filter { $0.isScramblable }
        let hidden = Set(cast.people.map(\.romaji).filter { !$0.isEmpty })
        return (items, hidden)
    }

    var body: some View {
        let session = self.session
        if session.items.isEmpty {
            // 同梱漏れ等で空のときは無言で落とさず、状態を見せる。
            VStack(spacing: 12) {
                Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("コンテンツを よみこめませんでした")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Button("とじる") { dismiss() }
            }
            .padding(32)
        } else {
            // 名前は復習チップから除外（未成年実名を綴り練習→単語同期で端末外へ出さない）。
            // 間違えた文は ReviewQueue（grammar キュー）に記録し、今後のラウンド/セッションで
            // 「もういちど」マーク付きで繰り返し出題＝数回正解で卒業（練習側には出さない方針）。
            WordOrderingDemoView(items: session.items,
                                 hiddenReviewWords: session.hidden,
                                 onEnrollReviewWord: { model.enrollReviewWord($0) },
                                 composeRound: { model.composeGrammarRound(base: $0) },
                                 onGrade: { model.recordGrammarResult(itemID: $0, correct: $1) },
                                 onRoundComplete: { model.advanceGrammarRound() })
        }
    }
}

// MARK: - DEBUG 起動ボタン

#if DEBUG
struct RealContentSessionDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.trailing, 12).padding(.bottom, 60)
        .accessibilityLabel("本物コンテンツ試遊（名前入り）")
        .sheet(isPresented: $isPresented) { RealContentSessionView() }
    }
}
#endif

#Preview {
    // バンドル/JSON 解析に依存させず、固定の見本で見た目だけ確認する。
    RealContentSessionView(items: [
        SentenceItem(en: "Sakura likes apples", ja: "さくらは りんごが すき",
                     tokens: ["Sakura", "likes", "apples"], gradeBand: 1, grammar: .presentSimple),
        SentenceItem(en: "Kenta can run fast", ja: "けんたは はやく はしれる",
                     tokens: ["Kenta", "can", "run", "fast"], gradeBand: 1, grammar: .canModal)
    ])
}
