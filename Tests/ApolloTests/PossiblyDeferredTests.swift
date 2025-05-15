import XCTest
import Nimble
@_spi(Execution) @testable import Apollo
import ApolloInternalTestHelpers

private struct TestError: Error {}
private struct OtherTestError: Error {}

class PossiblyDeferredTests: XCTestCase {
  func testImmediateSuccess() async {
    let possiblyDeferred = PossiblyDeferred.immediate(.success("foo"))

    await expect { try await possiblyDeferred.get() }.to(equal("foo"))
  }
  
  func testImmediateFailure() async {
    let possiblyDeferred = PossiblyDeferred<String>.immediate(.failure(TestError()))
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
  }
  
  func testDeferredSuccess() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred.deferred { () -> String in
      numberOfInvocations += 1
      return "foo"
    }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(equal("foo"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testDeferredFailure() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred.deferred { () -> String in
      numberOfInvocations += 1
      throw TestError()
    }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  // MARK: - Map
  
  func testMapOverImmediateSuccessIsImmediate() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred.immediate(.success("foo"))
      .map { value -> String in
        numberOfInvocations += 1
        return value + "bar"
      }
    
    XCTAssertEqual(numberOfInvocations, 1)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testMapOverDeferredSuccessIsDeferred() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred.deferred { "foo" }
      .map { value -> String in
        numberOfInvocations += 1
        return value + "bar"
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testMapOverImmediateFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred<String>.immediate(.failure(TestError()))
      .map { value -> String in
        numberOfInvocations += 1
        return value + "bar"
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testMapOverDeferredFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = PossiblyDeferred<String>.deferred { throw TestError() }
      .map { value -> String in
        numberOfInvocations += 1
        return value + "bar"
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testMapPropagatesError() async {
    let possiblyDeferred = PossiblyDeferred<String>.deferred { throw TestError() }
      .map { _ in "foo" }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
  }
  
  func testErrorThrownFromMapIsPropagated() async {
    let possiblyDeferred = PossiblyDeferred.deferred { "foo" }
      .map { _ in throw TestError() }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
  }
  
  // MARK: - Flat map
  
  func testImmediateFlatMapOverImmediateSuccessIsImmediate() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred.immediate(.success("foo"))
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 1)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testImmediateFlatMapOverDeferredSuccessIsDeferred() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred.deferred { "foo" }
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testDeferredFlatMapOverImmediateSuccessIsDeferred() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred.immediate(.success("foo"))
      .flatMap { value -> PossiblyDeferred<String> in
        return .deferred {
          numberOfInvocations += 1
          return value + "bar"
        }
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testDeferredFlatMapOverDeferredSuccessIsDeferred() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred.deferred { "foo" }
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .deferred { value + "bar" }
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }
  
  func testImmediateFlatMapOverImmediateFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred<String>.immediate(.failure(TestError()))
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testImmediateFlatMapOverDeferredFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred<String>.deferred { throw TestError() }
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testDeferredFlatMapOverImmediateFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred<String>.immediate(.failure(TestError()))
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testDeferredFlatMapOverDeferredFailureIsNotInvoked() async {
    var numberOfInvocations = 0
    
    let possiblyDeferred = await PossiblyDeferred<String>.deferred { throw TestError() }
      .flatMap { value -> PossiblyDeferred<String> in
        numberOfInvocations += 1
        return .immediate(.success(value + "bar"))
      }
    
    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
  
  func testFlatMapPropagatesError() async {
    let possiblyDeferred = await PossiblyDeferred<String>.deferred { throw TestError() }
      .flatMap { _ in .immediate(.success("foo")) }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
  }
  
  func testErrorReturnedFromFlatMapIsPropagated() async {
    let possiblyDeferred = await PossiblyDeferred.deferred { "foo" }
      .flatMap { _ -> PossiblyDeferred<String> in .immediate(.failure(TestError())) }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
  }

  // MARK: - Map error
  
  func testMapErrorOverImmediateFailure() async {
    let possiblyDeferred = PossiblyDeferred<String>.immediate(.failure(TestError()))
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  func testMapErrorOverDeferredFailure() async {
    let possiblyDeferred = PossiblyDeferred<String>.deferred { throw TestError() }
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  func testMapErrorOverMapOverImmediateFailure() async {
    let possiblyDeferred = PossiblyDeferred<String>.immediate(.failure(TestError()))
      .map { _ in "foo" }
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  func testMapErrorOverMapOverDeferredFailure() async {
    let possiblyDeferred = PossiblyDeferred<String>.deferred { throw TestError() }
      .map { _ in "foo" }
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  func testMapErrorOverMapThrowingErrorOverImmediateSuccess() async {
    let possiblyDeferred = PossiblyDeferred.immediate(.success("foo"))
      .map { value -> String in
        throw TestError()
      }
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  func testMapErrorOverMapThrowingErrorOverDeferredSuccess() async {
    let possiblyDeferred = PossiblyDeferred.deferred { "foo" }
      .map { value -> String in
        throw TestError()
      }
      .mapError { error in
        XCTAssert(error is TestError)
        return OtherTestError()
      }
    
    await expect { try await possiblyDeferred.get() }.to(throwError { error in
      XCTAssert(error is OtherTestError)
    })
  }
  
  // MARK: - Lazily evaluate all
  
  func testLazilyEvaluateAllIsDeferred() async throws {
    let possiblyDeferreds: [PossiblyDeferred<String>] = [.deferred { "foo" }, .deferred { "bar" }]

    var numberOfInvocations = 0

    let deferred = lazilyEvaluateAll(possiblyDeferreds).map { values -> String in
      numberOfInvocations += 1
      XCTAssertEqual(values, ["foo", "bar"])
      return values.joined()
    }

    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await deferred.get() }.to(equal("foobar"))
    XCTAssertEqual(numberOfInvocations, 1)
  }

  func testLazilyEvaluateAllFailsWhenAnyOfTheElementsFails() async throws {
    let possiblyDeferreds: [PossiblyDeferred<String>] = [.deferred { "foo" }, .deferred { throw TestError() }]

    var numberOfInvocations = 0

    let deferred = lazilyEvaluateAll(possiblyDeferreds).map { values -> String in
      numberOfInvocations += 1
      XCTAssertEqual(values, ["foo", "bar"])
      return values.joined()
    }

    XCTAssertEqual(numberOfInvocations, 0)
    await expect { try await deferred.get() }.to(throwError { error in
      XCTAssert(error is TestError)
    })
    XCTAssertEqual(numberOfInvocations, 0)
  }
}
