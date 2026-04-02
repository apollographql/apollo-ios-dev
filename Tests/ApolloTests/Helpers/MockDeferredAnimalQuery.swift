@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers

/// A shared mock query with deferred fragments for testing incremental response parsing.
/// Used by both `JSONResponseParsingInterceptorTests_IncrementalItems` and
/// `JSONResponseParser_IncrementalResponseParsingTests`.
struct MockDeferredAnimalQuery: GraphQLQuery, @unchecked Sendable {
  static var operationName: String { "AnimalQuery" }

  static var operationDocument: OperationDocument {
    .init(definition: .init("Mock Operation Definition"))
  }

  static var responseFormat: IncrementalDeferredResponseFormat {
    IncrementalDeferredResponseFormat(deferredFragments: [
      DeferredFragmentIdentifier(label: "deferredGenus", fieldPath: ["animal"]): AnAnimal.Animal.DeferredGenus.self,
      DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["animal"]): AnAnimal.Animal.DeferredFriend.self,
    ])
  }

  typealias Data = AnAnimal
  final class AnAnimal: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {
      [
        .field("animal", Animal.self)
      ]
    }

    var animal: Animal { __data["animal"] }

    final class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("species", String.self),
          .deferred(DeferredGenus.self, label: "deferredGenus"),
          .deferred(DeferredFriend.self, label: "deferredFriend"),
        ]
      }

      var species: String { __data["species"] }

      struct Fragments: FragmentContainer {
        let __data: DataDict
        init(_dataDict: DataDict) {
          __data = _dataDict
          _deferredGenus = Deferred(_dataDict: _dataDict)
          _deferredFriend = Deferred(_dataDict: _dataDict)
        }

        @Deferred var deferredGenus: DeferredGenus?
        @Deferred var deferredFriend: DeferredFriend?
      }

      final class DeferredGenus: MockTypeCase, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("genus", String.self)
          ]
        }

        var genus: String { __data["genus"] }
      }

      final class DeferredFriend: MockTypeCase, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("friend", Friend.self)
          ]
        }

        var friend: Friend { __data["friend"] }

        final class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("name", String.self)
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }
  }
}
