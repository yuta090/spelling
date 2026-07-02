import Foundation
import SpellingSyncCore

/// `SyncEngine`（Supabase）を `WordSyncTransport` に適合させるアダプタ。
/// DTO ⇄ wire 型 `WordRow` の単純な写し替えだけを担う（変換の判断ロジックは `WordWire`）。
struct WordsSupabaseTransport: WordSyncTransport {
    let engine: SyncEngine

    func pullAll(table: String, since cursor: Int, profileID: UUID?) async throws -> WordPullPage {
        let result = try await engine.pullAll(WordDTO.self, since: cursor, profileID: profileID)
        let rows = result.rows.map { dto in
            WordRow(
                id: dto.id, householdID: dto.householdId, profileID: dto.profileId,
                text: dto.text, promptText: dto.promptText, source: dto.source,
                displayOrder: dto.displayOrder, updatedAt: dto.updatedAt, deletedAt: dto.deletedAt,
                storageStepID: dto.storageStepId,
                linkedCourseID: dto.linkedCourseId,
                linkedBeforeStepID: dto.linkedBeforeStepId
            )
        }
        return WordPullPage(rows: rows, nextCursor: result.nextCursor)
    }

    func push(table: String, rows: [WordRow]) async throws {
        let upserts = rows.map { row in
            WordUpsert(
                id: row.id, householdId: row.householdID, profileId: row.profileID,
                stepId: nil,                         // §7.5: サーバー UUID step_id は当面同期しない（storage_step_id text で往復）
                text: row.text, promptText: row.promptText, source: row.source,
                displayOrder: row.displayOrder, updatedAt: row.updatedAt, deletedAt: row.deletedAt,
                storageStepId: row.storageStepID,    // Ph4: ローカル String の保管ステップ
                linkedCourseId: row.linkedCourseID,
                linkedBeforeStepId: row.linkedBeforeStepID
            )
        }
        try await engine.push(upserts)
    }
}

/// `ProfileProvisioner` を Supabase（`SyncEngine.push`）で実装するアダプタ（Phase 5b）。
/// `words.profile_id → profiles(id)` の FK を満たすため、その profile_id の words を push する **前に**
/// 対応する `profiles` 行を upsert する。ローカル `ChildProfile.id` をそのまま `profiles.id` に使う
/// （クライアント権威 ID）。冪等（既存行はサーバ LWW ガードが古い更新を無視）。
struct ProfilesSupabaseProvisioner: ProfileProvisioner {
    let engine: SyncEngine

    func provision(_ profile: ProvisionedProfile) async throws {
        let upsert = ProfileUpsert(
            id: profile.id,
            householdId: profile.householdID,
            displayName: profile.displayName,
            appLanguage: profile.appLanguage,
            activeStepId: nil,                        // active_step_id はローカル派生ステップと不一致（§7.5）＝同期しない
            updatedAt: WordWire.rfc3339(from: profile.updatedAt),
            deletedAt: nil
        )
        try await engine.push([upsert])
    }
}

/// `words` 同期の **薄い I/O コーディネータ**。
///
/// 手順（pull→merge→push）と判断は `SpellingSyncCore`（`WordSyncRunner`/`WordSyncReducer`、TDD 済）に
/// 寄せ、ここは「トランスポート呼び出し」「多重実行ガード」「スコープ・ガード」「反映/永続化の委譲」だけに保つ
/// （CLAUDE.md: アプリ本体は薄く）。
///
/// **同期状態はプロファイル別**（Phase 5）。サイクル開始時に「アクティブプロファイル」を捕捉し、
/// 同期簿記（サイドカー/カーソル）は `AppModel` 経由で **その捕捉プロファイルのスコープに明示的に**
/// 読み書きする（アクティブ prefix に依存しない）。pull/push の await 中に切替が入ったら、捕捉した
/// スコープ `(household, profile)` が現在と一致するかを再確認し、一致しなければ副作用（反映・state 前進・
/// push）ごと破棄する（他児スコープを汚さない）。原子性が要点の「localWords 読取 → merge → 反映 → 永続化」
/// は await を挟まず同期に連続実行する。
/// 設計: docs/supabase-adapter-design.md §7.5, docs/multi-child-profiles-design-2026-07-01.md §6
@MainActor
final class WordSyncCoordinator {
    private let transport: any WordSyncTransport
    /// `profiles` provisioning のネットワーク境界（Phase 5b）。words を push する前に走らせる。
    private let provisioner: any ProfileProvisioner
    private let now: () -> Date

