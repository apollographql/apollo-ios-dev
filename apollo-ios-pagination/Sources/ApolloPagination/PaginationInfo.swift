public protocol PaginationInfo: Sendable {
  var canLoadMore: Bool { get }
}
