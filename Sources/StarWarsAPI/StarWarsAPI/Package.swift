// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "StarWarsAPI",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "StarWarsAPI", targets: ["StarWarsAPI"]),
  ],
  dependencies: [
    .package(name: "apollo-ios", path: "../../../apollo-ios"),
  ],
  targets: [
    .target(
      name: "StarWarsAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
