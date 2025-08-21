#if !COCOAPODS
import ApolloAPI
#endif

/// A `GraphQLExecutionSource` configured to execute upon the data stored in a ``NormalizedCache``.
///
/// Each object exposed by the cache is represented as a `Record`.
struct CacheDataExecutionSource: GraphQLExecutionSource {
  typealias RawObjectData = Record
  typealias FieldCollector = CacheDataFieldSelectionCollector

  /// A `weak` reference to the transaction the cache data is being read from during execution.
  /// This transaction is used to resolve references to other objects in the cache during field
  /// value resolution.
  ///
  /// This property is `weak` to ensure there is not a retain cycle between the transaction and the
  /// execution pipeline. If the transaction has been deallocated, execution cannot continue
  /// against the cache data.
  weak var transaction: ApolloStore.ReadTransaction?

  /// Used to determine whether deferred selections within a selection set should be executed at the same
  /// time as the other selections.
  ///
  /// When executing on cache data all selections, including deferred, must be executed together because
  /// there is only a single response from the cache data. Any deferred selection that was cached will
  /// be returned in the response.
  var shouldAttemptDeferredFragmentExecution: Bool { true }

  init(transaction: ApolloStore.ReadTransaction) {
    self.transaction = transaction
  }

  func resolveField(
    with info: FieldExecutionInfo,
    on object: Record
  ) -> PossiblyDeferred<AnyHashable?> {
    PossiblyDeferred {
      
      let value = try resolveCacheKey(with: info, on: object)

      switch value {
      case let reference as CacheReference:
        return deferredResolve(reference: reference).map { $0 as AnyHashable }

      case let referenceList as [JSONValue]:
        return referenceList
          .enumerated()
          .deferredFlatMap { index, element in
            guard let cacheReference = element as? CacheReference else {
              return .immediate(.success(element))
            }

            return self.deferredResolve(reference: cacheReference)
              .mapError { error in
                if !(error is GraphQLExecutionError) {
                  return GraphQLExecutionError(
                    path: info.responsePath.appending(String(index)),
                    underlying: error
                  )
                } else {
                  return error
                }
              }.map { $0 as AnyHashable }
          }.map { $0._asAnyHashable }

      default:
        return .immediate(.success(value))
      }
    }
  }
  
  private func resolveCacheKey(
    with info: FieldExecutionInfo,
    on object: Record
  ) throws -> AnyHashable? {
    // TODO: Add call to new SchemaConfiguration method for programmatic field policy
    // TODO: Revisit to determine what data we want to expose to pass to SchemaConfiguration
    
    if let keys = resolveFieldPolicy(with: info) {
      if keys.count > 1 {
        return keys.compactMap { $0 as? CacheKey }.map { object[$0] }
      } else if let key = keys.first as? CacheKey {
        return object[key]
      }
        return nil
    }
    
    let key = try info.cacheKeyForField()
    return object[key]
  }
  
  private func resolveFieldPolicy(with info: FieldExecutionInfo) -> [AnyHashable]? {
    guard let fieldPolicy = info.field.fieldPolicy,
          let arguments = info.field.arguments else {
      return nil
    }
    
    struct ParsedKey { let name: String; let path: [String]? }

    let parsed: [ParsedKey] = fieldPolicy.keys.map { key in
      if let dot = key.firstIndex(of: ".") {
        let name = String(key[..<dot])
        let rest = key[key.index(after: dot)...]
        return ParsedKey(name: name, path: rest.split(separator: ".").map(String.init))
      } else {
        return ParsedKey(name: key, path: nil)
      }
    }

    var fixedParts = [String?](repeating: nil, count: parsed.count)
    var listIndex: Int? = nil
    var listValues: [String] = []

    for (i, pk) in parsed.enumerated() {
      guard let argVal = arguments[pk.name] else {
        return nil
      }

      guard let resolved = argVal.resolveValue(keyPath: pk.path, variables: info.parentInfo.variables), !resolved.isEmpty else {
        return nil
      }
      
      if resolved.count > 1 {
        listIndex = i
        listValues = resolved
      } else {
        guard let value = resolved.first else {
          return nil
        }
        fixedParts[i] = value
      }
    }

    if let idx = listIndex {
      var keys: [String] = []
      keys.reserveCapacity(listValues.count)
      for item in listValues {
        var parts = [String]()
        parts.reserveCapacity(parsed.count)
        for j in 0..<parsed.count {
          if j == idx {
            parts.append(item)
          } else if let v = fixedParts[j] {
            parts.append(v)
          } else {
            return nil
          }
        }
        keys.append("\(typename(for: info)):\(parts.joined(separator: "+"))")
      }
      return keys
    } else {
      let parts = fixedParts.compactMap { $0 }
      guard parts.count == parsed.count else {
        return nil
      }
      return ["\(typename(for: info)):\(parts.joined(separator: "+"))"]
    }
  }
  
