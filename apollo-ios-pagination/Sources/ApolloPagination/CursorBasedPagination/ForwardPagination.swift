extension CursorBasedPagination {
  /// A cursor based pagination strategy that supports forward pagination; fetching the next page.
  public struct Forward: PaginationInfo, Hashable, Sendable {
    public let hasNext: Bool
    public let endCursor: String?

    public var canLoadNext: Bool { hasNext }
    public var canLoadPrevious: Bool { false }

    public init(hasNext: Bool, endCursor: String?) {
      self.hasNext = hasNext
      self.endCursor = endCursor
    }
  }
}
