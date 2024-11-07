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
    let (validFields, deprecatedFields) = graphqlInputObject.fields.filterFields()
    let memberAccessControl = accessControlModifier(for: .member)
    
    return TemplateString(
    """
    \(documentation: graphqlInputObject.documentation, config: config)
    \(graphqlInputObject.name.typeNameDocumentation)
    \(accessControlModifier(for: .parent))\
    enum \(graphqlInputObject.render(as: .typename)): InputObject {
      \(graphqlInputObject.fields.map({ "\(FieldCaseTemplate($1))" }), separator: "\n")
    
      \(memberAccessControl)var __data: InputDict {
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
    case \(field.render(config: config))(\(field.renderInputValueType(config: config.config)))
    """
  }
  
  private func FieldCaseDataTemplate(_ field: GraphQLInputField) -> TemplateString {
    """
    case .\(field.render(config: config))(let value):
      return InputDict(["\(field.name.schemaName)": value._jsonEncodableValue])
    """
  }
  
}
