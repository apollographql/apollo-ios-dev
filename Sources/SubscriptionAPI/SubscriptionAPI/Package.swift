// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "SubscriptionAPI",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5),
  ],
  products: [
    .library(name: "SubscriptionAPI", targets: ["SubscriptionAPI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.18.0"),
  ],
  targets: [
    .target(
      name: "SubscriptionAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
  ]
)
