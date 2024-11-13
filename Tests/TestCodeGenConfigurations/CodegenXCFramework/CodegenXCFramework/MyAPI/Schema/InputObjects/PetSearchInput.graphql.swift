// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension MyAPI {
  enum PetSearchInput: OneOfInputObject {
    case ownerID(ID)
    case petID(ID)
    case searchFilters(PetSearchFilters)

    public var __data: InputDict {
      switch self {
      case .ownerID(let value):
        return InputDict(["ownerID": value])
      case .petID(let value):
        return InputDict(["petID": value])
      case .searchFilters(let value):
        return InputDict(["searchFilters": value])
      }
    }
  }
}