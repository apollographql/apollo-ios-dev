// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "ApolloCodegen",
  platforms: [
    .macOS(.v10_15)    
  ],
  products: [
    .library(name: "ApolloCodegenLib", targets: ["ApolloCodegenLib"]),
    .library(name: "CodegenCLI", targets: ["CodegenCLI"])
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
        "GraphQLCompiler",
        "IR",
        "TemplateString",
        .product(name: "InflectorKit", package: "InflectorKit"),
        .product(name: "OrderedCollections", package: "swift-collections")
      ]
    ),
    .target(
      name: "GraphQLCompiler",
      dependencies: [
        "TemplateString",
        .product(name: "OrderedCollections", package: "swift-collections")
      ],
      exclude: [
        "JavaScript"
      ]
    ),
    .target(
      name: "IR",
      dependencies: [
        "GraphQLCompiler",
        "TemplateString",
        "Utilities",
        .product(name: "OrderedCollections", package: "swift-collections")        
      ]
    ),
    .target(
      name: "TemplateString",
      dependencies: []
    ),
    .target(
      name: "Utilities",
      dependencies: []
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
