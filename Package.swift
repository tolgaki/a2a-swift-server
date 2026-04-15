// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "a2a-swift-server",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "A2AServer", targets: ["A2AServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tolgaki/a2a-swift.git", from: "1.2.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "A2AServer",
            dependencies: [
                .product(name: "A2ACore", package: "a2a-swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/A2AServer"
        ),
        .testTarget(
            name: "A2AInteropTests",
            dependencies: [
                "A2AServer",
                .product(name: "A2ACore", package: "a2a-swift"),
                .product(name: "A2AClient", package: "a2a-swift"),
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
                .product(name: "A2AClient", package: "a2a-swift"),
            ],
            path: "Examples/PushNotificationsAgent"
        ),
        .executableTarget(
            name: "MultiAgent",
            dependencies: [
                "A2AServer",
                .product(name: "A2AClient", package: "a2a-swift"),
            ],
            path: "Examples/MultiAgent"
        ),
    ]
)
