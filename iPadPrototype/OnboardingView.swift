import SwiftUI

/// 初回だけ出す**子ども向けミニツアー**（オフライン優先・全部任意）。
///
/// なんねんせい？（学年→レベルに合う初期単語をシード）→ すきな なかま＆はいけい → 保護者の方へ（任意）。
/// 各ステップに「スキップ」（押すと確認）。最後に `AppModel.hasCompletedOnboarding = true` を立て、
/// `RootView` がホームへ切り替える。子に「レベル/順位」は見せない（学年は事実として聞くだけ）。
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: SyncSession

    private enum Step: Int, CaseIterable {
        case welcome, grade, lookAndFeel, parent
    }

    @State private var step: Step = .welcome
    @State private var pickedGrade: GradeLevel?
    @State private var name = ""
    @State private var didLoadName = false
    @State private var bounce = false
    @State private var showingAccount = false
    @State private var showingSkipConfirm = false

    var body: some View {
        ZStack {
            // 選んだ背景をそのまま下敷きにして、変更が即反映される楽しさを出す。
            HomeBackground(themeID: model.selectedBackgroundID)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                Spacer(minLength: 8)
                content
                Spacer(minLength: 8)
                controls
            }
            .padding(28)
            .frame(maxWidth: 760)
        }
        .onAppear {
            // 既存ユーザーのニックネームを引き継ぐ（空で上書きして消さないため）。
            if !didLoadName { name = model.childName; didLoadName = true }
        }
        .sheet(isPresented: $showingAccount) { AccountSyncView(session: session) }
        .confirmationDialog("ほんとうに スキップする？", isPresented: $showingSkipConfirm, titleVisibility: .visible) {
            Button("スキップする", role: .destructive) { advance() }
            Button("つづける", role: .cancel) {}
        } message: {
            Text("あとで「保護者メニュー」からも変えられます。")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            // 進み具合（小さなドット）。ウェルカムは“表紙”なので出さない。
            if step != .welcome {
                HStack(spacing: 6) {
                    ForEach(Step.allCases.filter { $0 != .welcome }, id: \.rawValue) { s in
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            Spacer()
            if step != .welcome {
                Button("スキップ") { showingSkipConfirm = true }
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var controls: some View {
        Button(primaryTitle) { primaryAction() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(step == .grade && pickedGrade == nil)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "はじめる"
        case .parent: return "やってみる！"
        default: return "つぎへ"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            advance()
        case .grade:
            if let pickedGrade {
                model.seedStarterWordsIfDefault(for: pickedGrade)
            }
            advance()
        case .lookAndFeel:
            advance()
        case .parent:
            finish()
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .grade: gradeStep
        case .lookAndFeel: lookAndFeelStep
        case .parent: parentStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            RewardCharacterAvatar(character: HomeRewardCharacter.character(id: model.selectedCharacterID))
                .frame(width: 150, height: 150)
                .scaleEffect(bounce ? 1.0 : 0.86)
                .rotationEffect(.degrees(bounce ? 0 : -6))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            Text("はじめまして！")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Text("えいごの たんごで\nいっしょに あそぼう！")
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.5).repeatCount(3, autoreverses: true)) {
                bounce = true
            }
        }
    }

    private var gradeStep: some View {
        VStack(spacing: 20) {
            title(emoji: "🎒", text: "なんねんせい？")
            subtitle("あうレベルの たんごを ようい します。")

            VStack(spacing: 12) {
                gradeRow(GradeLevel.allCases.filter(\.isElementary))
                gradeRow(GradeLevel.allCases.filter { !$0.isElementary })
            }
        }
    }

    private func gradeRow(_ grades: [GradeLevel]) -> some View {
        HStack(spacing: 10) {
            ForEach(grades) { grade in
                Button {
                    pickedGrade = grade
                } label: {
                    Text(grade.label)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(width: 72, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(pickedGrade == grade ? Color.accentColor : Color(.secondarySystemBackground))
                        )
                        .foregroundStyle(pickedGrade == grade ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lookAndFeelStep: some View {
        VStack(spacing: 18) {
            title(emoji: "✨", text: "すきな なかま と はいけい")
            subtitle("タップで えらべるよ。")

            // なかま（解放済みのみ）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(unlockedCharacters) { character in
                        Button {
                            model.selectCharacter(id: character.id)
                        } label: {
                            RewardCharacterAvatar(character: character)
                                .frame(width: 64, height: 64)
                                .padding(8)
                                .background(
                                    Circle().fill(model.selectedCharacterID == character.id
                                                  ? Color.accentColor.opacity(0.25) : Color.clear)
                                )
                                .overlay(
                                    Circle().stroke(model.selectedCharacterID == character.id
                                                    ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            // はいけい（解放済みのみ）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(unlockedBackgrounds) { theme in
                        Button {
                            model.selectBackground(id: theme.id)
                        } label: {
                            HomeBackgroundThumbnail(theme: theme)
                                .frame(width: 96, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(model.selectedBackgroundID == theme.id
                                                ? Color.accentColor : Color.white.opacity(0.6), lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            if unlockedBackgrounds.count <= 1 {
                Text("れんしゅうして コインをためると、はいけいが ふえるよ！")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var parentStep: some View {
        VStack(spacing: 16) {
            title(emoji: "👋", text: "保護者の方へ")
            subtitle("ニックネームや、ほかの端末との同期は任意です（あとでも設定できます）。")

            TextField("お子さんのニックネーム（任意）", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(maxWidth: 360)

            Button(session.activeHouseholdID != nil ? "同期は設定済み ✓" : "サインインして同期する（任意）") {
                showingAccount = true
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private var unlockedCharacters: [HomeRewardCharacter] {
        HomeRewardCharacter.catalog.filter { model.unlockedCharacterIDs.contains($0.id) }
    }

    private var unlockedBackgrounds: [HomeBackgroundTheme] {
        HomeBackgroundTheme.catalog.filter { model.unlockedBackgroundIDs.contains($0.id) }
    }

    private func title(emoji: String, text: String) -> some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 52))
            Text(text)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            finish()
        }
    }

    private func finish() {
        // 入力があったときだけ更新（空で既存ニックネームを消さない）。
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { model.childName = trimmed }
        model.hasCompletedOnboarding = true   // RootView がホームへ切り替える
    }
}
