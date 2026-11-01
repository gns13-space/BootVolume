// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BootVolume",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BootVolume",
            path: "Sources/BootVolume",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
