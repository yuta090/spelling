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
        // confusables_sound 辞書のビルド/検証ツール（開発時のみ）。
        // draft CSV ＋ wordbank → 検証 → 同梱 CSV。設計: docs/confusables-sound-authoring-DRAFT-2026-06-28.md §5
        .executable(name: "confusables-build", targets: ["ConfusablesBuild"]),
        // 文バンク前処理ツール（開発時のみ）。
        // curated 素（person_templates）＋ wordbank → 学年タグ付け検証 → 同梱 sentence_bank.json。
        // 設計: docs/sentence-builder-design-2026-06-27.md §3
        .executable(name: "sentence-bank-build", targets: ["SentenceBankBuild"]),
        // マルチデバイス同期の純粋ロジック（競合解決・論理削除・スコープ）。
        // iPad/iPhone アプリ本体から取り込む「狭いストア境界」の土台。
        // 設計: docs/multi-user-cloudkit-sync-design.md
        .library(name: "SpellingSyncCore", targets: ["SpellingSyncCore"])
    ],
    targets: [
        .executableTarget(name: "SpellingOCRLab"),
        .executableTarget(name: "ConfusablesBuild", dependencies: ["SpellingSyncCore"]),
        .executableTarget(name: "SentenceBankBuild", dependencies: ["SpellingSyncCore"]),
        .target(name: "SpellingSyncCore"),
        .testTarget(
            name: "SpellingSyncCoreTests",
            dependencies: ["SpellingSyncCore"]
        )
    ]
)
