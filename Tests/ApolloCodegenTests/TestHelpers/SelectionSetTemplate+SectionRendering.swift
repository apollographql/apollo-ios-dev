@testable import ApolloCodegenLib
import IR

extension SelectionSetTemplate {

  /// Renders the child entity template for the given selection using a mocked validation context.
  ///
  /// This is used to test rendering of templates without requiring the entire operation.
  /// Validation performed by the `SelectionSetValidationContext` will not be exhaustive.
  func test_render(childEntity: IR.ComputedSelectionSet) -> String? {
    let context = SelectionSetContext(
      selectionSet: childEntity,
      validationContext: .init(config: self.config)
    )
    return self.render(childEntity: context)
  }

  /// Renders the inline fragment template for the given selection using a mocked validation context.
  ///
  /// This is used to test rendering of templates without requiring the entire operation.
  /// Validation performed by the `SelectionSetValidationContext` will not be exhaustive.
  func test_render(inlineFragment: IR.ComputedSelectionSet) -> String {
    let context = SelectionSetContext(
      selectionSet: inlineFragment,
      validationContext: .init(config: self.config)
    )
    return self.render(inlineFragment: context)
  }

}
