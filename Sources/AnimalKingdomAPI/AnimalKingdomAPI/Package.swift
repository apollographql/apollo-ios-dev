// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "AnimalKingdomAPI",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "AnimalKingdomAPI", targets: ["AnimalKingdomAPI"]),
    .library(name: "AnimalKingdomAPITestMocks", targets: ["AnimalKingdomAPITestMocks"]),
  ],
  dependencies: [
    .package(name: "apollo-ios", path: "../../../apollo-ios"),
  ],
  targets: [
    .target(
      name: "AnimalKingdomAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
    .target(
      name: "AnimalKingdomAPITestMocks",
      dependencies: [
        .product(name: "ApolloTestSupport", package: "apollo-ios"),
        .target(name: "AnimalKingdomAPI"),
      ],
      path: "./TestMocks"
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
