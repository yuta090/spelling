import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeMode: SessionMode?
    @State private var showingParent = false
    @State private var showingResults = false

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                HomeBackground()

                VStack(spacing: 20) {
                    header

                    Spacer(minLength: 8)

                    Text(language.text(japanese: "✨ 今日のスペリング ✨", english: "✨ Today's Spelling ✨"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.31, blue: 0.70))
                        .multilineTextAlignment(.center)

                    HStack(alignment: .center, spacing: 24) {
                        VStack(spacing: 18) {
                            HomeActionCard(
                                title: language.text(japanese: "れんしゅうする", english: "Practice"),
                                subtitle: language.text(japanese: "書いておぼえる", english: "Look, listen, and write"),
                                systemImage: "pencil",
                                colors: [Color(red: 0.35, green: 0.64, blue: 0.96), Color(red: 0.10, green: 0.35, blue: 0.78)]
                            ) {
                                activeMode = .practice
                            }

                            HomeActionCard(
                                title: language.text(japanese: "テストする", english: "Take Test"),
                                subtitle: language.text(japanese: "力をためそう", english: "Check today's words"),
                                systemImage: "checkmark.clipboard.fill",
                                colors: [Color(red: 0.50, green: 0.78, blue: 0.34), Color(red: 0.18, green: 0.58, blue: 0.20)]
                            ) {
                                activeMode = .test
                            }
                        }
                        .frame(maxWidth: 440)

                        ReviewHomeCard(language: language, reviewCount: model.reviewWords.count) {
                            activeMode = .review
                        }
                        .frame(width: 270)
                    }

                    HomeStatsRow(language: language)
                        .environmentObject(model)

                    Spacer(minLength: 64)
                }
                .padding(.horizontal, 36)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .navigationDestination(item: $activeMode) { mode in
                SpellingSessionView(
                    mode: mode,
                    words: mode == .review ? model.reviewWords : model.words
                )
            }
            .sheet(isPresented: $showingParent) {
                ParentDashboardView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingResults) {
                ResultsView()
                    .environmentObject(model)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Label(language.text(japanese: "ホーム", english: "Home"), systemImage: "house.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.10, green: 0.32, blue: 0.74))

            Spacer()

            Button {
                showingResults = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .accessibilityLabel(language.text(japanese: "結果", english: "Results"))

            Button {
                showingParent = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomeIconButtonStyle())
            .accessibilityLabel(language.text(japanese: "保護者メニュー", english: "Parent menu"))
        }
    }
}

private struct HomeActionCard: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var colors: [Color]
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 22) {
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .bold))
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 9) {
                    Text(title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.92)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 142)
            .padding(.horizontal, 28)
            .background(
                LinearGradient(colors: disabled ? [.gray.opacity(0.5), .gray.opacity(0.65)] : colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: colors.last?.opacity(disabled ? 0 : 0.24) ?? .clear, radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct ReviewHomeCard: View {
    var language: AppLanguage
    var reviewCount: Int
    var action: () -> Void

    private var hasReviewWords: Bool {
        reviewCount > 0
    }

    var body: some View {
        VStack(spacing: 14) {
            BearMascot()
                .frame(width: 96, height: 96)

            VStack(spacing: 6) {
                Text(language.text(japanese: "まちがえた単語が", english: "Words to review"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.12))

                Text(hasReviewWords ? "\(reviewCount)" : "0")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(hasReviewWords ? .red : .secondary)

                Text(language.text(japanese: hasReviewWords ? "こあります" : "ありません", english: hasReviewWords ? "need practice" : "none yet"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Button(action: action) {
                Label(language.text(japanese: "ふくしゅうする", english: "Review"), systemImage: "book.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.52, green: 0.35, blue: 0.76))
            .disabled(!hasReviewWords)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 258)
        .background(Color(red: 1.0, green: 0.95, blue: 0.84).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.95, green: 0.70, blue: 0.36).opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

private struct HomeStatsRow: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            HomeStatChip(
                title: language.text(japanese: "今日", english: "Today"),
                value: "\(model.todaysCorrectCount)/\(model.todaysAttempts.count)",
                systemImage: "target"
            )
            HomeStatChip(
                title: language.text(japanese: "単語", english: "Words"),
                value: "\(model.words.count)",
                systemImage: "list.bullet"
            )
            HomeStatChip(
                title: language.text(japanese: "ふくしゅう", english: "Review"),
                value: "\(model.reviewWords.count)",
                systemImage: "arrow.counterclockwise"
            )
        }
        .frame(maxWidth: 760)
    }
}

private struct HomeStatChip: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.16, green: 0.38, blue: 0.76))
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.38))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }
}

