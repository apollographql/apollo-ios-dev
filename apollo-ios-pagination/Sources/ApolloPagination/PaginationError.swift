public enum PaginationError: Error {
  case missingInitialPage
  case pageHasNoMoreContent
  case loadInProgress
  case noQuery
}
