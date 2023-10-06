import GraphQLCompiler

// TODO: Documentation for this to be completed in issue #3141
public struct DeferCondition: Hashable, CustomDebugStringConvertible {
  public let label: String
  public let variable: String?

  init(label: String, variable: String? = nil) {
    self.label = label
    self.variable = variable
  }

  init(_ compilationResult: CompilationResult.DeferCondition) {
    self.init(label: compilationResult.label, variable: compilationResult.variable)
  }

  public var debugDescription: String {
    var string = "Defer \"\(label)\""
    if let variable {
      string += " - if \"\(variable)\""
    }

    return string
  }
}
