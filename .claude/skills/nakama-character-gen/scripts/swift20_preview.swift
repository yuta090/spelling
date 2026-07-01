// モードS の新規なかま20体フェイスをアプリ無しで PNG 化して Preview.app で確認する一時ハーネス。
// OK なら各 View を iPadPrototype/HomeView.swift に移植する（このファイルが実機見た目の代理）。
// 使い方: swift swift20_preview.swift out.png
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

// 共有シェイプ(HomeView.swift と同等)
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
struct WhiskerLines: View {
    var color: Color
    var body: some View {
        ZStack {
            Rectangle().fill(color).frame(width: 16, height: 2).offset(x: -30, y: 14)
            Rectangle().fill(color).frame(width: 16, height: 2).rotationEffect(.degrees(10)).offset(x: -30, y: 8)
            Rectangle().fill(color).frame(width: 16, height: 2).offset(x: 30, y: 14)
            Rectangle().fill(color).frame(width: 16, height: 2).rotationEffect(.degrees(-10)).offset(x: 30, y: 8)
        }
    }
}

// ===================== 動物 =====================

// ねずみ Mouse
struct MouseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 38, height: 38).offset(x: -28, y: -24)
            Circle().fill(character.primary).frame(width: 38, height: 38).offset(x: 28, y: -24)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: -28, y: -24)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: 28, y: -24)
            Circle().fill(character.primary).frame(width: 70, height: 70).offset(y: 8)
            Circle().fill(character.secondary).frame(width: 34, height: 26).offset(y: 20)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 9, height: 7).offset(y: 16)
            WhiskerLines(color: character.secondary.opacity(0.9))
        }
    }
}

// うし Cow
struct CowCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 12, height: 18).rotationEffect(.degrees(-24)).offset(x: -20, y: -40)
            Capsule().fill(character.accent).frame(width: 12, height: 18).rotationEffect(.degrees(24)).offset(x: 20, y: -40)
            Ellipse().fill(character.primary).frame(width: 32, height: 22).offset(x: -36, y: -16)
            Ellipse().fill(character.primary).frame(width: 32, height: 22).offset(x: 36, y: -16)
            Circle().fill(character.primary).frame(width: 76, height: 72).offset(y: 6)
            Circle().fill(character.accent).frame(width: 26, height: 22).offset(x: -22, y: -10)
            Ellipse().fill(character.secondary).frame(width: 46, height: 34).offset(y: 22)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 7, height: 7).offset(x: -9, y: 22)
            Circle().fill(character.accent).frame(width: 7, height: 7).offset(x: 9, y: 22)
        }
    }
}

// うま Horse
struct HorseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 20, height: 26).rotationEffect(.degrees(-10)).offset(x: -20, y: -38)
            Triangle().fill(character.primary).frame(width: 20, height: 26).rotationEffect(.degrees(10)).offset(x: 20, y: -38)
            Capsule().fill(character.accent).frame(width: 16, height: 30).offset(y: -28)
            Ellipse().fill(character.primary).frame(width: 56, height: 80).offset(y: 6)
            Capsule().fill(character.accent).frame(width: 12, height: 16).offset(y: -30)
            Ellipse().fill(character.secondary).frame(width: 40, height: 38).offset(y: 30)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -8, y: 34)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 8, y: 34)
        }
    }
}

// オオカミ Wolf
struct WolfCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 30, height: 36).rotationEffect(.degrees(-14)).offset(x: -26, y: -32)
            Triangle().fill(character.primary).frame(width: 30, height: 36).rotationEffect(.degrees(14)).offset(x: 26, y: -32)
            Circle().fill(character.primary).frame(width: 76, height: 74).offset(y: 6)
            Triangle().fill(character.secondary).frame(width: 26, height: 24).rotationEffect(.degrees(-20)).offset(x: -28, y: 10)
            Triangle().fill(character.secondary).frame(width: 26, height: 24).rotationEffect(.degrees(20)).offset(x: 28, y: 10)
            Circle().fill(character.secondary).frame(width: 40, height: 40).offset(y: 18)
            Triangle().fill(character.primary).frame(width: 26, height: 22).rotationEffect(.degrees(180)).offset(y: 10)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 9, height: 8).offset(y: 16)
        }
    }
}

