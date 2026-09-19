// swift-tools-version:5.9
// FineTuning Patcher — built with SwiftPM + scripts/build-app.sh (no Xcode required).
import PackageDescription

let package = Package(
    name: "FineTuningPatcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FineTuningPatcher",
            path: "Sources/FineTuningPatcher"
        )
    ]
)
