// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpellingOCRLab",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .executable(name: "spelling-ocr-lab", targets: ["SpellingOCRLab"]),
        // マルチデバイス同期の純粋ロジック（競合解決・論理削除・スコープ）。
        // iPad/iPhone アプリ本体から取り込む「狭いストア境界」の土台。
        // 設計: docs/multi-user-cloudkit-sync-design.md
        .library(name: "SpellingSyncCore", targets: ["SpellingSyncCore"])
    ],
    targets: [
        .executableTarget(name: "SpellingOCRLab"),
        .target(name: "SpellingSyncCore"),
        .testTarget(
            name: "SpellingSyncCoreTests",
            dependencies: ["SpellingSyncCore"]
        )
    ]
)
