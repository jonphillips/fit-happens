// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "FitHappensInboxKit",
  platforms: [.iOS(.v27), .macOS(.v27)],
  products: [
    .library(name: "FitHappensInboxKit", targets: ["FitHappensInboxKit"]),
  ],
  dependencies: [
    .package(path: "../../jon-platform/packages/ChatAccessKit"),
    .package(path: "../../jon-platform/packages/LLMHandoffKit"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
  ],
  targets: [
    .target(name: "FitHappensInboxKit", dependencies: [
      .product(name: "ChatAccessKit", package: "ChatAccessKit"),
      .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
      .product(name: "Dependencies", package: "swift-dependencies"),
      .product(name: "Sharing", package: "swift-sharing"),
    ]),
    .testTarget(name: "FitHappensInboxKitTests", dependencies: [
      "FitHappensInboxKit",
      .product(name: "ChatAccessKit", package: "ChatAccessKit"),
      .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
      .product(name: "Dependencies", package: "swift-dependencies"),
    ]),
  ],
  swiftLanguageModes: [.v6]
)
