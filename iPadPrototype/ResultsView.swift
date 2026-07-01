import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage {
        model.settings.appLanguage
    }

    // テスト(attempts)だけでなく練習(practiceSamples)も数える。おぼえる/練習で書いた日も 0 にしない。
    private var todayTotal: Int {
        model.todaysWrittenWordCount
    }

    // 学習者の結果画面は「いま開いているコースの今のステップ」の見直し語を出す（親の personal 集計とは別）。
    private var reviewList: [SpellingWord] {
        model.selectedReviewWords
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ResultsBackground()

                VStack(spacing: 16) {
                    header

                    ChildTaskBanner(
                        title: language.text(japanese: "今日の結果を見よう", english: "Look at Today's Results"),
                        message: language.text(japanese: "できた単語と、もう一度やる単語をたしかめよう。", english: "Check what you got and what to try again."),
                        systemImage: "trophy.fill",
                        tint: Color(red: 0.84, green: 0.36, blue: 0.08),
                        compact: true
                    )

                    ScrollView {
                        VStack(spacing: 16) {
                            trophyCard

                            HStack(alignment: .top, spacing: 16) {
                                ReviewWordsCard(language: language, words: reviewList)
                                EffortCard(language: language)
                                    .environmentObject(model)
                            }
                        }
                        .padding(.bottom, 12)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label(language.text(japanese: "おわる", english: "Done"), systemImage: "house.fill")
                            .font(.title3.weight(.bold))
                            .frame(minWidth: 230)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
            .tapFeedback()
                    .tint(Color(red: 0.93, green: 0.70, blue: 0.16))
                }
                .padding(24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            Text(language.text(japanese: "結果", english: "Results"))
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.75, green: 0.22, blue: 0.08))

            Spacer()

            Button {
                dismiss()
            } label: {
                Label(language.text(japanese: "閉じる", english: "Close"), systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .tapFeedback()
        }
        .font(.headline.weight(.bold))
    }

    private var trophyCard: some View {
        VStack(spacing: 12) {
            Text(language.text(japanese: "よくできました！", english: "Great work!"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.84, green: 0.20, blue: 0.08))

            Image(systemName: "trophy.fill")
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(Color(red: 0.96, green: 0.68, blue: 0.04))

            // 子どもには点数・正解数を見せない（「点が取れない＝間違い」でやる気を折らない）。
            // 努力＝きょう書いた数だけを、やさしく讃える。数字の内訳は親側にだけ残す。
            Text(language.text(japanese: "きょうは \(todayTotal)こ かけたね！", english: "You wrote \(todayTotal) today!"))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.70, green: 0.29, blue: 0.05))
                .padding(.vertical, 8)
                .padding(.horizontal, 28)
                .background(Color(red: 1.0, green: 0.97, blue: 0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.95, green: 0.66, blue: 0.18), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.95, green: 0.73, blue: 0.34), lineWidth: 1)
        )
    }
}

private struct ReviewWordsCard: View {
    var language: AppLanguage
    var words: [SpellingWord]

    var body: some View {
        ResultCard(title: language.text(japanese: "もう一度やる単語", english: "Words to Try Again"), systemImage: "arrow.counterclockwise") {
            if words.isEmpty {
                Text(language.text(japanese: "見直し単語はありません。", english: "No review words."))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(words.prefix(8)) { word in
                        Text(word.text)
                            .font(.title3.weight(.bold))
                            // 赤（＝バツ/失敗）は避け、やさしい前向きな色にする。
                            .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.90))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct EffortCard: View {
    @EnvironmentObject private var model: AppModel
    var language: AppLanguage

    var body: some View {
        ResultCard(title: language.text(japanese: "がんばりポイント", english: "Effort Points"), systemImage: "star.fill") {
            VStack(spacing: 12) {
                // 「正解した数」は見せない（点＝評価になる）。書いた数＝努力と、次にやる単語だけ。
                // テスト＋練習の両方を数える（おぼえる/練習で書いた日も 0 にしない）。
                ResultValueRow(title: language.text(japanese: "きょう かいた かず", english: "Words written today"), value: "\(model.todaysWrittenWordCount)")
                ResultValueRow(title: language.text(japanese: "つぎに やる単語", english: "Words for next time"), value: "\(model.selectedReviewWords.count)")
            }
        }
    }
}

private struct ResultCard<Content: View>: View {
    var title: String
    var systemImage: String
    var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.64, green: 0.27, blue: 0.08))

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.94, green: 0.72, blue: 0.35), lineWidth: 1)
        )
    }
}

private struct ResultValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
        }
    }
}

private struct ResultsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.97, blue: 0.90),
                Color(red: 1.0, green: 0.99, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ResultsView()
        .environmentObject(AppModel())
}
