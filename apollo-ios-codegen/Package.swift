// swift-tools-version:5.9
//
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Swift 5.9 is available from Xcode 15.0.

import PackageDescription

let package = Package(
  name: "ApolloCodegen",
  platforms: [
    .macOS(.v12)
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
      .upToNextMajor(from: "1.1.0")),
    .package(
      url: "https://github.com/apple/swift-argument-parser.git", 
      .upToNextMajor(from: "1.3.0")),
  ],
  targets: [
    .target(
      name: "ApolloCodegenLib",
      dependencies: [
        "GraphQLCompiler",
        "IR",
        "TemplateString",
        .product(name: "InflectorKit", package: "InflectorKit"),
        .product(name: "OrderedCollections", package: "swift-collections")
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .target(
      name: "GraphQLCompiler",
      dependencies: [
        "TemplateString",
        .product(name: "OrderedCollections", package: "swift-collections")
      ],
      exclude: [
        "JavaScript"
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .target(
      name: "IR",
      dependencies: [
        "GraphQLCompiler",
        "TemplateString",
        "Utilities",
        .product(name: "OrderedCollections", package: "swift-collections")        
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .target(
      name: "TemplateString",
      dependencies: [],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .target(
      name: "Utilities",
      dependencies: [],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .executableTarget(
      name: "apollo-ios-cli",
      dependencies: [
        "CodegenCLI",
      ],
      exclude: [
        "README.md",
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .target(
      name: "CodegenCLI",
      dependencies: [
        "ApolloCodegenLib",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
  ]
)
