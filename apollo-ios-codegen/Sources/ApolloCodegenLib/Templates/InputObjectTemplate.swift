import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Input Object](https://spec.graphql.org/draft/#sec-Input-Objects)
/// into Swift code.
struct InputObjectTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Input Object](https://spec.graphql.org/draft/#sec-Input-Objects).
  let irInputObject: IR.InputObjectType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .inputObject)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let (validFields, deprecatedFields) = filterFields(irInputObject.fields)
    let memberAccessControl = accessControlModifier(for: .member)

    return TemplateString(
    """
    \(documentation: irInputObject.documentation, config: config)
    \(accessControlModifier(for: .parent))\
    struct \(irInputObject.render(as: .typename, config: config)): InputObject {
      \(memberAccessControl)private(set) var __data: InputDict
    
      \(memberAccessControl)init(_ data: InputDict) {
        __data = data
      }

      \(if: !deprecatedFields.isEmpty && !validFields.isEmpty && shouldIncludeDeprecatedWarnings, """
      \(memberAccessControl)init(
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
      \(memberAccessControl)init(
        \(InitializerParametersTemplate(irInputObject.fields))
      ) {
        __data = InputDict([
          \(InputDictInitializerTemplate(irInputObject.fields))
        ])
      }

      \(irInputObject.fields.map({ "\(FieldPropertyTemplate($1))" }), separator: "\n\n")
    }

    """
    )
  }

  private var shouldIncludeDeprecatedWarnings: Bool {
    config.options.warningsOnDeprecatedUsage == .include
  }

  private func filterFields(
    _ fields: IR.InputFieldDictionary
  ) -> (valid: IR.InputFieldDictionary, deprecated: IR.InputFieldDictionary) {
    var valid: IR.InputFieldDictionary = [:]
    var deprecated: IR.InputFieldDictionary = [:]

    for (key, value) in fields {
      if let _ = value.deprecationReason {
        deprecated[key] = value
      } else {
        valid[key] = value
      }
    }

    return (valid: valid, deprecated: deprecated)
  }

  private func deprecatedMessage(for fields: IR.InputFieldDictionary) -> String {
    guard !fields.isEmpty else { return "" }

    let names: String = fields.values.map({ $0.name }).joined(separator: ", ")

    if fields.count > 1 {
      return "Arguments '\(names)' are deprecated."
    } else {
      return "Argument '\(names)' is deprecated."
    }
  }

  private func InitializerParametersTemplate(
    _ fields: IR.InputFieldDictionary
  ) -> TemplateString {
    TemplateString("""
    \(fields.map({
      "\($1.customName ?? $1.name.renderAsInputObjectName(config: config.config)): \($1.renderInputValueType(includeDefault: true, config: config.config))"
    }), separator: ",\n")
    """)
  }

  private func InputDictInitializerTemplate(
    _ fields: IR.InputFieldDictionary
  ) -> TemplateString {
    TemplateString("""
    \(fields.map({ "\"\($1.name)\": \($1.customName ?? $1.name.renderAsInputObjectName(config: config.config))" }), separator: ",\n")
    """)
  }

  private func FieldPropertyTemplate(_ field: IR.InputField) -> TemplateString {
    """
    \(documentation: field.documentation, config: config)
    \(deprecationReason: field.deprecationReason, config: config)
    \(accessControlModifier(for: .member))\
    var \(field.customName ?? field.name.renderAsInputObjectName(config: config.config)): \(field.renderInputValueType(config: config.config)) {
      get { __data["\(field.name)"] }
      set { __data["\(field.name)"] = newValue }
    }
    """
  }
}
