// swift-tools-version:5.9
// Endfield Patcher — built with SwiftPM + scripts/build-app.sh (no Xcode required).
import PackageDescription

let package = Package(
    name: "EndfieldPatcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EndfieldPatcher",
            path: "Sources/EndfieldPatcher"
        )
    ]
)
