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
        // 7.11.1+ bundles SQLite for non-Darwin platforms (Android/Linux).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.10.0"),
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
                // Apple-only: no CZlib module for Android; backup packaging is
                // guarded off there (#if canImport(ZIPFoundation)).
                .product(name: "ZIPFoundation", package: "ZIPFoundation",
                         condition: .when(platforms: [.iOS, .macOS])),
                // CryptoKit replacement off-Apple; on Apple platforms the
                // Crypto module re-exports CryptoKit so there is one code path.
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.android, .linux])),
                // Prebuilt xcframework — Apple-only until the Android libllama
                // lands; LlamaCppBackend is guarded by #if canImport(llama).
                .target(name: "llama", condition: .when(platforms: [.iOS, .macOS])),
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
