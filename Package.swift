// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "iphone-mcp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "IPhoneMCPCore", dependencies: [.product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "iphone-mcp", dependencies: ["IPhoneMCPCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "IPhoneMCPCoreTests", dependencies: ["IPhoneMCPCore"]),
    ],
    swiftLanguageModes: [.v5]
)
