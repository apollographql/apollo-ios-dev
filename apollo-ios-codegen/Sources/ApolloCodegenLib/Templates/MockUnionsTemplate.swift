import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

struct MockUnionsTemplate: TemplateRenderer {

  let graphQLUnions: OrderedSet<GraphQLUnionType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(graphQLUnions.map {
        "typealias \($0.formattedName) = Union"
      }, separator: "\n")
    }
    
    """)
  }
}
