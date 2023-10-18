import XCTest

public func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail(message())
  } catch {
    errorHandler(error)
  }
}
