// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "SwapiSchema",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5),
  ],
  products: [
    .library(name: "SwapiSchema", targets: ["SwapiSchema"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.23.0"),
  ],
  targets: [
    .target(
      name: "SwapiSchema",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
  ]
)
