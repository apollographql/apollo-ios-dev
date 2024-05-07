import Foundation
import Nimble
import OrderedCollections
import GraphQLCompiler
@testable import IR
import TemplateString
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers

protocol SelectionShallowMatchable {
  typealias Field = IR.Field
  typealias InlineFragment = IR.InlineFragmentSpread
  typealias NamedFragment = IR.NamedFragmentSpread

  var fields: OrderedDictionary<String, Field> { get }
  var inlineFragments: OrderedDictionary<IR.ScopeCondition, InlineFragment> { get }
  var namedFragments: OrderedDictionary<String, NamedFragment> { get }

  var isEmpty: Bool { get }
}

extension IR.DirectSelections: SelectionShallowMatchable { }
extension IR.DirectSelections.ReadOnly: SelectionShallowMatchable {}
extension IR.MergedSelections: SelectionShallowMatchable { }
extension IR.EntityTreeScopeSelections: SelectionShallowMatchable {
  var inlineFragments: OrderedDictionary<IR.ScopeCondition, InlineFragment> { [:] }
}

typealias SelectionMatcherTuple = (fields: [ShallowFieldMatcher],
                                   typeCases: [ShallowInlineFragmentMatcher],
                                   fragments: [ShallowFragmentSpreadMatcher])

// MARK - Custom Matchers

func beEmpty<T: SelectionShallowMatchable>() -> Nimble.Matcher<T> {
    return Matcher.simple("be empty") { actualExpression in
      guard let actual = try actualExpression.evaluate() else { return .fail }
      return MatcherStatus(bool: actual.isEmpty)
    }
}

/// A Matcher that matches that the AST `MergedSelections` are equal, but does not check any nested
/// selection sets of the `fields`, `typeCases`, and `fragments`. This is used for conveniently
/// checking the `MergedSelections` without having to mock out the entire nested selection sets.
func shallowlyMatch<T: SelectionShallowMatchable>(
  _ expectedValue: SelectionMatcherTuple
) -> Nimble.Matcher<T> {
  return satisfyAllOf([
    shallowlyMatch(expectedValue.fields).mappingActualTo { $0?.fields.values },
    shallowlyMatch(expectedValue.typeCases).mappingActualTo { $0?.inlineFragments.values.map(\.selectionSet) },
    shallowlyMatch(expectedValue.fragments).mappingActualTo { $0?.namedFragments.values }
  ])
}

func shallowlyMatch<T: SelectionShallowMatchable>(
  _ expectedValue: [ShallowSelectionMatcher]
) -> Nimble.Matcher<T> {
  var expectedFields: [ShallowFieldMatcher] = []
  var expectedTypeCases: [ShallowInlineFragmentMatcher] = []
  var expectedFragments: [ShallowFragmentSpreadMatcher] = []

  for selection in expectedValue {
    switch selection {
    case let .shallowField(field): expectedFields.append(field)
    case let .shallowInlineFragment(inlineFragment): expectedTypeCases.append(inlineFragment)
    case let .shallowFragmentSpread(fragment): expectedFragments.append(fragment)
    }
  }

  return shallowlyMatch((expectedFields, expectedTypeCases, expectedFragments))
}

// MARK: - SelectionsMatcher

struct SelectionsMatcher {
  let direct: [ShallowSelectionMatcher]?
  let merged: [ShallowSelectionMatcher]
  let mergedSources: OrderedSet<IR.MergedSelections.MergedSource>

  let ignoreMergedSelections: Bool

  public init(
    direct: [ShallowSelectionMatcher]?,
    merged: [ShallowSelectionMatcher] = [],
    mergedSources: OrderedSet<IR.MergedSelections.MergedSource> = [],
    ignoreMergedSelections: Bool = false
  ) {
    self.direct = direct
    self.merged = merged
    self.mergedSources = mergedSources
    self.ignoreMergedSelections = ignoreMergedSelections
  }

}

