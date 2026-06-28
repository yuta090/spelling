import Foundation

/// 着せ替えアバターの純ロジック（UI 非依存）。
///
/// 方式は B 方式（レイヤー合成）: 坊主マネキンの base body に、髪/服/靴などの透過パーツを
/// z-order で重ねる。各パーツの配置・抽出パイプラインは `scripts/avatars/`（spec.json / avatar_lib.py）
/// が単一ソース。ここはその成果物（manifest）を読み、「どのレイヤーをどの順で描くか」だけを決める。
/// SwiftUI 側はここが返す `AvatarRenderLayer` 配列を ZStack で描画するだけ（位置計算ゼロ）。

// MARK: - スロット（着替え軸）

/// 子が着替えできる軸。1 スロット = 1 つ選ぶ。
public enum AvatarSlot: String, Codable, CaseIterable, Sendable {
    case hair
    case top
    case bottom
    case shoes
    case face
    case accessory
}

// MARK: - manifest（同梱データの単一表現）

/// 1 枚の透過パーツ画像とその配置メタ。`z` は描画順キー（manifest.zOrder のいずれか）。
public struct AvatarLayer: Codable, Equatable, Sendable {
    public var file: String
    public var z: String
    public var offsetX: Double
    public var offsetY: Double
    public var scale: Double

    public init(file: String, z: String, offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1) {
        self.file = file
        self.z = z
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }
}

/// 着替え 1 候補。1 パーツが複数レイヤーを持てる（例: 髪は back_hair + front_hair）。
/// `base` は対象ベース id（"female"/"male"）。`"*"` は全ベース共通。
public struct AvatarPart: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var slot: AvatarSlot
    public var labelJa: String
    public var base: String
    public var layers: [AvatarLayer]

    public init(id: String, slot: AvatarSlot, labelJa: String, base: String, layers: [AvatarLayer]) {
        self.id = id
        self.slot = slot
        self.labelJa = labelJa
        self.base = base
        self.layers = layers
    }

    /// このパーツが `baseID` のベースに適用できるか（"*" は常に可）。
    public func appliesTo(baseID: String) -> Bool {
        base == "*" || base == baseID
    }
}

/// ベースボディ（坊主マネキン）。年齢では分けず男女 2 種のみ。
public struct AvatarBase: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var labelJa: String
    public var file: String

    public init(id: String, labelJa: String, file: String) {
        self.id = id
        self.labelJa = labelJa
        self.file = file
    }
}

/// 同梱 manifest（`Resources/avatars/manifest.json`）の Swift 表現。
public struct AvatarManifest: Codable, Equatable, Sendable {
    public var canvas: [Int]
    public var zOrder: [String]
    public var bases: [AvatarBase]
    public var parts: [AvatarPart]

    public init(canvas: [Int], zOrder: [String], bases: [AvatarBase], parts: [AvatarPart]) {
        self.canvas = canvas
        self.zOrder = zOrder
        self.bases = bases
        self.parts = parts
    }

    /// canvas 幅（px）。未指定時は spec.json 既定の 1024。
    public var canvasWidth: Double { Double(canvas.first ?? 1024) }
    /// canvas 高さ（px）。未指定時は spec.json 既定の 1536。
    public var canvasHeight: Double { Double(canvas.count > 1 ? canvas[1] : 1536) }

    public func base(id: String) -> AvatarBase? { bases.first { $0.id == id } }
    public func part(id: String) -> AvatarPart? { parts.first { $0.id == id } }
}

// MARK: - 選択状態

/// 今の着せ替え選択。base + スロットごとに選んだパーツ id。
/// スロットにキーが無い = そのスロットは未着用（例: accessory なし）。
public struct DressUpSelection: Equatable, Sendable {
    public var baseID: String
    public var parts: [AvatarSlot: String]

    public init(baseID: String, parts: [AvatarSlot: String]) {
        self.baseID = baseID
        self.parts = parts
    }

    /// 指定スロットのパーツを差し替えた新しい選択を返す（id が nil なら脱がす）。
    public func selecting(_ slot: AvatarSlot, partID: String?) -> DressUpSelection {
        var next = parts
        if let partID { next[slot] = partID } else { next[slot] = nil }
        return DressUpSelection(baseID: baseID, parts: next)
    }
}