// かんがるー Kangaroo
struct KangarooCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 18, height: 44).rotationEffect(.degrees(-12)).offset(x: -22, y: -34)
            Capsule().fill(character.primary).frame(width: 18, height: 44).rotationEffect(.degrees(12)).offset(x: 22, y: -34)
            Capsule().fill(character.accent).frame(width: 9, height: 28).rotationEffect(.degrees(-12)).offset(x: -22, y: -32)
            Capsule().fill(character.accent).frame(width: 9, height: 28).rotationEffect(.degrees(12)).offset(x: 22, y: -32)
            Ellipse().fill(character.primary).frame(width: 60, height: 72).offset(y: 6)
            Ellipse().fill(character.secondary).frame(width: 34, height: 40).offset(y: 24)
            CharacterEyes(color: .black.opacity(0.78))
            Triangle().fill(character.accent).frame(width: 12, height: 9).rotationEffect(.degrees(180)).offset(y: 18)
        }
    }
}

// こうもり Bat
struct BatCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 46, height: 40).rotationEffect(.degrees(-90)).offset(x: -38, y: 0)
            Triangle().fill(character.primary).frame(width: 46, height: 40).rotationEffect(.degrees(90)).offset(x: 38, y: 0)
            Triangle().fill(character.primary).frame(width: 22, height: 24).offset(x: -16, y: -32)
            Triangle().fill(character.primary).frame(width: 22, height: 24).offset(x: 16, y: -32)
            Circle().fill(character.secondary).frame(width: 60, height: 56).offset(y: 4)
            CharacterEyes(color: character.accent)
            Triangle().fill(.white).frame(width: 7, height: 8).rotationEffect(.degrees(180)).offset(x: -7, y: 16)
            Triangle().fill(.white).frame(width: 7, height: 8).rotationEffect(.degrees(180)).offset(x: 7, y: 16)
        }
    }
}

// やぎ Goat
struct GoatCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 12, height: 30).rotationEffect(.degrees(-30)).offset(x: -18, y: -40)
            Capsule().fill(character.accent).frame(width: 12, height: 30).rotationEffect(.degrees(30)).offset(x: 18, y: -40)
            Ellipse().fill(character.secondary).frame(width: 30, height: 18).rotationEffect(.degrees(-20)).offset(x: -34, y: -8)
            Ellipse().fill(character.secondary).frame(width: 30, height: 18).rotationEffect(.degrees(20)).offset(x: 34, y: -8)
            Ellipse().fill(character.primary).frame(width: 62, height: 70).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 36, height: 34).offset(y: 22)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -8, y: 22)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: 8, y: 22)
            Capsule().fill(character.secondary).frame(width: 13, height: 15).offset(y: 42)
        }
    }
}

// ===================== 海 =====================

// らっこ Otter
struct OtterCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 22, height: 22).offset(x: -28, y: -22)
            Circle().fill(character.primary).frame(width: 22, height: 22).offset(x: 28, y: -22)
            Circle().fill(character.primary).frame(width: 72, height: 70).offset(y: 8)
            Circle().fill(character.secondary).frame(width: 30, height: 28).offset(x: -13, y: 18)
            Circle().fill(character.secondary).frame(width: 30, height: 28).offset(x: 13, y: 18)
            CharacterEyes(color: .black.opacity(0.78))
            Circle().fill(character.accent).frame(width: 12, height: 9).offset(y: 12)
            WhiskerLines(color: character.accent.opacity(0.6))
        }
    }
}

// しゃち Orca
struct OrcaCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 22, height: 26).offset(x: 2, y: -30)
            Triangle().fill(character.primary).frame(width: 26, height: 22).rotationEffect(.degrees(-90)).offset(x: 38, y: -2)
            Ellipse().fill(character.primary).frame(width: 74, height: 50).offset(y: 4)
            Ellipse().fill(character.secondary).frame(width: 44, height: 22).offset(y: 18)
            Ellipse().fill(character.secondary).frame(width: 14, height: 10).offset(x: -16, y: -8)
            Circle().fill(.black.opacity(0.85)).frame(width: 7, height: 7).offset(x: -16, y: -8)
            Circle().fill(.black.opacity(0.85)).frame(width: 7, height: 7).offset(x: 4, y: -6)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: -8, y: 8)
        }
    }
}

