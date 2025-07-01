//
//  RetryToCountThenSucceedInterceptor.swift
//  ApolloTests
//
//  Created by Ellen Shapiro on 8/19/20.
//  Copyright © 2020 Apollo GraphQL. All rights reserved.
//

import Apollo
import ApolloAPI
import Foundation

final class RetryToCountThenSucceedInterceptor: GraphQLInterceptor {
  let timesToCallRetry: Int
  nonisolated(unsafe) var timesRetryHasBeenCalled = 0

  init(timesToCallRetry: Int) {
    self.timesToCallRetry = timesToCallRetry
  }

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: (Request) async -> InterceptorResultStream<Request>
  ) async throws -> InterceptorResultStream<Request> {
    if self.timesRetryHasBeenCalled < self.timesToCallRetry {
      self.timesRetryHasBeenCalled += 1
      throw RequestChain.Retry(request: request)

    } else {
      return await next(request)
    }
  }
}
