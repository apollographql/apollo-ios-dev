import Foundation
import OrderedCollections
import IR
import TemplateString

struct MockUnionsTemplate: TemplateRenderer {

  let irUnions: OrderedSet<IR.UnionType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(irUnions.map {
      "typealias \($0.render(as: .typename, config: config)) = Union"
      }, separator: "\n")
    }
    
    """)
  }
}
