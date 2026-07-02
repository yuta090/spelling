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

private enum CastPalette {
    static let primary = Color(red: 0.17, green: 0.45, blue: 0.24)
    static let primarySoft = Color(red: 0.91, green: 0.97, blue: 0.90)
    static let surface = Color.white.opacity(0.92)
    static let surfaceTint = Color(red: 0.97, green: 0.99, blue: 0.97)
    static let ink = Color(red: 0.12, green: 0.22, blue: 0.34)
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
            intro

            // 本人
            castSection(
                title: language.text(japanese: "本人", english: "Child"),
                systemImage: "person.fill"
            ) {
                if let child {
                    personRow(child)
                } else {
                    addButton(
                        label: language.text(japanese: "本人を登録", english: "Add child"),
                        systemImage: "person.badge.plus"
                    ) {
                        editing = CastDraft(role: .child)
                    }
                }
            }

            // 友達（複数）
            castSection(
                title: language.text(japanese: "ともだち", english: "Friends"),
                systemImage: "person.2.fill"
            ) {
                if friends.isEmpty {
                    Text(language.text(japanese: "まだいません。追加すると例文に名前が出ます。",
                                       english: "None yet. Add friends to see their names in lines."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friends) { personRow($0) }
                }
                addButton(
                    label: language.text(japanese: "ともだちを追加", english: "Add friend"),
                    systemImage: "plus.circle.fill"
                ) {
                    editing = CastDraft(role: .friend)
                }
            }

            // 例文セットのプレビュー（親側ツール・子フローには出さない）
            previewSection
        }
        .sheet(item: $editing) { draft in
            CastPersonEditorSheet(language: language, draft: draft)
                .environmentObject(model)
                .presentationDetents([.large])
        }
    }

    // MARK: 部品

    private var intro: some View {
        HStack(spacing: 8) {
            Text(language.text(japanese: "例文に名前を出す", english: "Names in example lines"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(CastPalette.ink)
            ParentInfoButton(
                title: language.text(japanese: "例文に名前を出す", english: "Names in example lines"),
                message: language.text(
                    japanese: "登録した友達の名前が「Yuki likes apples」のように例文に登場します。本人は「Yuta, look!」のような呼びかけで出ます。",
                    english: "Registered friends appear in lines like “Yuki likes apples.” The child appears as a call, e.g. “Yuta, look!”"
                ),
                tint: CastPalette.primary
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CastPalette.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            title: language.text(japanese: "例文セットをみる", english: "Preview lines"),
            systemImage: "text.bubble.fill",
            info: (
                title: language.text(japanese: "例文セットをみる", english: "Preview lines"),
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
        VStack(alignment: .leading, spacing: 3) {
            Text(item.en)
                .font(.headline.weight(.bold))
                .foregroundStyle(CastPalette.ink)
            Text(item.ja)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CastPalette.surfaceTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func personRow(_ person: CastPerson) -> some View {
        Button {
            editing = CastDraft(person: person)
        } label: {
            HStack(spacing: 32) {
                CastAvatarBadge(characterID: person.avatarCharacterID, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(person.displayNameJa.isEmpty ? person.romaji : person.displayNameJa)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CastPalette.ink)
                        if !person.isActive {
                            Text(language.text(japanese: "おやすみ", english: "Off"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 6) {
                        Text(person.romaji)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                        if person.role == .friend {
                            genderChip(person.gender)
                        }
                    }
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(CastPalette.surfaceTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .tapFeedback()
    }

    private func genderChip(_ gender: PersonGender) -> some View {
        let (label, color): (String, Color) = {
            switch gender {
            case .boy: return (language.text(japanese: "男の子", english: "Boy"), Color.blue)
            case .girl: return (language.text(japanese: "女の子", english: "Girl"), Color.pink)
            case .unspecified: return (language.text(japanese: "未設定", english: "—"), Color.secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private func addButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.bordered)
        .tint(CastPalette.primary)
        .tapFeedback()
    }
}

// MARK: - 編集シート

private struct CastPersonEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var language: AppLanguage

    @State private var draft: CastDraft

    init(language: AppLanguage, draft: CastDraft) {
        self.language = language
        _draft = State(initialValue: draft)
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
            field(
                title: language.text(japanese: "ローマ字（英文に出る綴り）", english: "Romaji (spelled in lines)"),
                hint: "Yuki",
                text: $draft.romaji
            )
            Text(language.text(
                japanese: "※ ローマ字は英字のみ・1語（例文では「Yuki」のまま出ます）。",
                english: "Romaji: letters only, one word (appears as “Yuki”)."
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
    let id = UUID()           // シート識別用
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
