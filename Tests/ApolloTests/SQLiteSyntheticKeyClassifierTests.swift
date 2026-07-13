import XCTest
import Nimble
@testable import ApolloSQLite
import ApolloInternalTestHelpers

/// Pins the relationship between the two synthetic-key classifiers in
/// `SQLiteSchema.Records`: the Swift regex (`syntheticKeySuffixPattern`,
/// used by `isSyntheticKey` on read assembly) and the SQL `LIKE` pattern
/// (`syntheticKeySuffixLikePattern`, used by the cascade-delete walks
/// and pattern-delete exclusions). The `LIKE` pattern is deliberately
/// coarser (SQLite `LIKE` has no digit character class), so exact
/// equivalence is NOT the invariant. The invariants are:
///
/// 1. Every key the regex classifies as synthetic is also matched by
///    `LIKE` (regex ⊆ LIKE) — the SQL walks never miss a real
///    synthetic key.
/// 2. Any key where the two classifiers disagree contains the reserved
///    token `.$[` — which `insertOrUpdate` rejects at write time
///    (`SQLiteError.reservedCacheKey`) — so no *storable* user key can
///    ever be classified differently by the two implementations.
///
/// `LIKE` semantics are evaluated by SQLite itself via
/// `SQLiteTestDatabaseInspector`, not re-implemented in Swift.
class SQLiteSyntheticKeyClassifierTests: XCTestCase {

  // MARK: - Classifiers under test

  private func regexMatches(_ key: String) -> Bool {
    key.range(
      of: SQLiteSchema.Records.syntheticKeySuffixPattern,
      options: .regularExpression
    ) != nil
  }

  private func likeMatches(_ key: String) throws -> Bool {
    try SQLiteTestDatabaseInspector.sqliteLIKEMatches(
      pattern: SQLiteSchema.Records.syntheticKeySuffixLikePattern,
      candidate: key
    )
  }

  // MARK: - Canonical key corpus

  /// Keys the writer actually produces for nested-list indirection.
  private static let syntheticKeys = [
    "User:1.tags.$[0]",
    "User:1.tags.$[12]",
    "Math:cube.cube.$[0].$[3]",
    "x.$[0]",
  ]

  /// Ordinary cache keys a user or the normalizer can produce.
  private static let ordinaryKeys = [
    "User:1",
    "QUERY_ROOT",
    "User:1.tags",
    "hero(episode:JEDI)",
    "a.b.c",
    "price$",
    "$[0]",
    "User:1.tags.[0]",
  ]

  /// Keys containing the reserved token `.$[` without the exact
  /// synthetic shape — rejected at write time by the reserved-key
  /// audit, so the classifiers' disagreement on them is unreachable
  /// for stored data.
  private static let reservedLookalikes = [
    "Order:receipt.$[final]",
    "X.$[]",
    "X.$[1x]",
    "X.$[3]extra",
  ]

  private static var fullCorpus: [String] {
    syntheticKeys + ordinaryKeys + reservedLookalikes
  }

  // MARK: - Tests

  func test__classifiers__givenWriterProducedSyntheticKeys__bothMatch() throws {
    for key in Self.syntheticKeys {
      expect(self.regexMatches(key)).to(beTrue(), description: "regex should match synthetic key '\(key)'")
      expect(try self.likeMatches(key)).to(beTrue(), description: "LIKE should match synthetic key '\(key)'")
    }
  }

  func test__classifiers__givenOrdinaryKeys__neitherMatches() throws {
    for key in Self.ordinaryKeys {
      expect(self.regexMatches(key)).to(beFalse(), description: "regex should not match ordinary key '\(key)'")
      expect(try self.likeMatches(key)).to(beFalse(), description: "LIKE should not match ordinary key '\(key)'")
    }
  }

  func test__classifiers__regexMatchesAreSubsetOfLikeMatches() throws {
    // The SQL walks (which use LIKE) must never miss a key the Swift
    // side (regex) considers synthetic.
    for key in Self.fullCorpus where regexMatches(key) {
      expect(try self.likeMatches(key)).to(
        beTrue(),
        description: "regex matches '\(key)' but LIKE does not — the SQL cascade walk would miss it"
      )
    }
  }

  func test__classifiers__anyDisagreementImpliesReservedToken() throws {
    // Where the coarser LIKE pattern and the exact regex disagree,
    // the key must contain the reserved token `.$[`, which
    // `insertOrUpdate` rejects — so no storable key is ever
    // classified inconsistently.
    for key in Self.fullCorpus {
      let regex = regexMatches(key)
      let like = try likeMatches(key)
      if regex != like {
        expect(key.contains(SQLiteSchema.Records.syntheticKeyToken)).to(
          beTrue(),
          description: "classifiers disagree on '\(key)' (regex: \(regex), LIKE: \(like)) but the key does not contain the reserved token — it would be storable with inconsistent classification"
        )
      }
    }
  }
}
