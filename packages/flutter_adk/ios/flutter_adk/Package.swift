// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_adk",
  platforms: [
    .iOS(.v13),
  ],
  products: [
    .library(
      name: "flutter_adk",
      targets: ["flutter_adk"]
    ),
  ],
  targets: [
    .target(
      name: "flutter_adk",
      path: "Sources/flutter_adk"
    ),
  ]
)
