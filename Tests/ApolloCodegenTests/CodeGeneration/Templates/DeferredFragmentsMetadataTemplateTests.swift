import XCTest
import Nimble
import OrderedCollections
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class DeferredFragmentsMetadataTemplateTests: XCTestCase {
  
  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var operation: IR.Operation!
  var configContext: ApolloCodegen.ConfigurationContext!
  var subject: DeferredFragmentsMetadataTemplate!
  
  override func setUp() {
    super.setUp()

    configContext = .init(config: .mock())
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    operation = nil
    configContext = nil
    subject = nil

    super.tearDown()
  }
  
  private func buildSubjectAndOperation(named operationName: String = "TestOperation") async throws {
    ir = try await .mock(schema: schemaSDL, document: document)
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)

    let mockTemplateRenderer = MockTemplateRenderer(
      target: .operationFile(),
      template: "",
      config: configContext
    )

    subject = DeferredFragmentsMetadataTemplate(
      operation: operation,
      config: configContext,
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .parent)
    )
  }
  
  private func renderSubject() -> String? {
    subject.render()?.description
  }
  
  // MARK: - Deferred Inline Fragments
  
  func test__render__givenDeferredInlineFragmentWithoutTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... @defer(label: "root") {
            species
          }
        }
      }
      """.appendingDeferDirective()

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: Data.AllAnimal.Root.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenDeferredInlineFragmentOnSameTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Animal @defer(label: "root") {
            species
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: Data.AllAnimal.Root.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      
      interface Dog {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "root") {
            species
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: Data.AllAnimal.AsDog.Root.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenSiblingDeferredInlineFragmentsOnSameTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "one") {
            species
          }
          ... on Dog @defer(label: "two") {
            genus
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let one = DeferredFragmentIdentifier(label: "one", fieldPath: ["allAnimals"])
        static let two = DeferredFragmentIdentifier(label: "two", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.one: Data.AllAnimal.AsDog.One.self,
        DeferredFragmentIdentifiers.two: Data.AllAnimal.AsDog.Two.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenSiblingDeferredInlineFragmentsOnDifferentTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Cat {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "one") {
            species
          }
          ... on Cat @defer(label: "two") {
            genus
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let one = DeferredFragmentIdentifier(label: "one", fieldPath: ["allAnimals"])
        static let two = DeferredFragmentIdentifier(label: "two", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.one: Data.AllAnimal.AsDog.One.self,
        DeferredFragmentIdentifiers.two: Data.AllAnimal.AsCat.Two.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenNestedDeferredInlineFragments_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
        friend: Animal!
      }
      
      interface Cat {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "outer") {
            species
            friend {
              ... on Cat @defer(label: "inner") {
                genus
              }
            }
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let outer = DeferredFragmentIdentifier(label: "outer", fieldPath: ["allAnimals"])
        static let inner = DeferredFragmentIdentifier(label: "inner", fieldPath: ["allAnimals", "friend"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.outer: Data.AllAnimal.AsDog.Outer.self,
        DeferredFragmentIdentifiers.inner: Data.AllAnimal.AsDog.Outer.Friend.AsCat.Inner.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  // MARK: Deferred Named Fragments
  
  func test__render__givenDeferredNamedFragmentOnSameTypeCase_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: AnimalFragment.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenDeferredNamedFragmentOnDifferentTypeCase_rendersDeferMetadata() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment @defer(label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: DogFragment.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenDeferredInlineFragment_insideNamedFragment_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment
        }
      }

      fragment DogFragment on Dog {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: Data.Root.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_rendersDeferMetadata() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment
        }
      }

      fragment DogFragment on Animal {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()
    
    // then
    let rendered = renderSubject()
    
    expect(rendered).to(equalLineByLine("""
      // MARK: - Deferred Fragment Metadata

      enum DeferredFragmentIdentifiers {
        static let root = DeferredFragmentIdentifier(label: "root", fieldPath: ["allAnimals"])
      }

      public static var deferredFragments: [DeferredFragmentIdentifier: any ApolloAPI.SelectionSet.Type]? {[
        DeferredFragmentIdentifiers.root: Data.AsDog.Root.self,
      ]}
      """,
      atLine: 2,
      ignoringExtraLines: false)
    )
  }
  
}
