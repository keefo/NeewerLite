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
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "1.27.3"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "NeewerLite",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "NeewerLite"
        )
    ]
)
