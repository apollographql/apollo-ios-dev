import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

struct MockInterfacesTemplate: TemplateRenderer {

  let graphqlInterfaces: OrderedSet<GraphQLInterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlRenderer(for: .parent).render())extension MockObject {
      \(graphqlInterfaces.map {
      "typealias \($0.render(as: .typename())) = Interface"
      }, separator: "\n")
    }

    """)
  }
}