func shallowlyMatch(
  _ expectedValue: SelectionsMatcher
) -> Nimble.Matcher<SelectionSetTestWrapper> {
  let directMatcher: Nimble.Matcher<IR.DirectSelections.ReadOnly> = expectedValue.direct == nil
  ? beNil()
  : shallowlyMatch(expectedValue.direct!)

  var matchers: [Nimble.Matcher<SelectionSetTestWrapper>] = [
    directMatcher.mappingActualTo { $0?.computed.direct },
  ]

  if !expectedValue.ignoreMergedSelections {
    matchers.append(contentsOf: [
      shallowlyMatch(expectedValue.merged).mappingActualTo { $0?.computed.merged },
      equal(expectedValue.mergedSources).mappingActualTo { $0?.computed.merged.mergedSources }
    ])
  }

  return satisfyAllOf(matchers)
}

// MARK: - SelectionSetMatcher

struct SelectionSetMatcher {
  let parentType: GraphQLCompositeType
  let inclusionConditions: [CompilationResult.InclusionCondition]?
  let selections: SelectionsMatcher

  private init(
    parentType: GraphQLCompositeType,
    inclusionConditions: [CompilationResult.InclusionCondition]?,
    directSelections: [ShallowSelectionMatcher]?,
    mergedSelections: [ShallowSelectionMatcher],
    mergedSources: OrderedSet<IR.MergedSelections.MergedSource>,
    ignoreMergedSelections: Bool
  ) {
    self.parentType = parentType
    self.inclusionConditions = inclusionConditions
    self.selections = SelectionsMatcher(
      direct: directSelections,
      merged: mergedSelections,
      mergedSources: mergedSources,
      ignoreMergedSelections: ignoreMergedSelections
    )
  }

  public init(
    parentType: GraphQLCompositeType,
    inclusionConditions: [CompilationResult.InclusionCondition]? = nil,
    directSelections: [ShallowSelectionMatcher]? = [],
    mergedSelections: [ShallowSelectionMatcher] = [],
    mergedSources: OrderedSet<IR.MergedSelections.MergedSource> = []
  ) {
    self.init(
      parentType: parentType,
      inclusionConditions: inclusionConditions,
      directSelections: directSelections,
      mergedSelections: mergedSelections,
      mergedSources: mergedSources,
      ignoreMergedSelections: false
    )
  }

  public static func directOnly(
    parentType: GraphQLCompositeType,
    inclusionConditions: [CompilationResult.InclusionCondition]? = nil,
    directSelections: [ShallowSelectionMatcher]? = []
  ) -> SelectionSetMatcher {
    self.init(
      parentType: parentType,
      inclusionConditions: inclusionConditions,
      directSelections: directSelections,
      mergedSelections: [],
      mergedSources: [],
      ignoreMergedSelections: true
    )
  }
}

func shallowlyMatch(
  _ expectedValue: SelectionSetMatcher
) -> Nimble.Matcher<SelectionSetTestWrapper> {
  let expectedInclusionConditions = IR.InclusionConditions.allOf(
    expectedValue.inclusionConditions ?? []
  ).conditions

  let inclusionMatcher: Nimble.Matcher<IR.InclusionConditions> = expectedInclusionConditions == nil
  ? beNil()
  : equal(expectedInclusionConditions!)

  return satisfyAllOf([
    equal(expectedValue.parentType).mappingActualTo { $0?.parentType },
    inclusionMatcher.mappingActualTo { $0?.inclusionConditions },
    shallowlyMatch(expectedValue.selections)
  ])
}

// MARK: - Shallow Selection Matcher

public enum ShallowSelectionMatcher {
  case shallowField(ShallowFieldMatcher)
  case shallowInlineFragment(ShallowInlineFragmentMatcher)
  case shallowFragmentSpread(ShallowFragmentSpreadMatcher)

  public static func field(
    _ name: String,
    alias: String? = nil,
    type: GraphQLType? = nil,
    inclusionConditions: AnyOf<IR.InclusionConditions>? = nil,
    arguments: [CompilationResult.Argument]? = nil
  ) -> ShallowSelectionMatcher {
    .shallowField(ShallowFieldMatcher(
      name: name, alias: alias, type: type,
      inclusionConditions: inclusionConditions, arguments: arguments)
    )
  }

  public static func inlineFragment(
    parentType: GraphQLCompositeType,
    inclusionConditions: [IR.InclusionCondition]? = nil
  ) -> ShallowSelectionMatcher {
    .shallowInlineFragment(ShallowInlineFragmentMatcher(
      parentType: parentType,
      inclusionConditions: inclusionConditions,
      deferCondition: nil
    ))
  }

