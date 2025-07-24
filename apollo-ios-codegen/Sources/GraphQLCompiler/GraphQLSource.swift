import Foundation
import JavaScriptCore

/// A representation of source input to GraphQL parsing.
/// Corresponds to https://github.com/graphql/graphql-js/blob/master/src/language/source.js
public final class GraphQLSource: JavaScriptObject, @unchecked Sendable {
  public let filePath: String

  public let body: String

  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    self.filePath = jsValue["name"]
    self.body = jsValue["body"]
    super.init(jsValue, bridge: bridge)
  }

}

/// Represents a location in a GraphQL source file.
public struct GraphQLSourceLocation: Sendable {
  let filePath: String?

  let lineNumber: Int
  let columnNumber: Int
}

// MARK: - ASTNodes

// These classes correspond to the AST node types defined in
// https://github.com/graphql/graphql-js/blob/master/src/language/ast.js
// But since we don't need to access these directly, we haven't defined specific wrapper types except for
// `GraphQLDocument`.

/// An AST node.
public class ASTNode: JavaScriptObject, @unchecked Sendable {
  public let kind: String

  public let source: GraphQLSource?

  public var filePath: String? { source?.filePath }

  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    self.kind = jsValue["kind"]
    self.source = .fromJSValue(jsValue["loc"]["source"], bridge: bridge)
    super.init(jsValue, bridge: bridge)
  }

  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    self.init(jsValue, bridge: bridge)
  }

}

/// A parsed GraphQL document.
public final class GraphQLDocument: ASTNode, @unchecked Sendable {
  public let definitions: [ASTNode]

  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    self.definitions = .fromJSValue(jsValue["definitions"], bridge: bridge)
    super.init(jsValue, bridge: bridge)

    precondition(kind == "Document", "Expected GraphQL DocumentNode but found: \(jsValue)")
  }
}
