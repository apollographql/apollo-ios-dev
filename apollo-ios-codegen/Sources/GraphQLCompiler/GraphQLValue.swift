import Foundation
import JavaScriptCore
import OrderedCollections

/// A value in a GraphQL document
///
/// The `Sendable` implementation of this enum is `@unchecked` because `OrderedDictionary` is not
/// currently marked as `Sendable`. v1.1 of the OrderedCollections module will mark the dictionary
/// as `Sendable` from this pull request https://github.com/apple/swift-collections/pull/191. Once
/// that version is released and we upgrade to it, `@unchecked` can be removed here.
/// Regardless, the `OrderedDictionary` should be compliant with `Sendable` as it uses
/// copy-on-write value semantics.
public indirect enum GraphQLValue: @unchecked Sendable, Hashable {
  case variable(String)
  case int(Int)
  case float(Double)
  case string(String)
  case boolean(Bool)
  case null
  case `enum`(String)
  case list([GraphQLValue])
  case object(OrderedDictionary<String, GraphQLValue>)
}

extension GraphQLValue: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

    let kind: String = jsValue["kind"].toString()

    switch kind {
    case "Variable":
      self = .variable(jsValue["value"].toString())
    case "IntValue":
      self = .int(jsValue["value"].toInt())
    case "FloatValue":
      self = .float(jsValue["value"].toDouble())
    case "StringValue":
      self = .string(jsValue["value"].toString())
    case "BooleanValue":
      self = .boolean(jsValue["value"].toBool())
    case "NullValue":
      self = .null
    case "EnumValue":
      self = .enum(jsValue["value"].toString())
    case "ListValue":
      var value = jsValue["value"]
      if value.isUndefined {
        value = jsValue["values"]
      }
      self = .list(.init(value))
    case "ObjectValue":
      let value = jsValue["value"]

      /// The JS frontend does not do value conversions of the default values for input objects,
      /// because no other compilation is needed, these are passed through as is from `graphql-js`.
      /// We need to handle both converted object values and default values and represented by
      /// `graphql-js`.
      if !value.isUndefined {
        self = .object(.init(value))

      } else {
        let fields = jsValue["fields"].toOrderedDictionary { field in
          (field["name"]["value"].toString(), GraphQLValue(field["value"]))
        }
        self = .object(fields)
      }

    default:
      preconditionFailure("""
        Unknown GraphQL value of kind "\(kind)"
        """)
    }
  }
}