private struct HomeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.13, green: 0.35, blue: 0.76))
            .background(.white.opacity(configuration.isPressed ? 0.65 : 0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.54, green: 0.70, blue: 0.94).opacity(0.55), lineWidth: 1)
            )
    }
}

private struct BearMascot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 82, height: 82)
                .offset(y: 10)

            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 28, height: 28)
                .offset(x: -30, y: -25)
            Circle()
                .fill(Color(red: 0.87, green: 0.55, blue: 0.22))
                .frame(width: 28, height: 28)
                .offset(x: 30, y: -25)

            Circle()
                .fill(Color(red: 0.97, green: 0.77, blue: 0.44))
                .frame(width: 46, height: 38)
                .offset(y: 18)

            Circle()
                .fill(.black.opacity(0.75))
                .frame(width: 7, height: 7)
                .offset(x: -16, y: 2)
            Circle()
                .fill(.black.opacity(0.75))
                .frame(width: 7, height: 7)
                .offset(x: 16, y: 2)
            Circle()
                .fill(.black.opacity(0.78))
                .frame(width: 9, height: 7)
                .offset(y: 14)
        }
    }
}

private struct HomeBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.97, blue: 1.0),
                    Color(red: 0.98, green: 0.99, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Cloud()
                .fill(.white.opacity(0.78))
                .frame(width: 150, height: 62)
                .offset(x: -330, y: -560)
            Cloud()
                .fill(.white.opacity(0.68))
                .frame(width: 120, height: 54)
                .offset(x: 320, y: -550)

            Hills()
                .fill(Color(red: 0.73, green: 0.88, blue: 0.54))
                .frame(height: 142)
                .ignoresSafeArea(edges: .bottom)

            Hills()
                .fill(Color(red: 0.52, green: 0.80, blue: 0.73).opacity(0.75))
                .frame(height: 118)
                .offset(y: 12)
                .ignoresSafeArea(edges: .bottom)

            HStack {
                Tree().frame(width: 42, height: 70)
                Spacer()
                Tree().frame(width: 34, height: 58)
                Spacer()
                Tree().frame(width: 52, height: 88)
                Spacer()
                Tree().frame(width: 38, height: 66)
            }
            .padding(.horizontal, 58)
            .padding(.bottom, 36)
        }
    }
}

private struct Cloud: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.40, width: rect.width * 0.35, height: rect.height * 0.35))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.20, width: rect.width * 0.38, height: rect.height * 0.46))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.34, width: rect.width * 0.34, height: rect.height * 0.36))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.48, width: rect.width * 0.76, height: rect.height * 0.22), cornerSize: CGSize(width: 18, height: 18))
        return path
    }
}

private struct Hills: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 24))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + 10),
            control1: CGPoint(x: rect.width * 0.25, y: rect.midY - 36),
            control2: CGPoint(x: rect.width * 0.64, y: rect.midY + 72)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Tree: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.63, green: 0.45, blue: 0.24))
                .frame(width: 8, height: 36)

            Circle()
                .fill(Color(red: 0.31, green: 0.67, blue: 0.38))
                .frame(width: 34, height: 34)
                .offset(y: -24)
            Circle()
                .fill(Color(red: 0.43, green: 0.76, blue: 0.48))
                .frame(width: 24, height: 24)
                .offset(x: -10, y: -18)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppModel())
}
