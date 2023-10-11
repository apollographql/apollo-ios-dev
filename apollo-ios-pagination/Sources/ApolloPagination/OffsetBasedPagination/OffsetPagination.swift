public struct OffsetPagination: PaginationInfo, Hashable {
  public let offset: Int
  public let canLoadMore: Bool

  public init(offset: Int, canLoadMore: Bool) {
    self.offset = offset
    self.canLoadMore = canLoadMore
  }
}
