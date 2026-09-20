// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MyStockCore", platforms: [.macOS(.v14)],
  products: [.library(name: "MyStockCore", targets: ["MyStockCore"])],
  targets: [
    .target(name: "MyStockCore", path: "MyStock/Models"),
    .testTarget(name: "MyStockCoreTests", dependencies: ["MyStockCore"], path: "MyStockTests"),
  ])
