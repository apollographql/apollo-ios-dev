@testable import ApolloPagination

extension PaginationError {
  static func isCancellation(error: PaginationError?) -> Bool {
    if case .cancellation = error {
      return true
    } else {
      return false
    }
  }

  static func isLoadInProgress(error: PaginationError?) -> Bool {
    if case .loadInProgress = error {
      return true
    } else {
      return false
    }
  }
}
