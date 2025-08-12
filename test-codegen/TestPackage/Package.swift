// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "TestPackage",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5),
  ],
  products: [
    .library(name: "TestPackage", targets: ["TestPackage"]),
  ],
  dependencies: [
    .package(path: "../SwapiSchema")
  ],
  targets: [
    .target(
      name: "TestPackage",
      dependencies: [
        .product(name: "SwapiSchema", package: "SwapiSchema"),
      ],
      path: "./Sources"
    ),
  ]
)
