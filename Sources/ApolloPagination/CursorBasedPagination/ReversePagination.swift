extension CursorBasedPagination {
    public struct ReversePagination: PaginationInfo, Hashable {
        public let hasPrevious: Bool
        public let startCursor: String?

        public var canLoadMore: Bool { hasPrevious }

        public init(hasPrevious: Bool, startCursor: String?) {
            self.hasPrevious = hasPrevious
            self.startCursor = startCursor
        }
    }

}
