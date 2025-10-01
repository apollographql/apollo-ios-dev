extension OffsetPagination {
  public struct Reverse: PaginationInfo, Hashable, Sendable {
    public let offset: Int
    public var canLoadNext: Bool { false }
    public let canLoadPrevious: Bool

    public init(offset: Int, canLoadPrevious: Bool) {
      self.offset = offset
      self.canLoadPrevious = canLoadPrevious
    }
  }

}
