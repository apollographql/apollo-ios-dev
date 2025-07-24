import ApolloAPI

/// An enumeration that can determine whether we are paginating forward or backwards.
public enum PaginationDirection: Hashable, Sendable {
  case next
  case previous
}