  public static func fragmentSpread(
    _ name: String,
    type: GraphQLCompositeType,
    inclusionConditions: AnyOf<IR.InclusionConditions>? = nil
  ) -> ShallowSelectionMatcher {
    .shallowFragmentSpread(ShallowFragmentSpreadMatcher(
      name: name,
      type: type,
      inclusionConditions: inclusionConditions,
      deferCondition: nil
    ))
  }

  public static func fragmentSpread(
    _ fragment: CompilationResult.FragmentDefinition,
    inclusionConditions: AnyOf<IR.InclusionConditions>
  ) -> ShallowSelectionMatcher {
    .shallowFragmentSpread(ShallowFragmentSpreadMatcher(
      name: fragment.name,
      type: fragment.type,
      inclusionConditions: inclusionConditions,
      deferCondition: nil
    ))
  }

  public static func fragmentSpread(
    _ fragment: CompilationResult.FragmentDefinition,
    inclusionConditions: [IR.InclusionCondition]? = nil
  ) -> ShallowSelectionMatcher {
    .shallowFragmentSpread(ShallowFragmentSpreadMatcher(
      name: fragment.name,
      type: fragment.type,
      inclusionConditions: inclusionConditions,
      deferCondition: nil
    ))
  }

  public static func deferred(
    _ parentType: GraphQLCompositeType,
    label: String,
    variable: String? = nil
  ) -> ShallowSelectionMatcher {
    .shallowInlineFragment(ShallowInlineFragmentMatcher(
      parentType: parentType,
      inclusionConditions: nil,
      deferCondition: CompilationResult.DeferCondition(label: label, variable: variable)
    ))
  }

  public static func deferred(
    _ fragment: CompilationResult.FragmentDefinition,
    label: String,
    variable: String? = nil
  ) -> ShallowSelectionMatcher {
    .shallowFragmentSpread(ShallowFragmentSpreadMatcher(
      name: fragment.name,
      type: fragment.type,
      inclusionConditions: nil,
      deferCondition: CompilationResult.DeferCondition(label: label, variable: variable)
    ))
  }
}

// MARK: - Shallow Field Matcher

public struct ShallowFieldMatcher: Equatable, CustomDebugStringConvertible {
  let name: String
  let alias: String?
  let type: GraphQLType?
  let inclusionConditions: AnyOf<IR.InclusionConditions>?
  let arguments: [CompilationResult.Argument]?

  public static func mock(
    _ name: String,
    alias: String? = nil,
    type: GraphQLType? = nil,
    inclusionConditions: AnyOf<IR.InclusionConditions>? = nil,
    arguments: [CompilationResult.Argument]? = nil
  ) -> ShallowFieldMatcher {
    self.init(
      name: name, alias: alias, type: type,
      inclusionConditions: inclusionConditions, arguments: arguments
    )
  }

  public var debugDescription: String {
    TemplateString("""
    \(name): \(type.debugDescription)\(ifLet: inclusionConditions, {
      " \($0.debugDescription)"
      })
    """).description
  }
}

public func shallowlyMatch<T: Collection>(
  _ expectedValue: [ShallowFieldMatcher]
) -> Nimble.Matcher<T> where T.Element == IR.Field {
  return Matcher.define { actual in
    return shallowlyMatch(expected: expectedValue, actual: try actual.evaluate())
  }
}

public func shallowlyMatch<T: Collection>(
  _ expectedValue: [ShallowSelectionMatcher]
) -> Nimble.Matcher<T> where T.Element == IR.Field {
  return Matcher.define { actual in
    let expectedAsFields: [ShallowFieldMatcher] = try expectedValue.map {
      guard case let .shallowField(field) = $0 else {
        throw TestError("Selection \($0) is not a field!")
      }
      return field
    }
    return try shallowlyMatch(expectedAsFields).satisfies(actual)
  }
}