// たつのおとしご Seahorse
struct SeahorseCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 12, height: 10).offset(x: -2, y: -42)
            Triangle().fill(character.secondary).frame(width: 12, height: 10).offset(x: 8, y: -40)
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: -2, y: -28)
            Capsule().fill(character.secondary).frame(width: 16, height: 14).rotationEffect(.degrees(-30)).offset(x: -18, y: -30)
            Capsule().fill(character.primary).frame(width: 30, height: 50).offset(x: 2, y: 4)
            ForEach(0..<3) { i in
                Triangle().fill(character.secondary).frame(width: 12, height: 10).rotationEffect(.degrees(-90)).offset(x: 20, y: CGFloat(-8 + i * 16))
            }
            Circle().fill(character.primary).frame(width: 24, height: 24).offset(x: -8, y: 34)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 2, y: -30)
            Circle().fill(.white).frame(width: 3, height: 3).offset(x: 4, y: -32)
        }
    }
}

// えび Shrimp
struct ShrimpCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Rectangle().fill(character.accent).frame(width: 2, height: 30).rotationEffect(.degrees(20)).offset(x: -34, y: -22)
            Rectangle().fill(character.accent).frame(width: 2, height: 38).rotationEffect(.degrees(34)).offset(x: -32, y: -16)
            Triangle().fill(character.secondary).frame(width: 26, height: 30).rotationEffect(.degrees(140)).offset(x: 34, y: 18)
            ForEach(0..<5) { i in
                Circle().fill(character.primary)
                    .frame(width: CGFloat(38 - i * 4), height: CGFloat(38 - i * 4))
                    .offset(x: CGFloat(-22 + i * 13), y: CGFloat(i * i) * 1.1 - 2)
            }
            Circle().fill(.black.opacity(0.82)).frame(width: 8, height: 8).offset(x: -22, y: -8)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 10, height: 5).offset(x: -20, y: 6)
        }
    }
}

// ===================== 鳥 =====================

// あひる Duck
struct DuckCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.primary).frame(width: 16, height: 20).rotationEffect(.degrees(20)).offset(x: 16, y: -36)
            Circle().fill(character.primary).frame(width: 72, height: 70).offset(y: 2)
            Ellipse().fill(character.secondary).frame(width: 40, height: 26).offset(y: 24)
            CharacterEyes(color: .black.opacity(0.82))
            Ellipse().fill(character.accent).frame(width: 40, height: 18).offset(y: 16)
            Ellipse().fill(character.accent.opacity(0.6)).frame(width: 40, height: 7).offset(y: 21)
        }
    }
}

// フラミンゴ Flamingo
struct FlamingoCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 58, height: 44).offset(y: 22)
            Ellipse().fill(character.secondary).frame(width: 30, height: 24).offset(x: 8, y: 28)
            Capsule().fill(character.primary).frame(width: 18, height: 56).rotationEffect(.degrees(20)).offset(x: -14, y: -18)
            Circle().fill(character.primary).frame(width: 34, height: 34).offset(x: -24, y: -38)
            Triangle().fill(character.accent).frame(width: 20, height: 14).rotationEffect(.degrees(-110)).offset(x: -38, y: -34)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -26, y: -42)
        }
    }
}

// インコ Parrot
struct ParrotCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.secondary).frame(width: 18, height: 24).rotationEffect(.degrees(-18)).offset(x: -6, y: -36)
            Circle().fill(character.primary).frame(width: 70, height: 70).offset(y: 2)
            Ellipse().fill(character.secondary).frame(width: 30, height: 44).offset(x: 24, y: 14)
            Circle().fill(character.accent.opacity(0.55)).frame(width: 18, height: 18).offset(x: -22, y: 8)
            CharacterEyes(color: .black.opacity(0.82))
            Circle().fill(character.accent).frame(width: 22, height: 18).offset(y: 16)
            Triangle().fill(character.accent).frame(width: 16, height: 16).rotationEffect(.degrees(180)).offset(y: 24)
        }
    }
}

