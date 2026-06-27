import SwiftUI
import UIKit

/// 初回だけ出す**子ども向けミニツアー**（オフライン優先・全部任意）。
///
/// なんねんせい？（学年→レベルに合う初期単語をシード）→ すきな なかま＆はいけい → 保護者の方へ（任意）。
/// 各ステップに「スキップ」（押すと確認）。最後に `AppModel.hasCompletedOnboarding = true` を立て、
/// `RootView` がホームへ切り替える。子に「レベル/順位」は見せない（学年は事実として聞くだけ）。
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: SyncSession

    private enum Step: Int, CaseIterable {
        case welcome, grade, lookAndFeel, coinGift, parent
    }

    /// 初回プレゼントするコイン数（なかま4〜6・はいけい8〜のので、最初の解放を体験できる量）。
    private let coinGift = 12

    @State private var step: Step = .welcome
    @State private var pickedGrade: GradeLevel?
    @State private var name = ""
    @State private var didLoadName = false
    @State private var bounce = false
    @State private var launched = false
    @State private var pressPop = false
    @State private var coinsGranted = false
    @State private var coinPop = false
    @State private var coinBurst = false
    @State private var showingAccount = false
    @State private var showingSkipConfirm = false

    var body: some View {
        ZStack {
            // 選んだ背景をそのまま下敷きにして、変更が即反映される楽しさを出す。
            HomeBackground(themeID: model.selectedBackgroundID)
                .ignoresSafeArea()
                .opacity(launched ? 1 : 0)

            VStack(spacing: 20) {
                header
                Spacer(minLength: 12)
                // ボタンはコンテンツ直下に置いて中央寄せ（最下部に固定しない）。
                VStack(spacing: 28) {
                    content
                    controls
                }
                Spacer(minLength: 12)
            }
            .padding(28)
            .frame(maxWidth: 760)
            .opacity(launched ? 1 : 0)
            .scaleEffect(launched ? 1 : 0.94)
            .offset(y: launched ? 0 : 16)
        }
        .onAppear {
            // 既存ユーザーのニックネームを引き継ぐ（空で上書きして消さないため）。
            if !didLoadName { name = model.childName; didLoadName = true }
            // 初回起動の入場トランジション（全体をふわっと出す）。
            if !launched {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) { launched = true }
            }
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
        if step == .welcome {
            startButton
        } else {
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(step == .grade && pickedGrade == nil)
        }
    }

    /// ウェルカムの「はじめる」。タップで派手にポップ＋スパークル＋触覚 → 次へ。
    private var startButton: some View {
        Button { celebrateAndStart() } label: {
            Text("はじめる")
                .font(.title2.weight(.heavy))
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor))
                .scaleEffect(pressPop ? 1.18 : 1.0)
                .shadow(color: Color.accentColor.opacity(0.45), radius: pressPop ? 18 : 8, y: 5)
                .overlay { if pressPop { SparkleBurst() } }
        }
        .buttonStyle(.plain)
    }

    private func celebrateAndStart() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pressPop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.15)) { pressPop = false }
            primaryAction()
        }
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
        case .coinGift:
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
        case .coinGift: coinGiftStep
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

    /// コインのプレゼント演出。表示と同時に派手に付与し、タップでもう一度はじける。
    private var coinGiftStep: some View {
        VStack(spacing: 18) {
            Text("🎁 プレゼント！")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Button { tapCoin() } label: {
                ZStack {
                    if coinBurst { CoinBurst() }
                    CoinView()
                        .frame(width: 132, height: 132)
                        .scaleEffect(coinPop ? 1.16 : 1.0)
                        .rotation3DEffect(.degrees(coinPop ? 18 : 0), axis: (x: 0, y: 1, z: 0))
                        .shadow(color: .orange.opacity(0.4), radius: coinPop ? 18 : 10, y: 6)
                }
            }
            .buttonStyle(.plain)

            Text("コインを \(coinGift)こ もらったよ！")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.10))

            Text("コインで なかま や はいけい を\nふやせるよ！ タップしてみてね")
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            // 初回だけ付与（行き来しても二重に増やさない）。
            if !coinsGranted {
                coinsGranted = true
                model.rewardCoins += coinGift
            }
            popCoin()
        }
    }

    private func tapCoin() {
        popCoin()
    }

    private func popCoin() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        coinBurst = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { coinPop = true }
        coinBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.18)) { coinPop = false }
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
        model.pendingFirstSession = true      // ホームで自動的に1回プレイを始める
        model.hasCompletedOnboarding = true   // RootView がホームへ切り替える
    }
}

/// 「はじめる」タップ時に放射するスパークル（楽しさの演出）。
private struct SparkleBurst: View {
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8.0 * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.yellow)
                    .offset(x: go ? cos(angle) * 72 : 0, y: go ? sin(angle) * 72 : 0)
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.3 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { go = true }
        }
    }
}

/// 金貨の見た目（金グラデの円＋星）。
private struct CoinView: View {
    private let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.86, blue: 0.35), Color(red: 0.96, green: 0.66, blue: 0.13)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle().fill(gold)
            Circle().stroke(Color(red: 0.82, green: 0.52, blue: 0.08), lineWidth: 5)
            Image(systemName: "star.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}

/// コイン付与時にはじける小さな金貨（外へ放射＋少し落下）。
private struct CoinBurst: View {
    @State private var go = false
    private let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.86, blue: 0.35), Color(red: 0.96, green: 0.66, blue: 0.13)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10.0 * 2 * .pi
                Circle()
                    .fill(gold)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    )
                    .offset(x: go ? cos(angle) * 92 : 0, y: go ? sin(angle) * 70 + 56 : 0)
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.5 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { go = true }
        }
    }
}
