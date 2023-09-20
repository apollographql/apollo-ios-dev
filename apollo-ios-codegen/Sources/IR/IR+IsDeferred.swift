import GraphQLCompiler

// TODO: Documentation for this to be completed in issue #3141
public enum IsDeferred: Hashable, ExpressibleByBooleanLiteral {
  case value(Bool)
  case `if`(_ variable: String)

  public init(booleanLiteral value: BooleanLiteralType) {
    switch value {
    case true:
      self = .value(true)
    case false:
      self = .value(false)
    }
  }

  init(_ compilationResult: CompilationResult.IsDeferred) {
    switch compilationResult {
    case let .value(value):
      self = .value(value)

    case let .variable(variable):
      self = .if(variable)
    }
  }

  var definitionDirectiveDescription: String {
    switch self {
    case .value(false): return ""
    case .value(true): return " @defer"
    case let .if(variable):
      return " @defer(if: \(variable))"
    }
  }
}
