// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ua-commander",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ua-commander",
            path: "Sources/ua-commander",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("Carbon"),
                .linkedFramework("AudioToolbox"),
            ]
        )
    ]
)
