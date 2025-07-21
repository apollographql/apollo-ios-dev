extension OffsetPagination {
  public struct Bidirectional: PaginationInfo, Hashable, Sendable {
    public let offset: Int
    public var canLoadNext: Bool
    public let canLoadPrevious: Bool

    public init(offset: Int, canLoadNext: Bool, canLoadPrevious: Bool) {
      self.offset = offset
      self.canLoadNext = canLoadNext
      self.canLoadPrevious = canLoadPrevious
    }
  }
}
