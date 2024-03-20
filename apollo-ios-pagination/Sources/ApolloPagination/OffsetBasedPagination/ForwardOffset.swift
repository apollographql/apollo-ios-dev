extension OffsetPagination {
  public struct Forward: PaginationInfo, Hashable {
    public let offset: Int
    public let canLoadNext: Bool
    public var canLoadPrevious: Bool { false }

    public init(offset: Int, canLoadNext: Bool) {
      self.offset = offset
      self.canLoadNext = canLoadNext
    }
  }

}
