public protocol PaginationInfo: Sendable {
  var canLoadNext: Bool { get }
  var canLoadPrevious: Bool { get }
}
