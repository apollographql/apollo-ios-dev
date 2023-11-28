extension CursorBasedPagination {
  public struct Forward: PaginationInfo, Hashable {
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
