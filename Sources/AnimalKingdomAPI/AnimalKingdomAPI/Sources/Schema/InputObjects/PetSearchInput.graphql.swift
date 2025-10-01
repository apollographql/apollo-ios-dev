// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

public enum PetSearchInput: OneOfInputObject {
  case ownerID(ID)
  case petID(ID)
  case searchFilters(PetSearchFilters)

  @_spi(Unsafe) public var __data: InputDict {
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