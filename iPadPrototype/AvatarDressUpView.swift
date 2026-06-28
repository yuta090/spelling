import SwiftUI
import SpellingSyncCore

// 着せ替えアバターの SwiftUI 表示・操作（薄い層）。
//
// 純ロジック（manifest 解釈・z-order 合成・選択解決）は SpellingSyncCore の
// `AvatarComposer` にある。ここはその結果（`AvatarRenderLayer` 配列）を ZStack で描き、
// スロットごとに大きいタップで着替えさせるだけ。
//
// 画像契約（重要・固定）: 各パーツ PNG は **フルキャンバス（manifest.canvas, 既定 1024x1536）の透過 PNG**。
// パーツの位置はピクセルに焼き込み済み（scripts/avatars/ の avatar_lib.compose がフルキャンバスに合成して書き出す）。
// よって manifest の `offset`/`scale` は **bbox 由来の配置ではなく、中心基準の微調整ナッジ**（既定 0 / 1.0）。
// これにより「フルキャンバスにさらに offset を足して二重シフト」する不整合を避ける。
// 実 PNG が無いレイヤーは「スロット別プレースホルダ」を描く（=実画像が来たら自動で差し替わる）。
//
// ⚠ ナビ未接続（CLAUDE.md: 子/親の通常導線には出さない）。将来「開発者だけが見られるページ
// または iPad で確認できる QA UI」として親ゲートの奥に置く。現状は #Preview とこの View 単体で確認する。

// MARK: - アセット読込

/// パーツ画像をバンドルから引く。見つからなければ nil（呼び出し側がプレースホルダにフォールバック）。
/// 1024x1536 級の PNG を body から毎フレーム decode しないよう NSCache でメモ化する。
enum AvatarAssetStore {
    #if canImport(UIKit)
    // NSCache はドキュメント上スレッドセーフ。Swift 6 の Sendable 推論には乗らないので unsafe を明示。
    private nonisolated(unsafe) static let cache = NSCache<NSString, UIImage>()

    static func uiImage(named file: String) -> UIImage? {
        guard !file.isEmpty else { return nil }
        let key = file as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let stem = (file as NSString).deletingPathExtension
        let extName = (file as NSString).pathExtension.isEmpty ? "png" : (file as NSString).pathExtension

        var found: UIImage? = UIImage(named: stem)
        if found == nil {
            for sub in ["avatars", "avatars/out", nil] {
                if let url = Bundle.main.url(forResource: stem, withExtension: extName, subdirectory: sub),
                   let ui = UIImage(contentsOfFile: url.path) {
                    found = ui
                    break
                }
            }
        }
        if let found { cache.setObject(found, forKey: key) }
        return found
    }

    static func image(named file: String) -> Image? {
        uiImage(named: file).map { Image(uiImage: $0) }
    }
    #else
    static func image(named file: String) -> Image? { nil }
    #endif

    /// 同梱 manifest の読込結果。`decodeFailed` = ファイルはあるが壊れている（silent に握りつぶさない）。
    struct ManifestLoad {
        var manifest: AvatarManifest?
        var decodeFailed: Bool
    }

    /// 同梱 manifest を読む。無ければ manifest=nil/decodeFailed=false（デモ manifest にフォールバック）。
    /// ファイルは在るが decode 失敗なら decodeFailed=true を返し、DEBUG では assert・常にログする。
    static func loadManifest() -> ManifestLoad {
        for sub in ["avatars", nil] {
            guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: sub) else {
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let m = try JSONDecoder().decode(AvatarManifest.self, from: data)
                return ManifestLoad(manifest: m, decodeFailed: false)
            } catch {
                print("[AvatarDressUp] manifest.json は存在するが decode に失敗: \(error)")
                assertionFailure("avatar manifest decode failed: \(error)")
                return ManifestLoad(manifest: nil, decodeFailed: true)
            }
        }
        return ManifestLoad(manifest: nil, decodeFailed: false)
    }
}

// MARK: - レイヤー合成ビュー（純表示）

/// `AvatarComposer.compose` が返したレイヤー列を ZStack 合成する。
///
/// 描画モデル（フルキャンバス契約）: 各レイヤーはフィット後のキャンバス矩形（w×h）いっぱいに描く。
/// PNG は位置を焼き込んだフルキャンバス透過前提なので、これで正しく重なる。
/// `scale` は中心基準の拡縮（scaleEffect）、`offset` は中心からの微調整ナッジ（fit でスケール）。
struct LayeredAvatarView: View {
    let layers: [AvatarRenderLayer]
    let canvas: CGSize
    var showQA: Bool = false

