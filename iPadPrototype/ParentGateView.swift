import SwiftUI

/// 大人ゲートの計算問題（純粋ロジック）。2桁＋2桁の足し算。
/// 答えを**手入力**させる（選択式の総当たりを避ける）。暗算できない年齢の子を弾く軽い関所。
struct ParentGateChallenge: Equatable {
    let a: Int
    let b: Int

    var answer: Int { a + b }

    static func random() -> ParentGateChallenge {
        ParentGateChallenge(a: Int.random(in: 11...29), b: Int.random(in: 12...29))
    }
}

/// 子の誤操作で保護者メニューが開かないようにする「かんたんな大人ゲート」。
/// 2桁の足し算の答えを手入力し、正解すると `onPass` を呼ぶ。
/// 選択式ではないので当てずっぽうでは抜けにくい。子側 UX なので文字は最小。
struct ParentGateView: View {
    let onPass: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var challenge = ParentGateChallenge.random()
    @State private var entry = ""
    @State private var shake: CGFloat = 0
    @State private var wrongCount = 0

    var body: some View {
        VStack(spacing: 22) {
            Text("おうちのひとに きいてね")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("つぎの けいさんの こたえを いれてね")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(challenge.a)　＋　\(challenge.b)　＝　？")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .modifier(ShakeEffect(animatableData: shake))

            TextField("こたえ", text: $entry)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(width: 160)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(check)

            Button("かくにん", action: check)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(entry.isEmpty)

            Button("とじる") { dismiss() }
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .presentationDetents([.medium])
    }

    private func check() {
        if Int(entry.trimmingCharacters(in: .whitespaces)) == challenge.answer {
            onPass()
        } else {
            wrongCount += 1
            entry = ""
            withAnimation(.default) { shake += 1 }
            // 数回まちがえたら新しい問題に差し替える（総当たり防止）。
            if wrongCount % 3 == 0 { challenge = ParentGateChallenge.random() }
        }
    }
}

/// 不正解時に左右に揺らすエフェクト。
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
