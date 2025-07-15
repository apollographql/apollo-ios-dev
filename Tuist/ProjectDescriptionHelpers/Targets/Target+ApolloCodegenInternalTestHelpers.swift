import ProjectDescription

extension Target {

  public static func apolloCodegenInternalTestHelpersFramework() -> Target {
    let target: ApolloTarget = .apolloCodegenInternalTestHelpers

    return .target(
      name: target.name,
      destinations: target.destinations,
      product: .framework,
      bundleId: "com.apollographql.\(target.name.lowercased())",
      deploymentTargets: target.deploymentTargets,
      infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
      sources: [
        "Tests/\(target.name)/**"
      ],
      resources: .resources([
        .folderReference(path: "Sources/\(ApolloTarget.animalKingdomAPI.name)/animalkingdom-graphql"),
        .folderReference(path: "Sources/\(ApolloTarget.starWarsAPI.name)/starwars-graphql"),
      ]),
      dependencies: [
        .target(name: ApolloTarget.apolloCodegenLibWrapper.name),
        .package(product: "OrderedCollections"),
      ],
      settings: .forTarget(target)
    )
  }

}
