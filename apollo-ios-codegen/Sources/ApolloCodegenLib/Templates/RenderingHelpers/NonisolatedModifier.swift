import TemplateString

extension ApolloCodegen.ConfigurationContext {
  /// Returns `"nonisolated "` when `markTypesNonisolated` is enabled, empty string otherwise.
  ///
  /// Used by templates to prefix generated type declarations (structs, enums, protocols, classes)
  /// so they opt out of the consuming module's default actor isolation. This ensures generated
  /// GraphQL models remain `Sendable`-compatible when the user enables Swift 6.2's
  /// `defaultIsolation = MainActor` (SE-0466).
  var nonisolatedModifier: TemplateString {
    config.options.markTypesNonisolated ? "nonisolated " : ""
  }
}
