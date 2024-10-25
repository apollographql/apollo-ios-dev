import Foundation

public struct CapitalizationRule: Codable, Equatable, Sendable {
  public enum Term: Codable, Equatable, Sendable {
    case string(String)
    case regex(String)
  }

  public enum CaseStrategy: String, Codable, Equatable, Sendable {
    case upper
    case lower
    case camel
    case pascal
  }

  public let term: Term
  public let strategy: CaseStrategy

  public init(term: Term, strategy: CaseStrategy) {
    self.term = term
    self.strategy = strategy
  }
}
