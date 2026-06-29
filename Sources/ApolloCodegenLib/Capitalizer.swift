import Foundation

/// A rule that defines how a specific term should be capitalized in generated Swift code.
public struct CapitalizationRule: Codable, Equatable, Sendable {

  /// The term to match within generated names.
  public enum Term: Codable, Equatable, Sendable {
    /// Match a whole camelCase word segment, compared case-insensitively.
    ///
    /// Matching is performed per word segment rather than by raw substring, so `.string("id")`
    /// matches the `Id` segment in `userId` but does *not* match the `id` inside `Hidden`.
    case string(String)
    /// Match a regular expression against an individual camelCase word segment.
    ///
    /// The pattern is **not anchored**: it matches when the pattern occurs anywhere within a
    /// segment, and the *entire* segment is then re-cased. Anchor the pattern (e.g. `^id$`) to
    /// avoid over-matching — an unanchored `id` would also match the `id` inside the `Hidden`
    /// segment and uppercase the whole word.
    case regex(String)

    private enum CodingKeys: String, CodingKey {
      case string
      case regex
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let value = try container.decodeIfPresent(String.self, forKey: .string) {
        self = .string(value)
      } else if let value = try container.decodeIfPresent(String.self, forKey: .regex) {
        self = .regex(value)
      } else {
        throw DecodingError.dataCorrupted(.init(
          codingPath: decoder.codingPath,
          debugDescription: "CapitalizationRule.Term expects a 'string' or 'regex' key."
        ))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .string(let value): try container.encode(value, forKey: .string)
      case .regex(let value): try container.encode(value, forKey: .regex)
      }
    }
  }

  /// The capitalization strategy to apply when a term is matched.
  public enum CaseStrategy: Codable, Equatable, Sendable {
    /// Uppercase the matched segment (e.g., "Id" → "ID").
    ///
    /// Only applied when the matched segment's first character is already uppercase, matching
    /// SwiftFormat's `acronyms` rule (so a leading lowercase `id` in `idToken` is preserved).
    case upper
    /// Lowercase the matched segment (e.g., "ID" → "id").
    case lower
    /// Replace the matched segment with an exact literal string (e.g., "graphql" → "GraphQL").
    ///
    /// Use this for mixed-case acronyms that neither ``upper`` nor ``lower`` can produce.
    case replace(String)

    private enum CodingKeys: String, CodingKey {
      case replace
    }

    public init(from decoder: any Decoder) throws {
      // Simple string form: "upper" / "lower".
      if let single = try? decoder.singleValueContainer(),
         let rawValue = try? single.decode(String.self) {
        switch rawValue {
        case "upper": self = .upper; return
        case "lower": self = .lower; return
        default: break
        }
      }
      // Keyed object form: { "replace": "<string>" }.
      let container = try decoder.container(keyedBy: CodingKeys.self)
      guard let replacement = try container.decodeIfPresent(String.self, forKey: .replace) else {
        throw DecodingError.dataCorrupted(.init(
          codingPath: decoder.codingPath,
          debugDescription: #"CaseStrategy expects "upper", "lower", or {"replace": <string>}."#
        ))
      }
      self = .replace(replacement)
    }

    public func encode(to encoder: any Encoder) throws {
      switch self {
      case .upper:
        var container = encoder.singleValueContainer()
        try container.encode("upper")
      case .lower:
        var container = encoder.singleValueContainer()
        try container.encode("lower")
      case .replace(let replacement):
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(replacement, forKey: .replace)
      }
    }
  }

  /// The term to search for within generated names.
  public let term: Term
  /// The capitalization strategy to apply when the term is matched.
  public let strategy: CaseStrategy

  public init(term: Term, strategy: CaseStrategy) {
    self.term = term
    self.strategy = strategy
  }
}

/// Applies ``CapitalizationRule``s to generated Swift names.
///
/// The capitalizer splits camelCase strings into word segments, matches each segment against the
/// configured rules, applies the appropriate capitalization strategy, and recombines the segments.
struct Capitalizer: Sendable, Equatable {

  private let rules: [CapitalizationRule]

