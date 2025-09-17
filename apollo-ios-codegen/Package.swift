// swift-tools-version:6.1

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
      swiftSettings: [.swiftLanguageMode(.v6)]
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
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "IR",
      dependencies: [
        "GraphQLCompiler",
        "TemplateString",
        "Utilities",
        .product(name: "OrderedCollections", package: "swift-collections")        
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "TemplateString",
      dependencies: [],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Utilities",
      dependencies: [],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "apollo-ios-cli",
      dependencies: [
        "CodegenCLI",
      ],
      exclude: [
        "README.md",
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "CodegenCLI",
      dependencies: [
        "ApolloCodegenLib",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
