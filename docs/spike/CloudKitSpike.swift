// CloudKitSpike.swift — CKShare 検証スパイクの参照雛形
//
// ⚠️ これはビルド対象外の参照コード（docs/spike 配下）。
//    スパイク時に Xcode で一時的に Sources へ追加し、capability 設定後に試す。
//    本実装ではなく「別 Apple ID 間 CKShare が成立するか」の前提実証が目的。
//    手順は docs/cloudkit-ckshare-spike-runbook.md を参照。
//
// 対象 OS: iOS 16+（CKSyncEngine は使わない。NSPersistentCloudKitContainer の共有を使用）

import CloudKit
import CoreData
import SwiftUI
import UIKit

// MARK: - 1. デュアルストア（private + shared）コンテナ

/// private（自分が所有する世帯）と shared（招待されて参加する世帯）の 2 ストアを
/// CloudKit にミラーする最小コンテナ。iOS 15+ で利用可能。
enum SpikePersistence {
    static let cloudKitContainerID = "iCloud.com.yuta090.SpellingTrainer"

    static func makeContainer() -> NSPersistentCloudKitContainer {
        // モデルはスパイク用に最小の Household / Attempt を含む .xcdatamodeld を用意する想定。
        let container = NSPersistentCloudKitContainer(name: "SpikeModel")

        guard let baseURL = container.persistentStoreDescriptions.first?.url else {
            fatalError("missing store description")
        }

        // --- private ストア ---
        let privateDesc = container.persistentStoreDescriptions.first!
        privateDesc.configuration = "Default"
        privateDesc.cloudKitContainerOptions = {
            let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
            opts.databaseScope = .private
            return opts
        }()
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // --- shared ストア（別ファイル） ---
        let sharedURL = baseURL.deletingLastPathComponent().appendingPathComponent("spike-shared.sqlite")
        let sharedDesc = NSPersistentStoreDescription(url: sharedURL)
        sharedDesc.configuration = "Default"
        sharedDesc.cloudKitContainerOptions = {
            let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
            opts.databaseScope = .shared
            return opts
        }()
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        container.loadPersistentStores { desc, error in
            if let error { print("❌ load store failed:", desc.cloudKitContainerOptions?.databaseScope as Any, error) }
            else { print("✅ loaded store scope:", desc.cloudKitContainerOptions?.databaseScope.rawValue ?? -1) }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }
}

// MARK: - 2. 世帯の作成と共有（親側）

@MainActor
enum SpikeSharing {
    /// 親が世帯を作り、CKShare を生成して招待 UI を出す。
    static func createAndShareHousehold(
        container: NSPersistentCloudKitContainer,
        title: String,
        presenter: UIViewController
    ) async {
        let context = container.viewContext
        let household = NSEntityDescription.insertNewObject(forEntityName: "Household", into: context)
        household.setValue(UUID(), forKey: "id")
        household.setValue(title, forKey: "title")
        try? context.save()

        do {
            // share(_:to:) は (ids, CKShare, CKContainer) を返す（iOS 15+）。
            let (_, share, ckContainer) = try await container.share([household], to: nil)
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue

            let sharingController = UICloudSharingController(share: share, container: ckContainer)
            sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
            presenter.present(sharingController, animated: true)
            // 観察: owner から見るとこの household は private DB に存在する。
        } catch {
            print("❌ share failed:", error)
        }
    }
}

// MARK: - 3. 招待受諾（子側）

// SwiftUI の場合、UIWindowSceneDelegate を用意してこのフックを実装する。
final class SpikeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = AppSpikeEnvironment.shared.container
        container.acceptShareInvitations(from: [cloudKitShareMetadata], into: container) { _, error in
            if let error { print("❌ accept share failed:", error) }
            else { print("✅ share accepted; data should appear in the SHARED store") }
        }
    }
}

// MARK: - 4. リモート変更 → 採点待ち件数 → ローカル通知（通知スパイク）

import UserNotifications

@MainActor
final class SpikeReviewNotifier {
    private let container: NSPersistentCloudKitContainer

    init(container: NSPersistentCloudKitContainer) {
        self.container = container
        NotificationCenter.default.addObserver(
            self, selector: #selector(remoteChange(_:)),
            name: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator
        )
    }

    @objc private func remoteChange(_ note: Notification) {
        // 1) shared ストアの Attempt を取得
        // 2) 「requiresParentReview && unreviewed」を数える
        //    → SpellingSyncCore.ReviewProgress.pendingCount(items) がそのまま使える
        // 3) 件数 > 0 ならローカル通知
        let pending = fetchPendingReviewCount()
        guard pending > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "さいてんまち"
        content.body = "\(pending)もん、さいてんをまっています"
        let req = UNNotificationRequest(identifier: "pending-review", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
        // 観察: 通知の遅延・取りこぼし・強制終了後の挙動を runbook の E に記録。
    }

    private func fetchPendingReviewCount() -> Int {
        // スパイクでは Attempt エンティティを fetch して decision/parentReview を見て数える。
        // 本実装では SpellingSyncCore.ReviewProgress に委譲する。
        return 0 // TODO: スパイクで実装
    }
}

// 補助: スパイク用の最小 DI。
@MainActor
final class AppSpikeEnvironment {
    static let shared = AppSpikeEnvironment()
    let container = SpikePersistence.makeContainer()
    lazy var notifier = SpikeReviewNotifier(container: container)
    private init() {}
}