  init(rules: [CapitalizationRule] = []) {
    self.rules = rules
  }

  /// Applies all capitalization rules to the given string.
  ///
  /// The string is split into camelCase word segments. Each segment is checked against the rules
  /// in order. If a rule matches, the segment is replaced according to the rule's strategy.
  ///
  /// - Parameter string: The camelCase string to process.
  /// - Returns: The string with capitalization rules applied.
  func apply(to string: String) -> String {
    guard !rules.isEmpty, !string.isEmpty else { return string }

    var segments = splitCamelCase(string)

    for rule in rules {
      for i in segments.indices {
        if matches(rule: rule, segment: segments[i]) {
          segments[i] = applyStrategy(rule.strategy, to: segments[i])
        }
      }
    }

    return joinCamelCase(segments)
  }

  // MARK: - Private

  /// Splits a camelCase string into word segments.
  ///
  /// Examples:
  /// - `"userId"` → `["user", "Id"]`
  /// - `"imageURL"` → `["image", "URL"]`
  /// - `"userID"` → `["user", "ID"]`
  /// - `"XMLParser"` → `["XML", "Parser"]`
  /// - `"id"` → `["id"]`
  private func splitCamelCase(_ string: String) -> [String] {
    var segments: [String] = []
    var current = ""

    let chars = Array(string)
    for i in chars.indices {
      let char = chars[i]

      if i == 0 {
        current.append(char)
        continue
      }

      let prevChar = chars[i - 1]

      if char.isUppercase {
        if prevChar.isLowercase {
          // Transition: lower → UPPER (e.g., "user|I" in "userId")
          segments.append(current)
          current = String(char)
        } else if prevChar.isUppercase {
          // Check if next char is lowercase — if so, this starts a new word
          // e.g., "XM|L|P" in "XMLParser" → split before "P"
          if i + 1 < chars.count && chars[i + 1].isLowercase {
            segments.append(current)
            current = String(char)
          } else {
            current.append(char)
          }
        } else {
          current.append(char)
        }
      } else {
        current.append(char)
      }
    }

    if !current.isEmpty {
      segments.append(current)
    }

    return segments
  }

  /// Checks whether a rule matches a given word segment.
  private func matches(rule: CapitalizationRule, segment: String) -> Bool {
    switch rule.term {
    case .string(let term):
      return segment.caseInsensitiveCompare(term) == .orderedSame
    case .regex(let pattern):
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return false
      }
      let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
      return regex.firstMatch(in: segment, range: range) != nil
    }
  }

  /// Applies the capitalization strategy to a segment.
  private func applyStrategy(
    _ strategy: CapitalizationRule.CaseStrategy,
    to segment: String
  ) -> String {
    switch strategy {
    case .upper:
      // Mirror SwiftFormat's `acronyms` rule, which only capitalizes an acronym when its first
      // character is already uppercase. This preserves leading lowercase words — the `api` in
      // `apiKey` or the `id` in `idToken` must stay lowercase in a property or enum case name —
      // while still uppercasing mid-word acronyms like the `Id` in `userId` and every segment of
      // a PascalCase name.
      guard segment.first?.isUppercase == true else { return segment }
      return segment.uppercased()
    case .lower:
      return segment.lowercased()
    case .replace(let replacement):
      // Explicit substitution — applied verbatim whenever the term matches, regardless of the
      // segment's original casing or position.
      return replacement
    }
  }

  /// Rejoins word segments into a camelCase string.
  ///
  /// The first segment preserves its original casing. Subsequent segments are capitalized
  /// (first character uppercased) unless they are fully uppercased (acronyms).
  private func joinCamelCase(_ segments: [String]) -> String {
    guard !segments.isEmpty else { return "" }

    var result = segments[0]
    for i in 1..<segments.count {
      let segment = segments[i]
      if segment.isEmpty { continue }

      // Segments after the first should start with uppercase
      // If the segment is already all-uppercase (acronym), keep it as-is
      if segment == segment.uppercased() {
        result += segment
      } else {
        result += segment.prefix(1).uppercased() + segment.dropFirst()
      }
    }

    return result
  }
}
