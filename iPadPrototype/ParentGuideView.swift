import SwiftUI

/// 保護者メニューを**初めて開いたとき**に一度だけ出す、大人向けの短いガイド。
///
/// 「単語を入れる → 練習/テスト → 記録を見る」の3枚で全体像だけ伝える。
/// `AppModel.hasSeenParentGuide` が false の間だけ `ParentDashboardView` が提示し、
/// 見終える／スキップで true にする。設定の「ガイドをもう一度」から再表示できる。
struct ParentGuideView: View {
    var language: AppLanguage
    var onFinish: () -> Void

    @State private var page = 0

    private enum Palette {
        static let primary = Color(red: 0.17, green: 0.45, blue: 0.24)
        static let ink = Color(red: 0.12, green: 0.22, blue: 0.34)
    }

    private struct Card: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let body: String
    }

    private var cards: [Card] {
        [
            Card(
                systemImage: "square.and.pencil",
                title: language.text(japanese: "① 単語を登録する", english: "① Add words"),
                body: language.text(
                    japanese: "「コース・単語」タブで、練習させたい単語を追加できます。カメラで学校のテストを読み取ることもできます。",
                    english: "In the “Course / Words” tab you can add words to practice — or scan a school test with the camera."
                )
            ),
            Card(
                systemImage: "pencil.and.outline",
                title: language.text(japanese: "② れんしゅう と テスト", english: "② Practice & test"),
                body: language.text(
                    japanese: "お子さんはホームから練習・テストに進みます。難しさや読み上げの速さは「設定」で調整できます。",
                    english: "Your child starts practice and tests from Home. Adjust difficulty and speech speed in Settings."
                )
            ),
            Card(
                systemImage: "chart.bar.fill",
                title: language.text(japanese: "③ きろくを見る・つける", english: "③ Records & grading"),
                body: language.text(
                    japanese: "「きろく」で進み具合を、「つける」で手書きの丸つけと学校テストの入力ができます。",
                    english: "See progress in “Records”, and grade handwriting or enter school test scores in “Grade”."
                )
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    cardView(card).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack {
            Label(
                language.text(japanese: "はじめてのご案内", english: "Quick guide"),
                systemImage: "hand.wave.fill"
            )
            .font(.headline.weight(.bold))
            .foregroundStyle(Palette.primary)

            Spacer()

            Button {
                onFinish()
            } label: {
                Text(language.text(japanese: "スキップ", english: "Skip"))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 20) {
            Image(systemName: card.systemImage)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Palette.primary)
                .frame(width: 108, height: 108)
                .background(Circle().fill(Palette.primary.opacity(0.12)))

            Text(card.title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(card.body)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        let isLast = page >= cards.count - 1
        Button {
            if isLast {
                onFinish()
            } else {
                withAnimation { page += 1 }
            }
        } label: {
            Text(isLast
                 ? language.text(japanese: "はじめる", english: "Get started")
                 : language.text(japanese: "つぎへ", english: "Next"))
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
