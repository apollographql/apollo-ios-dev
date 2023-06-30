// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "ApolloCodegen",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_15),
    .tvOS(.v12),
    .watchOS(.v5)
  ],
  products: [
    .library(name: "ApolloCodegenLib", targets: ["ApolloCodegenLib"]),
    .library(name: "CodegenCLI", targets: ["CodegenCLI"]),
    .executable(name: "apollo-ios-cli", targets: ["apollo-ios-cli"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/mattt/InflectorKit",
      .upToNextMajor(from: "1.0.0")),
    .package(
      url: "https://github.com/apple/swift-collections",
      .upToNextMajor(from: "1.0.0")),
    .package(
      url: "https://github.com/apple/swift-argument-parser.git", 
      .upToNextMajor(from: "1.2.0")),
  ],
  targets: [
    .target(
      name: "ApolloCodegenLib",
      dependencies: [
        .product(name: "InflectorKit", package: "InflectorKit"),
        .product(name: "OrderedCollections", package: "swift-collections")
      ],
      exclude: [
        "Frontend/JavaScript",
      ]
    ),
    .executableTarget(
      name: "apollo-ios-cli",
      dependencies: [
        "CodegenCLI",
      ],
      exclude: [
        "README.md",
      ]
    ),
    .target(
      name: "CodegenCLI",
      dependencies: [
        "ApolloCodegenLib",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
  ]
)
