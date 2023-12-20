import Foundation
import GraphQLCompiler
import Utilities

public class DefinitionEntityStorage {
  let sourceDefinition: Entity.Location.SourceDefinition
  private(set) var entitiesForFields: [Entity.Location: Entity] = [:]

  init(rootEntity: Entity) {
    self.sourceDefinition = rootEntity.location.source
    self.entitiesForFields[rootEntity.location] = rootEntity
  }

  func entity(
    for field: CompilationResult.Field,
    on enclosingEntity: Entity
  ) -> Entity {
    precondition(
      enclosingEntity.location.source == self.sourceDefinition,
      "Enclosing entity from other source definition is invalid."
    )

    let location = enclosingEntity
      .location
      .appending(.init(name: field.responseKey, type: field.type))

    var rootTypePath: LinkedList<GraphQLCompositeType> {
      guard let fieldType = field.selectionSet?.parentType else {
        fatalError("Entity cannot be created for non-entity type field \(field).")
      }
      return enclosingEntity.rootTypePath.appending(fieldType)
    }

    return entitiesForFields[location] ??
    createEntity(location: location, rootTypePath: rootTypePath)
  }

  func entity(
    for entityInFragment: Entity,
    inFragmentSpreadAtTypePath fragmentSpreadTypeInfo: SelectionSet.TypeInfo
  ) -> Entity {
    precondition(
      fragmentSpreadTypeInfo.entity.location.source == self.sourceDefinition,
      "Enclosing entity from fragment spread in other source definition is invalid."
    )

    var location = fragmentSpreadTypeInfo.entity.location
    if let pathInFragment = entityInFragment.location.fieldPath {
      location = location.appending(pathInFragment)
    }

    var rootTypePath: LinkedList<GraphQLCompositeType> {
      let otherRootTypePath = entityInFragment.rootTypePath.dropFirst()
      return fragmentSpreadTypeInfo.entity.rootTypePath.appending(otherRootTypePath)
    }

    return entitiesForFields[location] ??
    createEntity(location: location, rootTypePath: rootTypePath)
  }

  private func createEntity(
    location: Entity.Location,
    rootTypePath: LinkedList<GraphQLCompositeType>
  ) -> Entity {
    let entity = Entity(location: location, rootTypePath: rootTypePath)
    entitiesForFields[location] = entity
    return entity
  }

}
