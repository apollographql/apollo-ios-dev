// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftScripts",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(name: "Apollo", path: "../apollo-ios"),
    .package(name: "ApolloCodegen", path: "../apollo-ios-codegen"),
    .package(name: "ApolloPagination", path: "../apollo-ios-pagination"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.2.0")),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  ],
  targets: [
    .target(name: "TargetConfig",
            dependencies: [
              .product(name: "ApolloCodegenLib", package: "ApolloCodegen"),
            ]),
    .target(name: "SwiftScriptHelpers"),
    .executableTarget(name: "Codegen",
            dependencies: [
              .product(name: "ApolloCodegenLib", package: "ApolloCodegen"),
              .product(name: "ArgumentParser", package: "swift-argument-parser"),
              .target(name: "TargetConfig"),
              .target(name: "SwiftScriptHelpers")
            ]),
    .executableTarget(name: "SchemaDownload",
            dependencies: [
              .product(name: "ApolloCodegenLib", package: "ApolloCodegen"),
              .target(name: "TargetConfig"),
              .target(name: "SwiftScriptHelpers")
            ]),
    .executableTarget(name: "DocumentationGenerator",
            dependencies: [
              .product(name: "ApolloCodegenLib", package: "ApolloCodegen"),
              .product(name: "Apollo", package: "Apollo"),
              .product(name: "ApolloAPI", package: "Apollo"),
              .product(name: "ApolloSQLite", package: "Apollo"),
              .product(name: "ApolloWebSocket", package: "Apollo"),
              .product(name: "ApolloPagination", package: "ApolloPagination"),
              .target(name: "SwiftScriptHelpers")
            ]
           ),
    .testTarget(name: "CodegenTests",
                dependencies: [
                  "Codegen"
                ]),
  ]
)
