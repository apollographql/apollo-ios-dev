import Foundation
@testable import ApolloCodegenLib
import GraphQLCompiler

extension ValidationOptions {

  public static func mock(schemaNamespace: String = "TestSchema") -> Self {
    let context = ApolloCodegen.ConfigurationContext(
      config: ApolloCodegenConfiguration.mock(schemaNamespace: schemaNamespace))

    return ValidationOptions(config: context)
  }

}
