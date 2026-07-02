import SwiftUI
import SpellingSyncCore

/// 保護者向けの「端末をつなぐ」画面（製品 UI・親ゲートの奥）。
///
/// ペアリングは *設定＝管理者(親)の仕事* なので、子のプレイ画面には出さず「アカウント・同期」から開く。
/// 使い方は2ステップ:
///  ① 親のiPad（サインイン＋世帯あり）で **コードを発行**。
///  ② 子のiPad で **そのコードを入力** して同じ世帯につなぐ。
///
/// 実疎通には Supabase 側の設定（`app.pairing_pepper` の設定・匿名サインイン有効化）が必要。
/// I/O は `SyncSession`（薄いラッパ）に寄せ、コード入力の正規化は `PairingCodeEntry`（コア・TDD）に置く。
struct PairingView: View {
    @ObservedObject var session: SyncSession

    @State private var issued: SupabaseService.PairingCode?
    @State private var codeInput = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var isError = false

    private var canIssue: Bool {
        session.isSignedIn && !session.isAnonymous && session.activeHouseholdID != nil
    }
    private var canConsume: Bool { PairingCodeEntry.isComplete(codeInput) }

    var body: some View {
        Form {
            if let message {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(isError ? Color.red : Color.green)
                }
            }
            issueSection
            consumeSection
            Section {
                Text("親のiPadでコードを発行し、子のiPadでそのコードを入力すると、同じ単語・記録を共有できます。コードは15分間・1回だけ使えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("端末をつなぐ")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isBusy { ProgressView().scaleEffect(1.3) } }
        .task { await session.refreshOnAppear() }
    }

    // MARK: - ① 発行（親のiPad）

    @ViewBuilder
    private var issueSection: some View {
        Section("① 親のiPadでコードを発行") {
            if canIssue {
                if let issued {
                    Text(grouped(issued.code))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                    if let until = expiryText(issued.expiresAt) {
                        Text(until)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Button("新しいコードを発行") { issue() }
                } else {
                    Button("つなぐコードを発行する") { issue() }
                }
            } else {
                Text("コードの発行には、保護者のサインインと世帯の作成が必要です（「アカウント・同期」から）。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - ② 入力（子のiPad）

    @ViewBuilder
    private var consumeSection: some View {
        Section("② 子のiPadでコードを入力") {
            if canIssue {
                // すでにこの世帯のオーナー端末（親サインイン＋世帯あり）。ここでコードを消費すると
                // 親IDのまま消費してサーバに弾かれるだけなので、入力欄は出さず案内に留める。
                Text("この端末はすでに世帯につながっています。コードは子のiPadで入力してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                TextField("6桁コード", text: Binding(
                    get: { codeInput },
                    set: { codeInput = PairingCodeEntry.normalize($0) }
                ))
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                Button("この端末をつなぐ") { consume() }
                    .disabled(!canConsume)
            }
        }
    }

    // MARK: - Actions

    private func issue() {
        run { [self] in
            let code = try await session.issuePairingCode()
            issued = code
            return "コードを発行しました。子のiPadで入力してください。"
        }
    }

    private func consume() {
        run { [self] in
            let result = try await session.consumePairingCode(codeInput)
            switch result.status {
            case .ok:
                codeInput = ""
                return "つながりました。同じ単語・記録を共有します。"
            case .invalidOrExpired:
                isError = true
                return "コードが正しくないか、期限切れです。新しいコードを発行してもらってください。"
            case .rateLimited:
                isError = true
                return "試行が多すぎます。しばらく待ってからやり直してください。"
            case .alreadyPaired:
                isError = true
                return "この端末はすでにつながっています。"
            }
        }
    }

    /// 成功メッセージ（緑）は返り値、失敗は例外か action 内の `isError=true` で表す共通ランナー。
    /// `isError` は毎回ここでリセットするので、非OK分岐（`isError=true`）は action 実行後にのみ効く。
    private func run(_ action: @escaping () async throws -> String) {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        isError = false
        Task {
            do {
                message = try await action()
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isBusy = false
        }
    }

    // MARK: - 表示ヘルパ

    /// "123456" → "123 456"（読みやすさ用。桁数が違えばそのまま返す）。
    private func grouped(_ code: String) -> String {
        guard code.count == PairingCodeEntry.length else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }

    /// 期限（RFC3339 文字列）を「HH:mm まで有効」に整形。解釈できなければ nil。
    private func expiryText(_ rfc3339: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: rfc3339) ?? {
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: rfc3339)
        }()
        guard let date else { return nil }
        let time = DateFormatter()
        time.locale = Locale(identifier: "ja_JP")
        time.dateFormat = "H:mm"
        return "\(time.string(from: date)) まで有効"
    }
}
