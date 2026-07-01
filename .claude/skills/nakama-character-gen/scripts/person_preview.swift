// モードS（SwiftUI 手続き描画）の人物なかまを、アプリ無しで PNG コンタクトシートに書き出すツール。
// macOS の ImageRenderer を使うので「SwiftUI はアプリでしか見られない」を回避できる。
//
// 使い方:  swift person_preview.swift [out.png]
// 出力:    全 PersonHair の顔を 4 列グリッドで 1 枚に。崩れ確認・修正イテレーション用。
//
// ⚠ ここの PersonCharacterFace / PersonHair は iPadPrototype/HomeView.swift と「手で同期」する。
//    髪型を直したら両方を同じ内容にすること（このツールが実機の見た目の代理）。
import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        func b(_ s: Substring) -> Double { Double(Int(s, radix: 16) ?? 0) / 255 }
        self.init(red: b(h.prefix(2)), green: b(h.dropFirst(2).prefix(2)), blue: b(h.dropFirst(4).prefix(2)))
    }
}

// HomeRewardCharacter の代理（primary=肌 / secondary=服 / accent=髪）
struct Char { var primary: Color; var secondary: Color; var accent: Color }

// ===== HomeView.swift からコピーした補助 View（同期対象）=====
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath(); return p
    }
}
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}
struct CharacterEyes: View {
    var color: Color
    var body: some View {
        HStack(spacing: 24) {
            Circle().fill(color).frame(width: 7, height: 7)
            Circle().fill(color).frame(width: 7, height: 7)
        }.offset(y: 2)
    }
}

// ===== PersonHair / PersonCharacterFace（HomeView.swift と同期）=====
enum PersonHair: String, CaseIterable {
    case short, long, curly, bun, buzz, ponytail
    case twintails, bob, afro, spiky, braids, wavy
}

struct PersonCharacterFace: View {
    var character: Char
    var hair: PersonHair
    private var cheek: Color { Color(red: 0.95, green: 0.55, blue: 0.58) }

    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 82, height: 48).offset(y: 52)
            RoundedRectangle(cornerRadius: 8).fill(character.primary).frame(width: 18, height: 16).offset(y: 33)
            hairBack
            Circle().fill(character.primary).frame(width: 62, height: 66).offset(y: 2)
            Circle().fill(character.primary).frame(width: 13, height: 15).offset(x: -31, y: 6)
            Circle().fill(character.primary).frame(width: 13, height: 15).offset(x: 31, y: 6)
            hairFront
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(cheek.opacity(0.30)).frame(width: 11, height: 9).offset(x: -19, y: 13)
            Circle().fill(cheek.opacity(0.30)).frame(width: 11, height: 9).offset(x: 19, y: 13)
            SmileArc().stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 20, height: 11).offset(y: 15)
        }
    }

    @ViewBuilder private var hairBack: some View {
        switch hair {
        case .long:
            RoundedRectangle(cornerRadius: 26).fill(character.accent).frame(width: 72, height: 88).offset(y: 8)
        case .ponytail:
            Capsule().fill(character.accent).frame(width: 20, height: 48).rotationEffect(.degrees(18)).offset(x: 35, y: 8)
        case .bun:
            Circle().fill(character.accent).frame(width: 26, height: 26).offset(y: -34)
        case .twintails:
            Capsule().fill(character.accent).frame(width: 18, height: 46).rotationEffect(.degrees(-22)).offset(x: -34, y: 10)
            Capsule().fill(character.accent).frame(width: 18, height: 46).rotationEffect(.degrees(22)).offset(x: 34, y: 10)
        case .bob:
            RoundedRectangle(cornerRadius: 22).fill(character.accent).frame(width: 76, height: 70).offset(y: 2)
        case .afro:
            Circle().fill(character.accent).frame(width: 86, height: 82).offset(y: -4)
        case .braids:
            ForEach(0..<3) { index in
                Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: -33, y: CGFloat(index) * 13 + 6)
            }
            ForEach(0..<3) { index in
                Circle().fill(character.accent).frame(width: 16, height: 16).offset(x: 33, y: CGFloat(index) * 13 + 6)
            }
        case .wavy:
            RoundedRectangle(cornerRadius: 30).fill(character.accent).frame(width: 72, height: 84).offset(y: 10)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(x: -29, y: 44)
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(x: 29, y: 44)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var hairFront: some View {
        switch hair {
        case .buzz:
            Circle().fill(character.accent).frame(width: 60, height: 60).offset(y: -8)
                .mask(Rectangle().frame(width: 64, height: 24).offset(y: -22))
        case .short:
            Circle().fill(character.accent).frame(width: 66, height: 64).offset(y: -10)
                .mask(Rectangle().frame(width: 70, height: 34).offset(y: -18))
        case .curly:
            ForEach(0..<6) { index in
                Circle().fill(character.accent).frame(width: 24, height: 24).offset(y: -30)
                    .rotationEffect(.degrees(Double(index) * 28 - 70))
            }
            Circle().fill(character.accent).frame(width: 24, height: 24).offset(y: -32)
        case .spiky:
            // 髪の土台キャップ → そこからトゲを生やす（坊主に浮かないよう接続）
            Circle().fill(character.accent).frame(width: 66, height: 62).offset(y: -12)
                .mask(Rectangle().frame(width: 70, height: 28).offset(y: -22))
            ForEach(0..<5) { index in
                Triangle().fill(character.accent).frame(width: 16, height: 22)
                    .offset(x: CGFloat(index - 2) * 14, y: -34)
            }
        default:
            // long, ponytail, bun, twintails, bob, afro, braids, wavy: 共通の前髪
            Circle().fill(character.accent).frame(width: 64, height: 58).offset(y: -12)
                .mask(Rectangle().frame(width: 70, height: 30).offset(y: -20))
        }
    }
}

