// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FitHappensCore",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [.library(name: "FitHappensCore", targets: ["FitHappensCore"])],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(path: "../../jon-platform/packages/CloudSyncKit"),
    .package(path: "../../jon-platform/packages/LLMHandoffKit"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
  ],
  targets: [
    .target(
      name: "FitHappensCore",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "CloudSyncKit", package: "CloudSyncKit"),
        .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "FitHappensCoreTests",
      dependencies: [
        "FitHappensCore",
        .product(name: "CloudSyncKit", package: "CloudSyncKit"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      resources: [.copy("Fixtures")]
    ),
  ]
)