// MARK: - 合成結果（SwiftUI が描く 1 レイヤー）

/// ZStack で描く 1 レイヤー。`zIndex` 昇順に並んでいる（手前ほど大きい）。
/// `sourcePartID` は base body のとき nil。`slot` は欠落画像のプレースホルダ表示に使う。
public struct AvatarRenderLayer: Equatable, Sendable, Identifiable {
    public var id: String
    public var file: String
    public var z: String
    public var zIndex: Int
    public var offsetX: Double
    public var offsetY: Double
    public var scale: Double
    public var sourcePartID: String?
    public var slot: AvatarSlot?

    public init(id: String, file: String, z: String, zIndex: Int,
                offsetX: Double, offsetY: Double, scale: Double,
                sourcePartID: String?, slot: AvatarSlot?) {
        self.id = id
        self.file = file
        self.z = z
        self.zIndex = zIndex
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.sourcePartID = sourcePartID
        self.slot = slot
    }
}

// MARK: - Composer（純関数）

public enum AvatarComposer {

    /// zOrder 上の位置。未知の z は末尾（最前面）にまとめる。
    private static func zIndex(of z: String, in zOrder: [String]) -> Int {
        zOrder.firstIndex(of: z) ?? zOrder.count
    }

    /// 指定 base に出せるスロット候補（manifest 内の出現順を保つ。"*" は全 base に出る）。
    public static func parts(manifest: AvatarManifest, slot: AvatarSlot, baseID: String) -> [AvatarPart] {
        manifest.parts.filter { $0.slot == slot && $0.appliesTo(baseID: baseID) }
    }

    /// 各スロットの先頭候補を選んだ初期状態（候補が無いスロットは未設定）。
    public static func defaultSelection(manifest: AvatarManifest, baseID: String) -> DressUpSelection {
        var picks: [AvatarSlot: String] = [:]
        for slot in AvatarSlot.allCases {
            if let first = parts(manifest: manifest, slot: slot, baseID: baseID).first {
                picks[slot] = first.id
            }
        }
        return DressUpSelection(baseID: baseID, parts: picks)
    }

    /// 選択 → ZStack 描画用レイヤー列（zIndex 昇順、安定ソート）。
    /// base body は常に含む。未知パーツ id・base 不一致のパーツは安全に無視する。
    public static func compose(manifest: AvatarManifest, selection: DressUpSelection) -> [AvatarRenderLayer] {
        var collected: [(order: Int, layer: AvatarRenderLayer)] = []
        var seq = 0

        func push(file: String, z: String, offsetX: Double, offsetY: Double, scale: Double,
                  sourcePartID: String?, slot: AvatarSlot?) {
            let zi = zIndex(of: z, in: manifest.zOrder)
            let layer = AvatarRenderLayer(
                id: "\(seq)-\(file)",
                file: file, z: z, zIndex: zi,
                offsetX: offsetX, offsetY: offsetY, scale: scale,
                sourcePartID: sourcePartID, slot: slot
            )
            collected.append((seq, layer))
            seq += 1
        }

        // 1) base body（常に最初に積む）
        if let base = manifest.base(id: selection.baseID) {
            push(file: base.file, z: "base_body", offsetX: 0, offsetY: 0, scale: 1,
                 sourcePartID: nil, slot: nil)
        }

        // 2) 選択パーツ（スロットの定義順 → そのパーツのレイヤー順で積む）
        for slot in AvatarSlot.allCases {
            guard let partID = selection.parts[slot],
                  let part = manifest.part(id: partID),
                  part.slot == slot,
                  part.appliesTo(baseID: selection.baseID) else { continue }
            for layer in part.layers {
                push(file: layer.file, z: layer.z,
                     offsetX: layer.offsetX, offsetY: layer.offsetY, scale: layer.scale,
                     sourcePartID: part.id, slot: slot)
            }
        }

        // 3) zIndex 昇順に安定ソート（同 z は積んだ順を保つ）
        return collected
            .sorted { $0.layer.zIndex != $1.layer.zIndex ? $0.layer.zIndex < $1.layer.zIndex : $0.order < $1.order }
            .map(\.layer)
    }
}
