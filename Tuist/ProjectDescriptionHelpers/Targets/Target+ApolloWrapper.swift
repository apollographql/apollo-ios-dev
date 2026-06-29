import ProjectDescription

extension Target {

  public static func apolloWrapperFramework() -> Target {
    let target: ApolloTarget = .apolloWrapper

    return .target(
      name: target.name,
      destinations: target.destinations,
      product: .framework,
      bundleId: "com.apollographql.\(target.name.lowercased())",
      deploymentTargets: target.deploymentTargets,
      infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
      // This wrapper must be the ONLY target in the workspace that links Apollo package products.
      // SPM library products are statically linked, so every target that links one embeds its own
      // copy of the module — including duplicate copies of each type's runtime metadata. Dynamic
      // casts (e.g. `as? DataDict`) compare nominal type descriptors by pointer, so a value
      // created in one image fails to cast in another. All other targets must depend on this
      // framework (directly or transitively) so exactly one copy of each module exists at runtime.
      dependencies: [
        .package(product: "Apollo"),
        .package(product: "ApolloAPI"),
        .package(product: "ApolloSQLite"),
        .package(product: "ApolloWebSocket"),
        .package(product: "ApolloTestSupport"),
        .package(product: "ApolloPagination"),
      ],
      settings: .forTarget(target)
    )
  }

}
