// モードS の新規宇宙人フェイスをアプリ無しで PNG 化して Preview.app で確認する一時ハーネス。
// OK なら各 View を iPadPrototype/HomeView.swift に移植する（このファイルが実機見た目の代理）。
// 使い方: swift alien_preview.swift out.png
import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        func b(_ s: Substring) -> Double { Double(Int(s, radix: 16) ?? 0) / 255 }
        self.init(red: b(h.prefix(2)), green: b(h.dropFirst(2).prefix(2)), blue: b(h.dropFirst(4).prefix(2)))
    }
}
struct Char { var primary: Color; var secondary: Color; var accent: Color }
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)); return p
    }
}

// ===== 非人型: ひとつ目ブロブ =====
struct AlienBlobCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 14, height: 12).offset(x: -16, y: 40)
            Capsule().fill(character.primary).frame(width: 14, height: 12).offset(x: 16, y: 40)
            Capsule().fill(character.primary).frame(width: 4, height: 16).offset(y: -38)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(y: -46)
            Ellipse().fill(character.primary).frame(width: 80, height: 74).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 46, height: 40).offset(y: 22)
            Circle().fill(.white).frame(width: 44, height: 44).offset(y: -4)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(y: -3)
            Circle().fill(.black).frame(width: 12, height: 12).offset(y: -3)
            Circle().fill(.white).frame(width: 5, height: 5).offset(x: 5, y: -7)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 24)
        }
    }
}

// ===== 人型: 三つ目リトルエイリアン =====
struct AlienTriclopsCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 10, height: 26).rotationEffect(.degrees(22)).offset(x: -32, y: 20)
            Capsule().fill(character.primary).frame(width: 10, height: 26).rotationEffect(.degrees(-22)).offset(x: 32, y: 20)
            Capsule().fill(character.secondary).frame(width: 46, height: 42).offset(y: 32)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(18)).offset(x: -12, y: -38)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(-18)).offset(x: 12, y: -38)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: -15, y: -44)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 15, y: -44)
            Circle().fill(character.primary).frame(width: 68, height: 60).offset(y: -6)
            ForEach(-1...1, id: \.self) { i in
                Circle().fill(.white).frame(width: 17, height: 19).offset(x: CGFloat(i) * 19, y: -8)
                Circle().fill(.black).frame(width: 8, height: 8).offset(x: CGFloat(i) * 19, y: -6)
            }
            SmileArc().stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 16, height: 7).offset(y: 12)
        }
    }
}

// ===== 非人型: ふわふわイカ/クラゲ宇宙人 =====
struct AlienSquidCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(i % 2 == 0 ? character.primary : character.secondary)
                    .frame(width: 9, height: 30)
                    .rotationEffect(.degrees(Double(i - 2) * 9))
                    .offset(x: CGFloat(i - 2) * 14, y: 34)
            }
            Ellipse().fill(character.primary).frame(width: 84, height: 70).offset(y: -6)
            Ellipse().fill(character.secondary).frame(width: 84, height: 26).offset(y: 16)
                .mask(Ellipse().frame(width: 84, height: 70).offset(y: -6))
            Circle().fill(.white).frame(width: 20, height: 22).offset(x: -15, y: -8)
            Circle().fill(.white).frame(width: 20, height: 22).offset(x: 15, y: -8)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: -14, y: -6)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 16, y: -6)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 8)
        }
    }
}

// ===== 非人型: いもむし宇宙人 =====
struct AlienWormCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: 14, y: 40)
            Circle().fill(character.secondary).frame(width: 11, height: 11).offset(x: 14, y: 40)
            Circle().fill(character.primary).frame(width: 36, height: 36).offset(x: -8, y: 26)
            Circle().fill(character.secondary).frame(width: 13, height: 13).offset(x: -8, y: 26)
            Circle().fill(character.primary).frame(width: 40, height: 40).offset(x: 10, y: 8)
            Circle().fill(character.secondary).frame(width: 14, height: 14).offset(x: 10, y: 8)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(20)).offset(x: -8, y: -30)
            Capsule().fill(character.primary).frame(width: 3, height: 14).rotationEffect(.degrees(-20)).offset(x: 8, y: -30)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: -11, y: -36)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 11, y: -36)
            Circle().fill(character.primary).frame(width: 50, height: 48).offset(x: -8, y: -14)
            Circle().fill(.white).frame(width: 13, height: 14).offset(x: -16, y: -16)
            Circle().fill(.white).frame(width: 13, height: 14).offset(x: 0, y: -16)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: -16, y: -15)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: 0, y: -15)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 13, height: 6).offset(x: -8, y: -3)
        }
    }
}

// ===== 非人型: きのこ宇宙人 =====
struct AlienMushroomCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 46, height: 54).offset(y: 24)
            Ellipse().fill(character.primary).frame(width: 92, height: 60).offset(y: -18)
            Circle().fill(character.accent).frame(width: 14, height: 14).offset(x: -24, y: -22)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 6, y: -30)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 26, y: -16)
            Circle().fill(.white).frame(width: 15, height: 16).offset(x: -11, y: 18)
            Circle().fill(.white).frame(width: 15, height: 16).offset(x: 11, y: 18)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: -11, y: 19)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: 11, y: 19)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 14, height: 6).offset(y: 32)
        }
    }
}

