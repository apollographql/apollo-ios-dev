import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Input Object](https://spec.graphql.org/draft/#sec-Input-Objects)
/// into Swift code.
struct InputObjectTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Input Object](https://spec.graphql.org/draft/#sec-Input-Objects).
  let graphqlInputObject: GraphQLInputObjectType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .inputObject)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let (validFields, deprecatedFields) = graphqlInputObject.fields.filterFields()
    let memberAccessControl = accessControlRenderer(for: .member)

    return TemplateString(
    """
    \(documentation: graphqlInputObject.documentation, config: config)
    \(graphqlInputObject.name.typeNameDocumentation)
    \(accessControlRenderer(for: .parent).render())\
    struct \(graphqlInputObject.render(as: .typename())): InputObject {
      \(memberAccessControl.render(withSPIs: [.Unsafe]))private(set) var __data: InputDict
    
      \(memberAccessControl.render(withSPIs: [.Unsafe]))init(_ data: InputDict) {
        __data = data
      }

      \(if: !deprecatedFields.isEmpty && !validFields.isEmpty && shouldIncludeDeprecatedWarnings, """
      \(memberAccessControl.render())init(
        \(InitializerParametersTemplate(validFields))
      ) {
        __data = InputDict([
          \(InputDictInitializerTemplate(validFields))
        ])
      }

      """
      )
      \(if: !deprecatedFields.isEmpty && shouldIncludeDeprecatedWarnings, """
      @available(*, deprecated, message: "\(deprecatedMessage(for: deprecatedFields))")
      """)
      \(memberAccessControl.render())init(
        \(InitializerParametersTemplate(graphqlInputObject.fields))
      ) {
        __data = InputDict([
          \(InputDictInitializerTemplate(graphqlInputObject.fields))
        ])
      }

      \(graphqlInputObject.fields.map({ "\(FieldPropertyTemplate($1))" }), separator: "\n\n")
    }

    """
    )
  }

  private var shouldIncludeDeprecatedWarnings: Bool {
    config.options.warningsOnDeprecatedUsage == .include
  }

  private func deprecatedMessage(for fields: GraphQLInputFieldDictionary) -> String {
    guard !fields.isEmpty else { return "" }

    let names: String = fields.values.map({ $0.render(config: config) }).joined(separator: ", ")

    if fields.count > 1 {
      return "Arguments '\(names)' are deprecated."
    } else {
      return "Argument '\(names)' is deprecated."
    }
  }

  private func InitializerParametersTemplate(
    _ fields: GraphQLInputFieldDictionary
  ) -> TemplateString {
    TemplateString("""
    \(fields.map({
      "\($1.render(config: config)): \($1.renderInputValueType(includeDefault: true, config: config.config))"
    }), separator: ",\n")
    """)
  }

  private func InputDictInitializerTemplate(
    _ fields: GraphQLInputFieldDictionary
  ) -> TemplateString {
    TemplateString("""
    \(fields.map({
      TemplateString("""
      "\($1.name.schemaName)": \($1.render(config: config))\(
          if: !$1.type.isNullable && $1.hasDefaultValue, " ?? GraphQLNullable.none"
        )
      """)
    }), separator: ",\n")
    """)
  }

  private func FieldPropertyTemplate(_ field: GraphQLInputField) -> TemplateString {
    """
    \(documentation: field.documentation, config: config)
    \(deprecationReason: field.deprecationReason, config: config)
    \(field.name.typeNameDocumentation)
    \(accessControlRenderer(for: .member).render())\
    var \(field.render(config: config)): \(field.renderInputValueType(config: config.config)) {
      get { __data["\(field.name.schemaName)"] }
      set { __data["\(field.name.schemaName)"] = newValue }
    }
    """
  }
}

extension GraphQLInputFieldDictionary {
  
  func filterFields() -> (valid: GraphQLInputFieldDictionary, deprecated: GraphQLInputFieldDictionary) {
    var valid: GraphQLInputFieldDictionary = [:]
    var deprecated: GraphQLInputFieldDictionary = [:]

    for (key, value) in self {
      if let _ = value.deprecationReason {
        deprecated[key] = value
      } else {
        valid[key] = value
      }
    }

    return (valid: valid, deprecated: deprecated)
  }
  
}
