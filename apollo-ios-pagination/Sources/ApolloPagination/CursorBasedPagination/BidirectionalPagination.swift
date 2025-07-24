extension CursorBasedPagination {
  /// A cursor based pagination strategy that can support fetching previous and next pages.
  public struct Bidirectional: PaginationInfo, Hashable, Sendable {
    public let hasNext: Bool
    public let endCursor: String?
    public let hasPrevious: Bool
    public let startCursor: String?

    public var canLoadNext: Bool { hasNext }
    public var canLoadPrevious: Bool { hasPrevious }

    public init(
      hasNext: Bool,
      endCursor: String?,
      hasPrevious: Bool,
      startCursor: String?
    ) {
      self.hasNext = hasNext
      self.endCursor = endCursor
      self.hasPrevious = hasPrevious
      self.startCursor = startCursor
    }
  }
}
