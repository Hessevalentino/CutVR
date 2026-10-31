// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CutVR",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "CutVR", path: "Sources/CutVR")
    ],
    swiftLanguageModes: [.v5]
)
