@testable @_spi(Execution) import Apollo
@_spi(Execution) @_spi(Unsafe) @_spi(Internal) import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

final class FieldProjectionCollectorTests: XCTestCase {

  // MARK: - Field selections

  func test__collect__givenSimpleScalarSelection__emitsOneProjectionPerField() throws {
    let selections: [Selection] = [
      .field("name", String.self),
      .field("age", Int.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections) == Set([
      FieldProjection(cacheKey: "User:1", fieldName: "name",
                      columnShape: .string, cardinality: .scalar),
      FieldProjection(cacheKey: "User:1", fieldName: "age",
                      columnShape: .int, cardinality: .scalar),
    ])
  }

  func test__collect__givenListField__emitsListCardinalityProjection() throws {
    let selections: [Selection] = [
      .field("tags", [String].self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections) == Set([
      FieldProjection(cacheKey: "User:1", fieldName: "tags",
                      columnShape: .string, cardinality: .list)
    ])
  }

  func test__collect__givenObjectField__emitsChildKeyColumnShape() throws {
    class FriendSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("name", String.self)
      ]}
    }

    let selections: [Selection] = [
      .field("bestFriend", FriendSelectionSet.self)
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections) == Set([
      FieldProjection(cacheKey: "User:1", fieldName: "bestFriend",
                      columnShape: .childKey, cardinality: .scalar)
    ])
  }

  func test__collect__givenNestedObjectSelection__collectsOnlyTopLevel() throws {
    // The collector intentionally does NOT recurse past an object
    // boundary — the child's cache key isn't known until the parent's
    // child_key_value is loaded. The caller's per-level loop drives the
    // next collect() call against the resolved child key.
    class FriendSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("name", String.self),
        .field("age", Int.self),
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .field("bestFriend", FriendSelectionSet.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    // Friend's `name` and `age` are NOT in the projection set — only
    // the top-level fields are.
    expect(projections.count) == 2
    expect(projections.contains(where: { $0.fieldName == "name" })) == true
    expect(projections.contains(where: { $0.fieldName == "bestFriend" })) == true
    expect(projections.contains(where: { $0.fieldName == "age" })) == false
  }

  func test__collect__givenFieldWithArguments__usesCacheKeyForField() throws {
    // `Selection.Field.cacheKey(with:)` composes the cache field key
    // from the field name and its arguments. The collector forwards
    // variables so the cache field key matches what the executor
    // would compute.
    let selections: [Selection] = [
      .field("hero", String.self, arguments: ["episode": "JEDI"])
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Query.viewer",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.count) == 1
    let projection = try XCTUnwrap(projections.first)
    expect(projection.fieldName) == "hero(episode:JEDI)"
  }

  // MARK: - Conditional selections (@include / @skip)

  func test__collect__givenConditionalIncludeTrue__entersConditional() throws {
    let selections: [Selection] = [
      .field("__typename", String.self),
      .include(if: "showAge", .field("age", Int.self)),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: ["showAge": true],
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "age" })) == true
  }

  func test__collect__givenConditionalIncludeFalse__skipsConditional() throws {
    let selections: [Selection] = [
      .field("__typename", String.self),
      .include(if: "showAge", .field("age", Int.self)),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: ["showAge": false],
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "age" })) == false
    // The unconditional field still appears.
    expect(projections.contains(where: { $0.fieldName == "__typename" })) == true
  }

  func test__collect__givenConditionalSkipTrue__skipsConditional() throws {
    let selections: [Selection] = [
      .include(if: !"skipAge", .field("age", Int.self)),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: ["skipAge": true],
      resolveRuntimeType: { nil }
    )

    expect(projections.isEmpty) == true
  }

  // MARK: - Fragment selections

  func test__collect__givenFragment__alwaysEntersFragmentSelections() throws {
    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("name", String.self),
        .field("age", Int.self),
      ]}
    }

    let selections: [Selection] = [
      .field("__typename", String.self),
      .fragment(GivenFragment.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "name" })) == true
    expect(projections.contains(where: { $0.fieldName == "age" })) == true
    expect(projections.contains(where: { $0.fieldName == "__typename" })) == true
  }

  func test__collect__givenSameFieldInOuterAndFragment__dedupesViaSet() throws {
    // GraphQL allows the same field to appear in both the outer
    // selection and a fragment; both contribute to the same response
    // key. The Set return type collapses them into one projection.
    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("name", String.self),
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .fragment(GivenFragment.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.count) == 1
    expect(projections.first?.fieldName) == "name"
  }

  // MARK: - Inline fragment selections (type cases)

  @MainActor
  func test__collect__givenInlineFragmentMatchingRuntimeType__entersTypeCase() throws {
    let droidType = Object(typename: "Droid", implementedInterfaces: [])
    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      typename == "Droid" ? droidType : nil
    })

    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .inlineFragment(AsDroid.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Droid:2001",
      variables: nil,
      resolveRuntimeType: { droidType }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == true
    expect(projections.contains(where: { $0.fieldName == "name" })) == true
  }

  @MainActor
  func test__collect__givenInlineFragmentNonMatchingRuntimeType__skipsTypeCase() throws {
    let humanType = Object(typename: "Human", implementedInterfaces: [])

    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .inlineFragment(AsDroid.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Human:1",
      variables: nil,
      resolveRuntimeType: { humanType }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == false
    expect(projections.contains(where: { $0.fieldName == "name" })) == true
  }

  @MainActor
  func test__collect__givenInlineFragmentNilRuntimeType__skipsTypeCase() throws {
    // When the caller has no `__typename` available (and supplies a
    // nil-returning resolver), every inline fragment is conservatively
    // skipped — we cannot prove the type case applies. Top-level
    // fields still come through.
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __parentType: any ParentType {
        Object(typename: "Droid", implementedInterfaces: [])
      }
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .inlineFragment(AsDroid.self),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == false
    expect(projections.contains(where: { $0.fieldName == "name" })) == true
  }

  // MARK: - Deferred selections

  func test__collect__givenDeferredSelection__entersFragmentSelections() throws {
    // The cache executor path eagerly executes deferred fragments
    // regardless of the `@defer(if:)` condition. The collector mirrors
    // that — both `if:`-true and `if:`-false deferred selections have
    // their fields projected, matching what the executor will read.
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .field("name", String.self),
      .deferred(AsDroid.self, label: "AsDroid"),
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Droid:2001",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == true
    expect(projections.contains(where: { $0.fieldName == "name" })) == true
  }

  func test__collect__givenDeferredWithConditionFalse__entersFragmentSelections() throws {
    // `@defer(if: false)` — under the cache path, behaves as fulfilled.
    // Fields are projected.
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .deferred(if: "doDefer", AsDroid.self, label: "AsDroid")
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Droid:2001",
      variables: ["doDefer": false],
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == true
  }

  func test__collect__givenDeferredWithConditionTrue__entersFragmentSelections() throws {
    // `@defer(if: true)` — under the cache path, eagerly resolved.
    // Fields are projected.
    class AsDroid: MockTypeCase, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("primaryFunction", String.self)
      ]}
    }

    let selections: [Selection] = [
      .deferred(if: "doDefer", AsDroid.self, label: "AsDroid")
    ]

    let projections = try FieldProjectionCollector.collect(
      selections: selections,
      cacheKey: "Droid:2001",
      variables: ["doDefer": true],
      resolveRuntimeType: { nil }
    )

    expect(projections.contains(where: { $0.fieldName == "primaryFunction" })) == true
  }

  // MARK: - Empty input

  func test__collect__givenEmptySelections__returnsEmptySet() throws {
    let projections = try FieldProjectionCollector.collect(
      selections: [],
      cacheKey: "User:1",
      variables: nil,
      resolveRuntimeType: { nil }
    )

    expect(projections.isEmpty) == true
  }
}
