// swift-tools-version:5.7

import PackageDescription

let package = Package(
  name: "AnimalKingdomAPI",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5),
  ],
  products: [
    .library(name: "AnimalKingdomAPI", targets: ["AnimalKingdomAPI"]),
    .library(name: "AnimalKingdomAPITestMocks", targets: ["AnimalKingdomAPITestMocks"]),
  ],
  dependencies: [
    .package(name: "apollo-ios", path: "../../../../apollo-ios"),
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
      path: "./AnimalKingdomAPITestMocks"
    ),
  ]
)
