import Foundation
import UIKit
import MetricKit
import SpellingSyncCore

// =============================================================================
// 運用テレメトリ（送信専用）のアプリ層。
//
// 役割分担:
//  * 純粋ロジック（イベント定義・アウトボックス・単調クロック・検証/バケット）は SpellingSyncCore。
//  * ここは I/O だけ: 端末アウトボックスの永続化・バッチ送信・MetricKit 購読・ライフサイクル flush。
//
// 送信経路は SECURITY DEFINER RPC `log_events`（バッチ・冪等 ON CONFLICT DO NOTHING）。
// 直接 upsert を使わない理由: ON CONFLICT DO NOTHING は RLS 下で「競合した既存行が SELECT 可視」
// でないと弾かれ、送信専用（SELECT ポリシ無し）と両立しない。RPC なら RLS をバイパスしつつ
// 関数内で has_access により自世帯限定を担保でき、テーブルはクライアントから読めないまま保てる。
// 設計: docs/telemetry-design.md
// =============================================================================

/// event_log への送信専用アップローダ（RPC `log_events` で一括 insert・重複は DB 側で無視）。
@MainActor
struct TelemetryUploader {
    private let service: SupabaseService

    init(service: SupabaseService = .shared) {
        self.service = service
    }

    private struct Params: Encodable { let events: [TelemetryWire.Row] }

    /// 行をまとめて送る。`event_id` 衝突は RPC 内の ON CONFLICT DO NOTHING で握りつぶす
    /// （再送・多重 flush でも二重計上しない／UPDATE は発生しない）。
    func upload(_ rows: [TelemetryWire.Row]) async throws {
        guard !rows.isEmpty else { return }
        try await service.client
            .rpc("log_events", params: Params(events: rows))
            .execute()
    }
}

/// 端末側テレメトリの司令塔。記録 → 端末アウトボックスに溜める → 折を見てバッチ送信。
///
/// - 高頻度の逐次送信はしない（バッチ＝Supabase 負荷を抑える）。
/// - 未ペアリング（world household 不明）の間は送らず溜める（RLS で弾かれるため）。
/// - 送信失敗時は溜めたまま次の flush で再送（テレメトリ送信の失敗で別テレメトリを出して
///   ループにしない）。
@MainActor
final class TelemetryCoordinator: ObservableObject {
    static let shared = TelemetryCoordinator()

    private let store: UserDataStore
    private let uploader: TelemetryUploader

    private var outbox: EventOutbox
    private var stamper: MonotonicStamper
    private let deviceID: UUID
    private let appVersion: String
    private let osVersion: String

    /// 世帯供給元（送信可否の判定）。未設定/nil の間は送らず溜める。
    private var householdIDProvider: () -> UUID? = { nil }
    /// 容量超過で落とした件数の累計（次 flush で `telemetry.dropped` として 1 件にまとめて報告）。
    private var accumulatedDropped = 0
    private var isFlushing = false
    private var mxSubscriber: TelemetryMetricSubscriber?

    private let outboxKey = "telemetry.outbox.v1"
    private let deviceKey = "telemetry.device_id.v1"
    private let clockKey  = "telemetry.clock_last.v1"
    private let droppedKey = "telemetry.dropped_count.v1"
    private let batchLimit = 100
    private let outboxCapacity = 500

    init(store: UserDataStore = AppPersistenceStore(), uploader: TelemetryUploader = TelemetryUploader()) {
        self.store = store
        self.uploader = uploader

        // 端末ID（インストール単位の安定 UUID。非秘密）。
        if let raw = store.load(String.self, key: deviceKey), let id = UUID(uuidString: raw) {
            self.deviceID = id
        } else {
            let id = UUID()
            store.save(id.uuidString, key: deviceKey)
            self.deviceID = id
        }

        // 既存アウトボックス（容量はコードを正とし、読み込み時に再クランプ）。
        let loaded = store.load(EventOutbox.self, key: outboxKey)
        self.outbox = EventOutbox(capacity: outboxCapacity, events: loaded?.events ?? [])

        // 単調クロックの直近値を復元（再起動を跨いでも occurredAt を後退させない）。
        let last = store.load(Double.self, key: clockKey).map { Date(timeIntervalSince1970: $0) }
        self.stamper = MonotonicStamper(last: last)

        // 容量超過で落とした件数（再起動を跨いで観測を失わない）。
        self.accumulatedDropped = store.load(Int.self, key: droppedKey) ?? 0

        self.appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        self.osVersion = UIDevice.current.systemVersion
    }

    /// 世帯供給元を注入し、MetricKit 購読を開始する（アプリ起動時に 1 回）。
    func configure(householdIDProvider: @escaping () -> UUID?) {
        self.householdIDProvider = householdIDProvider
        if mxSubscriber == nil {
            let sub = TelemetryMetricSubscriber(coordinator: self)
            MXMetricManager.shared.add(sub)
            self.mxSubscriber = sub
        }
    }

