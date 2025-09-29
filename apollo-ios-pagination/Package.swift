// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "ApolloPagination",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "ApolloPagination", targets: ["ApolloPagination"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apollographql/apollo-ios.git",
      exact: "2.0.0-beta-3"
    ),
    .package(
      url: "https://github.com/apple/swift-collections",
      .upToNextMajor(from: "1.0.0")
    ),
  ],
  targets: [
    .target(
      name: "ApolloPagination",
      dependencies: [
        .product(name: "Apollo", package: "apollo-ios"),
        .product(name: "ApolloAPI", package: "apollo-ios"),
        .product(name: "OrderedCollections", package: "swift-collections"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
