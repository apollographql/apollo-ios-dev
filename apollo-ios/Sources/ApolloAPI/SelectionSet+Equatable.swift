import Foundation

// MARK: - Equatable & Hashable for ResponseModel
public extension SelectionSet where Self: ResponseModel {

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
    
    let selectionSetType = determineSelectionSetTypeForEquality()
    addFulfilledSelections(of: selectionSetType, to: &fields)
    
    return fields
  }
  
  private func determineSelectionSetTypeForEquality() -> any SelectionSet.Type {
    // For inline fragments, try to use their root entity type for more accurate equality checks
    if let inlineFragment = self as? (any InlineFragment & ResponseModel) {
      // Check if we can safely access the root entity type
      let rootEntity = inlineFragment.asRootEntityType
      if rootEntity is any ResponseModel {
        return type(of: rootEntity)
      }
    }
    
    // Default to using the current type
    return type(of: self)
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
        add(field: field, to: &fields)

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

  private func add(
    field: Selection.Field,
    to fields: inout [String: DataDict.FieldValue]
  ) {
    let nullableFieldData = self.__data._data[field.responseKey].asNullable
    let fieldData: DataDict.FieldValue
    switch nullableFieldData {
    case let .some(value):
      fieldData = value
    case .none, .null:
      return
    }
    addData(for: field.type)

    func addData(for type: Selection.Field.OutputType, inList: Bool = false) {
      switch type {
      case .scalar, .customScalar:
        fields[field.responseKey] = fieldData

      case let .nonNull(innerType):
        addData(for: innerType, inList: inList)

      case let .list(innerType):
        addData(for: innerType, inList: true)

      case let .object(selectionSetType):
        switch inList {
        case false:
          guard let objectData = fieldData as? DataDict else {
            preconditionFailure("Expected object data for object field: \(field)")
          }
          // Create a ResponseModel instance using the proper initializer
          if let responseModelType = selectionSetType as? any ResponseModel.Type {
            fields[field.responseKey] = responseModelType.init(_dataDict: objectData)
          }

        case true:
          guard let listData = fieldData as? [DataDict.FieldValue] else {
            preconditionFailure("Expected list data for field: \(field)")
          }
          
          if let rootSelectionSetType = selectionSetType as? any RootSelectionSet.Type {
            fields[field.responseKey] = convertElements(of: listData, to: rootSelectionSetType) as DataDict.FieldValue
          }
        }
      }
    }
  }

  private func convertElements(
    of list: [DataDict.FieldValue],
    to selectionSetType: any RootSelectionSet.Type
  ) -> [DataDict.FieldValue] {
    if let dataDictList = list as? [DataDict],
       let responseModelType = selectionSetType as? any ResponseModel.Type {
      return dataDictList.map { responseModelType.init(_dataDict: $0) }
    }

    if let nestedList = list as? [[DataDict.FieldValue]] {
      return nestedList.map { self.convertElements(of: $0, to: selectionSetType) as DataDict.FieldValue }
    }

    preconditionFailure("Expected list data to contain objects.")
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

      case let .field(field):
        add(field: field, to: &fields)
      }
    }
  }

}
