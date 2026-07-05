// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalFirstRAG",
    // Platform floor is set by the highest minimum among the frameworks this
    // package commits to, not by any single one of them:
    //   - SwiftData (`@Model`)                         iOS 17.0 / macOS 14.0
    //   - NLEmbedding.sentenceEmbedding(for:)           iOS 14.0 / macOS 11.0
    //   - CSSearchableItem / CSSearchableIndex          iOS  9.0 / macOS 10.11 (no watchOS/tvOS)
    //   - AppIntent / AppShortcutsProvider              iOS 16.0 / macOS 13.0
    // SwiftData sets the real floor on iOS/macOS. Core Spotlight is unavailable
    // on watchOS/tvOS, and Spotlight indexing is a required part of this
    // package's design, so those platforms are not supported. See README for
    // the full rationale.
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "LocalFirstRAG",
            targets: ["LocalFirstRAG"]
        ),
    ],
    targets: [
        .target(
            name: "LocalFirstRAG",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LocalFirstRAGTests",
            dependencies: ["LocalFirstRAG"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