public func shallowlyMatch<T: Collection>(
  expected: [ShallowFieldMatcher],
  actual: T?
) -> MatcherResult where T.Element == IR.Field {
  let message: ExpectationMessage = .expectedActualValueTo("have fields equal to \(expected)")

  guard let actual = actual,
        expected.count == actual.count else {
    return MatcherResult(status: .fail, message: message.appended(details: "Fields Did Not Match!"))
  }

  for (index, field) in zip(expected, actual).enumerated() {
    guard shallowlyMatch(expected: field.0, actual: field.1) else {
      return MatcherResult(
        status: .fail,
        message: message.appended(
          details: "Expected fields[\(index)] to equal \(field.0), got \(field.1)."
        )
      )
    }
  }

  return MatcherResult(status: .matches, message: message)
}

fileprivate func shallowlyMatch(expected: ShallowFieldMatcher, actual: IR.Field) -> Bool {
  func matchType() -> Bool {
    guard let type = expected.type else { return true }
    return type == actual.type
  }
  return expected.name == actual.name &&
  expected.alias == actual.alias &&
  expected.arguments == actual.arguments &&
  expected.inclusionConditions == actual.inclusionConditions &&
  matchType()
}

// MARK: - Shallow InlineFragment Matcher

public struct ShallowInlineFragmentMatcher: Equatable, CustomDebugStringConvertible {
  let parentType: GraphQLCompositeType
  let inclusionConditions: IR.InclusionConditions?
  let deferCondition: CompilationResult.DeferCondition?

  init(
    parentType: GraphQLCompositeType,
    inclusionConditions: [IR.InclusionCondition]?,
    deferCondition: CompilationResult.DeferCondition?
  ) {
    self.parentType = parentType
    self.deferCondition = deferCondition

    if let inclusionConditions = inclusionConditions {
      self.inclusionConditions = IR.InclusionConditions.allOf(inclusionConditions).conditions
    } else {
      self.inclusionConditions = nil
    }
  }

  public static func mock(
    parentType: GraphQLCompositeType,
    inclusionConditions: [IR.InclusionCondition]? = nil,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> ShallowInlineFragmentMatcher {
    self.init(
      parentType: parentType,
      inclusionConditions: inclusionConditions,
      deferCondition: deferCondition
    )
  }

  public var debugDescription: String {
    TemplateString("""
      ... on \(parentType.debugDescription)\
      \(ifLet: inclusionConditions, { " \($0.debugDescription)"})\
      \(ifLet: deferCondition, { " \($0.debugDescription)"})
      """).description
  }
}

public func shallowlyMatch<T: Collection>(
  _ expectedValue: [ShallowInlineFragmentMatcher]
) -> Nimble.Matcher<T> where T.Element == IR.SelectionSet {
  return Matcher.define { actual in
    return shallowlyMatch(expected: expectedValue, actual: try actual.evaluate())
  }
}

fileprivate func shallowlyMatch<T: Collection>(
  expected: [ShallowInlineFragmentMatcher],
  actual: T?
) -> MatcherResult where T.Element == IR.SelectionSet {
  let message: ExpectationMessage = .expectedActualValueTo("have typeCases equal to \(expected)")
  guard let actual = actual,
        expected.count == actual.count else {
    return MatcherResult(status: .fail, message: message.appended(details: "Inline Fragments Did Not Match!"))
  }

  for (index, typeCase) in zip(expected, actual).enumerated() {
    guard shallowlyMatch(expected: typeCase.0, actual: typeCase.1) else {
      return MatcherResult(
        status: .fail,
        message: message.appended(
          details: "Expected typeCases[\(index)] to equal \(typeCase.0), got \(typeCase.1)."
        )
      )
    }
  }

  return MatcherResult(status: .matches, message: message)
}

fileprivate func shallowlyMatch(
  expected: ShallowInlineFragmentMatcher,
  actual: IR.SelectionSet
) -> Bool {
  return expected.parentType == actual.typeInfo.parentType
    && expected.inclusionConditions == actual.inclusionConditions
    && expected.deferCondition == actual.deferCondition
}

// MARK: - Shallow Fragment Spread Matcher

public struct ShallowFragmentSpreadMatcher: Equatable, CustomDebugStringConvertible {
  let name: String
  let type: GraphQLCompositeType
  let inclusionConditions: AnyOf<IR.InclusionConditions>?
  let deferCondition: CompilationResult.DeferCondition?

