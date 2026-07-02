import SwiftUI

/// 保護者向けの「アカウント・同期」画面（製品 UI）。
///
/// メール OTP でサインインし、世帯を作成する。オフライン優先なので **任意**（使わなくてもアプリは動く）。
/// オンボーディングの同期ステップと、保護者メニューの両方から開く。
/// 接続診断（profiles 件数など）の細かい導線は DEBUG の `SyncDebugView` 側に残す。
struct AccountSyncView: View {
    @ObservedObject var session: SyncSession
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var householdTitle = "わが家"
    @State private var otpSent = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var isError = false

    private var isSignedInParent: Bool { session.isSignedIn && !session.isAnonymous }

    var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section {
                        Text(message).font(.callout).foregroundStyle(isError ? Color.red : Color.green)
                    }
                }
                if isSignedInParent {
                    signedInSection
                } else {
                    signInSection
                }
                Section {
                    NavigationLink {
                        PairingView(session: session)
                    } label: {
                        Label("べつの端末とつなぐ", systemImage: "ipad.and.iphone")
                    }
                } footer: {
                    Text("親のiPadでコードを発行し、子のiPadで入力すると、同じ単語・記録を共有できます。")
                }
                Section {
                    Text("アカウントは任意です。サインインしなくても、この端末だけでそのまま使えます。複数の端末で同じ単語・記録を使いたいときに同期します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("アカウント・同期")
            .toolbar {
                // 通信中でも「とじる」は押せるようにする（任意機能で詰まらせない）。
                ToolbarItem(placement: .cancellationAction) { Button("とじる") { dismiss() } }
            }
            .overlay { if isBusy { ProgressView().scaleEffect(1.3) } }
            .task { await session.refreshOnAppear() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var signInSection: some View {
        Section("保護者のメールでサインイン") {
            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(otpSent ? "コードを再送する" : "サインイン用コードを送る") {
                run("コードを送りました。メールを確認してください。") {
                    try await session.sendParentOTP(email: email)
                    otpSent = true
                }
            }
            .disabled(email.isEmpty)

            if otpSent {
                TextField("メールに届いた6桁コード", text: $code)
                    .keyboardType(.numberPad)
                Button("サインイン") {
                    run("サインインしました。") {
                        try await session.verifyParentOTP(email: email, code: code)
                    }
                }
                .disabled(code.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var signedInSection: some View {
        Section("サインイン中") {
            if let household = session.activeHouseholdID {
                LabeledContent("同期", value: "オン")
                LabeledContent("世帯", value: household.uuidString.prefix(8) + "…")
            } else {
                Text("世帯を作成すると同期が始まります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("世帯の名前", text: $householdTitle)
                Button("世帯を作成して同期を始める") {
                    run("世帯を作成しました。同期を開始します。") {
                        try await session.createHousehold(title: householdTitle)
                    }
                }
                .disabled(householdTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button("サインアウト", role: .destructive) {
                run("サインアウトしました。") {
                    try await session.signOut()
                    otpSent = false
                    code = ""
                }
            }
        }
    }

    // MARK: - Action helper

    private func run(_ success: String, _ action: @escaping () async throws -> Void) {
        guard !isBusy else { return }   // 通信中の二重実行を防ぐ（フォームは無効化しない）
        isBusy = true
        message = nil
        Task {
            do {
                try await action()
                message = success
                isError = false
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isBusy = false
        }
    }
}
