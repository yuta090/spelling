import SwiftUI
import SpellingSyncCore

// 親側「なかま」登録画面。例文パーソナライズの登場人物（本人＋友達）を登録する。
// 仕様: docs/personalized-sentences-spec-2026-06-28.md（§6 登録UI）。
//
// プロダクト規約：
// - これは「管理する人（親）」の画面。親ゲートの奥。子のホーム/たんご画面には出さない。
// - 未成年実名のため **ローカル保存のみ**（同期しない・解析に送らない）。
// - 名前は綴り練習の出題語にしない（resolver 側で contentLemmas から除外済み）。
// - アバターは新しい見た目を増やさず、既存キャラ図鑑(HomeRewardCharacter)から選ぶ。
//
// 画面の狙い（UX）：
// - 子のキャラ（オンボーディングで選択済み）と名前は最初から分かっている。
//   → ヒーローで「◯◯の名前が問題に登場する」を名前入り例文つきで先に見せ、
//     登録はかな・ローマ字・アバターをプリフィルして「確認して保存するだけ」にする。
// - 例文中の名前はキャラ色でハイライトし、「自分の名前で問題が作られる」を一目で伝える。

private enum CastPalette {
    static let primary = Color(red: 0.17, green: 0.45, blue: 0.24)
    static let primarySoft = Color(red: 0.91, green: 0.97, blue: 0.90)
    static let surface = Color.white.opacity(0.92)
    static let surfaceTint = Color(red: 0.97, green: 0.99, blue: 0.97)
    static let ink = Color(red: 0.12, green: 0.22, blue: 0.34)
    static let spark = Color(red: 0.98, green: 0.72, blue: 0.18)
}

// MARK: - 本体

