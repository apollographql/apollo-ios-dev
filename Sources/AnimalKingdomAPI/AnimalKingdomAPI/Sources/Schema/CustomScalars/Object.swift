// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI

public struct Object: CustomScalarType {
  let value: String

  public init(_jsonValue value: ApolloAPI.JSONValue) throws {
    self.value = value as? String ?? ""
  }

  public var _jsonValue: ApolloAPI.JSONValue {
    return value
  }

}
