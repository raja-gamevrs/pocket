// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "pocket",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "pocket",
            targets: ["pocket"]),
    ],
    dependencies: [
        .package(url: "https://github.com/eastriverlee/LLM.swift/", branch: "main"),
    ],
    targets: [
        .target(
            name: "pocket",
            dependencies: [
                .product(name: "LLM", package: "LLM.swift")
            ]),
    ]
) 