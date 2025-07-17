import Foundation
import JavaScriptCore

public struct ValidationOptions {

  public struct DisallowedFieldNames {
    public let allFields: Set<String>
    public let entity: Set<String>
    public let entityList: Set<String>

    public init(
      allFields: Set<String>,
      entity: Set<String>,
      entityList: Set<String>
    ) {
      self.allFields = allFields
      self.entity = entity
      self.entityList = entityList
    }

    var asDictionary: Dictionary<String, Array<String>> {
      return [
        "allFields": Array(allFields),
        "entity": Array(entity),
        "entityList": Array(entityList)
      ]
    }
  }

  public let schemaNamespace: String
  public let disallowedFieldNames: DisallowedFieldNames
  public let disallowedInputParameterNames: Set<String>

  public init(
    schemaNamespace: String,
    disallowedFieldNames: DisallowedFieldNames,
    disallowedInputParameterNames: Set<String>
  ) {
    self.schemaNamespace = schemaNamespace
    self.disallowedFieldNames = disallowedFieldNames
    self.disallowedInputParameterNames = disallowedInputParameterNames
  }

  final class Bridged: JavaScriptObject {
    @MainActor
    convenience init(_ options: ValidationOptions, bridge: JavaScriptBridge) {
      let jsValue = JSValue(newObjectIn: bridge.context)

      jsValue?.setValue(
        JSValue(object: options.schemaNamespace, in: bridge.context),
        forProperty: "schemaNamespace"
      )

      jsValue?.setValue(
        JSValue(object: options.disallowedFieldNames.asDictionary, in: bridge.context),
        forProperty: "disallowedFieldNames"
      )

      jsValue?.setValue(
        JSValue(object: Array(options.disallowedInputParameterNames), in: bridge.context),
        forProperty: "disallowedInputParameterNames"
      )

      self.init(jsValue!, bridge: bridge)
    }
  }

}
