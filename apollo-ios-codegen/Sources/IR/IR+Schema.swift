import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

public final class Schema {
  public let referencedTypes: ReferencedTypes
  public let documentation: String?

  init(
    referencedTypes: Schema.ReferencedTypes,
    documentation: String? = nil
  ) {
    self.referencedTypes = referencedTypes
    self.documentation = documentation
  }

  public final class ReferencedTypes: CustomDebugStringConvertible {
    public let allTypes: OrderedSet<GraphQLNamedType>
    public let schemaRootTypes: CompilationResult.RootTypeDefinition

    public let objects: OrderedSet<GraphQLObjectType>
    public let interfaces: OrderedSet<GraphQLInterfaceType>
    public let unions: OrderedSet<GraphQLUnionType>
    public let scalars: OrderedSet<GraphQLScalarType>
    public let customScalars: OrderedSet<GraphQLScalarType>
    public let enums: OrderedSet<GraphQLEnumType>
    public let inputObjects: OrderedSet<GraphQLInputObjectType>

    private let typeToUnionMap: [GraphQLObjectType: Set<GraphQLUnionType>]

    init(
      _ types: [GraphQLNamedType],
      schemaRootTypes: CompilationResult.RootTypeDefinition
    ) {
      // Ensure allTypes is stable
      self.allTypes = OrderedSet(types.sorted(by: { $0.name.schemaName < $1.name.schemaName }))
      self.schemaRootTypes = schemaRootTypes

      var objects = OrderedSet<GraphQLObjectType>()
      var interfaces = OrderedSet<GraphQLInterfaceType>()
      var unions = OrderedSet<GraphQLUnionType>()
      var scalars = OrderedSet<GraphQLScalarType>()
      var customScalars = OrderedSet<GraphQLScalarType>()
      var enums = OrderedSet<GraphQLEnumType>()
      var inputObjects = OrderedSet<GraphQLInputObjectType>()

      for type in allTypes {
        switch type {
        case let type as GraphQLObjectType: objects.append(type)
        case let type as GraphQLInterfaceType: interfaces.append(type)
        case let type as GraphQLUnionType: unions.append(type)
        case let type as GraphQLScalarType:
          if type.isCustomScalar {
            customScalars.append(type)
          } else {
            scalars.append(type)
          }
        case let type as GraphQLEnumType: enums.append(type)
        case let type as GraphQLInputObjectType: inputObjects.append(type)
        default: continue
        }
      }

      self.objects = objects
      self.interfaces = interfaces
      self.unions = unions
      self.scalars = scalars
      self.customScalars = customScalars
      self.enums = enums
      self.inputObjects = inputObjects

      var typeToUnionMap: [GraphQLObjectType: Set<GraphQLUnionType>] = [:]
      objects.forEach { type in
        typeToUnionMap[type] = Set(unions.filter { $0.types.contains(type) })
      }
      self.typeToUnionMap = typeToUnionMap
    }

    public func unions(including type: GraphQLObjectType) -> Set<GraphQLUnionType> {
      typeToUnionMap[type].unsafelyUnwrapped
    }

    public var debugDescription: String {
      TemplateString("""
        objects: [\(list: objects)]
        interfaces: [\(list: interfaces)]
        unions: [\(list: unions)]
        scalars: [\(list: scalars)]
        customScalars: [\(list: customScalars)]
        enums: [\(list: enums)]
        inputObjects: [\(list: inputObjects)]
        """).description
    }
  }
}
