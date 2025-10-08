import Foundation
import GraphQLCompiler
import TemplateString

struct OneOfInputObjectTemplate: TemplateRenderer {
    
  let graphqlInputObject: GraphQLInputObjectType
  
  let config: ApolloCodegen.ConfigurationContext
  
  let target: TemplateTarget = .schemaFile(type: .inputObject)
  
  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let memberAccessControl = accessControlRenderer(for: .member)
    
    return TemplateString(
    """
    \(documentation: graphqlInputObject.documentation, config: config)
    \(graphqlInputObject.name.typeNameDocumentation)
    \(accessControlRenderer(for: .parent).render())\
    enum \(graphqlInputObject.render(as: .typename())): OneOfInputObject {
      \(graphqlInputObject.fields.map({ "\(FieldCaseTemplate($1))" }), separator: "\n")
    
      \(memberAccessControl.render(withSPIs: [.Unsafe]))var __data: InputDict {
        switch self {
        \(graphqlInputObject.fields.map({ "\(FieldCaseDataTemplate($1))" }), separator: "\n")
        }
      }
    }
    """
    )
  }
  
  private func FieldCaseTemplate(_ field: GraphQLInputField) -> TemplateString {
    """
    \(documentation: field.documentation, config: config)
    \(deprecationReason: field.deprecationReason, config: config)
    \(field.name.typeNameDocumentation)
    case \(field.render(config: config))(\(field.type.renderAsInputValue(inNullable: false, config: config.config)))
    """
  }
  
  private func FieldCaseDataTemplate(_ field: GraphQLInputField) -> TemplateString {
    """
    case .\(field.render(config: config))(let value):
      return InputDict(["\(field.name.schemaName)": value])
    """
  }
  
}
