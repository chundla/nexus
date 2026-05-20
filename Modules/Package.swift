// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [
        .macOS(.v10_15)
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
            name: "NexusService",
            type: .static,
            targets: ["NexusService"]
        )
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
            name: "NexusService",
            dependencies: ["NexusDomain", "NexusIPC"]
        )
    ]
)
