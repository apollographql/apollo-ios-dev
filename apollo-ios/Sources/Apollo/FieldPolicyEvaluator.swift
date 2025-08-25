import Foundation
import ApolloAPI

enum FieldPolicyResult {
  case single(CacheKeyInfo)
  case list([CacheKeyInfo])
}

struct FieldPolicyEvaluator {
  let field: Selection.Field
  let variables: GraphQLOperation.Variables?
  
  init(
    field: Selection.Field,
    variables: GraphQLOperation.Variables?
  ) {
    self.field = field
    self.variables = variables
  }
  
  func resolveFieldPolicy() -> FieldPolicyResult? {
    guard let fieldPolicy = field.fieldPolicy,
          let arguments = field.arguments else {
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

      guard let resolved = argVal.resolveValue(keyPath: pk.path, variables: variables), !resolved.isEmpty else {
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
      var keys: [CacheKeyInfo] = []
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
        keys.append(CacheKeyInfo(id: parts.joined(separator: "+")))
      }
      return .list(keys)
    } else {
      let parts = fixedParts.compactMap { $0 }
      guard parts.count == parsed.count else {
        return nil
      }
      return .single(CacheKeyInfo(id: parts.joined(separator: "+")))
    }
  }
  
}

extension ScalarType {
  fileprivate var cacheKeyComponentStringValue: String {
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
  fileprivate func cacheKeyComponentStringValue(keyPath: [String]? = nil) -> [String]? {
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
