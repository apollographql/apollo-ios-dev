import Foundation
import OrderedCollections
import Utilities

public class DirectSelections: Equatable, CustomDebugStringConvertible {

  public fileprivate(set) var fields: OrderedDictionary<String, Field> = [:]
  public fileprivate(set) var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:]
  public fileprivate(set) var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

  init() {}

  init(
    fields: [Field] = [],
    inlineFragments: [InlineFragmentSpread] = [],
    namedFragments: [NamedFragmentSpread] = []
  ) {
    mergeIn(fields)
    mergeIn(inlineFragments)
    mergeIn(namedFragments)
  }

  init(
    fields: OrderedDictionary<String, Field> = [:],
    inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:],
    namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]
  ) {
    mergeIn(fields.values)
    mergeIn(inlineFragments.values)
    mergeIn(namedFragments.values)
  }

  func mergeIn(_ selections: DirectSelections) {
    mergeIn(selections.fields.values)
    mergeIn(selections.inlineFragments.values)
    mergeIn(selections.namedFragments.values)
  }

  func mergeIn(_ field: Field) {
    let keyInScope = field.hashForSelectionSetScope

    if let existingField = fields[keyInScope] {

      if let existingField = existingField as? EntityField, let field = field as? EntityField {
        fields[keyInScope] = merge(field, with: existingField)

      } else {
        existingField.inclusionConditions =
        (existingField.inclusionConditions || field.inclusionConditions)

      }
    } else {
      fields[keyInScope] = field
    }
  }

  private func merge(_ newField: EntityField, with existingField: EntityField) -> EntityField {
    var mergedField = existingField

    if existingField.inclusionConditions == newField.inclusionConditions {
      mergedField.selectionSet.selections!
        .mergeIn(newField.selectionSet.selections!)

    } else if existingField.inclusionConditions != nil {
      mergedField = createInclusionWrapperField(wrapping: existingField, mergingIn: newField)

    } else {
      merge(field: newField, intoInclusionWrapperField: existingField)
    }

    return mergedField
  }

  private func createInclusionWrapperField(
    wrapping existingField: EntityField,
    mergingIn newField: EntityField
  ) -> EntityField {
    let wrapperScope = existingField.selectionSet.scopePath.mutatingLast { _ in
      ScopeDescriptor.descriptor(
        forType: existingField.selectionSet.parentType,
        inclusionConditions: nil,
        givenAllTypesInSchema: existingField.selectionSet.scope.allTypesInSchema
      )
    }

    let typeInfo = SelectionSet.TypeInfo(
      entity: existingField.entity,
      scopePath: wrapperScope
    )

    let selectionSet = SelectionSet(
      typeInfo: typeInfo,
      selections: DirectSelections()
    )

    let wrapperField = EntityField(
      existingField.underlyingField,
      inclusionConditions: (existingField.inclusionConditions || newField.inclusionConditions),
      selectionSet: selectionSet
    )

    merge(field: existingField, intoInclusionWrapperField: wrapperField)
    merge(field: newField, intoInclusionWrapperField: wrapperField)

    return wrapperField
  }

  private func merge(field newField: EntityField, intoInclusionWrapperField wrapperField: EntityField) {
    if let newFieldConditions = newField.selectionSet.inclusionConditions {
      let typeInfo = SelectionSet.TypeInfo(
        entity: newField.entity,
        scopePath: wrapperField.selectionSet.scopePath.mutatingLast {
          $0.appending(newFieldConditions)
        }
      )

      let newFieldSelectionSet = SelectionSet(
        typeInfo: typeInfo,
        selections: newField.selectionSet.selections.unsafelyUnwrapped
      )

      let newFieldInlineFragment = InlineFragmentSpread(
        selectionSet: newFieldSelectionSet
      )
      wrapperField.selectionSet.selections?.mergeIn(newFieldInlineFragment)

    } else {
      wrapperField.selectionSet.selections?.mergeIn(
        newField.selectionSet.selections.unsafelyUnwrapped
      )
    }
  }

  func mergeIn(_ fragment: InlineFragmentSpread) {
    let scopeCondition = fragment.selectionSet.scope.scopePath.last.value

    if let existingTypeCase = inlineFragments[scopeCondition]?.selectionSet {
      existingTypeCase.selections!
        .mergeIn(fragment.selectionSet.selections!)

    } else {
      inlineFragments[scopeCondition] = fragment
    }
  }

  func mergeIn(_ fragment: NamedFragmentSpread) {
    if let existingFragment = namedFragments[fragment.hashForSelectionSetScope] {
      existingFragment.inclusionConditions =
      (existingFragment.inclusionConditions || fragment.inclusionConditions)
      return
    }

    namedFragments[fragment.hashForSelectionSetScope] = fragment
  }

  func mergeIn<T: Sequence>(_ fields: T) where T.Element == Field {
    fields.forEach { mergeIn($0) }
  }

  func mergeIn<T: Sequence>(_ inlineFragments: T) where T.Element == InlineFragmentSpread {
    inlineFragments.forEach { mergeIn($0) }
  }

  func mergeIn<T: Sequence>(_ fragments: T) where T.Element == NamedFragmentSpread {
    fragments.forEach { mergeIn($0) }
  }

  public var isEmpty: Bool {
    fields.isEmpty && inlineFragments.isEmpty && namedFragments.isEmpty
  }

  public static func == (lhs: DirectSelections, rhs: DirectSelections) -> Bool {
    lhs.fields == rhs.fields &&
    lhs.inlineFragments == rhs.inlineFragments &&
    lhs.namedFragments == rhs.namedFragments
  }

  public var debugDescription: String {
      """
      Fields: \(fields.values.elements)
      InlineFragments: \(inlineFragments.values.elements.map(\.debugDescription))
      Fragments: \(namedFragments.values.elements.map(\.debugDescription))
      """
  }

  var readOnlyView: ReadOnly {
    ReadOnly(value: self)
  }

  public struct ReadOnly: Equatable {
    fileprivate let value: DirectSelections

    public var fields: OrderedDictionary<String, Field> { value.fields }
    public var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> { value.inlineFragments }
    public var namedFragments: OrderedDictionary<String, NamedFragmentSpread> { value.namedFragments }
    public var isEmpty: Bool { value.isEmpty }

    public var groupedByInclusionCondition: GroupedByInclusionCondition {
      GroupedByInclusionCondition(self)
    }
  }


  public class GroupedByInclusionCondition: Equatable {

    public private(set) var unconditionalSelections:
    DirectSelections.ReadOnly = .init(value: DirectSelections())

    public private(set) var inclusionConditionGroups:
    OrderedDictionary<AnyOf<InclusionConditions>, DirectSelections.ReadOnly> = [:]

    init(_ directSelections: DirectSelections.ReadOnly) {
      for selection in directSelections.fields {
        if let condition = selection.value.inclusionConditions {
          inclusionConditionGroups.updateValue(
            forKey: condition,
            default: .init(value: DirectSelections())) { selections in
              selections.value.fields[selection.key] = selection.value
            }

        } else {
          unconditionalSelections.value.fields[selection.key] = selection.value
        }
      }

      for selection in directSelections.inlineFragments {
        if let condition = selection.value.inclusionConditions {
          inclusionConditionGroups.updateValue(
            forKey: AnyOf(condition),
            default: .init(value: DirectSelections())) { selections in
              selections.value.inlineFragments[selection.key] = selection.value
            }

        } else {
          unconditionalSelections.value.inlineFragments[selection.key] = selection.value
        }
      }

      for selection in directSelections.namedFragments {
        if let condition = selection.value.inclusionConditions {
          inclusionConditionGroups.updateValue(
            forKey: condition,
            default: .init(value: DirectSelections())) { selections in
              selections.value.namedFragments[selection.key] = selection.value
            }

        } else {
          unconditionalSelections.value.namedFragments[selection.key] = selection.value
        }
      }
    }

    public static func == (
      lhs: DirectSelections.GroupedByInclusionCondition,
      rhs: DirectSelections.GroupedByInclusionCondition
    ) -> Bool {
      lhs.unconditionalSelections == rhs.unconditionalSelections &&
      lhs.inclusionConditionGroups == rhs.inclusionConditionGroups
    }
  }

}
