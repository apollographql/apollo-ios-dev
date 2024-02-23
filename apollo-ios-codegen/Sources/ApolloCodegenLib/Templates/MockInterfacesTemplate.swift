import Foundation
import OrderedCollections
import IR
import TemplateString

struct MockInterfacesTemplate: TemplateRenderer {

  let irInterfaces: OrderedSet<IR.InterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .testMockFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .parent))extension MockObject {
      \(irInterfaces.map {
      "typealias \($0.render(as: .typename, config: config)) = Interface"
      }, separator: "\n")
    }

    """)
  }
}
