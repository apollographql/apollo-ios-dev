import XCTest

public func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail(message())
  } catch {
    errorHandler(error)
  }
}

public func XCTUnwrapping<T>(
    _ expression: @autoclosure () async throws -> T?,
    _ message: @autoclosure () -> String = ""
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value)
}
