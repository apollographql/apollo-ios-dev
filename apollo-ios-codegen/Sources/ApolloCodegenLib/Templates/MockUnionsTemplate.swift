import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

struct MockUnionsTemplate: TemplateRenderer {

  let graphqlUnions: OrderedSet<GraphQLUnionType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(graphqlUnions.map {
      "typealias \($0.render(as: .typename)) = Union"
      }, separator: "\n")
    }
    
    """)
  }
}
