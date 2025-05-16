//
//  CancellationHandlingInterceptor.swift
//  ApolloTests
//
//  Created by Ellen Shapiro on 9/17/20.
//  Copyright © 2020 Apollo GraphQL. All rights reserved.
//

import Apollo
import ApolloAPI
import Foundation

final class CancellationTestingInterceptor: ApolloInterceptor {
  private(set) nonisolated(unsafe) var hasBeenCancelled = false

  func intercept<Request>(
    request: Request,
    next: (Request) async throws -> InterceptorResultStream<Request.Operation>
  ) async throws -> InterceptorResultStream<Request.Operation> where Request: GraphQLRequest {
    do {
      try Task.checkCancellation()
      return try await next(request)

    } catch is CancellationError {
      self.hasBeenCancelled = true
      throw CancellationError()
    }
  }

  func cancel() {
    self.hasBeenCancelled = true
  }
}
