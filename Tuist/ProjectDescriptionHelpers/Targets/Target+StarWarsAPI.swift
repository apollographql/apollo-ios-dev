import ProjectDescription

extension Target {

  public static func starWarsFramework() -> Target {
    let target: ApolloTarget = .starWarsAPI

    return .target(
      name: target.name,
      destinations: target.destinations,
      product: .framework,
      bundleId: "com.apollographql.\(target.name.lowercased())",
      deploymentTargets: target.deploymentTargets,
      infoPlist: .file(path: "Sources/\(target.name)/Info.plist"),
      sources: [
        "Sources/\(target.name)/\(target.name)/Sources/**"
      ],
      resources: .resources([
        .folderReference(path: "Sources/\(target.name)/starwars-graphql")
      ]),
      dependencies: [
        .package(product: "ApolloAPI")
      ],
      settings: .forTarget(target)
    )
  }

}
