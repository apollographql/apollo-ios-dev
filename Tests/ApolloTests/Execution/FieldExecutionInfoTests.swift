import XCTest
@_spi(Execution)
@testable import Apollo

@_spi(Execution)
@_spi(Internal)
@_spi(Unsafe)
import ApolloAPI

@_spi(Execution)
@_spi(Unsafe)
import ApolloInternalTestHelpers

import Nimble

/// Tests for `FieldExecutionInfo`'s `cacheReadStrategy` memo lifecycle:
/// the strategy is computed from `(field, variables, schema,
/// responsePath)` and memoized; `copy()` carries the memo, and mutating
/// `responsePath` (the only mutable input) invalidates it so a
/// path-sensitive `FieldPolicy.Provider` can never observe a stale
/// strategy.
final class FieldExecutionInfoTests: XCTestCase, @unchecked Sendable {

  class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
    override class var __selections: [Selection] { [
      .field("hero", Hero.self, arguments: ["name": .variable("name")])
    ]}

    class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Hero", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
      ]}
    }
  }

  final class ProviderSpy: @unchecked Sendable {
    var receivedPaths: [String] = []
  }

  /// Stubs `FieldPolicySchemaMetadata`'s provider to derive the cache
  /// key from the response path it was handed, recording each
  /// invocation on the returned spy.
  private func stubPathSensitiveProvider() async -> ProviderSpy {
    let spy = ProviderSpy()
    await FieldPolicySchemaMetadata.stub_cacheKeyForField_SingleReturn { _, _, path in
      spy.receivedPaths.append(path.joined)
      return CacheKeyInfo(id: path.joined)
    }
    return spy
  }

  private struct UnexpectedTestState: Error {}

  private func makeHeroFieldInfo() throws -> FieldExecutionInfo {
    guard case .field(let field) = HeroSelectionSet.__selections[0] else {
      XCTFail("Test setup produced a non-field selection.")
      throw UnexpectedTestState()
    }
    let parentInfo = ObjectExecutionInfo(
      rootType: HeroSelectionSet.self,
      variables: ["name": "Luke"],
      schema: FieldPolicySchemaMetadata.self
    )
    return FieldExecutionInfo(field: field, parentInfo: parentInfo)
  }

  private func policyReferenceKey(from strategy: CacheReadStrategy) throws -> String {
    guard case .policyReference(let key) = strategy else {
      XCTFail("Expected .policyReference, got \(strategy).")
      throw UnexpectedTestState()
    }
    return key
  }

  // MARK: - Tests

  func test__cacheReadStrategy__givenRepeatedAccess__evaluatesPolicyOnce() async throws {
    let spy = await stubPathSensitiveProvider()
    let info = try makeHeroFieldInfo()

    let first = try policyReferenceKey(from: info.cacheReadStrategy)
    let second = try policyReferenceKey(from: info.cacheReadStrategy)

    expect(first).to(equal("Hero:hero"))
    expect(second).to(equal("Hero:hero"))
    expect(spy.receivedPaths).to(equal(["hero"]))
  }

  func test__cacheReadStrategy__givenCopy__carriesMemoWithoutReevaluation() async throws {
    let spy = await stubPathSensitiveProvider()
    let info = try makeHeroFieldInfo()
    _ = try info.cacheReadStrategy

    let copy = info.copy()
    let copiedKey = try policyReferenceKey(from: copy.cacheReadStrategy)

    expect(copiedKey).to(equal("Hero:hero"))
    expect(spy.receivedPaths).to(equal(["hero"]))
  }

  func test__cacheReadStrategy__givenCopyWithMutatedResponsePath__reevaluatesWithNewPath() async throws {
    let spy = await stubPathSensitiveProvider()
    let info = try makeHeroFieldInfo()
    _ = try info.cacheReadStrategy

    // Mirrors the executor's list-element traversal: copy the field
    // info, then append the element index to the copy's response path.
    let elementInfo = info.copy()
    elementInfo.responsePath.append("0")

    let elementKey = try policyReferenceKey(from: elementInfo.cacheReadStrategy)

    expect(elementKey).to(equal("Hero:hero.0"))
    expect(spy.receivedPaths).to(equal(["hero", "hero.0"]))
  }

  func test__cacheReadStrategy__givenMutatedCopy__originalKeepsItsMemo() async throws {
    let spy = await stubPathSensitiveProvider()
    let info = try makeHeroFieldInfo()
    _ = try info.cacheReadStrategy

    let elementInfo = info.copy()
    elementInfo.responsePath.append("0")
    _ = try elementInfo.cacheReadStrategy

    let originalKey = try policyReferenceKey(from: info.cacheReadStrategy)

    expect(originalKey).to(equal("Hero:hero"))
    expect(spy.receivedPaths).to(equal(["hero", "hero.0"]))
  }

  func test__cacheReadStrategy__givenResponsePathMutationBeforeFirstAccess__evaluatesWithMutatedPath() async throws {
    let spy = await stubPathSensitiveProvider()
    let info = try makeHeroFieldInfo()

    info.responsePath.append("42")

    let key = try policyReferenceKey(from: info.cacheReadStrategy)

    expect(key).to(equal("Hero:hero.42"))
    expect(spy.receivedPaths).to(equal(["hero.42"]))
  }
}
