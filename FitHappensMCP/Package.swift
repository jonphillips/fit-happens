// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "FitHappensMCP",
  platforms: [.macOS(.v27)],
  products: [.executable(name: "fithappens-mcp", targets: ["FitHappensMCP"])],
  dependencies: [
    .package(path: "../FitHappensCore"),
    .package(path: "../../jon-platform/packages/ChatAccessKit"),
    .package(path: "../../jon-platform/packages/MCPServerKit"),
    .package(path: "../../jon-platform/packages/LLMHandoffKit"),
  ],
  targets: [
    .target(name: "FitHappensMCPServer", dependencies: [
      .product(name: "FitHappensCore", package: "FitHappensCore"),
      .product(name: "ChatAccessKit", package: "ChatAccessKit"),
      .product(name: "MCPServerKit", package: "MCPServerKit"),
      .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
    ]),
    .executableTarget(name: "FitHappensMCP", dependencies: [
      "FitHappensMCPServer", .product(name: "ChatAccessKit", package: "ChatAccessKit"),
    ]),
    .testTarget(name: "FitHappensMCPTests", dependencies: [
      "FitHappensMCPServer", .product(name: "ChatAccessKit", package: "ChatAccessKit"),
      .product(name: "MCPServerKit", package: "MCPServerKit"),
      .product(name: "FitHappensCore", package: "FitHappensCore"),
    ]),
  ],
  swiftLanguageModes: [.v6]
)
