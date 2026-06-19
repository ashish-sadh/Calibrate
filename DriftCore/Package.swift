// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriftCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DriftCore", targets: ["DriftCore"]),
        .executable(name: "DriftChatSim", targets: ["DriftChatSim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "../Frameworks/llama.xcframework"
        ),
        .target(
            name: "DriftCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                "llama",
            ],
            path: "Sources/DriftCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "DriftChatSim",
            dependencies: ["DriftCore"],
            path: "Sources/DriftChatSim"
        ),
        .testTarget(
            name: "DriftCoreTests",
            dependencies: ["DriftCore"],
            path: "Tests/DriftCoreTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
