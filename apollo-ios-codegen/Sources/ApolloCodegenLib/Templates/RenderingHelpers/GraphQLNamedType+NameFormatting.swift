import GraphQLCompiler
import Foundation

extension GraphQLNamedType {
  /// Provides a Swift type name for GraphQL-specific type names that are not compatible with Swift.
  var swiftName: String {
    switch name {
    case "Boolean": return "Bool"
    case "Float": return "Double"
    default: return name
    }
  }

  @objc var formattedName: String { swiftName }
}

extension GraphQLScalarType {

  var isSwiftType: Bool {
    switch name {
    case "String", "Int", "Float", "Boolean":
      return true
    default:
      return false
    }
  }

  override var formattedName: String {
    if !isCustomScalar {
      return swiftName
    }

    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_Scalar" : uppercasedName
  }

}

extension GraphQLEnumType {

  override var formattedName: String {
    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_Enum" : uppercasedName
  }

}

extension GraphQLInputObjectType {

  override var formattedName: String {
    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_InputObject" : uppercasedName
  }

}

extension GraphQLObjectType {

  override var formattedName: String {
    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_Object" : uppercasedName
  }

}

extension GraphQLInterfaceType {

  override var formattedName: String {
    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_Interface" : uppercasedName
  }

}

extension GraphQLUnionType {

  override var formattedName: String {
    let uppercasedName = swiftName.firstUppercased
    return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
            "\(uppercasedName)_Union" : uppercasedName
  }

}
