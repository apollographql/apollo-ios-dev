@testable @_spi(Execution) import Apollo
@_spi(Execution) @_spi(Unsafe) @_spi(Internal) import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

/// Tests for `SelectionWalker.walk(_:)` — focuses on the policy switches
/// that distinguish the resolve path (`.byRuntimeType` /
/// `.respectDeferCondition`) from the projection path (`.includeAll` /
/// `.eager`). The walker is the shared dispatch surface for both
/// `DefaultFieldSelectionCollector` and `FieldProjectionCollector`
/// (extracted in PR-009d-iv); these tests cover behaviors the two
/// collectors share at the policy layer rather than at their own
/// case-handling layer.
final class SelectionWalkerTests: XCTestCase {

  // MARK: - Test scaffold

  /// Captures the events the walker emits, keyed by event type. Tests
  /// inspect this to verify dispatch + ordering.
  private struct EventLog {
    var fields: [String] = []
    var fragmentsEntered: [String] = []
    var inlineFragmentsEntered: [String] = []
    var deferredEntered: [String] = []
    var deferredSkipped: [String] = []
  }

  private func runWalker(
    selections: [Selection],
    variables: GraphQLOperation.Variables? = nil,
    runtimeType: Object? = nil,
    inlineFragmentPolicy: SelectionWalker.InlineFragmentPolicy = .byRuntimeType,
    deferredFragmentPolicy: SelectionWalker.DeferredFragmentPolicy = .respectDeferCondition
  ) throws -> EventLog {
    var log = EventLog()
    try SelectionWalker.walk(
      selections,
      variables: variables,
      resolveRuntimeType: { runtimeType },
      inlineFragmentPolicy: inlineFragmentPolicy,
      deferredFragmentPolicy: deferredFragmentPolicy,
      onField: { field in log.fields.append(field.name) },
      onFragmentEntered: { type in log.fragmentsEntered.append(String(describing: type)) },
      onInlineFragmentEntered: { type in log.inlineFragmentsEntered.append(String(describing: type)) },
      onDeferredFragmentEntered: { type in log.deferredEntered.append(String(describing: type)) },
      onDeferredFragmentSkipped: { type in log.deferredSkipped.append(String(describing: type)) }
    )
    return log
  }

  // MARK: - DeferredFragmentPolicy.respectDeferCondition

