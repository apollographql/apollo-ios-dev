import XCTest
import Nimble
@testable import ApolloWebSocket

class OperationMessageIdCreatorTests: XCTestCase {

  // MARK: - ApolloSequencedOperationMessageIdCreator

  func test__sequencedCreator__defaultStartsAtOne() {
    var creator = ApolloSequencedOperationMessageIdCreator()

    expect(creator.requestId()).to(equal("1"))
    expect(creator.requestId()).to(equal("2"))
    expect(creator.requestId()).to(equal("3"))
  }

  func test__sequencedCreator__customStartNumber() {
    var creator = ApolloSequencedOperationMessageIdCreator(startAt: 5)

    expect(creator.requestId()).to(equal("5"))
    expect(creator.requestId()).to(equal("6"))
    expect(creator.requestId()).to(equal("7"))
  }

  func test__sequencedCreator__startAtZero() {
    var creator = ApolloSequencedOperationMessageIdCreator(startAt: 0)

    expect(creator.requestId()).to(equal("0"))
    expect(creator.requestId()).to(equal("1"))
  }

  func test__sequencedCreator__largeStartNumber() {
    var creator = ApolloSequencedOperationMessageIdCreator(startAt: 999_999)

    expect(creator.requestId()).to(equal("999999"))
    expect(creator.requestId()).to(equal("1000000"))
  }

  // MARK: - Custom OperationMessageIdCreator

  func test__customCreator__returnsExpectedIds() {
    struct FixedIdCreator: OperationMessageIdCreator {
      mutating func requestId() -> String {
        return "custom-fixed-id"
      }
    }

    var creator = FixedIdCreator()
    expect(creator.requestId()).to(equal("custom-fixed-id"))
    expect(creator.requestId()).to(equal("custom-fixed-id"))
  }

  func test__customCreator__uuidBased() {
    struct UUIDIdCreator: OperationMessageIdCreator {
      mutating func requestId() -> String {
        return UUID().uuidString
      }
    }

    var creator = UUIDIdCreator()
    let id1 = creator.requestId()
    let id2 = creator.requestId()

    // UUIDs should be unique.
    expect(id1).toNot(equal(id2))

    // UUIDs should be valid format (36 chars including hyphens).
    expect(id1.count).to(equal(36))
    expect(id2.count).to(equal(36))
  }

  func test__customCreator__withMutableState() {
    struct PrefixedSequenceCreator: OperationMessageIdCreator {
      var counter = 0
      let prefix: String

      mutating func requestId() -> String {
        counter += 1
        return "\(prefix)-\(counter)"
      }
    }

    var creator = PrefixedSequenceCreator(prefix: "op")
    expect(creator.requestId()).to(equal("op-1"))
    expect(creator.requestId()).to(equal("op-2"))
    expect(creator.requestId()).to(equal("op-3"))
  }
}
