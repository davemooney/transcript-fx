// swift-tools-version: 5.9
//
// Root manifest so the repository is consumable as a remote SPM dependency
// (Xcode / SwiftPM resolve Package.swift at the repo root only). The Swift
// sources live under swift/ alongside the web prototype; this manifest simply
// re-points the targets there. Keep in sync with swift/Package.swift, which
// remains the manifest for local development inside swift/.
import PackageDescription

let package = Package(
    name: "TranscriptFX",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TranscriptFX", targets: ["TranscriptFX"]),
    ],
    targets: [
        .target(name: "TranscriptFX", path: "swift/Sources/TranscriptFX"),
        .testTarget(
            name: "TranscriptFXTests",
            dependencies: ["TranscriptFX"],
            path: "swift/Tests/TranscriptFXTests"
        ),
    ]
)
