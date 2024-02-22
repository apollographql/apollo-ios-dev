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
    public let allTypes: OrderedSet<NamedType>
    public let schemaRootTypes: CompilationResult.RootTypeDefinition

    public let objects: OrderedSet<ObjectType>
    public let interfaces: OrderedSet<InterfaceType>
    public let unions: OrderedSet<UnionType>
    public let scalars: OrderedSet<ScalarType>
    public let customScalars: OrderedSet<ScalarType>
    public let enums: OrderedSet<EnumType>
    public let inputObjects: OrderedSet<InputObjectType>

    private let typeToUnionMap: [ObjectType: Set<UnionType>]

    init(
      _ types: [GraphQLNamedType],
      schemaRootTypes: CompilationResult.RootTypeDefinition
    ) {
      self.allTypes = OrderedSet(types.map { NamedType($0) })
      self.schemaRootTypes = schemaRootTypes

      var objects = OrderedSet<ObjectType>()
      var interfaces = OrderedSet<InterfaceType>()
      var unions = OrderedSet<UnionType>()
      var scalars = OrderedSet<ScalarType>()
      var customScalars = OrderedSet<ScalarType>()
      var enums = OrderedSet<EnumType>()
      var inputObjects = OrderedSet<InputObjectType>()

      for type in allTypes {
        switch type {
        case let type as ObjectType: objects.append(type)
        case let type as InterfaceType: interfaces.append(type)
        case let type as UnionType: unions.append(type)
        case let type as ScalarType:
          if type.isCustomScalar {
            customScalars.append(type)
          } else {
            scalars.append(type)
          }
        case let type as EnumType: enums.append(type)
        case let type as InputObjectType: inputObjects.append(type)
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

      var typeToUnionMap: [ObjectType: Set<UnionType>] = [:]
      objects.forEach { type in
        typeToUnionMap[type] = Set(unions.filter {
          $0.types.contains(type.graphqlObjectType)
        })
      }
      self.typeToUnionMap = typeToUnionMap
    }

    public func unions(including type: ObjectType) -> Set<UnionType> {
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
