// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ToonRepeater",
    platforms: [.macOS(.v11)],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ToonRepeater",
            dependencies: [.product(name: "TelemetryDeck", package: "SwiftSDK")],
            path: "Sources/ToonRepeater",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
        .testTarget(
            name: "ToonRepeaterTests",
            dependencies: ["ToonRepeater"],
            path: "Tests/ToonRepeaterTests"
        ),
    ]
)