// はくちょう Swan
struct SwanCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.primary).frame(width: 66, height: 46).offset(y: 22)
            Ellipse().fill(character.secondary).frame(width: 36, height: 30).offset(x: 14, y: 22)
            Capsule().fill(character.primary).frame(width: 16, height: 54).rotationEffect(.degrees(-18)).offset(x: -12, y: -16)
            Circle().fill(character.primary).frame(width: 30, height: 30).offset(x: -22, y: -38)
            Triangle().fill(character.accent).frame(width: 18, height: 12).rotationEffect(.degrees(-110)).offset(x: -36, y: -36)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -24, y: -42)
        }
    }
}

// ===================== 虫 =====================

// かたつむり Snail
struct SnailCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.secondary).frame(width: 76, height: 28).offset(x: -4, y: 26)
            Circle().fill(character.secondary).frame(width: 34, height: 34).offset(x: -34, y: 14)
            Rectangle().fill(character.secondary).frame(width: 3, height: 18).offset(x: -42, y: -2)
            Rectangle().fill(character.secondary).frame(width: 3, height: 18).offset(x: -34, y: -4)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -42, y: -12)
            Circle().fill(character.accent).frame(width: 6, height: 6).offset(x: -34, y: -14)
            Circle().fill(character.primary).frame(width: 64, height: 64).offset(x: 12, y: 0)
            Circle().fill(character.secondary).frame(width: 42, height: 42).offset(x: 12, y: 0)
            Circle().fill(character.accent).frame(width: 22, height: 22).offset(x: 12, y: 0)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: -36, y: 16)
            SmileArc().stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 9, height: 4).offset(x: -34, y: 24)
        }
    }
}

// とんぼ Dragonfly
struct DragonflyCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 40, height: 16).rotationEffect(.degrees(20)).offset(x: -24, y: -14)
            Ellipse().fill(character.secondary.opacity(0.85)).frame(width: 40, height: 16).rotationEffect(.degrees(-20)).offset(x: 24, y: -14)
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 34, height: 14).rotationEffect(.degrees(-18)).offset(x: -22, y: 4)
            Ellipse().fill(character.secondary.opacity(0.7)).frame(width: 34, height: 14).rotationEffect(.degrees(18)).offset(x: 22, y: 4)
            Capsule().fill(character.primary).frame(width: 13, height: 66).offset(y: 10)
            Circle().fill(character.primary).frame(width: 30, height: 28).offset(y: -28)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: -8, y: -30)
            Circle().fill(character.accent).frame(width: 12, height: 12).offset(x: 8, y: -30)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: -6, y: -32)
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: 10, y: -32)
        }
    }
}

// ===================== 食べ物 =====================

// バナナ Banana
struct BananaCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Capsule().fill(character.accent).frame(width: 10, height: 16).rotationEffect(.degrees(-40)).offset(x: -34, y: -18)
            Capsule().fill(character.primary).frame(width: 84, height: 34).rotationEffect(.degrees(-22)).offset(y: 6)
            Capsule().fill(character.secondary).frame(width: 60, height: 14).rotationEffect(.degrees(-22)).offset(x: 4, y: 0)
            Circle().fill(character.accent.opacity(0.8)).frame(width: 9, height: 9).offset(x: 34, y: 20)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: -6, y: 2)
            Circle().fill(.black.opacity(0.8)).frame(width: 6, height: 6).offset(x: 12, y: -4)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: 4, y: 6)
        }
    }
}

// たいやき Taiyaki
struct TaiyakiCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Triangle().fill(character.primary).frame(width: 30, height: 30).rotationEffect(.degrees(-90)).offset(x: 36, y: 0)
            Ellipse().fill(character.primary).frame(width: 76, height: 54).offset(x: -4, y: 2)
            ForEach(0..<3) { i in
                Triangle().fill(character.secondary).frame(width: 12, height: 9).offset(x: CGFloat(-14 + i * 12), y: -26)
            }
            Ellipse().fill(character.secondary).frame(width: 50, height: 28).offset(x: -8, y: 8)
            Circle().fill(.white).frame(width: 14, height: 14).offset(x: -22, y: -6)
            Circle().fill(.black.opacity(0.82)).frame(width: 7, height: 7).offset(x: -22, y: -6)
            SmileArc().stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 6).offset(x: -10, y: 8)
        }
    }
}

