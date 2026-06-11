// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "a2a-swift-server",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "A2AServer", targets: ["A2AServer"]),
    ],
    dependencies: [
        // TODO: switch to `from: "1.0.23"` once the v1.0 wire-format and
        // Linux (FoundationNetworking) fixes are tagged in a2a-swift-client.
        .package(url: "https://github.com/tolgaki/a2a-swift-client.git", branch: "claude/github-discussion-1931-fixes-46o8tz"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "A2AServer",
            dependencies: [
                .product(name: "A2AClient", package: "a2a-swift-client"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/A2AServer"
        ),
        .testTarget(
            name: "A2AInteropTests",
            dependencies: [
                "A2AServer",
                .product(name: "A2AClient", package: "a2a-swift-client"),
            ],
            path: "Tests/A2AInteropTests"
        ),

        // MARK: - Example executables

        .executableTarget(
            name: "EchoAgent",
            dependencies: ["A2AServer"],
            path: "Examples/EchoAgent"
        ),
        .executableTarget(
            name: "CustomHandler",
            dependencies: ["A2AServer"],
            path: "Examples/CustomHandler"
        ),
        .executableTarget(
            name: "StreamingAgent",
            dependencies: ["A2AServer"],
            path: "Examples/StreamingAgent"
        ),
        .executableTarget(
            name: "PushNotificationsAgent",
            dependencies: [
                "A2AServer",
                .product(name: "A2AClient", package: "a2a-swift-client"),
            ],
            path: "Examples/PushNotificationsAgent"
        ),
        .executableTarget(
            name: "MultiAgent",
            dependencies: [
                "A2AServer",
                .product(name: "A2AClient", package: "a2a-swift-client"),
            ],
            path: "Examples/MultiAgent"
        ),
    ]
)