// ===== 人型: とびだし目玉(バグアイ)宇宙人 =====
struct AlienBugeyeCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 9, height: 24).rotationEffect(.degrees(24)).offset(x: -28, y: 20)
            Capsule().fill(character.primary).frame(width: 9, height: 24).rotationEffect(.degrees(-24)).offset(x: 28, y: 20)
            Capsule().fill(character.secondary).frame(width: 46, height: 44).offset(y: 30)
            Circle().fill(character.primary).frame(width: 48, height: 44).offset(y: -2)
            Capsule().fill(character.primary).frame(width: 6, height: 22).offset(x: -14, y: -28)
            Capsule().fill(character.primary).frame(width: 6, height: 22).offset(x: 14, y: -28)
            Circle().fill(.white).frame(width: 26, height: 26).offset(x: -14, y: -40)
            Circle().fill(.white).frame(width: 26, height: 26).offset(x: 14, y: -40)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -12, y: -39)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 16, y: -39)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: -12, y: -39)
            Circle().fill(.black).frame(width: 6, height: 6).offset(x: 16, y: -39)
            SmileArc().stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 16, height: 7).offset(y: 6)
        }
    }
}

// ===== 非人型: クリスタル宇宙人 =====
struct AlienCrystalCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(character.secondary).frame(width: 26, height: 26).rotationEffect(.degrees(45)).offset(x: -34, y: 28)
            RoundedRectangle(cornerRadius: 10).fill(character.secondary).frame(width: 22, height: 22).rotationEffect(.degrees(45)).offset(x: 34, y: 30)
            RoundedRectangle(cornerRadius: 16).fill(character.primary).frame(width: 74, height: 74).rotationEffect(.degrees(45)).offset(y: -2)
            Capsule().fill(character.secondary.opacity(0.6)).frame(width: 3, height: 30).rotationEffect(.degrees(45)).offset(x: -10, y: -2)
            Capsule().fill(character.secondary.opacity(0.6)).frame(width: 3, height: 30).rotationEffect(.degrees(-45)).offset(x: 10, y: -2)
            Circle().fill(.white).frame(width: 14, height: 15).offset(x: -11, y: -4)
            Circle().fill(.white).frame(width: 14, height: 15).offset(x: 11, y: -4)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: -11, y: -3)
            Circle().fill(.black).frame(width: 7, height: 7).offset(x: 11, y: -3)
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 14, height: 6).offset(y: 12)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: 22, y: -26)
        }
    }
}

// ===== 非人型: ホバー(バイザー)宇宙人 =====
struct AlienHoverCharacterFace: View {
    var character: Char
    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.5)).frame(width: 54, height: 16).offset(y: 42)
            Capsule().fill(character.primary).frame(width: 3, height: 14).offset(y: -42)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(y: -50)
            Circle().fill(character.primary).frame(width: 74, height: 70).offset(y: -2)
            Ellipse().fill(character.secondary).frame(width: 70, height: 18).offset(y: 24)
                .mask(Circle().frame(width: 74, height: 70).offset(y: -2))
            Capsule().fill(.black.opacity(0.82)).frame(width: 58, height: 24).offset(y: -4)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -12, y: -4)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 12, y: -4)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: -14, y: -6)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: 10, y: -6)
        }
    }
}

let samples: [(AnyView, String)] = [
    (AnyView(AlienBlobCharacterFace(character: Char(primary: Color(hex: "6BCB77"), secondary: Color(hex: "BFF0A6"), accent: Color(hex: "2E5A8C")))), "blob(非/一つ目)"),
    (AnyView(AlienTriclopsCharacterFace(character: Char(primary: Color(hex: "B98CE0"), secondary: Color(hex: "7A5AB0"), accent: Color(hex: "1A1A2E")))), "triclops(人/三つ目)"),
    (AnyView(AlienSquidCharacterFace(character: Char(primary: Color(hex: "5BC8D6"), secondary: Color(hex: "C77AD6"), accent: Color(hex: "23314F")))), "squid(非/イカ)"),
    (AnyView(AlienWormCharacterFace(character: Char(primary: Color(hex: "7AC77A"), secondary: Color(hex: "C2F0A6"), accent: Color(hex: "2E5A8C")))), "worm(非/いもむし)"),
    (AnyView(AlienMushroomCharacterFace(character: Char(primary: Color(hex: "E0563B"), secondary: Color(hex: "F2DEC2"), accent: Color(hex: "FFF2E0")))), "mushroom(非/きのこ)"),
    (AnyView(AlienBugeyeCharacterFace(character: Char(primary: Color(hex: "6BCBB0"), secondary: Color(hex: "4A9E86"), accent: Color(hex: "E0A53C")))), "bugeye(人/目玉)"),
    (AnyView(AlienCrystalCharacterFace(character: Char(primary: Color(hex: "8C9EE0"), secondary: Color(hex: "C7D2F7"), accent: Color(hex: "F2D24C")))), "crystal(非/結晶)"),
    (AnyView(AlienHoverCharacterFace(character: Char(primary: Color(hex: "9AA6B2"), secondary: Color(hex: "8FD6E0"), accent: Color(hex: "5BE0C7")))), "hover(非/バイザー)"),
]

struct Cell: View {
    let v: AnyView; let label: String
    var body: some View {
        VStack(spacing: 6) {
            v.frame(width: 130, height: 140).background(Color(white: 0.97))
            Text(label).font(.system(size: 12)).foregroundColor(.black)
        }.padding(10).background(Color.white)
    }
}
struct Sheet: View {
    var body: some View {
        let cols = 4
        let rows = stride(from: 0, to: samples.count, by: cols).map { Array(samples[$0..<min($0+cols, samples.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) { ForEach(Array(row.enumerated()), id: \.offset) { _, s in Cell(v: s.0, label: s.1) } }
            }
        }.padding(16).background(Color(white: 0.88))
    }
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath + "/alien_preview.png"
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Sheet()); r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1) }
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("✅ wrote \(outPath)")
    let op = Process(); op.executableURL = URL(fileURLWithPath: "/usr/bin/open"); op.arguments = ["-a", "Preview", outPath]; try? op.run()
    print("🖼  opened in Preview.app")
}
