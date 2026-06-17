// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "NexusDomain",
            type: .static,
            targets: ["NexusDomain"]
        ),
        .library(
            name: "NexusIPC",
            type: .static,
            targets: ["NexusIPC"]
        ),
        .library(
            name: "NexusSessionPresentation",
            type: .static,
            targets: ["NexusSessionPresentation"]
        ),
        .library(
            name: "NexusService",
            type: .static,
            targets: ["NexusService"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "NexusDomain"
        ),
        .target(
            name: "NexusIPC",
            dependencies: ["NexusDomain"]
        ),
        .target(
            name: "NexusSessionPresentation",
            dependencies: [
                "NexusDomain",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "LaTeXSwiftUI", package: "LaTeXSwiftUI"),
            ]
        ),
        .target(
            name: "NexusService",
            dependencies: ["NexusDomain", "NexusIPC"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "NexusSessionPresentationTests",
            dependencies: ["NexusSessionPresentation"]
        ),
        .testTarget(
            name: "NexusServiceTests",
            dependencies: ["NexusService", "NexusIPC", "NexusSessionPresentation"]
        ),
    ]
)
