extension CursorBasedPagination {
    public struct ForwardPagination: PaginationInfo, Hashable {
        public let hasNext: Bool
        public let endCursor: String?

        public var canLoadMore: Bool { hasNext }

        public init(hasNext: Bool, endCursor: String?) {
            self.hasNext = hasNext
            self.endCursor = endCursor
        }
    }

}
