import ApolloAPI

/// An enumeration that can determine whether we are paginating forward or backwards.
public enum PaginationDirection: Hashable {
  case next
  case previous
}
