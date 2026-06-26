import XCTest
import Nimble
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib

class CapitalizerTests: XCTestCase {

  // MARK: - No Rules

  func test__apply__noRules__returnsUnchanged() {
    let capitalizer = Capitalizer(rules: [])

    expect(capitalizer.apply(to: "userId")).to(equal("userId"))
  }

  func test__apply__emptyString__returnsEmpty() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "")).to(equal(""))
  }

  // MARK: - String Term, Upper Strategy

  func test__apply__stringTermUpper__userId__becomesUserID() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "userId")).to(equal("userID"))
  }

  func test__apply__stringTermUpper__imageUrl__becomesImageURL() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("url"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "imageUrl")).to(equal("imageURL"))
  }

  func test__apply__stringTermUpper__leadingLowercaseTerm__isPreserved() {
    // Matches SwiftFormat's `acronyms` rule: an acronym is only capitalized when its first
    // character is already uppercase, so a leading lowercase `id` is left untouched. This is
    // the property-name case that previously mangled `apiKey` into `aPIKey`.
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "idField")).to(equal("idField"))
  }

  func test__apply__stringTermUpper__leadingUppercaseTerm__isCapitalized() {
    // A PascalCase (type-name style) input has an uppercase-leading segment, which IS treated
    // as an acronym and capitalized.
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "IdField")).to(equal("IDField"))
  }

  func test__apply__stringTermUpper__leadingLowercaseAcronymWithSuffix__isPreserved() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("api"), strategy: .upper),
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "apiKey")).to(equal("apiKey"))
    expect(capitalizer.apply(to: "idToken")).to(equal("idToken"))
  }

  func test__apply__stringTermUpper__fullStringMatchLowercase__isPreserved() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "id")).to(equal("id"))
  }

  func test__apply__stringTermUpper__fullStringMatchUppercase__isCapitalized() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "Id")).to(equal("ID"))
  }

  func test__apply__stringTermUpper__multipleSegmentsMatch__userIdAndGroupId() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "userIdAndGroupId")).to(equal("userIDAndGroupID"))
  }

  // MARK: - String Term, Lower Strategy

  func test__apply__stringTermLower__userID__becomesUserId() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .lower)
    ])

    expect(capitalizer.apply(to: "userID")).to(equal("userId"))
  }

  // MARK: - Replace Strategy

  func test__apply__replaceStrategy__midWordSegment__isReplacedVerbatim() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("graphql"), strategy: .replace("GraphQL"))
    ])

    // "myGraphqlClient" → ["my", "Graphql", "Client"]; "Graphql" matches and is replaced.
    expect(capitalizer.apply(to: "myGraphqlClient")).to(equal("myGraphQLClient"))
  }

  func test__apply__replaceStrategy__leadingSegment__isReplacedVerbatim() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("graphql"), strategy: .replace("GraphQL"))
    ])

    // Unlike `.upper`, replace applies regardless of the segment's position or original case.
    expect(capitalizer.apply(to: "graphqlEndpoint")).to(equal("GraphQLEndpoint"))
  }

  // MARK: - Regex Term

  func test__apply__regexTermUpper__userId__becomesUserID() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .regex("^[Ii]d$"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "userId")).to(equal("userID"))
  }

  func test__apply__regexTermUpper__restApi__becomesRestAPI() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .regex("^[Aa]pi$"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "restApi")).to(equal("restAPI"))
  }

  // MARK: - Term Not Found

  func test__apply__termNotFound__returnsUnchanged() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper)
    ])

    expect(capitalizer.apply(to: "userName")).to(equal("userName"))
  }

  // MARK: - Multiple Rules

  func test__apply__multipleRules__appliedInOrder() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("id"), strategy: .upper),
      .init(term: .string("url"), strategy: .upper)
    ])

    // The leading lowercase `url` is preserved (SwiftFormat semantics); the mid-word `Id` is
    // uppercased.
    expect(capitalizer.apply(to: "urlForUserId")).to(equal("urlForUserID"))
  }

  // MARK: - CamelCase Splitting

  func test__splitCamelCase__midWordAcronym__isCapitalized() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("xml"), strategy: .upper)
    ])

    // "parserForXml" splits to ["parser", "For", "Xml"]; the mid-word "Xml" → "XML".
    expect(capitalizer.apply(to: "parserForXml")).to(equal("parserForXML"))
  }

  func test__splitCamelCase__leadingLowercaseAcronym__isPreserved() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("xml"), strategy: .upper)
    ])

    // "xmlParser" splits to ["xml", "Parser"]; the leading lowercase "xml" is preserved.
    expect(capitalizer.apply(to: "xmlParser")).to(equal("xmlParser"))
  }

  func test__splitCamelCase__handlesExistingAcronyms() {
    let capitalizer = Capitalizer(rules: [
      .init(term: .string("url"), strategy: .lower)
    ])

    // "imageURL" splits to ["image", "URL"] → "image" + "url" = "imageUrl"
    // (url matched, lowercased)
    expect(capitalizer.apply(to: "imageURL")).to(equal("imageUrl"))
  }

  // MARK: - Field Property Rendering Integration

  private func makeConfig(
    _ rules: [CapitalizationRule]
  ) -> ApolloCodegen.ConfigurationContext {
    ApolloCodegen.ConfigurationContext(
      config: .mock(options: .init(additionalCapitalizationRules: rules))
    )
  }

  func test__renderAsFieldPropertyName__midWordAcronym__isCapitalized() {
    let config = makeConfig([.init(term: .string("id"), strategy: .upper)])

    expect("userId".renderAsFieldPropertyName(config: config)).to(equal("userID"))
  }

  func test__renderAsFieldPropertyName__leadingAcronym__isNotMangled() {
    // Regression for the `apiKey` → `aPIKey` mangling: a field whose name begins with a
    // configured acronym must render unchanged, because the leading word stays lowercase.
    let config = makeConfig([
      .init(term: .string("api"), strategy: .upper),
      .init(term: .string("id"), strategy: .upper)
    ])

    expect("apiKey".renderAsFieldPropertyName(config: config)).to(equal("apiKey"))
    expect("idToken".renderAsFieldPropertyName(config: config)).to(equal("idToken"))
  }

  func test__renderAsFieldPropertyName__standaloneAcronymField__isLowercased() {
    let config = makeConfig([.init(term: .string("id"), strategy: .upper)])

    expect("id".renderAsFieldPropertyName(config: config)).to(equal("id"))
  }

  func test__renderAsFieldPropertyName__noRules__isUnchanged() {
    let config = makeConfig([])

    expect("apiKey".renderAsFieldPropertyName(config: config)).to(equal("apiKey"))
    expect("userId".renderAsFieldPropertyName(config: config)).to(equal("userId"))
  }

  func test__renderAsTestMockFieldPropertyName__appliesSameRulesAsModelProperty() {
    let config = makeConfig([.init(term: .string("id"), strategy: .upper)])

    // Mock field properties pick up the same rules as the generated model properties so the
    // two stay in sync.
    expect("userId".renderAsTestMockFieldPropertyName(config: config))
      .to(equal("userId".renderAsFieldPropertyName(config: config)))
    expect("userId".renderAsTestMockFieldPropertyName(config: config)).to(equal("userID"))
  }

  func test__renderAsTestMockFieldPropertyName__noRules__isUnchanged() {
    let config = makeConfig([])

    expect("userId".renderAsTestMockFieldPropertyName(config: config)).to(equal("userId"))
  }

  // MARK: - CapitalizationRule Codable

  func test__capitalizationRule__roundTrips() throws {
    let rule = CapitalizationRule(term: .string("id"), strategy: .upper)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(rule)
    let decoded = try JSONDecoder().decode(CapitalizationRule.self, from: data)
    expect(decoded).to(equal(rule))
  }

  func test__capitalizationRule__regexRoundTrips() throws {
    let rule = CapitalizationRule(term: .regex("[Ii]d"), strategy: .lower)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(rule)
    let decoded = try JSONDecoder().decode(CapitalizationRule.self, from: data)
    expect(decoded).to(equal(rule))
  }

  func test__capitalizationRule__encodesStringTermAsFlatValue() throws {
    let rule = CapitalizationRule(term: .string("id"), strategy: .upper)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let json = try XCTUnwrap(String(data: encoder.encode(rule), encoding: .utf8))

    // Flat form — no synthesized `_0` wrapper.
    expect(json).to(equal(#"{"strategy":"upper","term":{"string":"id"}}"#))
  }

  func test__capitalizationRule__encodesRegexTermAsFlatValue() throws {
    let rule = CapitalizationRule(term: .regex("^[Ii]d$"), strategy: .lower)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let json = try XCTUnwrap(String(data: encoder.encode(rule), encoding: .utf8))

    expect(json).to(equal(#"{"strategy":"lower","term":{"regex":"^[Ii]d$"}}"#))
  }

  func test__capitalizationRule__decodesFlatStringTerm() throws {
    let json = Data(#"{"term":{"string":"id"},"strategy":"upper"}"#.utf8)

    let decoded = try JSONDecoder().decode(CapitalizationRule.self, from: json)

    expect(decoded).to(equal(CapitalizationRule(term: .string("id"), strategy: .upper)))
  }

  func test__capitalizationRule__decodesFlatRegexTerm() throws {
    let json = Data(#"{"term":{"regex":"^[Ii]d$"},"strategy":"upper"}"#.utf8)

    let decoded = try JSONDecoder().decode(CapitalizationRule.self, from: json)

    expect(decoded).to(equal(CapitalizationRule(term: .regex("^[Ii]d$"), strategy: .upper)))
  }

  func test__capitalizationRule__encodesReplaceStrategyAsObject() throws {
    let rule = CapitalizationRule(term: .string("graphql"), strategy: .replace("GraphQL"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let json = try XCTUnwrap(String(data: encoder.encode(rule), encoding: .utf8))

    // `.upper`/`.lower` stay plain strings; `.replace` is a keyed object.
    expect(json).to(equal(#"{"strategy":{"replace":"GraphQL"},"term":{"string":"graphql"}}"#))
  }

  func test__capitalizationRule__decodesReplaceStrategy() throws {
    let json = Data(#"{"term":{"string":"graphql"},"strategy":{"replace":"GraphQL"}}"#.utf8)

    let decoded = try JSONDecoder().decode(CapitalizationRule.self, from: json)

    expect(decoded).to(equal(CapitalizationRule(term: .string("graphql"), strategy: .replace("GraphQL"))))
  }
}
