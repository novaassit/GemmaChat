// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GemmaChat",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "GemmaChat", targets: ["GemmaChat"])
    ],
    dependencies: [
        // llama.cpp Swift package via mattt/llama.swift — provides on-device LLM inference
        .package(url: "https://github.com/mattt/llama.swift", .upToNextMajor(from: "2.8760.0"))
    ],
    targets: [
        .target(
            name: "GemmaChat",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            path: "GemmaChat"
        )
    ]
)
