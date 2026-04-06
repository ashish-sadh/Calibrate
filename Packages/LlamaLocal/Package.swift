// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaLocal",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ashish-sadh/Drift/releases/download/models-v1/llama-b7310-local.xcframework.zip",
            checksum: "201562c3615b6041f80eccd7e4173b2e3e3adfcfc840440d4099df3ef30c50d8"
        ),
    ]
)
