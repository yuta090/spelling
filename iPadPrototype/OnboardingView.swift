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
        case welcome, grade, lookAndFeel, coinGift, parentHandoff
    }

    /// 初回プレゼントするコイン数（なかま40〜60・はいけい80〜のので、最初の解放を体験できる量）。
    private let coinGift = 120

    @State private var step: Step = .welcome
    @State private var pickedGrade: GradeLevel?
    @State private var name = ""
    @State private var didLoadName = false
    @State private var bounce = false
    @State private var hintPulse = false
    @State private var charPop = false
    @State private var launched = false
    @State private var pressPop = false
    @State private var coinsGranted = false
    @State private var coinPop = false
    @State private var coinBurst = false
    @State private var coinSpin = 0.0
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
        case .parentHandoff: return "はじめる！"   // 最後のステップ（子がタップして完了）
        default: return "つぎへ"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            advance()
        case .grade:
            if let pickedGrade {
                model.applyOnboardingGrade(pickedGrade)
            }
            advance()
        case .lookAndFeel:
            advance()
        case .coinGift:
            advance()
        case .parentHandoff:
            advance()   // 最後のステップなので finish() に落ちる
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
        case .parentHandoff: parentHandoffStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            // キャラの上に「タップで きせかえ できるよ」のヒント（軽く脈打たせて気づかせる）。
            Label("タップで きせかえ できるよ", systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.92)))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .scaleEffect(hintPulse ? 1.06 : 1.0)

            Button { cycleCharacter() } label: {
                RewardCharacterAvatar(character: HomeRewardCharacter.character(id: model.selectedCharacterID))
                    .frame(width: 150, height: 150)
                    .scaleEffect((bounce ? 1.0 : 0.86) * (charPop ? 1.12 : 1.0))
                    .rotationEffect(.degrees(bounce ? 0 : -6))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            }
            .buttonStyle(.plain)

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
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                hintPulse = true
            }
        }
    }

    /// ウェルカムのキャラをタップ → 解放済みキャラを順に切り替える（その場で「きせかえ」）。
    private func cycleCharacter() {
        let unlocked = unlockedCharacters
        guard !unlocked.isEmpty else { return }
        let index = unlocked.firstIndex { $0.id == model.selectedCharacterID } ?? -1
        let next = unlocked[(index + 1) % unlocked.count]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.selectCharacter(id: next.id)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { charPop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.15)) { charPop = false }
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

    /// コインのプレゼント演出。表示と同時に派手に付与し、タップでもう一度はじける。
    private var coinGiftStep: some View {
        VStack(spacing: 18) {
            Text("🎁 プレゼント！")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.45, blue: 0.22), Color(red: 0.95, green: 0.28, blue: 0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            Button { tapCoin() } label: {
                ZStack {
                    if coinBurst { CoinBurst() }
                    CoinView()
                        .frame(width: 132, height: 132)
                        .scaleEffect(coinPop ? 1.2 : 1.0)
                        .rotation3DEffect(.degrees(coinSpin), axis: (x: 0, y: 1, z: 0))
                        .shadow(color: .orange.opacity(0.45), radius: coinPop ? 20 : 10, y: 6)
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
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        coinBurst = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { coinPop = true }
        withAnimation(.easeOut(duration: 0.6)) { coinSpin += 360 }   // 1回ぐるっと
        coinBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeOut(duration: 0.18)) { coinPop = false }
        }
    }

    /// 最後の1枚は**保護者向け**の引き継ぎ案内。子の演出のあとに、
    /// 「単語登録・設定はホーム右上の⚙️から」を大人向けの文で伝える（右上の歯車を指し示す）。
    private var parentHandoffStep: some View {
        VStack(spacing: 20) {
            // 画面の右上に歯車がある、というレイアウトを小さな模型で示す。
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 190, height: 128)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "house.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.5))
                    )

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: hintPulse ? 12 : 5, y: 3)
                    .scaleEffect(hintPulse ? 1.12 : 1.0)
                    .offset(x: 12, y: -12)
            }
            .padding(.top, 8)

            Text("保護者の方へ")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("単語の登録・レベル・設定は\nホーム右上の ⚙️ から。")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                Text("お子さんの画面には出ません。かんたんな計算で開きます。")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                hintPulse = true
            }
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

/// ツヤのある“鋳造された金貨”の見た目（放射状ハイライト＋ふち＋ベベル＋星）。
private struct CoinFace: View {
    var symbolSize: CGFloat
    var rim: CGFloat = 7
    var bevelInset: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [Color(red: 1.0, green: 0.96, blue: 0.66),
                         Color(red: 1.0, green: 0.80, blue: 0.26),
                         Color(red: 0.93, green: 0.58, blue: 0.08)],
                center: .init(x: 0.36, y: 0.30), startRadius: 1, endRadius: 80))
            Circle().stroke(Color(red: 0.78, green: 0.46, blue: 0.05), lineWidth: rim)   // ふち
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 2).padding(bevelInset)  // 内側のツヤ
            Image(systemName: "star.fill")
                .font(.system(size: symbolSize, weight: .heavy))
                .foregroundStyle(Color(red: 1.0, green: 0.98, blue: 0.82))
                .shadow(color: Color(red: 0.7, green: 0.4, blue: 0.05).opacity(0.5), radius: 1, y: 1)
        }
    }
}

/// 中央の大きな金貨。
private struct CoinView: View {
    var body: some View { CoinFace(symbolSize: 50) }
}

/// コイン付与時にはじける**たくさんの金貨**（全方向へ噴出＋回転＋落下）。
private struct CoinBurst: View {
    @State private var go = false
    private let count = 46

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                // 2周ぶんに散らして全方向をびっしり埋める。
                let angle = Double(i) / Double(count) * 4 * .pi + (i % 2 == 0 ? 0.0 : 0.22)
                let dist = 90.0 + Double((i * 53) % 135)    // ばらけた飛距離 90〜225
                let size = 13.0 + Double(i % 5) * 5.0       // 13〜33
                CoinFace(symbolSize: size * 0.5, rim: 1.5, bevelInset: 3)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(go ? Double((i * 71) % 360) + 540 : 0))
                    .offset(x: go ? cos(angle) * dist : 0,
                            y: go ? sin(angle) * dist + 170 : 0)   // 外へ＋重力で落下（やや遠くまで）
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.4 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { go = true }
        }
    }
}
