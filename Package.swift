// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Apollo",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5)
  ],
  products: [
    .library(name: "ApolloCodegenLib", targets: ["ApolloCodegenLib"]),
    .executable(name: "apollo-ios-cli", targets: ["apollo-ios-cli"]),
    .plugin(name: "InstallCLI", targets: ["Install CLI"]),
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
        "Info.plist",
        "Frontend/JavaScript",
      ]),
    .executableTarget(
      name: "apollo-ios-cli",
      dependencies: [
        "CodegenCLI",
      ],
      exclude: [
        "README.md",
      ]),
    .target(
      name: "CodegenCLI",
      dependencies: [
        "ApolloCodegenLib",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      exclude: [
        "Info.plist",
      ]),
    .plugin(
      name: "Install CLI",
      capability: .command(
        intent: .custom(
          verb: "apollo-cli-install",
          description: "Installs the Apollo iOS Command line interface."),
        permissions: [
          .writeToPackageDirectory(reason: "Creates a symbolic link to the CLI executable in your project directory.")
        ]),
      dependencies: [
        "apollo-ios-cli"
      ],
      path: "Plugins/InstallCLI"),
  ]
)