  private func typename(for info: FieldExecutionInfo) -> String {
    switch info.field.type.namedType {
    case .object(let selectionSetType):
      return selectionSetType.__parentType.__typename
    default:
      break
    }
    return ""
  }

  private func deferredResolve(reference: CacheReference) -> PossiblyDeferred<Record> {
    guard let transaction else {
      return .immediate(.failure(ApolloStore.Error.notWithinReadTransaction))
    }

    return transaction.loadObject(forKey: reference.key)
  }

  func computeCacheKey(
    for object: Record,
    in schema: any SchemaMetadata.Type,
    inferredToImplementInterface interface: Interface?
  ) -> CacheKey? {
    return object.key
  }

  /// A wrapper around the `DefaultFieldSelectionCollector` that maps the `Record` object to it's
  /// `fields` representing the object's data.
  struct CacheDataFieldSelectionCollector: FieldSelectionCollector {
    static func collectFields(
      from selections: [Selection],
      into groupedFields: inout FieldSelectionGrouping,
      for object: Record,
      info: ObjectExecutionInfo
    ) throws {
      return try DefaultFieldSelectionCollector.collectFields(
        from: selections,
        into: &groupedFields,
        for: object.fields,
        info: info
      )
    }
  }
}

extension ScalarType {
  var cacheKeyComponentStringValue: String {
    switch self {
    case let strVal as String:
      return strVal
    case let boolVal as Bool:
      return boolVal ? "true" : "false"
    case let intVal as Int:
      return String(intVal)
    case let doubleVal as Double:
      return String(doubleVal)
    case let floatVal as Float:
      return String(floatVal)
    default:
      return String(describing: self)
    }
  }
}

extension JSONValue {
  func cacheKeyComponentStringValue(keyPath: [String]? = nil) -> [String]? {
    switch self {
    case let strVal as String:
      return [strVal]
    case let boolVal as Bool:
      return boolVal ? ["true"] : ["false"]
    case let intVal as Int:
      return [String(intVal)]
    case let doubleVal as Double:
      return [String(doubleVal)]
    case let floatVal as Float:
      return [String(floatVal)]
    case let arrVal as [JSONValue]:
      let values: [String] = arrVal.compactMap { $0.cacheKeyComponentStringValue()?.first }
      guard !values.isEmpty else { return nil }
      return values
    case let objVal as JSONObject:
      guard let keyPath, !keyPath.isEmpty else { return nil }
      guard let targetValue = objVal.walk(path: keyPath[...]) else { return nil }
      return targetValue.cacheKeyComponentStringValue()
    default:
      return [String(describing: self)]
    }
  }
}

extension JSONObject {
  fileprivate func walk(
    path: ArraySlice<String>
  ) -> JSONValue? {
    guard let head = path.first else { return self }
    guard let next = self[head] else { return nil }
    if path.count == 1 { return next }
    if let nested = next as? JSONObject {
      return nested.walk(path: path.dropFirst())
    }
    return nil
  }
}

extension InputValue {
  fileprivate func resolveValue(keyPath: [String]? = nil, variables: [String: (any GraphQLOperationVariableValue)]? = nil) -> [String]? {
    switch self {
    case .scalar(let scalar):
      return [scalar.cacheKeyComponentStringValue]
    case .variable(let varName):
      guard let varValue = variables?[varName] else {
        return nil
      }
      return varValue._jsonEncodableValue?._jsonValue.cacheKeyComponentStringValue(keyPath: keyPath)
    case .list(let list):
      if list.contains(where: { if case .list = $0 { return true } else { return false } }) {
        return nil
      }
      let values = list.compactMap { $0.resolveValue()?.first }
      guard !values.isEmpty else { return nil }
      return values
    case .object(let dict):
      guard let keyPath, !keyPath.isEmpty else { return nil }
      guard let targetValue = self.walk(dict: dict, path: keyPath[...]) else { return nil }
      return targetValue.resolveValue()
    default:
      return nil
    }
  }
  
//  fileprivate func resolveScalar(_ scalar: any ScalarType) -> String? {
//    switch scalar {
//    case let strVal as String:
//      return strVal
//    case let boolVal as Bool:
//      return boolVal ? "true" : "false"
//    case let intVal as Int:
//      return String(intVal)
//    case let doubleVal as Double:
//      return String(doubleVal)
//    case let floatVal as Float:
//      return String(floatVal)
//    default:
//      return String(describing: scalar)
//    }
//  }
  
  fileprivate func walk(
    dict: [String: InputValue],
    path: ArraySlice<String>
  ) -> InputValue? {
    guard let head = path.first else { return .object(dict) }
    guard let next = dict[head] else { return nil }
    if path.count == 1 { return next }
    if case .object(let nested) = next {
      return walk(dict: nested, path: path.dropFirst())
    }
    return nil
  }
}


