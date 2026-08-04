// swift-tools-version: 5.9
import PackageDescription

// Skip stages this manifest into its skipstone tree without binary artifacts —
// SwiftPM rejects a binaryTarget with no binary even when a platform condition
// excludes it from the build, so the llama xcframework must be omitted there
// entirely. LlamaCppBackend is #if canImport(llama)-guarded and the AI ladder
// falls through to the cloud/Gemini tiers when the module is absent.
let includeLlama = !#filePath.contains("/skipstone/")

var driftCoreDependencies: [Target.Dependency] = [
    .product(name: "GRDB", package: "GRDB.swift"),
    // Apple-only: no CZlib module for Android; backup packaging is
    // guarded off there (#if canImport(ZIPFoundation)).
    .product(name: "ZIPFoundation", package: "ZIPFoundation",
             condition: .when(platforms: [.iOS, .macOS])),
    // CryptoKit replacement off-Apple; on Apple platforms the
    // Crypto module re-exports CryptoKit so there is one code path.
    .product(name: "Crypto", package: "swift-crypto",
             condition: .when(platforms: [.android, .linux])),
]
if includeLlama {
    // Prebuilt xcframework — Apple-only until the Android libllama lands.
    driftCoreDependencies.append(.target(name: "llama", condition: .when(platforms: [.iOS, .macOS])))
}

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
        .target(
            name: "DriftCore",
            dependencies: driftCoreDependencies,
            path: "Sources/DriftCore",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                // liblog — PlainLogger calls __android_log_write directly so
                // Log.* reaches logcat (Utilities/Log.swift).
                .linkedLibrary("log", .when(platforms: [.android])),
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

if includeLlama {
    package.targets.append(.binaryTarget(name: "llama", path: "../Frameworks/llama.xcframework"))
}
