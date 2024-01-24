import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

struct MockInterfacesTemplate: TemplateRenderer {

  let graphQLInterfaces: OrderedSet<GraphQLInterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(graphQLInterfaces.map {
        "typealias \($0.formattedName) = Interface"
      }, separator: "\n")
    }

    """)
  }
}
