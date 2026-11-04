// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KairosCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KairosCore", targets: ["KairosCore"])],
    targets: [
        .target(name: "KairosCore", path: "Kairos/Kairos/Core", resources: [.process("Resources")]),
        .testTarget(name: "KairosCoreTests", dependencies: ["KairosCore"], path: "Tests/KairosCoreTests")
    ]
)
