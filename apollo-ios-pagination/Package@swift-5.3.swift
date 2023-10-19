// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "ApolloPagination",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6)
  ],
  products: [
    .library(name: "ApolloPagination", targets: ["ApolloPagination"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apollographql/apollo-ios.git",
      branch: "ci-test")
    )
  ],
  targets: [
    .target(
      name: "ApolloPagination",
      dependencies: [
        .product(name: "Apollo", package: "apollo-ios"),
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ]
    ),
  ]
)
