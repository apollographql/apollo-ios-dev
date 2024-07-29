public enum PaginationError: Error {
  case missingInitialPage
  case pageHasNoMoreContent
  case loadInProgress
  case noQuery
  case cancellation
  // Workaround for https://github.com/apple/swift-evolution/blob/f0128e6ed3cbea226c66c8ac630e216dd4140a69/proposals/0413-typed-throws.md
  case unknown(any Error)
}
