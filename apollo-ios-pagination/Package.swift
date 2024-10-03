// swift-tools-version:5.9
//
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Swift 5.9 is available from Xcode 15.0.

import PackageDescription

let package = Package(
  name: "ApolloPagination",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(name: "ApolloPagination", targets: ["ApolloPagination"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apollographql/apollo-ios.git",
      .upToNextMajor(from: "1.2.0")
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
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
  ]
)