    var body: some View {
        GeometryReader { geo in
            // canvas が不正（0 以下）なら NaN を避けて何も描かない。
            if canvas.width > 0, canvas.height > 0, geo.size.width > 0, geo.size.height > 0 {
                let fit = min(geo.size.width / canvas.width, geo.size.height / canvas.height)
                let w = canvas.width * fit
                let h = canvas.height * fit
                ZStack {
                    ForEach(layers) { layer in
                        layerContent(layer)
                            .frame(width: w, height: h)            // 全レイヤー＝フィット後キャンバス
                            .scaleEffect(layer.scale)              // 中心基準の微調整
                            .offset(x: layer.offsetX * fit, y: layer.offsetY * fit)
                            .zIndex(Double(layer.zIndex))
                    }
                }
                .frame(width: w, height: h)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .aspectRatio(canvas.width / max(canvas.height, 1), contentMode: .fit)
    }

    @ViewBuilder
    private func layerContent(_ layer: AvatarRenderLayer) -> some View {
        Group {
            if let image = AvatarAssetStore.image(named: layer.file) {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                AvatarPlaceholderLayer(layer: layer, canvas: canvas)
            }
        }
        .overlay(alignment: .topLeading) { if showQA { qaTag(layer) } }
    }

    private func qaTag(_ layer: AvatarRenderLayer) -> some View {
        Text("\(layer.z)\n\(layer.sourcePartID ?? "base")")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(2)
            .background(.black.opacity(0.55))
            .foregroundStyle(.white)
            .padding(2)
    }
}

// MARK: - プレースホルダ（実 PNG が来るまでの仮描画）

/// 実画像が無いレイヤーを、スロットに応じた位置・色のシルエットで描く。
/// これにより z-order と着替えが「画像ゼロでも」目視確認できる。
private struct AvatarPlaceholderLayer: View {
    let layer: AvatarRenderLayer
    let canvas: CGSize

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack {
                shape(in: CGSize(width: W, height: H))
                    .fill(tint.opacity(layer.sourcePartID == nil ? 0.85 : 0.78))
                shape(in: CGSize(width: W, height: H))
                    .stroke(.white.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    /// パーツ id からの安定したパステル色（着替えが見て分かるよう個体ごとに変える）。
    private var tint: Color {
        guard let pid = layer.sourcePartID else {
            return Color(hue: 0.08, saturation: 0.18, brightness: 0.92) // base body = 肌色っぽいベージュ
        }
        let hue = Double(abs(pid.hashValue) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.9)
    }

    /// スロット別の正規化矩形 → Path。3 頭身チビの目安配置。
    private func shape(in size: CGSize) -> Path {
        let W = size.width, H = size.height
        func rrect(_ nx: CGFloat, _ ny: CGFloat, _ nw: CGFloat, _ nh: CGFloat, _ r: CGFloat = 0.04) -> Path {
            let rect = CGRect(x: nx * W, y: ny * H, width: nw * W, height: nh * H)
            return Path(roundedRect: rect, cornerRadius: r * W)
        }
        switch layer.slot {
        case nil: // base body: 頭(円)＋胴＋脚のだるま
            var p = Path()
            p.addEllipse(in: CGRect(x: 0.30 * W, y: 0.02 * H, width: 0.40 * W, height: 0.30 * H)) // 頭
            p.addPath(rrect(0.34, 0.32, 0.32, 0.40, 0.06)) // 胴
            p.addPath(rrect(0.36, 0.70, 0.10, 0.26, 0.05)) // 左脚
            p.addPath(rrect(0.54, 0.70, 0.10, 0.26, 0.05)) // 右脚
            return p
        case .hair:   return rrect(0.28, 0.0, 0.44, 0.16, 0.10)            // 頭頂のアーチ
        case .face:   return rrect(0.40, 0.14, 0.20, 0.10, 0.05)          // 顔の中央
        case .top:    return rrect(0.33, 0.33, 0.34, 0.26, 0.06)          // 胴(トップス)
        case .bottom: return rrect(0.34, 0.56, 0.32, 0.20, 0.05)          // 腰〜腿
        case .shoes:                                                      // 足元 左右
            var p = rrect(0.35, 0.92, 0.12, 0.06, 0.03)
            p.addPath(rrect(0.53, 0.92, 0.12, 0.06, 0.03))
            return p
        case .accessory: return rrect(0.60, 0.04, 0.16, 0.10, 0.05)        // 右上の小物
        }
    }
}

// MARK: - 着せ替え画面

struct AvatarDressUpView: View {
    @State private var manifest: AvatarManifest
    @State private var selection: DressUpSelection
    @State private var showQA = false
    private let usingDemo: Bool
    private let manifestDecodeFailed: Bool

    init() {
        let load = AvatarAssetStore.loadManifest()
        manifestDecodeFailed = load.decodeFailed
        if let m = load.manifest {
            _manifest = State(initialValue: m)
            usingDemo = false
            _selection = State(initialValue: AvatarComposer.defaultSelection(manifest: m, baseID: m.bases.first?.id ?? "female"))
        } else {
            let m = AvatarDressUpView.demoManifest
            _manifest = State(initialValue: m)
            usingDemo = true
            _selection = State(initialValue: AvatarComposer.defaultSelection(manifest: m, baseID: "female"))
        }
    }

    private var layers: [AvatarRenderLayer] {
        AvatarComposer.compose(manifest: manifest, selection: selection)
    }
    private var canvas: CGSize {
        CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            LayeredAvatarView(layers: layers, canvas: canvas, showQA: showQA)
                .frame(maxHeight: 360)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [Color(.systemBackground), Color.blue.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.quaternary, lineWidth: 1))
                .padding(.horizontal)

            if manifest.bases.count > 1 { basePicker }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(AvatarSlot.allCases, id: \.self) { slot in
                        let options = AvatarComposer.parts(manifest: manifest, slot: slot, baseID: selection.baseID)
                        if !options.isEmpty {
                            slotRow(slot: slot, options: options)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("きせかえ")
    }

    private var header: some View {
        HStack {
            if manifestDecodeFailed {
                Label("manifest.json 読込失敗", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else if usingDemo {
                Label("デモ（実パーツ未同梱）", systemImage: "wand.and.stars")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $showQA) {
                Label("QA表示", systemImage: "ladybug")
                    .font(.caption.bold())
            }
            .toggleStyle(.button)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var basePicker: some View {
        Picker("ベース", selection: Binding(
            get: { selection.baseID },
            set: { newBase in
                selection = AvatarComposer.defaultSelection(manifest: manifest, baseID: newBase)
            }
        )) {
            ForEach(manifest.bases) { base in
                Text(base.labelJa).tag(base.id)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func slotRow(slot: AvatarSlot, options: [AvatarPart]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: slotIcon(slot))
                Text(slotLabel(slot)).font(.subheadline.bold())
            }
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // accessory は「なし」を許す
                    if slot == .accessory {
                        chip(title: "なし", selected: selection.parts[slot] == nil) {
                            selection = selection.selecting(slot, partID: nil)
                        }
                    }
                    ForEach(options) { part in
                        chip(title: part.labelJa, selected: selection.parts[slot] == part.id) {
                            selection = selection.selecting(slot, partID: part.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minWidth: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? Color.accentColor.opacity(0.22) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func slotLabel(_ slot: AvatarSlot) -> String {
        switch slot {
        case .hair: return "かみがた"
        case .top: return "ふく（うえ）"
        case .bottom: return "ふく（した）"
        case .shoes: return "くつ"
        case .face: return "ひょうじょう"
        case .accessory: return "こもの"
        }
    }
    private func slotIcon(_ slot: AvatarSlot) -> String {
        switch slot {
        case .hair: return "comb"
        case .top: return "tshirt"
        case .bottom: return "figure.walk"
        case .shoes: return "shoeprints.fill"
        case .face: return "face.smiling"
        case .accessory: return "eyeglasses"
        }
    }

    // MARK: デモ用 manifest（実パーツが無くても着替えを体験/確認できる）

    static let demoManifest: AvatarManifest = {
        func part(_ id: String, _ slot: AvatarSlot, _ ja: String, _ z: String) -> AvatarPart {
            AvatarPart(id: id, slot: slot, labelJa: ja, base: "*",
                       layers: [AvatarLayer(file: "", z: z)])
        }
        return AvatarManifest(
            canvas: [1024, 1536],
            zOrder: ["back_hair", "base_body", "bottom", "shoes", "top", "outer", "face", "front_hair", "accessory"],
            bases: [
                AvatarBase(id: "female", labelJa: "おんなのこ", file: "base_female.png"),
                AvatarBase(id: "male", labelJa: "おとこのこ", file: "base_male.png")
            ],
            parts: [
                part("hair_short", .hair, "ショート", "front_hair"),
                part("hair_twin", .hair, "ツインテール", "front_hair"),
                part("hair_bob", .hair, "ボブ", "front_hair"),
                part("top_red", .top, "あかT", "top"),
                part("top_blue", .top, "あおパーカー", "top"),
                part("top_white", .top, "しろシャツ", "top"),
                part("bottom_shorts", .bottom, "はんズボン", "bottom"),
                part("bottom_pants", .bottom, "ながズボン", "bottom"),
                part("bottom_skirt", .bottom, "スカート", "bottom"),
                part("shoes_white", .shoes, "しろくつ", "shoes"),
                part("shoes_red", .shoes, "あかくつ", "shoes"),
                part("acc_glasses", .accessory, "めがね", "accessory"),
                part("acc_cap", .accessory, "ぼうし", "accessory")
            ]
        )
    }()
}

#Preview {
    NavigationStack {
        AvatarDressUpView()
    }
}
