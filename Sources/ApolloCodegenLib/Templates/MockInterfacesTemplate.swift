import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

struct MockInterfacesTemplate: TemplateRenderer {

  let graphQLInterfaces: OrderedSet<GraphQLInterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  var template: TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(graphQLInterfaces.map {
        "typealias \($0.formattedName) = Interface"
      }, separator: "\n")
    }

    """)
  }
}
