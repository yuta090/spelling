import SwiftUI

/// 初回だけ出す**軽い保護者向けオンボーディング**。
///
/// オフライン優先なので、サインイン/同期は任意（スキップしてそのまま使える）。
/// ようこそ → 子のニックネーム（任意）→ 同期（任意）→ おわり、の 1〜2 分の流れ。
/// 完了で `AppModel.hasCompletedOnboarding = true` を立て、`RootView` がホームへ切り替える。
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: SyncSession

    @State private var step = 0
    @State private var name = ""
    @State private var showingAccount = false

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            content
            Spacer()
            controls
        }
        .padding(32)
        .sheet(isPresented: $showingAccount) {
            AccountSyncView(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            page(emoji: "👋", title: "保護者の方へ",
                 body: "このアプリは、はじめに保護者の方が少しだけ設定します。1〜2分で終わります。")
        case 1:
            VStack(spacing: 20) {
                page(emoji: "🧒", title: "お子さんのニックネーム",
                     body: "ホームでの呼びかけに使います（任意・あとで変更できます）。")
                TextField("れい：たろう", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .frame(maxWidth: 360)
            }
        case 2:
            VStack(spacing: 18) {
                page(emoji: "🔄", title: "ほかの端末でも使う？",
                     body: "iPhone や別の iPad でも同じ単語・記録を使いたいときは同期します。今はしなくても大丈夫（あとで保護者メニューからいつでも設定できます）。")
                Button(session.activeHouseholdID != nil ? "同期は設定済み ✓" : "サインインして同期する") {
                    showingAccount = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        default:
            page(emoji: "🎉", title: "じゅんび OK！",
                 body: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "それでは はじめましょう。"
                    : "\(name) さん、いっしょに がんばろう！")
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if step == 1 || step == 2 {
                Button("スキップ") { advance() }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(step >= lastStep ? "はじめる" : "つぎへ") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: 420)
    }

    private func page(emoji: String, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.title.bold())
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private func advance() {
        if step >= lastStep {
            finish()
        } else {
            step += 1
        }
    }

    private func finish() {
        model.childName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.hasCompletedOnboarding = true   // RootView がこれを見てホームへ切り替える
    }
}
