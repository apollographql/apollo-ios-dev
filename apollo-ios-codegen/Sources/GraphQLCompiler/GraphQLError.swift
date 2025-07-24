import Foundation
import JavaScriptCore

/// A GraphQL error.
/// Corresponds to [graphql-js/GraphQLError](https://graphql.org/graphql-js/error/#graphqlerror)
/// You can get error details if you need them, or call `error.logLines` to get errors in a format
/// that lets Xcode show inline errors.
public final class GraphQLError: JavaScriptError, @unchecked Sendable {
  private let source: GraphQLSource?
  /// The source locations associated with this error.
  public let sourceLocations: [GraphQLSourceLocation]?

  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    // When the error is a “Too many validation errors” error, there is no `source` in the error
    // object. This was causing a crash. Check for this to be undefined to avoid this edge case.
    let sourceValue = jsValue["source"]
    if !sourceValue.isUndefined {
      let source = GraphQLSource.fromJSValue(sourceValue, bridge: bridge)
      self.source = source
      self.sourceLocations = Self.computeSourceLocations(for: source, from: jsValue, bridge: bridge)

    } else {
      self.source = nil
      self.sourceLocations = nil
    }

    super.init(jsValue, bridge: bridge)
  }

  @MainActor
  private static func computeSourceLocations(
    for source: GraphQLSource,
    from jsValue: JSValue,
    bridge: JavaScriptBridge
  ) -> [GraphQLSourceLocation]? {
    guard let locations = (jsValue["locations"]).toArray() as? [[String: Int]] else {
      return nil
    }

    if let nodes: [ASTNode] = .fromJSValue(jsValue["nodes"], bridge: bridge)  {
      // We have AST nodes, so this is a validation error.
      // Because errors can be associated with locations from different
      // source files, we ignore the `source` property and go through the
      // individual nodes instead.

      precondition(locations.count == nodes.count)

      return zip(locations, nodes).map { (location, node) in
        return GraphQLSourceLocation(
          filePath: node.filePath,
          lineNumber: location["line"]!,
          columnNumber: location["column"]!
        )
      }
    } else {
      // We have no AST nodes, so this is a syntax error. Those only apply to a single source file,
      // so we can rely on the `source` property.

      return locations.map {
        GraphQLSourceLocation(
          filePath: source.filePath,
          lineNumber: $0["line"]!,
          columnNumber: $0["column"]!
        )
      }
    }
  }
  
  /// Log lines for this error in a format that allows Xcode to show errors inline at the correct location.
  /// See https://shazronatadobe.wordpress.com/2010/12/04/xcode-shell-build-phase-reporting-of-errors/
  public var logLines: [String]? {
    return sourceLocations?.map {
      return [$0.filePath ?? "", String($0.lineNumber), "error", message ?? "?"].joined(separator: ":")
    }
  }
}

/// A GraphQL schema validation error. This wraps one or more underlying validation errors.
public class GraphQLSchemaValidationError: JavaScriptError, @unchecked Sendable {
  public let validationErrors: [GraphQLError]

  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    self.validationErrors = .fromJSValue(jsValue["validationErrors"], bridge: bridge)
    super.init(jsValue, bridge: bridge)
  }
}
