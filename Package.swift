// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftAI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "SwiftAI",
            targets: ["SwiftAI"]
        )
    ],
    targets: [
        .target(
            name: "SwiftAI",
            path: "Sources/SwiftAI"
        ),
        .testTarget(
            name: "SwiftAITests",
            dependencies: ["SwiftAI"],
            path: "Tests/SwiftAITests"
        )
    ]
)
