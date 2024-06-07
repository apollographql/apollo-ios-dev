import GraphQLCompiler

public actor FieldCollector {

  typealias CollectedField = (String, GraphQLType, deprecationReason: String?)

  private var collectedFields: [
    GraphQLCompositeType: [String: (GraphQLType, deprecationReason: String?)]
  ] = [:]

  func collectFields(from selectionSet: CompilationResult.SelectionSet) {
    guard let type = selectionSet.parentType as? (any GraphQLInterfaceImplementingType) else { return }
    for case let .field(field) in selectionSet.selections {
      add(field: field, to: type)
    }
  }

  func add<T: Sequence>(
    fields: T,
    to type: any GraphQLInterfaceImplementingType
  ) where T.Element == CompilationResult.Field {
    for field in fields {
      add(field: field, to: type)
    }
  }

  func add(
    field: CompilationResult.Field,
    to type: any GraphQLInterfaceImplementingType
  ) {
    var fields = collectedFields[type] ?? [:]
    add(field, to: &fields)
    collectedFields.updateValue(fields, forKey: type)
  }

  private func add(
    _ field: CompilationResult.Field,
    to referencedFields: inout [String: (GraphQLType, deprecationReason: String?)]
  ) {
    let key = field.responseKey
    if !referencedFields.keys.contains(key) {
      referencedFields[key] = (field.type, field.deprecationReason)
    }
  }

  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [(String, GraphQLType, deprecationReason: String?)] {
    var fields = collectedFields[type] ?? [:]

    for interface in type.interfaces {
      if let interfaceFields = collectedFields[interface] {
        fields.merge(interfaceFields) { field, _ in field }
      }
    }

    return fields.sorted { $0.0 < $1.0 }.map { ($0.key, $0.value.0, $0.value.deprecationReason )}
  }
}
