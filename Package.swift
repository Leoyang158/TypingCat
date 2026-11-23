// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TypingCat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TypingCat",
            path: "Sources/TypingCat",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
