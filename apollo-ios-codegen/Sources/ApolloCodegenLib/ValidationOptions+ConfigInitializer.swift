import GraphQLCompiler

extension ValidationOptions {
  init(config: ApolloCodegen.ConfigurationContext) {
    let singularizedSchemaNamespace = config.pluralizer.singularize(config.schemaNamespace)
    let pluralizedSchemaNamespace = config.pluralizer.pluralize(config.schemaNamespace)
    let disallowedEntityListFieldNames: Set<String>
    switch (config.schemaNamespace) {
    case singularizedSchemaNamespace:
      disallowedEntityListFieldNames = [pluralizedSchemaNamespace.firstLowercased]
    case pluralizedSchemaNamespace:
      disallowedEntityListFieldNames = [singularizedSchemaNamespace.firstLowercased]
    default:
      fatalError("Could not derive singular/plural of schema name '\(config.schemaNamespace)'")
    }

    self.init(
      schemaNamespace: config.schemaNamespace,
      disallowedFieldNames: DisallowedFieldNames(
        allFields: SwiftKeywords.DisallowedFieldNames,
        entity: [config.schemaNamespace.firstLowercased],
        entityList: disallowedEntityListFieldNames
      ),
      disallowedInputParameterNames: SwiftKeywords.DisallowedInputParameterNames
        .union([config.schemaNamespace.firstLowercased])
    )
  }
}