    /// イベントを 1 件記録する（送信は遅延・バッチ）。
    /// - Parameters:
    ///   - id: 冪等キー。既定はランダム（溜めた行は同じ id を保つので再送は安全）。同一論理イベントの
    ///         二重記録を避けたい場合のみ決定論 UUID を渡す。
    func record(
        _ code: TelemetryCode,
        severity: TelemetrySeverity? = nil,
        profileID: UUID? = nil,
        payload: [String: TelemetryValue] = [:],
        id: UUID = UUID()
    ) {
        // 世帯未確定（未ペアリング／サインアウト中）は送信不能（RLS／NOT NULL）。記録せず捨てる。
        // 送れない event を溜め込んでキュー先頭を詰まらせない（codex 指摘 #1）。
        guard householdIDProvider() != nil else { return }

        let event = TelemetryEvent(
            id: id,
            householdID: householdIDProvider(),
            profileID: profileID,
            deviceID: deviceID,
            occurredAt: stamper.stamp(Date()),
            code: code,
            severity: severity,
            appVersion: appVersion,
            osVersion: osVersion,
            payload: payload
        )
        let dropped = outbox.append(event)
        accumulatedDropped += dropped
        persistState()
    }

    /// 溜まったイベントをバッチ送信する（scenePhase の前面離脱・前面復帰などで呼ぶ）。
    func flush() async {
        guard !isFlushing else { return }
        guard householdIDProvider() != nil else { return }  // 未ペアリングは送らず溜める
        isFlushing = true
        defer { isFlushing = false }

        let batch = outbox.batch(limit: batchLimit)
        if !batch.isEmpty {
            // 検証を通った行だけ送る。通らない壊れた/送れない行は queue に残さず捨てる（詰まり防止）。
            let rows = batch.compactMap { TelemetryWire.row(from: $0) }
            let validIDs = Set(rows.map { $0.eventID })
            let invalidIDs = Set(batch.map { $0.id }).subtracting(validIDs)
            do {
                try await uploader.upload(rows)
                outbox.acknowledge(validIDs.union(invalidIDs))
            } catch {
                // 送信失敗: 溜めたまま次回再送。別テレメトリも出さない（ループ回避）。進捗なしで離脱。
                return
            }
        }

        // ここに来た＝送信成功 or 送るものが無い ＝ outbox に空きがある。
        // 落とした累計を 1 件にまとめて報告（空きがあるので新たな drop を誘発しない）。
        emitDroppedReportIfNeeded()
        persistState()
    }

    /// 容量超過で落とした累計を `telemetry.dropped` 1 件に集約して積む。
    /// **必ず outbox に空きがある状態で呼ぶこと**（呼ぶたびに real event を押し出す事故を避ける）。
    private func emitDroppedReportIfNeeded() {
        guard accumulatedDropped > 0, let household = householdIDProvider() else { return }
        let event = TelemetryEvent(
            id: UUID(), householdID: household, deviceID: deviceID,
            occurredAt: stamper.stamp(Date()), code: .telemetryDropped,
            appVersion: appVersion, osVersion: osVersion,
            payload: ["count_bucket": .string(TelemetryBucket.count(accumulatedDropped))]
        )
        // 空きがある前提なので append は 0 を返す（=報告分は落ちない）。万一さらに溢れたら
        // その件数を次回へ繰り越す（観測を失わない）。
        accumulatedDropped = outbox.append(event)
    }

    private func persistState() {
        store.save(outbox, key: outboxKey)
        store.save(accumulatedDropped, key: droppedKey)
        if let last = stamper.lastIssued {
            store.save(last.timeIntervalSince1970, key: clockKey)
        }
    }
}

/// MetricKit 購読（クラッシュ/診断ペイロード）。コールバックは別キューで来るため MainActor へ橋渡し。
private final class TelemetryMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    private weak var coordinator: TelemetryCoordinator?

    init(coordinator: TelemetryCoordinator) {
        self.coordinator = coordinator
    }

    // 通常メトリクス（パフォーマンス集計）。v1 では送らない（高頻度・大きい）。
    func didReceive(_ payloads: [MXMetricPayload]) {}

    // 診断（クラッシュ/ハング/ディスク書き込み超過 等）。v1 はクラッシュ件数のみ薄く記録。
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashCount = payload.crashDiagnostics?.count ?? 0
            guard crashCount > 0 else { continue }
            Task { @MainActor [weak coordinator] in
                coordinator?.record(
                    .crashDiagnostic,
                    payload: ["count_bucket": .string(TelemetryBucket.count(crashCount))]
                )
            }
        }
    }
}
