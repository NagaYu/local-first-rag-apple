// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotesApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "LocalFirstRAG", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "NotesApp",
            dependencies: ["LocalFirstRAG"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
