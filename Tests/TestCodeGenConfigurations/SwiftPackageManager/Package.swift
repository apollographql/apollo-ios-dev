// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "TestApp",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "TestApp", targets: ["TestApp"]),
  ],
  dependencies: [
    .package(name: "apollo-ios", path: "../../../apollo-ios"),
    .package(name: "AnimalKingdomAPI", path: "./AnimalKingdomAPI")
  ],
  targets: [
    .target(
      name: "TestApp",
      dependencies: [
        .product(name: "Apollo", package: "apollo-ios"),
        .product(name: "AnimalKingdomAPI", package: "AnimalKingdomAPI")
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    ),
    .testTarget(
      name: "SwiftPackageTests",
      dependencies: [
        .product(name: "Apollo", package: "apollo-ios"),
        .product(name: "ApolloTestSupport", package: "apollo-ios"),
        .product(name: "AnimalKingdomAPITestMocks", package: "AnimalKingdomAPI")
      ],
      swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
    )
  ]
)