    /// 多重実行ガード（pull の await 中に再入して二重反映しないため）。
    private var isSyncing = false
    /// 実行中に届いた同期要求の取りこぼし防止。実行後にもう一度だけ回す。
    private var pendingRerun = false
    /// 取りこぼし分の再実行に使う最新の世帯。
    private var pendingRerunHousehold: UUID?

    private let table = WordDTO.table   // "words"

    init(
        transport: (any WordSyncTransport)? = nil,
        provisioner: (any ProfileProvisioner)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let engine = SyncEngine()
        self.transport = transport ?? WordsSupabaseTransport(engine: engine)
        self.provisioner = provisioner ?? ProfilesSupabaseProvisioner(engine: engine)
        self.now = now
    }

    /// 1 サイクル同期する。世帯未選択（`householdID == nil`）なら何もしない。
    ///
    /// 多重実行はガードするが、**取りこぼさない**: 実行中に来た要求は `pendingRerun` に畳み込み、
    /// 現在のサイクル後にもう一度だけ回す（実行中に入った編集が次トリガまで未送信で残らないように）。
    func sync(appModel: AppModel, householdID: UUID?) async throws {
        guard let householdID else { return }
        guard !isSyncing else {
            // 実行中: 取りこぼさないよう再実行を予約（最新世帯で）。
            pendingRerun = true
            pendingRerunHousehold = householdID
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        var current = householdID
        repeat {
            pendingRerun = false
            try await runOneCycle(appModel: appModel, householdID: current)
            if pendingRerun, let next = pendingRerunHousehold { current = next }
        } while pendingRerun
    }

    private func runOneCycle(appModel: AppModel, householdID: UUID) async throws {
        // このサイクルが対象とするスコープ（世帯＋プロファイル）を捕捉する。以後の副作用は
        // すべてこの捕捉スコープに対して行い、await 境界ごとに現在と一致するか確認する。
        let profileID = appModel.activeProfileIDForSync
        // 同期を今の構成で走らせてよいか（世帯・プロファイルの一致）。
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        // Phase 5b: `words.profile_id → profiles(id)` の FK を満たすため、この profile の words を push する
        // **前に** サーバへ profiles 行を provision する（冪等）。親認証時のみ有効（子端末経路は世帯を
        // 返さないので、そもそも同期は走らない）。
        try await provisioner.provision(appModel.provisionPayload(profileID: profileID, householdID: householdID))
        // provision の await 中に切替が入っていたら打ち切る（他プロファイルを触らない）。
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        // 捕捉プロファイルの同期簿記を明示スコープで読む（アクティブ prefix に依存しない）。
        var state = appModel.loadWordSyncState(profileID: profileID)
        let key = WordSyncRunner.cursorKey(table: table, householdID: householdID)

        // フェーズ1a: pull（await）。**この profile の行だけ**に絞る（Phase 5b: 親認証は世帯の全子行が
        // 見えるため、RLS 任せにせずクエリで profile_id をフィルタし、他児データの混入を防ぐ）。
        let page = try await transport.pullAll(table: table, since: state.cursors.pullCursor(for: key), profileID: profileID)

        // pull の await 中に切替（or 世帯変更）が入っていたら、ここで打ち切る。
        // カーソルも state も前進させない（次サイクルで捕捉し直す）。
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }

        // フェーズ1b: 最新ローカル読取 → merge → 反映 → 永続化。**await を挟まず同期に連続実行**するので
        // その間に切替（MainActor 上の activateProfile）は割り込めない＝原子的。
        // ※ wire は捕捉プロファイルの profile_id を刻む（provisioning 済みなので FK を満たす）。
        let localWords = appModel.localWordsForSync()
        let outcome = WordSyncRunner.merge(
            table: table, householdID: householdID, state: state,
            page: page, localWords: localWords, now: now(), profileID: profileID
        )
        appModel.applyMergedWords(outcome.live)
        state = outcome.state
        appModel.saveWordSyncState(state, profileID: profileID)

        // フェーズ2: push（送れた分だけ high-water 前進）。
        guard !outcome.toPush.isEmpty else { return }
        state = try await WordSyncRunner.push(
            table: table, householdID: householdID, state: state,
            toPush: outcome.toPush, transport: transport
        )
        // push の await 中に切替が入っていたら high-water の永続化は次サイクルへ委ねる（重複送信は冪等）。
        guard appModel.canContinueWordSync(householdID: householdID, profileID: profileID) else { return }
        appModel.saveWordSyncState(state, profileID: profileID)
    }
}