  /// Closes the review-flagged gap: `FieldProjectionCollectorTests`'
  /// deferred tests all use the `.eager` policy and therefore can't
  /// verify the `@defer(if:)` condition is actually evaluated. This
  /// test uses `.respectDeferCondition` and confirms the condition
  /// branch is wired: when the condition evaluates to `false`, the
  /// walker *enters* the fragment (treating it as fulfilled, not
  /// deferred).
  func test__walk__withRespectDeferCondition__whenIfConditionEvaluatesFalse__entersFragment() throws {
    class GivenDeferred: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("nickname", String.self),
      ]}
    }

    let selections: [Selection] = [
      .field("__typename", String.self),
      .deferred(if: "doDefer", GivenDeferred.self, label: "given"),
    ]

    // Condition false → fragment is NOT deferred → walker enters it.
    let log = try runWalker(
      selections: selections,
      variables: ["doDefer": false],
      deferredFragmentPolicy: .respectDeferCondition
    )

    expect(log.fields).to(contain(["__typename", "nickname"]))
    expect(log.deferredEntered).to(haveCount(1))
    expect(log.deferredSkipped).to(beEmpty())
  }

  /// Mirror: condition `true` → fragment stays deferred → walker calls
  /// `onDeferredFragmentSkipped` and does NOT recurse into the
  /// fragment's selections. Together with the previous test, this
  /// proves the `if:` evaluation actually drives the branch.
  func test__walk__withRespectDeferCondition__whenIfConditionEvaluatesTrue__skipsFragment() throws {
    class GivenDeferred: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("nickname", String.self),
      ]}
    }

    let selections: [Selection] = [
      .field("__typename", String.self),
      .deferred(if: "doDefer", GivenDeferred.self, label: "given"),
    ]

    let log = try runWalker(
      selections: selections,
      variables: ["doDefer": true],
      deferredFragmentPolicy: .respectDeferCondition
    )

    expect(log.fields) == ["__typename"]
    expect(log.deferredEntered).to(beEmpty())
    expect(log.deferredSkipped).to(haveCount(1))
  }

  /// When no `if:` condition is present, `.respectDeferCondition`
  /// treats the fragment as deferred (the default semantic).
  func test__walk__withRespectDeferCondition__whenNoIfCondition__skipsFragment() throws {
    class GivenDeferred: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("nickname", String.self),
      ]}
    }

    let selections: [Selection] = [
      .deferred(GivenDeferred.self, label: "given"),
    ]

    let log = try runWalker(
      selections: selections,
      deferredFragmentPolicy: .respectDeferCondition
    )

    expect(log.deferredEntered).to(beEmpty())
    expect(log.deferredSkipped).to(haveCount(1))
    expect(log.fields).to(beEmpty())
  }

  // MARK: - DeferredFragmentPolicy.eager

  /// `.eager` ignores `@defer(if:)` entirely — every deferred fragment's
  /// selections are walked. Confirms the cache path's projection
  /// behavior at the policy layer (vs. the indirect tests in
  /// `FieldProjectionCollectorTests`).
  func test__walk__withEagerDeferredPolicy__entersEveryDeferredFragment_regardlessOfCondition() throws {
    class GivenDeferred: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("nickname", String.self),
      ]}
    }

    let selections: [Selection] = [
      .deferred(if: "doDefer", GivenDeferred.self, label: "given"),
    ]

    // Condition true under `.eager` still enters — the eager policy
    // disregards the condition altogether.
    let log = try runWalker(
      selections: selections,
      variables: ["doDefer": true],
      deferredFragmentPolicy: .eager
    )

    expect(log.fields) == ["nickname"]
    expect(log.deferredEntered).to(haveCount(1))
    expect(log.deferredSkipped).to(beEmpty())
  }

  // MARK: - InlineFragmentPolicy.byRuntimeType

  /// Inline fragment whose parent type matches the runtime type → entered.
  /// `canBeConverted(from:)` returns true for identical Objects.
  func test__walk__withByRuntimeType__whenRuntimeTypeMatches__entersInlineFragment() throws {
    let droidType = Object(typename: "Droid", implementedInterfaces: [])

    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsDroid.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: droidType,
      inlineFragmentPolicy: .byRuntimeType
    )

    expect(log.fields) == ["primaryFunction"]
    expect(log.inlineFragmentsEntered).to(haveCount(1))
  }

  /// Inline fragment whose parent type does NOT match the runtime type
  /// → skipped. The fragment's selections must not be walked.
  func test__walk__withByRuntimeType__whenRuntimeTypeMismatches__skipsInlineFragment() throws {
    let humanType = Object(typename: "Human", implementedInterfaces: [])

    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsDroid.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: humanType,
      inlineFragmentPolicy: .byRuntimeType
    )

    expect(log.fields).to(beEmpty())
    expect(log.inlineFragmentsEntered).to(beEmpty())
  }

  /// When `resolveRuntimeType` returns nil (e.g. the receiving object's
  /// `__typename` isn't yet loaded), `.byRuntimeType` skips. Distinct
  /// from `.includeAll` which would enter anyway.
  func test__walk__withByRuntimeType__whenRuntimeTypeIsNil__skipsInlineFragment() throws {
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsDroid.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: nil,
      inlineFragmentPolicy: .byRuntimeType
    )

    expect(log.fields).to(beEmpty())
    expect(log.inlineFragmentsEntered).to(beEmpty())
  }

  /// Inline fragment whose `__parentType` is an `Interface` and the
  /// runtime type is a concrete `Object` that implements the interface
  /// → entered. `canBeConverted(from:)` consults the Object's
  /// `implementedInterfaces` list, which is the more common GraphQL
  /// pattern (e.g. `fragment ... on Character` matching `Droid`).
  func test__walk__withByRuntimeType__whenInterfaceParentMatchedByImplementingObject__entersInlineFragment() throws {
    let characterInterface = Interface(
      name: "Character",
      keyFields: nil,
      implementingObjects: ["Droid", "Human"]
    )
    let droidType = Object(
      typename: "Droid",
      implementedInterfaces: [characterInterface]
    )

    class AsCharacter: MockTypeCase, @unchecked Sendable {
      static let givenInterface = Interface(
        name: "Character",
        keyFields: nil,
        implementingObjects: ["Droid", "Human"]
      )
      override class var __parentType: any ParentType { givenInterface }
      override class var __selections: [Selection] { [
        .field("name", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsCharacter.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: droidType,
      inlineFragmentPolicy: .byRuntimeType
    )

    expect(log.fields) == ["name"]
    expect(log.inlineFragmentsEntered).to(haveCount(1))
  }

  /// Mirror: an `Object` whose `implementedInterfaces` does NOT include
  /// the fragment's interface parent type → skipped. Confirms the
  /// interface-conversion path correctly rejects non-implementing
  /// types.
  func test__walk__withByRuntimeType__whenInterfaceParentNotMatchedByObject__skipsInlineFragment() throws {
    // `Vehicle` does not implement `Character`.
    let vehicleType = Object(
      typename: "Vehicle",
      implementedInterfaces: []
    )

    class AsCharacter: MockTypeCase, @unchecked Sendable {
      static let givenInterface = Interface(
        name: "Character",
        keyFields: nil,
        implementingObjects: ["Droid", "Human"]
      )
      override class var __parentType: any ParentType { givenInterface }
      override class var __selections: [Selection] { [
        .field("name", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsCharacter.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: vehicleType,
      inlineFragmentPolicy: .byRuntimeType
    )

    expect(log.fields).to(beEmpty())
    expect(log.inlineFragmentsEntered).to(beEmpty())
  }

  // MARK: - InlineFragmentPolicy.includeAll

  /// `.includeAll` enters every inline fragment regardless of
  /// `resolveRuntimeType` (the closure is never even called under this
  /// policy).
  func test__walk__withIncludeAll__entersEveryInlineFragment_regardlessOfRuntimeType() throws {
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self),
      ]}
    }
    class AsHuman: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Human", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("homePlanet", String.self),
      ]}
    }

    let selections: [Selection] = [
      .inlineFragment(AsDroid.self),
      .inlineFragment(AsHuman.self),
    ]

    let log = try runWalker(
      selections: selections,
      runtimeType: nil,  // never consulted under .includeAll
      inlineFragmentPolicy: .includeAll
    )

    expect(log.fields).to(contain(["primaryFunction", "homePlanet"]))
    expect(log.inlineFragmentsEntered).to(haveCount(2))
  }

}
