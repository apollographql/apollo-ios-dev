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

  private init(
    sourceDefinition: Entity.Location.SourceDefinition,
    entitiesForFields: [Entity.Location: Entity]
  ) {
    self.sourceDefinition = sourceDefinition
    self.entitiesForFields = entitiesForFields
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

extension DefinitionEntityStorage {
  func partial() -> DefinitionEntityStorage {
    return DefinitionEntityStorage(
      sourceDefinition: sourceDefinition,
      entitiesForFields: makePartialEntitiesForFields()
    )
  }

  private func makePartialEntitiesForFields() -> [Entity.Location: Entity] {
    var partialEntitiesForFields: [Entity.Location: Entity] = [:]
    for (location, entity) in entitiesForFields {
      /*
       Based on my understanding:
       Fragment rendering points to these entities.
       Whenever we try to render a top-level fragment spread, it resolves the fragment from the entity storage.
       In theory, the generation flow needs the types and entities to spread, fragments, and their underlying entities,
       hence the hardcoded 'count < 4'.

       Possibly, could iterate through the field path and exclude irrelevant entities rather than a hardcoded value?

       */
      if let count = location.fieldPath?.count, count < 4 {
        partialEntitiesForFields[location] = entity
      }
      if location.fieldPath == nil {
        partialEntitiesForFields[location] = entity
      }
    }
    return partialEntitiesForFields
  }
}

