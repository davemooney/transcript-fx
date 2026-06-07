// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscriptFX",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TranscriptFX", targets: ["TranscriptFX"]),
    ],
    targets: [
        .target(name: "TranscriptFX"),
        .testTarget(name: "TranscriptFXTests", dependencies: ["TranscriptFX"]),
    ]
)
