// Package.swift
import PackageDescription

let package = Package(
    name: "NeewerLite",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "NeewerLite", targets: ["NeewerLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "1.27.3"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "NeewerLite",
            dependencies: ["Swifter", "Sparkle", "swift-atomics"]
        )
    ]
)
