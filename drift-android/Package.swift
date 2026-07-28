// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "drift-android",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DriftAndroid", type: .dynamic, targets: ["DriftAndroid"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", exact: "1.9.4"),
        // Last release-proven Skip UI pair (build 61's shipped config), pinned
        // exact because Package.resolved is gitignored — the committed manifest is
        // the only durable lock (#1134). Do NOT float these:
        //   • skip-ui 1.59.0 → release Kotlin codegen crash (BridgedCustomShape.scaledToFill)
        //   • skip-ui 1.59.1 → requires skip-fuse-ui ≥1.18.1 (adds a `bridgedAxis`
        //     arg to the TextField/SecureField bridge); won't compile against 1.17.3.
        // 1.58.0 is the last skip-ui before both regressions and pairs with 1.17.3.
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", exact: "1.17.3"),
        .package(url: "https://source.skip.tools/skip-ui.git", exact: "1.58.0"),
        .package(path: "../DriftCore"),
    ],
    targets: [
        .target(name: "DriftAndroid", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "DriftCore", package: "DriftCore"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
