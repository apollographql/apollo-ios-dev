import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
import IR
@testable import ApolloCodegenLib

class IRFieldCollectorTests: XCTestCase {

  typealias ReferencedFields = [(String, TestMockFieldType, deprecationReason: String?)]

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var subject: IR.FieldCollector!

  var schema: IR.Schema { ir.schema }

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    subject = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildIR(reverseOperationOrder: Bool = false) async throws {
    ir = try await .mock(schema: schemaSDL, document: document)

    let operations = ir.compilationResult.operations
    for operation in reverseOperationOrder ? Array(operations.reversed()) : operations {
      _ = await ir.build(operation: operation)
    }

    subject = ir.fieldCollector
  }

  // MARK: - Tests

  func test__collectedFields__givenObject_collectsReferencedFieldsOnly() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        a
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenInterface_collectsReferencedFieldsOnly() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    interface Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        a
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[interface: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsInNonAlphabeticalOrder_retrurnsReferencedFieldsSortedAlphabetically() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
    }
    """

    document = """
    query Test {
      dog {
        b
        a
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenObjectImplementingInterface_collectsFieldsReferencedOnInterface() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal{
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      animal {
        a
        ... on Dog {
          b
        }
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromFragment_collectsFieldsReferencedInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      dog {
        ...FragmentB
        a
      }
    }

    fragment FragmentB on Dog {
      b
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromFragmentOnInterface_collectsFieldsReferencedInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test {
      animal {
        a
        ... on Dog {
          ...FragmentB
        }
      }
    }

    fragment FragmentB on Dog {
      b
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsFromQueryOnImplementedInterface_collectsFieldsReferencedInQueryOnInterface() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
      dog: Dog!
    }

    interface Animal {
      a: String
    }

    type Dog implements Animal {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test1 {
      animal {
        a
      }
    }

    query Test2 {
      dog {
        b
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil)
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenAliasedField_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a: String
      b: String
      c: String
    }
    """

    document = """
    query Test1 {
      dog {
        aliasedA: a
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("aliasedA", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldWithArguments_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a(arg1: String): String
    }
    """

    document = """
    query Test1 {
      dog {
        a(arg1: "test")
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("a", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenAliasedFieldsWithArguments_collectsFields() async throws {
    // given
    schemaSDL = """
    type Query {
      dog: Dog!
    }

    type Dog {
      a(arg1: String): String
    }
    """

    document = """
    query Test1 {
      dog {
        field1: a(arg1: "one")
        field2: a(arg1: "two")
      }
    }
    """

    // when
    try await buildIR()

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let expected: ReferencedFields = [
      ("field1", .string(), nil),
      ("field2", .string(), nil),
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenFieldsOnNestedInlineFragmentWithRedundantType_referenceFieldOnNestedTypeNotMatchingTargetType_doesNotCollectsField() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    interface Pet {
      b: String
    }

    type PetRock implements Pet {
      b: String
    }

    type Dog implements Animal & Pet {
      a: String
      b: String
    }
    """

    document = """
    query Test1 {
      animal {
        ... on Pet {
          ... on Animal {
            a
          }
          b
        }
      }
    }
    """

    // when
    try await buildIR()

    let PetRock = try schema[object: "PetRock"].xctUnwrapped()
    let petRockActual = await subject.collectedFields(for: PetRock, referencedTypes: schema.referencedTypes)

    let petRockExpected: ReferencedFields = [
      ("b", .string(), nil),
    ]

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let dogActual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let dogExpected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil),
    ]

    expect(petRockActual).to(equal(petRockExpected))
    expect(dogActual).to(equal(dogExpected))
  }

  func test__collectedFields__givenFieldsOnNestedNamedFragmentWithRedundantType_referenceFieldOnNestedTypeNotMatchingTargetType_doesNotCollectsField() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal!
    }

    interface Animal {
      a: String
    }

    interface Pet {
      b: String
    }

    type PetRock implements Pet {
      b: String
    }

    type Dog implements Animal & Pet {
      a: String
      b: String
    }
    """

    document = """
    query Test1 {
      animal {
        ... on Pet {
          ...FragA
          b
        }
      }
    }

    fragment FragA on Animal {
      a
    }
    """

    // when
    try await buildIR()

    let PetRock = try schema[object: "PetRock"].xctUnwrapped()
    let petRockActual = await subject.collectedFields(for: PetRock, referencedTypes: schema.referencedTypes)

    let petRockExpected: ReferencedFields = [
      ("b", .string(), nil),
    ]

    let Dog = try schema[object: "Dog"].xctUnwrapped()
    let dogActual = await subject.collectedFields(for: Dog, referencedTypes: schema.referencedTypes)

    let dogExpected: ReferencedFields = [
      ("a", .string(), nil),
      ("b", .string(), nil),
    ]

    expect(petRockActual).to(equal(petRockExpected))
    expect(dogActual).to(equal(dogExpected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDifferentNullability__joinsToNullableTypeRegardlessOfBuildOrder() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String!
      subtitle: String
      cover: Image
      thumbnail: Thumbnail
      gallery: [Image]
      strictGallery: [Image!]!
      thumbnails: [Image]!
      strictThumbnails: [Image!]
    }

    type Image {
      url: String
    }

    type Thumbnail {
      url: String
    }
    """

    document = """
    query BookQuery {
      book {
        title
        cover {
          url
        }
        gallery {
          url
        }
        thumbnails {
          url
        }
      }
    }

    query AliasedBookQuery {
      book {
        title: subtitle
        cover: thumbnail {
          url
        }
        gallery: strictGallery {
          url
        }
        thumbnails: strictThumbnails {
          url
        }
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let Image = try schema[object: "Image"].xctUnwrapped()

    let expected: ReferencedFields = [
      ("cover", .anyEntity, nil),
      ("gallery", .list(.entity(Image)), nil),
      ("thumbnails", .list(.entity(Image)), nil),
      ("title", .string(), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDeprecatedFields__isDeprecatedOnlyIfAllFieldsAreDeprecated() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String @deprecated(reason: "Use name.")
      name: String
      label: String @deprecated(reason: "Use caption.")
      caption: String @deprecated(reason: "Use heading.")
      status: String @deprecated(reason: "Use state.")
      state: String!
    }
    """

    document = """
    query BookQuery {
      book {
        title
        label
        status
      }
    }

    query AliasedBookQuery {
      book {
        title: name
        label: caption
        status: state
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("label", .string(), "Use heading."),
      ("status", .string(), nil),
      ("title", .string(), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDeprecatedFields__usesDeprecationReasonOfFirstFieldByName() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      title: String @deprecated(reason: "Caf\\u00E9")
      name: String @deprecated(reason: "Cafe\\u0301")
    }
    """

    document = """
    query BookQuery {
      book {
        title
      }
    }

    query AliasedBookQuery {
      book {
        title: name
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("title", .string(), "Cafe\u{301}")
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedOnObjectAndInterfacesWithDifferentFields__joinsTypesRegardlessOfWhereSelected() async throws {
    // given
    schemaSDL = """
    type Query {
      magazine: Magazine!
      titled: Titled!
      named: Named!
    }

    interface Titled {
      title: String!
      shortTitle: String
    }

    interface Named {
      title: String!
      shortTitle: String
    }

    type Book implements Titled & Named {
      title: String!
      shortTitle: String
    }

    type Magazine implements Named & Titled {
      title: String!
      shortTitle: String
    }
    """

    document = """
    query MagazineQuery {
      magazine {
        title
      }
    }

    query TitledQuery {
      titled {
        title
      }
    }

    query NamedQuery {
      named {
        title: shortTitle
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let Magazine = try schema[object: "Magazine"].xctUnwrapped()
    let documentOrderBookActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)
    let documentOrderMagazineActual = await subject.collectedFields(for: Magazine, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderBookActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)
    let reverseOrderMagazineActual = await subject.collectedFields(for: Magazine, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("title", .string(), nil)
    ]

    expect(documentOrderBookActual).to(equal(expected))
    expect(documentOrderMagazineActual).to(equal(expected))
    expect(reverseOrderBookActual).to(equal(expected))
    expect(reverseOrderMagazineActual).to(equal(expected))
  }

  func test__collectedFields__givenInterfaceFieldNarrowedByObject_selectedOnObjectAndInterface__usesObjectFieldType() async throws {
    // given
    schemaSDL = """
    type Query {
      titled: Titled!
      book: Book!
    }

    interface Titled {
      title: String
      cover: Image
    }

    interface Image {
      url: String
    }

    type Photo implements Image {
      url: String
    }

    type Book implements Titled {
      title: String!
      cover: Photo
    }
    """

    document = """
    query TitledQuery {
      titled {
        title
        cover {
          url
        }
      }
    }

    query BookQuery {
      book {
        title
        cover {
          url
        }
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let Photo = try schema[object: "Photo"].xctUnwrapped()

    let expected: ReferencedFields = [
      ("cover", .entity(Photo), nil),
      ("title", .nonNull(.string()), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenFieldSelectedOnlyThroughInterfacesWithDifferentTypes__usesObjectFieldType() async throws {
    // given
    schemaSDL = """
    type Query {
      titled: Titled!
      named: Named!
    }

    interface Titled {
      title: String
    }

    interface Named {
      title: String!
    }

    type Book implements Titled & Named {
      title: String!
    }
    """

    document = """
    query TitledQuery {
      titled {
        title
      }
    }

    query NamedQuery {
      named {
        title
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("title", .nonNull(.string()), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithDifferentCompositeTypes__joinsToAnyEntity() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    interface Picture {
      url: String
    }

    type Book {
      cover: Image
      legacyCover: LegacyImage
      picture: Picture
      images: [Image]
      legacyImages: [LegacyImage]
      strictImages: [Image!]!
      strictLegacyImages: [LegacyImage!]!
    }

    type Image implements Picture {
      url: String
    }

    type LegacyImage {
      url: String
    }
    """

    document = """
    query BookQuery {
      book {
        cover { url }
        art: cover { url }
        images { url }
        strictImages { url }
      }
    }

    query LegacyBookQuery {
      book {
        cover: legacyCover { url }
        art: picture { url }
        images: legacyImages { url }
        strictImages: strictLegacyImages { url }
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("art", .anyEntity, nil),
      ("cover", .anyEntity, nil),
      ("images", .list(.anyEntity), nil),
      ("strictImages", .nonNull(.list(.nonNull(.anyEntity))), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithIncompatibleTypes__joinsToAnyValue() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    enum Color {
      RED
    }

    enum Shade {
      DARK
    }

    type Book {
      count: Int!
      label: String!
      color: Color
      shade: Shade
      cover: Image
      coverURL: String
      images: [Image]
      imageGrid: [[Image]]
      tags: [String]
      numbers: [Int]
    }

    type Image {
      url: String
    }
    """

    document = """
    query BookQuery {
      book {
        count
        tone: color
        cover { url }
        shape: cover { url }
        grid: imageGrid { url }
        values: tags
      }
    }

    query OtherBookQuery {
      book {
        count: label
        tone: shade
        cover: coverURL
        shape: images { url }
        grid: images { url }
        values: numbers
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("count", .nonNull(.anyValue), nil),
      ("cover", .anyValue, nil),
      ("grid", .list(.anyValue), nil),
      ("shape", .anyValue, nil),
      ("tone", .anyValue, nil),
      ("values", .list(.anyValue), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenResponseKeySelectedWithIDAndString__joinsToString() async throws {
    // given
    schemaSDL = """
    type Query {
      book: Book!
    }

    type Book {
      id: ID!
      isbn: ID!
      name: String!
      identifiers: [ID]
      names: [String!]
    }
    """

    document = """
    query BookQuery {
      book {
        id
        key: id
        keys: identifiers
      }
    }

    query OtherBookQuery {
      book {
        id: isbn
        key: name
        keys: names
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let documentOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    try await buildIR(reverseOperationOrder: true)
    let reverseOrderActual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let ID = GraphQLScalarType.mock(name: "ID")

    let expected: ReferencedFields = [
      ("id", .nonNull(.named(.scalar(ID))), nil),
      ("key", .nonNull(.string()), nil),
      ("keys", .list(.string()), nil)
    ]

    expect(documentOrderActual).to(equal(expected))
    expect(reverseOrderActual).to(equal(expected))
  }

  func test__collectedFields__givenDeprecatedFieldSelectedThroughInterface__usesDeprecationOfSelectedField() async throws {
    // given
    schemaSDL = """
    type Query {
      titled: Titled!
    }

    interface Titled {
      title: String @deprecated(reason: "Interface title deprecated.")
      label: String
    }

    type Item implements Titled {
      title: String
      label: String @deprecated(reason: "Object label deprecated.")
    }
    """

    document = """
    query TitledQuery {
      titled {
        title
        label
      }
    }
    """

    // when
    try await buildIR()
    let Item = try schema[object: "Item"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Item, referencedTypes: schema.referencedTypes)

    // then
    let expected: ReferencedFields = [
      ("label", .string(), nil),
      ("title", .string(), "Interface title deprecated.")
    ]

    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenInterfaceFieldNarrowedByObjectToUngeneratedType__usesSelectedTypeWithObjectNullability() async throws {
    // given
    schemaSDL = """
    type Query {
      titled: Titled!
    }

    interface Image {
      url: String
    }

    interface HiResImage implements Image {
      url: String
    }

    interface Titled {
      cover: Image
    }

    type Book implements Titled {
      cover: HiResImage!
    }
    """

    document = """
    query TitledQuery {
      titled {
        cover {
          url
        }
      }
    }
    """

    // when
    try await buildIR()
    let Book = try schema[object: "Book"].xctUnwrapped()
    let actual = await subject.collectedFields(for: Book, referencedTypes: schema.referencedTypes)

    // then
    let Image = try schema[interface: "Image"].xctUnwrapped()

    let expected: ReferencedFields = [
      ("cover", .nonNull(.entity(Image)), nil)
    ]

    expect(self.schema[interface: "HiResImage"]).to(beNil())
    expect(actual).to(equal(expected))
  }

  func test__collectedFields__givenInterfaceFieldNarrowedByObjectToGeneratedType_selectedOnlyThroughInterface__usesObjectFieldType() async throws {
    // given
    schemaSDL = """
    type Query {
      edges: [Edge!]!
      users: [User!]!
    }

    interface Node {
      id: ID!
    }

    type User implements Node {
      id: ID!
      name: String
    }

    interface Edge {
      node: Node
    }

    type UserEdge implements Edge {
      node: User
    }
    """

    document = """
    query EdgesQuery {
      edges {
        node {
          id
        }
      }
    }

    query UsersQuery {
      users {
        name
      }
    }
    """

    // when
    try await buildIR()
    let UserEdge = try schema[object: "UserEdge"].xctUnwrapped()
    let actual = await subject.collectedFields(for: UserEdge, referencedTypes: schema.referencedTypes)

    // then
    let User = try schema[object: "User"].xctUnwrapped()

    let expected: ReferencedFields = [
      ("node", .entity(User), nil)
    ]

    expect(actual).to(equal(expected))
  }

  /// MARK: - Custom Matchers
  func equal(
    _ expected: ReferencedFields
  ) -> Nimble.Matcher<ReferencedFields> {
    return Matcher.define { actual in
      let message: ExpectationMessage = .expectedActualValueTo("have fields equal to \(expected)")

      guard let actual = try actual.evaluate(),
            expected.count == actual.count else {
        return MatcherResult(status: .fail, message: message.appended(details: "Fields Did Not Match!"))
      }

      for (index, (expectedField, actualField)) in zip(expected, actual).enumerated() {
        let expectedReason = expectedField.deprecationReason.map { Array($0.utf8) }
        let actualReason = actualField.deprecationReason.map { Array($0.utf8) }

        guard expectedField.0 == actualField.0,
              expectedField.1 == actualField.1,
              expectedReason == actualReason else {
          var details = "Expected fields[\(index)] to equal \(expectedField), got \(actualField)."
          if expectedReason != actualReason {
            details += " Deprecation reason UTF-8: expected \(expectedReason ?? []), got \(actualReason ?? [])."
          }
          return MatcherResult(status: .fail, message: message.appended(details: details))
        }
      }

      return MatcherResult(status: .matches, message: message)
    }
  }
}


private extension TestMockFieldType {
  static func string() -> Self { .named(.string()) }
  static func entity(_ type: GraphQLCompositeType) -> Self { .named(.entity(type)) }
}
