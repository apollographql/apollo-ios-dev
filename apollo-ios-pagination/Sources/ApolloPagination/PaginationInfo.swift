public protocol PaginationInfo: Sendable {
  var canLoadMore: Bool { get }
  var canLoadPrevious: Bool { get }
}
