// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ApolloController",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ApolloController",
            path: "Sources/ApolloController",
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