struct ParentCastPanel: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    @State private var editing: CastDraft?
    /// 例文プレビューの選択カテゴリ（nil=ぜんぶ）と決定論シード（「べつのをみる」で更新）。
    @State private var previewCategory: SentenceCategory?
    @State private var previewSeed: UInt64 = 0x5E_7A_C0_DE

    private var child: CastPerson? { model.cast.people.first { $0.role == .child } }
    private var friends: [CastPerson] { model.cast.people.filter { $0.role == .friend } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroCard
            castGridSection
            previewSection
        }
        .sheet(item: $editing) { draft in
            CastPersonEditorSheet(language: language, draft: draft)
                .environmentObject(model)
                .presentationDetents([.large])
        }
    }

    // MARK: ヒーロー（子のキャラ＋名前入り例文で「登録したい」を先に作る）

    /// ヒーローに出すキャラ。登録済みならそのアバター、未登録でも子が選んだ現行キャラを使う。
    private var heroCharacter: HomeRewardCharacter {
        HomeRewardCharacter.character(id: child?.avatarCharacterID ?? model.selectedCharacterID)
    }

    /// ヒーローで呼ぶ子の名前（登録済み > プロフィール名 > 汎称）。
    private var heroName: String {
        let registered = child?.displayNameJa.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !registered.isEmpty { return registered }
        let profile = model.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { return profile }
        return language.text(japanese: "お子さん", english: "Your child")
    }

    /// ヒーロー例文の元になる Cast。未登録の間はプロフィール名から見本キャストを組む。
    private var heroCast: Cast {
        if hasActiveCast { return model.cast }
        let kana = model.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        let romaji = KanaRomaji.romanize(kana)
        return Cast(people: [
            CastPerson(role: .child, gender: .unspecified,
                       displayNameJa: kana.isEmpty ? "ゆき" : kana,
                       romaji: romaji.isEmpty ? "Yuki" : romaji,
                       avatarCharacterID: model.selectedCharacterID),
            // 見本用の友達1人（登録を促すための例。実データには入れない）。
            CastPerson(role: .friend, gender: .boy,
                       displayNameJa: "れん",
                       romaji: "Ren",
                       avatarCharacterID: HomeRewardCharacter.defaultID),
        ])
    }

    /// ヒーローの吹き出しに出す1文（名前が実際に入っている文を優先して選ぶ）。
    private var heroItem: SentenceItem? {
        let cast = heroCast
        let items = PersonalizedSessionBuilder.build(
            templates: templates, cast: cast, category: nil, count: 8, seed: 0xCA_FE_F0_0D
        )
        let names = castNames(cast)
        return items.first { item in
            CastNameHighlighter.segments(in: item.en, names: names).contains(where: \.isName)
        } ?? items.first
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RewardCharacterAvatar(character: heroCharacter)
                    .frame(width: 92, height: 92)
                    .shadow(color: heroCharacter.primary.opacity(0.25), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(language.text(japanese: "\(heroName)の名前が、英語の問題に登場！",
                                           english: "\(heroName)'s name shows up in the questions!"))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(CastPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        ParentInfoButton(
                            title: language.text(japanese: "なかまと例文", english: "Cast & lines"),
                            message: language.text(
                                japanese: "登録した友達の名前が「Yuki likes apples.」のように例文へ入ります。本人は「Yuta, look!」のような呼びかけで登場します。名前はこの iPad の中だけに保存され、送信されません。",
                                english: "Registered friends appear in lines like “Yuki likes apples.” The child appears as a call, e.g. “Yuta, look!” Names stay on this iPad only and are never uploaded."
                            ),
                            tint: CastPalette.primary
                        )
                        Spacer(minLength: 0)
                    }

                    if let item = heroItem {
                        heroBubble(item)
                    }
                }
            }

            if child == nil {
                Button {
                    editing = makeChildDraft()
                } label: {
                    Label(language.text(japanese: "\(heroName)を登録して名前入りにする",
                                        english: "Add \(heroName) to personalize"),
                          systemImage: "wand.and.stars")
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(CastPalette.primary)
                .tapFeedback()

                Text(language.text(japanese: "名前とキャラはもう入っています。確認して保存するだけです。",
                                   english: "Name and character are already filled in — just review and save."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if friends.isEmpty {
                Text(language.text(japanese: "つぎは、ともだちを追加すると会話の例文がにぎやかになります。",
                                   english: "Next, add friends to make the dialogue lines livelier."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [heroCharacter.secondary.opacity(0.32), CastPalette.primarySoft],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(CastPalette.spark)
                .padding(10)
        }
    }

    private func heroBubble(_ item: SentenceItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            castHighlightedText(item.en, cast: heroCast, baseColor: CastPalette.ink)
                .font(.headline.weight(.bold))
            castHighlightedText(item.ja, cast: heroCast, baseColor: .secondary)
                .font(.subheadline)
            if !hasActiveCast {
                Text(language.text(japanese: "※ 見本です。登録すると本物の名前で作られます。",
                                   english: "Sample — register to use real names."))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .background(BubbleWithTail().fill(Color.white.opacity(0.95)))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 子の登録ドラフト。プロフィールの名前・選択中キャラをプリフィルして「保存するだけ」にする。
    private func makeChildDraft() -> CastDraft {
        var draft = CastDraft(role: .child)
        draft.displayNameJa = model.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.romaji = KanaRomaji.romanize(draft.displayNameJa)
        draft.avatarCharacterID = model.selectedCharacterID
        return draft
    }

    /// 友達の新規ドラフト。まだ使われていないキャラをプリフィルする（全員おなじ顔を避ける）。
    private func makeFriendDraft() -> CastDraft {
        var draft = CastDraft(role: .friend)
        let used = Set(model.cast.people.compactMap(\.avatarCharacterID))
        draft.avatarCharacterID = HomeRewardCharacter.catalog
            .first { model.unlockedCharacterIDs.contains($0.id) && !used.contains($0.id) }?
            .id
        return draft
    }

    // MARK: なかま一覧（アバター前面のカードグリッド）

    private var castGridSection: some View {
        castSection(
            title: language.text(japanese: "とうじょうする なかま", english: "Cast"),
            systemImage: "person.2.fill"
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                if let child {
                    personCard(child)
                } else {
                    addCard(label: language.text(japanese: "本人を登録", english: "Add child"),
                            systemImage: "person.badge.plus") {
                        editing = makeChildDraft()
                    }
                }
                ForEach(friends) { personCard($0) }
                addCard(label: language.text(japanese: "ともだちを追加", english: "Add friend"),
                        systemImage: "plus.circle.fill") {
                    editing = makeFriendDraft()
                }
            }

            if friends.count < 3 {
                Label(language.text(japanese: "ともだちが増えるほど、例文のバリエーションが増えます。",
                                    english: "More friends, more variety in the lines."),
                      systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CastPalette.primary)
            }

            Label(language.text(japanese: "名前はこの iPad の中だけに保存されます（送信しません）。",
                                english: "Names are stored on this iPad only (never uploaded)."),
                  systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func personCard(_ person: CastPerson) -> some View {
        let character = HomeRewardCharacter.character(id: person.avatarCharacterID ?? HomeRewardCharacter.defaultID)
        return Button {
            editing = CastDraft(person: person)
        } label: {
            VStack(spacing: 8) {
                CastAvatarBadge(characterID: person.avatarCharacterID, size: 64)
                Text(person.displayNameJa.isEmpty ? person.romaji : person.displayNameJa)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CastPalette.ink)
                    .lineLimit(1)
                Text(person.romaji)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if person.role == .child {
                        roleChip(language.text(japanese: "本人", english: "Child"), color: CastPalette.primary)
                    } else {
                        genderChip(person.gender)
                    }
                    if !person.isActive {
                        roleChip(language.text(japanese: "おやすみ", english: "Off"), color: .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(CastPalette.surfaceTint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(character.primary.opacity(0.30), lineWidth: 1.5)
            )
            .opacity(person.isActive ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }

    private func addCard(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(CastPalette.primary)
                    .frame(width: 64, height: 64)
                Text(label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CastPalette.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(CastPalette.primarySoft.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CastPalette.primary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }

    private func roleChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    // MARK: 例文セットのプレビュー

    /// 同梱の承認済みテンプレ（静的・一度だけ読み込み）。
    private var templates: [PersonSentenceTemplate] { RealContentTemplates.cachedTemplates }

    /// テンプレが1件以上あるカテゴリのみ（allCases 順で安定）。
    private var availableCategories: [SentenceCategory] {
        let counts = PersonalizedSessionBuilder.categoryCounts(templates: templates)
        return SentenceCategory.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    /// 選択カテゴリ＋シードで解決した例文セット（名前差し込み済み）。
    private var previewItems: [SentenceItem] {
        PersonalizedSessionBuilder.build(
            templates: templates,
            cast: model.cast,
            category: previewCategory,
            count: 6,
            seed: previewSeed
        )
    }

    private var hasActiveCast: Bool {
        model.cast.people.contains { $0.isActive && !$0.romaji.isEmpty }
    }

    @ViewBuilder
    private var previewSection: some View {
        castSection(
            title: language.text(japanese: "こんな問題が作られます", english: "Lines they'll see"),
            systemImage: "text.bubble.fill",
            info: (
                title: language.text(japanese: "こんな問題が作られます", english: "Lines they'll see"),
                message: language.text(
                    japanese: "カテゴリをえらぶと、登録したなかまの名前が入った例文セットを確認できます。",
                    english: "Pick a category to preview a set of example lines with your cast’s names."
                )
            )
        ) {
            categoryChips

            if !hasActiveCast {
                Label(language.text(japanese: "なかまを登録すると名前が入ります。",
                                    english: "Register cast members to see their names."),
                      systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            let items = previewItems
            if items.isEmpty {
                Text(language.text(japanese: "このカテゴリの例文はまだありません。",
                                   english: "No lines in this category yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { sentenceRow($0) }
                }
                Button {
                    previewSeed = UInt64.random(in: UInt64.min...UInt64.max)
                } label: {
                    Label(language.text(japanese: "べつのをみる", english: "Show another"),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)
                .tint(CastPalette.primary)
                .tapFeedback()
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: language.text(japanese: "ぜんぶ", english: "All"),
                             isSelected: previewCategory == nil) { previewCategory = nil }
                ForEach(availableCategories, id: \.self) { category in
                    categoryChip(title: categoryLabel(category),
                                 isSelected: previewCategory == category) { previewCategory = category }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? CastPalette.primary : CastPalette.primarySoft)
                .foregroundStyle(isSelected ? Color.white : CastPalette.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }

    private func sentenceRow(_ item: SentenceItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let person = firstNamedPerson(in: item) {
                CastAvatarBadge(characterID: person.avatarCharacterID, size: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                castHighlightedText(item.en, cast: model.cast, baseColor: CastPalette.ink)
                    .font(.headline.weight(.bold))
                castHighlightedText(item.ja, cast: model.cast, baseColor: .secondary)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CastPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 英文の最初に名前が出る人（行の左に小さいアバターを添える）。
    private func firstNamedPerson(in item: SentenceItem) -> CastPerson? {
        let segments = CastNameHighlighter.segments(in: item.en, names: castNames(model.cast))
        guard let name = segments.first(where: \.isName)?.text else { return nil }
        return model.cast.people.first { $0.isActive && ($0.romaji == name || $0.displayNameJa == name) }
    }

    private func categoryLabel(_ category: SentenceCategory) -> String {
        switch category {
        case .school:   return language.text(japanese: "学校", english: "School")
        case .play:     return language.text(japanese: "あそび", english: "Play")
        case .greeting: return language.text(japanese: "あいさつ", english: "Greeting")
        case .home:     return language.text(japanese: "おうち", english: "Home")
        case .daily:    return language.text(japanese: "せいかつ", english: "Daily")
        case .other:    return language.text(japanese: "そのほか", english: "Other")
        }
    }

    @ViewBuilder
    private func castSection<Content: View>(title: String, systemImage: String,
                                            info: (title: String, message: String)? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(CastPalette.primary)
                if let info {
                    ParentInfoButton(title: info.title, message: info.message, tint: CastPalette.primary)
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CastPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func genderChip(_ gender: PersonGender) -> some View {
        let (label, color): (String, Color) = {
            switch gender {
            case .boy: return (language.text(japanese: "男の子", english: "Boy"), Color.blue)
            case .girl: return (language.text(japanese: "女の子", english: "Girl"), Color.pink)
            case .unspecified: return (language.text(japanese: "未設定", english: "—"), Color.secondary)
            }
        }()
        return roleChip(label, color: color)
    }
}

// MARK: - 名前ハイライト（純ロジック CastNameHighlighter の描画側）

/// 例文中のなかま名をその人のキャラ色＋太字で光らせた Text を組む。
/// 名前→人の解決は romaji / かな名の完全一致（文はテンプレ由来なので一致が保証される）。
private func castHighlightedText(_ text: String, cast: Cast, baseColor: Color) -> Text {
    let people = cast.people.filter { $0.isActive }
    let names = people.flatMap { [$0.romaji, $0.displayNameJa] }.filter { !$0.isEmpty }
    var result = Text(verbatim: "")
    for segment in CastNameHighlighter.segments(in: text, names: names) {
        if segment.isName,
           let person = people.first(where: { $0.romaji == segment.text || $0.displayNameJa == segment.text }) {
            let character = HomeRewardCharacter.character(id: person.avatarCharacterID ?? HomeRewardCharacter.defaultID)
            result = result + Text(segment.text)
                .foregroundColor(character.accent)
                .fontWeight(.heavy)
        } else {
            result = result + Text(segment.text).foregroundColor(baseColor)
        }
    }
    return result
}

/// ハイライト対象の名前一覧（active かつ romaji が空でない人の romaji・かな名）。
private func castNames(_ cast: Cast) -> [String] {
    cast.people
        .filter { $0.isActive && !$0.romaji.isEmpty }
        .flatMap { [$0.romaji, $0.displayNameJa] }
}

/// 左に小さなしっぽの付いた吹き出し（ヒーローのキャラが話している見た目にする）。
private struct BubbleWithTail: Shape {
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 10
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: tail, y: 0, width: max(rect.width - tail, 0), height: rect.height),
            cornerSize: CGSize(width: 12, height: 12)
        )
        let midY = min(rect.height * 0.5, 34)
        path.move(to: CGPoint(x: tail + 2, y: midY - 8))
        path.addLine(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: tail + 2, y: midY + 8))
        path.closeSubpath()
        return path
    }
}

// MARK: - 編集シート

private struct CastPersonEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    @State private var draft: CastDraft
    /// ローマ字欄を親が触ったら自動補完をやめる（手入力を上書きしない）。
    @State private var romajiTouched: Bool
    @FocusState private var romajiFocused: Bool

    init(language: AppLanguage, draft: CastDraft) {
        self.language = language
        _draft = State(initialValue: draft)
        _romajiTouched = State(initialValue: draft.personID != nil)
    }

    private var isFriend: Bool { draft.role == .friend }

    /// 保存可否：かな名・ローマ字とも非空、ローマ字は英字のみ、友達は性別必須。
    private var canSave: Bool {
        let kanaOK = !draft.displayNameJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let romaji = draft.romaji.trimmingCharacters(in: .whitespacesAndNewlines)
        let romajiOK = !romaji.isEmpty && romaji.allSatisfy { $0.isLetter && $0.isASCII }
        let genderOK = !isFriend || draft.gender != .unspecified
        return kanaOK && romajiOK && genderOK
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameFields
                    if isFriend { genderField }
                    avatarField
                    draftPreview
                    if isFriend { activeField }
                    if draft.personID != nil { deleteButton }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text(japanese: "キャンセル", english: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text(japanese: "保存", english: "Save")) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var title: String {
        let new = draft.personID == nil
        if isFriend {
            return new ? language.text(japanese: "ともだちを追加", english: "Add friend")
                       : language.text(japanese: "ともだちを編集", english: "Edit friend")
        } else {
            return new ? language.text(japanese: "本人を登録", english: "Add child")
                       : language.text(japanese: "本人を編集", english: "Edit child")
        }
    }

    private var nameFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(
                title: language.text(japanese: "なまえ（かな）", english: "Name (kana)"),
                hint: language.text(japanese: "例：ゆき", english: "e.g. Yuki"),
                text: $draft.displayNameJa
            )
            .onChange(of: draft.displayNameJa) { newValue in
                // かな入力に追従してローマ字を自動補完（親がローマ字欄を触るまで）。変換不能なら触らない。
                guard !romajiTouched else { return }
                let romanized = KanaRomaji.romanize(newValue)
                if !romanized.isEmpty || newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.romaji = romanized
                }
            }
            field(
                title: language.text(japanese: "ローマ字（英文に出る綴り）", english: "Romaji (spelled in lines)"),
                hint: "Yuki",
                text: $draft.romaji
            )
            .focused($romajiFocused)
            .onChange(of: romajiFocused) { focused in
                if focused { romajiTouched = true }
            }
            Text(language.text(
                japanese: "※ ローマ字は英字のみ・1語（例文では「Yuki」のまま出ます）。かなを入れると自動で入ります。",
                english: "Romaji: letters only, one word (appears as “Yuki”). Auto-filled from kana."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func field(title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(CastPalette.ink)
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(japanese: "性別（代名詞 he / she に使います）", english: "Gender (for he / she)"))
                .font(.subheadline.weight(.bold)).foregroundStyle(CastPalette.ink)
            Picker("", selection: $draft.gender) {
                Text(language.text(japanese: "男の子", english: "Boy")).tag(PersonGender.boy)
                Text(language.text(japanese: "女の子", english: "Girl")).tag(PersonGender.girl)
            }
            .pickerStyle(.segmented)
        }
    }

    private var avatarField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(japanese: "アバター", english: "Avatar"))
                .font(.subheadline.weight(.bold)).foregroundStyle(CastPalette.ink)
            CastAvatarPicker(selection: $draft.avatarCharacterID,
                             unlockedIDs: model.unlockedCharacterIDs,
                             language: language)
        }
    }

    // MARK: この名前でどう出るか（保存前のライブプレビュー）

    /// 入力途中のドラフトを既存 cast に合成し、その人の名前が入った例文を1つ選ぶ。
    private var draftPreviewItem: (item: SentenceItem, cast: Cast)? {
        let romaji = AppModel.normalizeRomaji(draft.romaji)
        guard !romaji.isEmpty, romaji.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        let personID = draft.personID ?? draft.id
        let person = CastPerson(
            id: personID,
            role: draft.role,
            gender: draft.role == .child ? .unspecified : draft.gender,
            displayNameJa: draft.displayNameJa.trimmingCharacters(in: .whitespacesAndNewlines),
            romaji: romaji,
            avatarCharacterID: draft.avatarCharacterID,
            isActive: true
        )
        var people = model.cast.people.filter { $0.id != personID }
        if person.role == .child { people.removeAll { $0.role == .child } }
        people.append(person)
        let cast = Cast(people: people)

        let items = PersonalizedSessionBuilder.build(
            templates: RealContentTemplates.cachedTemplates,
            cast: cast, category: nil, count: 12, seed: 0xD1_2A_FF_07
        )
        let ownNames = [person.romaji, person.displayNameJa].filter { !$0.isEmpty }
        let item = items.first { item in
            CastNameHighlighter.segments(in: item.en, names: ownNames).contains(where: \.isName)
        }
        return item.map { ($0, cast) }
    }

    @ViewBuilder
    private var draftPreview: some View {
        if let preview = draftPreviewItem {
            VStack(alignment: .leading, spacing: 6) {
                Label(language.text(japanese: "こんなふうに出ます", english: "How it will look"),
                      systemImage: "text.bubble")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CastPalette.primary)
                VStack(alignment: .leading, spacing: 3) {
                    castHighlightedText(preview.item.en, cast: preview.cast, baseColor: CastPalette.ink)
                        .font(.headline.weight(.bold))
                    castHighlightedText(preview.item.ja, cast: preview.cast, baseColor: .secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CastPalette.primarySoft.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var activeField: some View {
        Toggle(isOn: $draft.isActive) {
            Text(language.text(japanese: "例文に登場させる", english: "Appear in lines"))
                .font(.subheadline.weight(.bold)).foregroundStyle(CastPalette.ink)
        }
        .tint(CastPalette.primary)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let id = draft.personID { model.removeCastPerson(id: id) }
            dismiss()
        } label: {
            Label(language.text(japanese: "削除", english: "Delete"), systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .padding(.top, 4)
    }

    private func save() {
        model.upsertCastPerson(
            personID: draft.personID,
            role: draft.role,
            gender: isFriend ? draft.gender : .unspecified,   // 本人は性別を持たせない（呼びかけ専用）
            displayNameJa: draft.displayNameJa,
            romaji: draft.romaji,
            avatarCharacterID: draft.avatarCharacterID,
            isActive: draft.isActive
        )
        dismiss()
    }
}

// MARK: - アバター（既存キャラ図鑑の再利用）

/// `avatarCharacterID` を既存 `RewardCharacterAvatar` で描画する小バッジ。nil は既定キャラ。
struct CastAvatarBadge: View {
    var characterID: String?
    var size: CGFloat = 44

    var body: some View {
        let character = HomeRewardCharacter.character(id: characterID ?? HomeRewardCharacter.defaultID)
        RewardCharacterAvatar(character: character)
            .frame(width: size, height: size)
    }
}

/// アンロック済みキャラから1体選ぶ横スクロールピッカー（OnboardingView と同じ見た目言語）。
private struct CastAvatarPicker: View {
    @Binding var selection: String?
    var unlockedIDs: Set<String>
    var language: AppLanguage

    private var characters: [HomeRewardCharacter] {
        HomeRewardCharacter.catalog.filter { unlockedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(characters) { character in
                    Button {
                        selection = character.id
                    } label: {
                        RewardCharacterAvatar(character: character)
                            .frame(width: 56, height: 56)
                            .padding(6)
                            .background(
                                Circle().fill(selection == character.id
                                              ? CastPalette.primary.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                Circle().stroke(selection == character.id
                                                ? CastPalette.primary : Color.clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                    .tapFeedback()
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 編集ドラフト

/// 編集シートを駆動する一時状態。`personID == nil` は新規。
private struct CastDraft: Identifiable {
    let id = UUID()           // シート識別用（新規時はライブプレビューの仮 person id にも使う）
    var personID: UUID?       // 既存人物 id（nil=新規）
    var role: CastRole
    var displayNameJa: String = ""
    var romaji: String = ""
    var gender: PersonGender = .unspecified
    var avatarCharacterID: String?
    var isActive: Bool = true

    init(role: CastRole) {
        self.personID = nil
        self.role = role
    }

    init(person: CastPerson) {
        self.personID = person.id
        self.role = person.role
        self.displayNameJa = person.displayNameJa
        self.romaji = person.romaji
        self.gender = person.gender
        self.avatarCharacterID = person.avatarCharacterID
        self.isActive = person.isActive
    }
}

// MARK: - AppModel 変更ヘルパ（永続化は @Published cast の didSet が担う）

extension AppModel {
    /// かな・ローマ字を正規化して cast に upsert（id 一致で置換・無ければ追加）。
    /// 不変条件はここ（唯一の書き手）で担保する：
    /// - 本人(.child)は性別を持たない（呼びかけ専用）→ 常に `.unspecified`、かつ常に1人。
    /// - 友達(.friend)は性別必須 → `.unspecified` は不正として無視（UI 側でも禁止済み）。
    func upsertCastPerson(personID: UUID?, role: CastRole, gender: PersonGender,
                          displayNameJa: String, romaji: String,
                          avatarCharacterID: String?, isActive: Bool) {
        if role == .friend && gender == .unspecified { return }   // 不正データを保存しない
        let resolvedGender: PersonGender = (role == .child) ? .unspecified : gender
        let person = CastPerson(
            id: personID ?? UUID(),
            role: role,
            gender: resolvedGender,
            displayNameJa: displayNameJa.trimmingCharacters(in: .whitespacesAndNewlines),
            romaji: Self.normalizeRomaji(romaji),
            avatarCharacterID: avatarCharacterID,
            isActive: isActive
        )
        // 本人は1人だけ：別 id の既存 child を除去してから反映する。
        if person.role == .child {
            cast.people.removeAll { $0.role == .child && $0.id != person.id }
        }
        if let idx = cast.people.firstIndex(where: { $0.id == person.id }) {
            cast.people[idx] = person
        } else {
            cast.people.append(person)
        }
    }

    func removeCastPerson(id: UUID) {
        cast.people.removeAll { $0.id == id }
    }

    /// 英文に1語で出る綴り。前後空白除去・先頭大文字（"yuki"→"Yuki"）。
    static func normalizeRomaji(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }
}
