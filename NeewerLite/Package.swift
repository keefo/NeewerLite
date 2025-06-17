// swift-tools-version: 5.10
// Package.swift
// Github CodeQL action need this
import PackageDescription

let package = Package(
    name: "NeewerLite",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NeewerLite", targets: ["NeewerLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "1.27.3"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "NeewerLite",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "NeewerLite"
        )
    ]
)
