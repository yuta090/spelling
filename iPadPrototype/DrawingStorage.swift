import Foundation
import Supabase
import SpellingSyncCore

/// 手書き/見本画像を Supabase Storage（非公開バケット `drawings`）に読み書きする**薄い I/O**。
///
/// パスの決定論生成は `SpellingSyncCore.DrawingStoragePath`（TDD 済）に寄せ、ここは SDK 呼び出しだけ。
/// バケット＋RLS は migration `0007`（`{hid}/{pid}/{attempts|reviews}/{id}.png`）。
/// I/O 主体なので薄く保つ（CLAUDE.md）。実疎通には Supabase の Storage バケット作成が前提。
/// `SyncEngine` と同様 `@MainActor`（`SupabaseService.shared` の既定値が MainActor 由来のため）。
@MainActor
struct DrawingStorage {
    private let service: SupabaseService

    init(service: SupabaseService = .shared) {
        self.service = service
    }

    /// PNG バイト列を指定パスへアップロード（再送に備え upsert=true で冪等）。
    func upload(_ data: Data, to path: String) async throws {
        _ = try await service.client.storage
            .from(DrawingStoragePath.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/png", upsert: true))
    }

    /// 指定パスの画像バイト列をダウンロード。存在しなければ SDK が throw する。
    func download(_ path: String) async throws -> Data {
        try await service.client.storage
            .from(DrawingStoragePath.bucket)
            .download(path: path)
    }
}
