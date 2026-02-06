// swift-tools-version: 6.0
// NOTE: This Package.swift is provided for editor support (SourceKit-LSP).
// Actual builds use the Makefile with swiftc directly,
// because CLT's libPackageDescription.dylib has ABI mismatch with Swift 6.1.
import PackageDescription

let package = Package(
    name: "MicBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MicBar",
            path: "Sources/MicBar"
        )
    ]
)