  init(
    name: String,
    type: GraphQLCompositeType,
    inclusionConditions: [IR.InclusionCondition]?,
    deferCondition: CompilationResult.DeferCondition?
  ) {
    self.name = name
    self.type = type
    self.deferCondition = deferCondition

    if let inclusionConditions = inclusionConditions,
     let evaluatedConditions = IR.InclusionConditions.allOf(inclusionConditions).conditions {
      self.inclusionConditions = AnyOf(evaluatedConditions)
    } else {
      self.inclusionConditions = nil
    }
  }

  @_disfavoredOverload
  init(
    name: String,
    type: GraphQLCompositeType,
    inclusionConditions: AnyOf<IR.InclusionConditions>?,
    deferCondition: CompilationResult.DeferCondition?
  ) {
    self.name = name
    self.type = type
    self.inclusionConditions = inclusionConditions
    self.deferCondition = deferCondition
  }

  public static func mock(
    _ name: String,
    type: GraphQLCompositeType,
    inclusionConditions: AnyOf<IR.InclusionConditions>? = nil,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> ShallowFragmentSpreadMatcher {
    self.init(
      name: name,
      type: type,
      inclusionConditions: inclusionConditions,
      deferCondition: deferCondition
    )
  }

  public static func mock(
    _ fragment: CompilationResult.FragmentDefinition,
    inclusionConditions: AnyOf<IR.InclusionConditions>? = nil,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> ShallowFragmentSpreadMatcher {
    self.init(
      name: fragment.name,
      type: fragment.type,
      inclusionConditions: inclusionConditions,
      deferCondition: deferCondition
    )
  }

  public var debugDescription: String {
    TemplateString("""
    fragment \(name) on \(type.debugDescription)\
    \(ifLet: inclusionConditions, { " \($0.debugDescription)" })
    \(ifLet: deferCondition, { " \($0.debugDescription)" })
    """).description
  }
}

public func shallowlyMatch<T: Collection>(
  _ expectedValue: [ShallowFragmentSpreadMatcher]
) -> Nimble.Matcher<T> where T.Element == IR.NamedFragmentSpread {
  return Matcher.define { actual in
    return shallowlyMatch(expected: expectedValue, actual: try actual.evaluate())
  }
}

public func shallowlyMatch<T: Collection>(
  _ expectedValue: [CompilationResult.FragmentDefinition]
) -> Nimble.Matcher<T> where T.Element == IR.NamedFragmentSpread {
  return Matcher.define { actual in
    return shallowlyMatch(expected: expectedValue.map { .mock($0) }, actual: try actual.evaluate())
  }
}

fileprivate func shallowlyMatch<T: Collection>(
  expected: [ShallowFragmentSpreadMatcher],
  actual: T?
) -> MatcherResult where T.Element == IR.NamedFragmentSpread {
  let message: ExpectationMessage = .expectedActualValueTo("have fragments equal to \(expected)")
  guard let actual = actual,
        expected.count == actual.count else {
    return MatcherResult(status: .fail, message: message.appended(details: "Fragments Did Not Match!"))
  }

  for (index, fragment) in zip(expected, actual).enumerated() {
    guard shallowlyMatch(expected: fragment.0, actual: fragment.1) else {
      return MatcherResult(
        status: .fail,
        message: message.appended(
          details: "Expected fragments[\(index)] to equal \(fragment.0), got \(fragment.1)."
        )
      )
    }
  }

  return MatcherResult(status: .matches, message: message)
}

fileprivate func shallowlyMatch(expected: ShallowFragmentSpreadMatcher, actual: IR.NamedFragmentSpread) -> Bool {
  return expected.name == actual.fragment.name 
  && expected.type == actual.fragment.type
  && expected.inclusionConditions == actual.inclusionConditions
  && expected.deferCondition == actual.typeInfo.deferCondition
}

// MARK: - Matcher Mapping

extension Nimble.Matcher {
  func mappingActualTo<U>(
    _ actualMapper: @escaping ((U?) throws -> T?)
  ) -> Nimble.Matcher<U> {
    Nimble.Matcher<U>.define { (actual: Expression<U>) in
      let newActual = actual.cast(actualMapper)
      return try self.satisfies(newActual)
    }
  }
}
