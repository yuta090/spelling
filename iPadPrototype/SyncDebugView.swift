import SwiftUI

/// 同期バックエンドの**開発用デバッグ画面**。
///
/// 親のメールOTPサインイン → 世帯作成 → 疎通確認（profiles件数）までを実機/シミュレータで叩くための最小UI。
/// 製品UIには出さない（`#if DEBUG` の `SyncDebugLauncher` からのみ開く）。
/// 設計: docs/supabase-adapter-design.md
struct SyncDebugView: View {
    @ObservedObject var session: SyncSession
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var householdTitle = "わが家"
    @State private var otpSent = false

    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationView {
            Form {
                statusSection
                authStateSection
                parentSignInSection
                householdSection
                connectivitySection
                wordSyncSection
                childSection
                if session.isSignedIn { signOutSection }
            }
            .task {
                // 表示時に認証状態を読み直し、サインイン済みの親なら所属世帯を読み込む。
                await session.refreshOnAppear()
            }
            .navigationTitle("同期デバッグ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .disabled(isBusy)
            .overlay {
                if isBusy { ProgressView().scaleEffect(1.4) }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            Section {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
        }
    }

    private var authStateSection: some View {
        Section("認証状態") {
            LabeledRow(label: "サインイン", value: session.isSignedIn ? "済" : "未")
            LabeledRow(label: "種別", value: session.isSignedIn ? (session.isAnonymous ? "匿名（子）" : "親") : "—")
            LabeledRow(label: "user_id", value: session.userID?.uuidString ?? "—", mono: true)
            LabeledRow(label: "active household", value: session.activeHouseholdID?.uuidString ?? "—", mono: true)
            if let count = session.lastProfileCount {
                LabeledRow(label: "profiles件数", value: "\(count)")
            }
        }
    }

    private var parentSignInSection: some View {
        Section("親サインイン（メールOTP）") {
            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("① コードを送信") {
                run("コードを送信しました。メールの6桁コードを入力してください。") {
                    try await session.sendParentOTP(email: email)
                    otpSent = true
                }
            }
            .disabled(email.isEmpty)

            if otpSent {
                TextField("6桁コード", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)

                Button("② 検証してサインイン") {
                    run("親としてサインインしました。") {
                        try await session.verifyParentOTP(email: email, code: code)
                    }
                }
                .disabled(code.isEmpty)
            }
        }
    }

    private var householdSection: some View {
        Section("世帯") {
            TextField("世帯名", text: $householdTitle)
            Button("世帯を作成（オーナーになる）") {
                run("世帯を作成し、active に設定しました。") {
                    try await session.createHousehold(title: householdTitle)
                }
            }
            .disabled(!session.isSignedIn || session.isAnonymous || householdTitle.isEmpty)

            if !session.ownedHouseholdIDs.isEmpty {
                ForEach(session.ownedHouseholdIDs, id: \.self) { id in
                    Button {
                        session.setActiveHousehold(id)
                        show("active household を切り替えました。")
                    } label: {
                        HStack {
                            Text(id.uuidString)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if id == session.activeHouseholdID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            Button("active household をクリア", role: .destructive) {
                session.setActiveHousehold(nil)
                show("active household をクリアしました。")
            }
            .disabled(session.activeHouseholdID == nil)
        }
    }

    private var connectivitySection: some View {
        Section("疎通確認") {
            Button("profiles 件数を取得") {
                run("profiles 件数を取得しました。") {
                    try await session.refreshProfileCount()
                }
            }
            .disabled(!session.isSignedIn)
        }
    }

    private var childSection: some View {
        Section("子端末") {
            Button("子として匿名サインイン") {
                run("匿名サインインしました（子端末）。") {
                    try await session.signInChildAnonymously()
                }
            }
            // 既にサインイン済みだと匿名サインインは no-op になり「成功」と誤表示するため無効化。
            // 切り替えるにはいったんサインアウトする。
            .disabled(session.isSignedIn)
            if session.isSignedIn {
                Text("匿名サインインするには、まずサインアウトしてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button("サインアウト", role: .destructive) {
                run("サインアウトしました。") {
                    try await session.signOut()
                    otpSent = false
                    code = ""
                }
            }
        }
    }

    /// words のサイドカー同期（pull→merge→push）を手動で叩く。
    /// active な世帯が必要（push スコープの前提）。
    @ViewBuilder
    private var wordSyncSection: some View {
        Section("単語同期（words）") {
            LabeledRow(label: "ローカル単語数", value: "\(model.words.count)")
            Button("単語を同期") {
                run("単語を同期しました") {
                    try await model.syncWords(householdID: session.activeHouseholdID)
                }
            }
            .disabled(session.activeHouseholdID == nil)
            if session.activeHouseholdID == nil {
                Text("世帯を選択/作成すると同期できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// 非同期アクションを busy 表示・エラー捕捉つきで実行する。
    private func run(_ successMessage: String, _ action: @escaping () async throws -> Void) {
        isBusy = true
        statusMessage = nil
        Task {
            do {
                try await action()
                show(successMessage)
            } catch {
                show(error.localizedDescription, isError: true)
            }
            isBusy = false
        }
    }

    private func show(_ message: String, isError: Bool = false) {
        self.statusMessage = message
        self.isError = isError
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .caption.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

#if DEBUG
/// 製品UIを汚さずに `SyncDebugView` を開く、DEBUG限定の小さな起動ボタン。
/// `SpellingTrainerApp` のルートに overlay として差し込む。
struct SyncDebugLauncher: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var session = SyncSession()
    @State private var isPresented = false

    var body: some View {
        Button {
            session.refreshAuthState()
            isPresented = true
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.leading, 12)
        .padding(.bottom, 12)
        .accessibilityLabel("同期デバッグ")
        .sheet(isPresented: $isPresented) {
            SyncDebugView(session: session)
                .environmentObject(model)
        }
    }
}
#endif
