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

final class RetryToCountThenSucceedInterceptor: ApolloInterceptor {
  let timesToCallRetry: Int
  nonisolated(unsafe) var timesRetryHasBeenCalled = 0

  init(timesToCallRetry: Int) {
    self.timesToCallRetry = timesToCallRetry
  }

  func intercept<Request>(
    request: Request,
    next: (Request) async throws -> InterceptorResultStream<Request.Operation>
  ) async throws -> InterceptorResultStream<Request.Operation> where Request: GraphQLRequest {
    if self.timesRetryHasBeenCalled < self.timesToCallRetry {
      self.timesRetryHasBeenCalled += 1
      throw RequestChainRetry(request: request)

    } else {
      return try await next(request)
    }
  }
}
