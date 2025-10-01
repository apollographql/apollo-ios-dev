// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "SubscriptionAPI",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SubscriptionAPI", targets: ["SubscriptionAPI"]),
  ],
  dependencies: [
    .package(name: "apollo-ios", path: "../../../apollo-ios"),
  ],
  targets: [
    .target(
      name: "SubscriptionAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
