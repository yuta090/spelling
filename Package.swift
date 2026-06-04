// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpellingOCRLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "spelling-ocr-lab", targets: ["SpellingOCRLab"])
    ],
    targets: [
        .executableTarget(name: "SpellingOCRLab")
    ]
)
