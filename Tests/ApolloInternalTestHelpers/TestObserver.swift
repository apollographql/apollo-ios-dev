import Apollo
import XCTest

@MainActor
public class TestObserver: NSObject, XCTestObservation {

  let stopAfterEachTest: Bool

  private var isStarted: Bool = false
  private let onFinish: (XCTestCase) -> Void

  public init(
    startOnInit: Bool = true,
    stopAfterEachTest: Bool = true,
    onFinish: @escaping (@MainActor (XCTestCase) -> Void)
  ) {
    self.stopAfterEachTest = stopAfterEachTest
    self.onFinish = onFinish
    super.init()

    if startOnInit { start() }
  }

  public func start() {
    guard !isStarted else { return }

    XCTestObservationCenter.shared.addTestObserver(self)
    isStarted = true
  }

  public func stop() {
    guard isStarted else { return }
    XCTestObservationCenter.shared.removeTestObserver(self)
    isStarted = false
  }

  public nonisolated func testCaseDidFinish(_ testCase: XCTestCase) {
    nonisolated(unsafe) let testCase = testCase
    MainActor.assumeIsolated {
      onFinish(testCase)
      if stopAfterEachTest { stop() }
    }
  }
}
