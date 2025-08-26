// MARK: - Equatable & Hashable
public extension SelectionSet {

  /// Creates a hash using a narrowly scoped algorithm that only combines fields in the underlying data
  /// that are relevant to the `SelectionSet`. This ensures that hashes for a fragment do not
  /// consider fields that are not included in the fragment, even if they are present in the data.
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.fieldsForEquality())
  }

  /// Checks for equality using a narrowly scoped algorithm that only compares fields in the underlying data
  /// that are relevant to the `SelectionSet`. This ensures that equality checks for a fragment do not
  /// consider fields that are not included in the fragment, even if they are present in the data.
  static func == (lhs: Self, rhs: Self) -> Bool {
    return AnySendableHashable.equatableCheck(
      lhs.fieldsForEquality(),
      rhs.fieldsForEquality()
    )
  }

  private func fieldsForEquality() -> [String: DataDict.FieldValue] {
    var fields: [String: DataDict.FieldValue] = [:]
    if let asTypeCase = self as? any InlineFragment {
      self.addFulfilledSelections(of: type(of: asTypeCase.asRootEntityType), to: &fields)

    } else {
      self.addFulfilledSelections(of: type(of: self), to: &fields)
      
    }
    return fields
  }

  private func addFulfilledSelections(
    of selectionSetType: any SelectionSet.Type,
    to fields: inout [String: DataDict.FieldValue]
  ) {
    guard self.__data.fragmentIsFulfilled(selectionSetType) else {
      return
    }

    for selection in selectionSetType.__selections {
      switch selection {
      case let .field(field):
        guard let fieldData = self.__data._data[field.responseKey] else {
          continue
        }

        if case let .object(selectionSetType) = field.type.namedType {
          guard let objectData = fieldData as? DataDict else {
            assertionFailure("Expected object data for object field: \(field)")
            return
          }
          fields[field.responseKey] = selectionSetType.init(_dataDict: objectData)
        } else {

          fields[field.responseKey] = fieldData
        }

      case let .inlineFragment(typeCase):
        self.addFulfilledSelections(of: typeCase, to: &fields)

      case let .conditional(_, selections):
        self.addConditionalSelections(selections, to: &fields)

      case let .fragment(fragmentType):
        self.addFulfilledSelections(of: fragmentType, to: &fields)

      case let .deferred(_, fragmentType, _):
        self.addFulfilledSelections(of: fragmentType, to: &fields)
      }
    }
  }

  private func addConditionalSelections(
    _ selections: [Selection],
    to fields: inout [String: DataDict.FieldValue]
  ) {
    for selection in selections {
      switch selection {
      case let .inlineFragment(typeCase):
        self.addFulfilledSelections(of: typeCase, to: &fields)

      case let .fragment(fragment):
        self.addFulfilledSelections(of: fragment, to: &fields)

      case let .deferred(_, fragment, _):
        self.addFulfilledSelections(of: fragment, to: &fields)

      case let .conditional(_, selections):
        addConditionalSelections(selections, to: &fields)

      case .field:
        assertionFailure("Conditional selections should not directly include fields. They should use an InlineFragment instead.")
      }
    }
  }

}
