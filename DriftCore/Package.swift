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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
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
                "llama",
            ],
            path: "Sources/DriftCore",
            resources: [
                .process("Resources"),
            ]
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