// ===== グリッド組み立て =====
// 実キャラの色（肌/服/髪）で代表させる
let samples: [(PersonHair, Char, String)] = [
    (.short,     Char(primary: Color(hex: "D89B6C"), secondary: Color(hex: "2A4A7A"), accent: Color(hex: "3A6EA5")), "short/Ren"),
    (.long,      Char(primary: Color(hex: "F2C9A6"), secondary: Color(hex: "66C2C2"), accent: Color(hex: "8B5CC7")), "long/Aoi"),
    (.curly,     Char(primary: Color(hex: "D89B6C"), secondary: Color(hex: "4CA66B"), accent: Color(hex: "C0392B")), "curly/Gen"),
    (.bun,       Char(primary: Color(hex: "F7D7B5"), secondary: Color(hex: "3A9E9E"), accent: Color(hex: "B8BCC2")), "bun/Eri"),
    (.buzz,      Char(primary: Color(hex: "8A5A38"), secondary: Color(hex: "F2C14E"), accent: Color(hex: "1A1410")), "buzz/Sho"),
    (.ponytail,  Char(primary: Color(hex: "FCE0C2"), secondary: Color(hex: "F2A6C2"), accent: Color(hex: "E06AA8")), "ponytail/Momo"),
    (.twintails, Char(primary: Color(hex: "F7D7B5"), secondary: Color(hex: "F2A6C2"), accent: Color(hex: "1A1410")), "twintails/Yui"),
    (.bob,       Char(primary: Color(hex: "FCE0C2"), secondary: Color(hex: "F2C14E"), accent: Color(hex: "E0B85C")), "bob/Emma"),
    (.afro,      Char(primary: Color(hex: "8A5A38"), secondary: Color(hex: "E0773C"), accent: Color(hex: "1A1410")), "afro/Max"),
    (.spiky,     Char(primary: Color(hex: "D89B6C"), secondary: Color(hex: "4CA66B"), accent: Color(hex: "4A2F1A")), "spiky/Kai"),
    (.braids,    Char(primary: Color(hex: "8A5A38"), secondary: Color(hex: "8B5CC7"), accent: Color(hex: "1A1410")), "braids/Sara"),
    (.wavy,      Char(primary: Color(hex: "FCE0C2"), secondary: Color(hex: "B98CE0"), accent: Color(hex: "8B3A2A")), "wavy/Lily"),
]

struct Cell: View {
    let hair: PersonHair; let ch: Char; let label: String
    var body: some View {
        VStack(spacing: 4) {
            PersonCharacterFace(character: ch, hair: hair)
                .frame(width: 130, height: 140)
                .background(Color(white: 0.97))
            Text(label).font(.system(size: 12)).foregroundColor(.black)
        }
        .padding(8)
        .background(Color.white)
    }
}

struct Sheet: View {
    var body: some View {
        let cols = 4
        let rows = stride(from: 0, to: samples.count, by: cols).map { Array(samples[$0..<min($0+cols, samples.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        Cell(hair: item.0, ch: item.1, label: item.2)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.88))
    }
}

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/person_preview.png"

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Sheet())
    renderer.scale = 2
    guard let img = renderer.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("⛔ render failed\n".utf8)); exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: outPath))
        print("✅ wrote \(outPath)")
        // 背景スキルと同じく、書き出した PNG を macOS の Preview.app で自動的に開く
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Preview", outPath]
        try? open.run()
        print("🖼  opened in Preview.app")
    } catch {
        FileHandle.standardError.write(Data("⛔ \(error)\n".utf8)); exit(1)
    }
}
