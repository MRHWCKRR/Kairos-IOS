// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xcode_spm_setup",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "8.27.7")),
        // XcodeProj 8.27.7 has a macOS 10.13 floor. Later AEXML patches raise
        // that floor without a matching XcodeProj manifest update.
        .package(url: "https://github.com/tadija/AEXML.git", exact: "4.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "xcode_spm_setup",
            dependencies: ["XcodeProj"],
            path: "Sources"
        )
    ]
)
