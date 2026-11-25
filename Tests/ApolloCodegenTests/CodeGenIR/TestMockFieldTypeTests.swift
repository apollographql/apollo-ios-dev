import XCTest
import Nimble
import GraphQLCompiler
import IR
import ApolloCodegenInternalTestHelpers

class TestMockFieldTypeTests: XCTestCase {

  let image: GraphQLType = .entity(GraphQLObjectType.mock("Image"))
  let legacyImage: GraphQLType = .entity(GraphQLObjectType.mock("LegacyImage"))
  let picture: GraphQLType = .entity(GraphQLInterfaceType.mock("Picture"))
  let media: GraphQLType = .entity(GraphQLUnionType.mock("Media"))
  let id: GraphQLType = .scalar(.mock(name: "ID"))
  let dateTime: GraphQLType = .scalar(.mock(name: "DateTime"))
  let color: GraphQLType = .enum(.mock(name: "Color"))
  let shade: GraphQLType = .enum(.mock(name: "Shade"))

  func joined(_ lhs: GraphQLType, _ rhs: GraphQLType) -> TestMockFieldType {
    TestMockFieldType(lhs).joined(with: TestMockFieldType(rhs))
  }

  // MARK: - Conversion

  func test__init__givenWrappedType__convertsWrappersAndNamedType() {
    let type = TestMockFieldType(.nonNull(.list(.nonNull(image))))

    expect(type).to(equal(.nonNull(.list(.nonNull(.named(self.image))))))
    expect(type.graphQLType).to(equal(.nonNull(.list(.nonNull(self.image)))))
  }

  func test__graphQLType__givenAnyEntityOrAnyValue__isNil() {
    expect(TestMockFieldType.list(.nonNull(.anyEntity)).graphQLType).to(beNil())
    expect(TestMockFieldType.nonNull(.anyValue).graphQLType).to(beNil())
  }

  // MARK: - Joining

  func test__joined__givenSameType__returnsType() {
    expect(self.joined(.nonNull(.string()), .nonNull(.string()))).to(equal(.nonNull(.named(.string()))))
    expect(self.joined(self.color, self.color)).to(equal(.named(self.color)))
  }

  func test__joined__givenDifferentNullability__returnsNullableTypeAtEveryLevel() {
    expect(self.joined(.nonNull(.string()), .string())).to(equal(.named(.string())))
    expect(self.joined(.nonNull(.list(self.image)), .list(.nonNull(self.image))))
      .to(equal(.list(.named(self.image))))
  }

  func test__joined__givenDifferentCompositeTypes__returnsAnyEntity() {
    expect(self.joined(self.image, self.legacyImage)).to(equal(.anyEntity))
    expect(self.joined(.nonNull(self.image), .nonNull(self.picture))).to(equal(.nonNull(.anyEntity)))
    expect(self.joined(self.picture, self.media)).to(equal(.anyEntity))
    expect(self.joined(.list(self.image), .list(self.legacyImage))).to(equal(.list(.anyEntity)))
  }

  func test__joined__givenIDAndString__returnsString() {
    expect(self.joined(self.id, .string())).to(equal(.named(.string())))
    expect(self.joined(.nonNull(.string()), .nonNull(self.id))).to(equal(.nonNull(.named(.string()))))
  }

  func test__joined__givenOtherScalarMismatch__returnsAnyValue() {
    expect(self.joined(.integer(), .string())).to(equal(.anyValue))
    expect(self.joined(self.color, self.shade)).to(equal(.anyValue))
    expect(self.joined(self.dateTime, .string())).to(equal(.anyValue))
    expect(self.joined(self.id, .integer())).to(equal(.anyValue))
  }

  func test__joined__givenScalarAndCompositeType__returnsAnyValue() {
    expect(self.joined(self.image, .string())).to(equal(.anyValue))
    expect(TestMockFieldType.anyEntity.joined(with: .named(.string()))).to(equal(.anyValue))
  }

  func test__joined__givenDifferentListDepths__returnsAnyValueAtDivergingLevel() {
    expect(self.joined(self.image, .list(self.image))).to(equal(.anyValue))
    expect(self.joined(.list(.list(self.image)), .list(self.image))).to(equal(.list(.anyValue)))
    expect(self.joined(.nonNull(.list(.nonNull(.list(self.image)))), .nonNull(.list(.nonNull(self.image)))))
      .to(equal(.nonNull(.list(.nonNull(.anyValue)))))
  }

  func test__joined__givenAnyTypes__isCommutativeAndAssociative() {
    let types: [TestMockFieldType] = [
      image, legacyImage, picture, id, .string(), .integer(), color,
      .nonNull(image), .nonNull(id), .nonNull(.string()),
      .list(image), .list(.nonNull(legacyImage)), .list(.list(image)), .nonNull(.list(id)),
    ].map(TestMockFieldType.init) + [.anyEntity, .anyValue]

    for a in types {
      for b in types {
        expect(a.joined(with: b)).to(equal(b.joined(with: a)), description: "\(a) ∨ \(b)")
        for c in types {
          expect(a.joined(with: b).joined(with: c))
            .to(equal(a.joined(with: b.joined(with: c))), description: "(\(a) ∨ \(b)) ∨ \(c)")
        }
      }
    }
  }
}
