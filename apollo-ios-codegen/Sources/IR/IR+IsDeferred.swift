import GraphQLCompiler

// TODO: Documentation for this to be completed in issue #3141
public struct DeferCondition: Equatable {
  public let label: String
  public let variable: String?

  init(label: String, variable: String? = nil) {
    self.label = label
    self.variable = variable
  }

  init(_ compilationResult: CompilationResult.DeferCondition) {
    self.init(label: compilationResult.label, variable: compilationResult.variable)
  }
}