// クッキー Cookie
struct CookieCharacterFace: View {
    var character: HomeRewardCharacter
    var body: some View {
        ZStack {
            Circle().fill(character.primary).frame(width: 78, height: 78).offset(y: 4)
            Circle().fill(character.secondary).frame(width: 60, height: 60).offset(y: 4)
            Circle().fill(character.accent).frame(width: 11, height: 11).offset(x: -22, y: -14)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 20, y: -18)
            Circle().fill(character.accent).frame(width: 10, height: 10).offset(x: 26, y: 16)
            Circle().fill(character.accent).frame(width: 8, height: 8).offset(x: -26, y: 20)
            Circle().fill(character.accent).frame(width: 9, height: 9).offset(x: 0, y: 28)
            CharacterEyes(color: .black.opacity(0.8))
            SmileArc().stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 18, height: 8).offset(y: 16)
        }
    }
}

// ===================== ハーネス =====================
struct HomeRewardCharacter { var primary: Color; var secondary: Color; var accent: Color }
func mk(_ p: String, _ s: String, _ a: String) -> HomeRewardCharacter {
    HomeRewardCharacter(primary: Color(hex: p), secondary: Color(hex: s), accent: Color(hex: a))
}

let samples: [(AnyView, String)] = [
    (AnyView(MouseCharacterFace(character: mk("B8BCC4", "ECEEF2", "E89BB0"))), "mouse ねずみ"),
    (AnyView(CowCharacterFace(character: mk("F2F0EB", "F4B6A6", "4A4038"))), "cow うし"),
    (AnyView(HorseCharacterFace(character: mk("C8915E", "E6C39A", "5B3A22"))), "horse うま"),
    (AnyView(WolfCharacterFace(character: mk("8C97A6", "D7DCE3", "3A3F4A"))), "wolf オオカミ"),
    (AnyView(KangarooCharacterFace(character: mk("C98A5E", "E8C9A8", "5B3A22"))), "kangaroo かんがるー"),
    (AnyView(BatCharacterFace(character: mk("6B5E7B", "9486A8", "F2D24C"))), "bat こうもり"),
    (AnyView(GoatCharacterFace(character: mk("EDE9E2", "D2C7B4", "8A7A5A"))), "goat やぎ"),
    (AnyView(OtterCharacterFace(character: mk("8A6A4F", "D9C3A8", "4A3324"))), "otter らっこ"),
    (AnyView(OrcaCharacterFace(character: mk("2B2F36", "F2F4F7", "FFFFFF"))), "orca しゃち"),
    (AnyView(SeahorseCharacterFace(character: mk("F2A93C", "F7C66B", "C9742A"))), "seahorse たつのおとしご"),
    (AnyView(ShrimpCharacterFace(character: mk("F08A6B", "F7C2A8", "C9542E"))), "shrimp えび"),
    (AnyView(DuckCharacterFace(character: mk("F4D24C", "FBE89A", "F2913C"))), "duck あひる"),
    (AnyView(FlamingoCharacterFace(character: mk("F299B8", "F7C2D4", "2B2F36"))), "flamingo フラミンゴ"),
    (AnyView(ParrotCharacterFace(character: mk("3FAE6B", "F2D24C", "E0533B"))), "parrot インコ"),
    (AnyView(SwanCharacterFace(character: mk("F4F4F2", "E3E6EC", "E0833C"))), "swan はくちょう"),
    (AnyView(SnailCharacterFace(character: mk("C99A6B", "E8D2B0", "8A5A38"))), "snail かたつむり"),
    (AnyView(DragonflyCharacterFace(character: mk("3FA8C2", "BFE6F0", "2E6B8C"))), "dragonfly とんぼ"),
    (AnyView(BananaCharacterFace(character: mk("F4D24C", "FBE89A", "8A6A3A"))), "banana バナナ"),
    (AnyView(TaiyakiCharacterFace(character: mk("D99A4C", "E8C48A", "8A5A2A"))), "taiyaki たいやき"),
    (AnyView(CookieCharacterFace(character: mk("D9A86B", "E8C99A", "6B4A2A"))), "cookie クッキー"),
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

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath + "/swift20_preview.png"
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Sheet()); r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1) }
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("✅ wrote \(outPath)")
    let op = Process(); op.executableURL = URL(fileURLWithPath: "/usr/bin/open"); op.arguments = ["-a", "Preview", outPath]; try? op.run()
    print("🖼  opened in Preview.app")
}
