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
//      self.allTypes = OrderedSet(types.map { NamedType($0) })
      self.schemaRootTypes = schemaRootTypes

      var allTypes = OrderedSet<NamedType>()
      var objects = OrderedSet<ObjectType>()
      var interfaces = OrderedSet<InterfaceType>()
      var unions = OrderedSet<UnionType>()
      var scalars = OrderedSet<ScalarType>()
      var customScalars = OrderedSet<ScalarType>()
      var enums = OrderedSet<EnumType>()
      var inputObjects = OrderedSet<InputObjectType>()

      for type in types {
        switch type {
        case let type as GraphQLObjectType: 
          let irObject = ObjectType(type)
          objects.append(irObject)
          allTypes.append(irObject)
        case let type as GraphQLInterfaceType:
          let irInterace = InterfaceType(type)
          interfaces.append(irInterace)
          allTypes.append(irInterace)
        case let type as GraphQLUnionType:
          let irUnion = UnionType(type)
          unions.append(irUnion)
          allTypes.append(irUnion)
        case let type as GraphQLScalarType:
          let irScalar = ScalarType(type)
          if type.isCustomScalar {
            customScalars.append(irScalar)
          } else {
            scalars.append(irScalar)
          }
          allTypes.append(irScalar)
        case let type as GraphQLEnumType:
          let irEnum = EnumType(type)
          enums.append(irEnum)
          allTypes.append(irEnum)
        case let type as GraphQLInputObjectType:
          let irInputObject = InputObjectType(type)
          inputObjects.append(irInputObject)
          allTypes.append(irInputObject)
        default: continue
        }
      }

      self.allTypes = allTypes
      self.objects = objects
      self.interfaces = interfaces
      self.unions = unions
      self.scalars = scalars
      self.customScalars = customScalars
      self.enums = enums
      self.inputObjects = inputObjects
      
      for objType in self.objects {
        for graphqlInterface in objType.graphqlObjectType.interfaces {
          if let irInterface = self.interfaces.first(where: { $0.graphqlInterfaceType == graphqlInterface }) {
            objType.interfaces.append(irInterface)
          }
        }
      }
      
      for unionType in self.unions {
        for graphqlObject in unionType.graphqlUnionType.types {
          if let irObject = self.objects.first(where: { $0.graphqlObjectType == graphqlObject }) {
            unionType.types.append(irObject)
          }
        }
      }

      var typeToUnionMap: [ObjectType: Set<UnionType>] = [:]
      objects.forEach { type in
        typeToUnionMap[type] = Set(unions.filter {
          $0.types.contains(type)
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
