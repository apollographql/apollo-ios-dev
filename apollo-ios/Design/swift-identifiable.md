# Summary

This document proposes a new GraphQL directive named `@identity`, to be used to mark a field which can uniquely identify an object.

# Introduction

SwiftUI makes heavy use of the [Identifiable](https://developer.apple.com/documentation/swift/identifiable) protocol, which is used to track the identity of entities across data changes. If an object with a List is replaced with a different object with the same identity, SwiftUI will animate the item changing instead of animating an insertion. Objects that do not conform to the Identifiable protocol require additional boilerplate to be usable inside SwiftUI.

Apollo Client iOS could assist the developer by adding conformance to the Identifiable protocol to its generated models. Selecting the field to be used as an identity is done by adding a new GraphQL directive.

A concept of identity is required to allow response objects to be cached. The various Apollo Client projects have mechanisms that allow for identifiers to be selected through additional code. The new directive could allow schema authors to assist client authors with caching.

# Definition

The directive is defined as:
```graphql
directive @identity(scope: IdentityScope = SELECTION) on FIELD | FIELD_DEFINITION

enum IdentityScope {
  SELECTION
  TYPE
  SERVICE
  GLOBAL
}
```

This directive MUST be used on a field with a non-nullable scalar type. Other types are not supported.

## Scope parameter

The directive can have a parameter indicating the scope of the identity. They are ordered from _narrowest_ to _widest_:

1. `SELECTION`: The identifier is only unique within the current list. Identifiers may be reused between different objects with the same typename.
2. `TYPE`: The identifier is unique for the type, e.g. an auto-incrementing column from a database table.
3. `SERVICE`: The identifier is unique across the current GraphQL Service.
4. `GLOBAL`: The identifier is unique across all GraphQL services. This can be used by identifiers generated according to [RFC 4122](https://datatracker.ietf.org/doc/html/rfc4122) or [RFC 9562](https://datatracker.ietf.org/doc/html/rfc9562) (also known as Universally Unique IDentifiers or UUIDs).

## Usage in types

A type MAY have a field annotated with the directive.

```graphql
type Animal {
	id: ID! @identity(scope: SERVICE)
	name: String
}
```

Within a type, the directive MUST NOT be used on more than one field.

## Usage in interfaces

It's possible for interfaces to use the directive on a field.

```graphql
interface Identifiable {
	id: ID! @identity(scope: TYPE)
}
```

Implementations of this interface MUST copy the directive to the same field. The scope argument in the implementation MUST NOT be narrower than the scope in the interface, but it may be wider.

## Usage in operations

It's likely that an external schema will not use this directive. In this case, an identity MAY be chosen when writing a query. The directive SHOULD NOT be included in the query sent to the GraphQL server.

```graphql
query GetAllAnimals {
	allAnimals {
		id @identity
		string
	}
}
```

It is allowed for a query and a type to both use the directive to describe the same field. If the schema and client define different scopes for the same field, the widest option is used. This allows client authors to widen the scope if required.

If the server defines a field as an identity, a query SHOULD NOT choose another field. A query MUST NOT use the directive on more than one field in the same selection (unless they are in differently nested objects).

## Protocol conformance

If an operation contains a field marked with the `@identity` directive (by either the schema or the operation itself), the generated SelectionSet will have a conformance to the Identifiable protocol. Since the [Swift documentation](https://developer.apple.com/documentation/swift/identifiable) states that the scope and duration of an identity is unspecified, the scope parameter is ignored when deciding to add a conformance.

```swift
// Inline selection
public struct Data: AnimalKingdomAPI.SelectionSet, Identifiable { /* ... */ }

// Fragment selection
public struct PetDetails: AnimalKingdomAPI.SelectionSet, Fragment, Identifiable { /* ... */ }
```

The protocol requires that the identity is accessible through a public field named exactly `id`. If the annotated field has a different name, an additional getter will be generated:

```swift
public var id: String { self.uuid }
```

### Naming conflicts

If the identity field is not called `id`, but another field called `id` is present in the selection, a custom getter cannot be added. Swift does not support using another field to handle the conformance.

In this case, a conformance to Identifiable SHOULD NOT be generated. Codegen should emit a warning without stopping the generation process.

## Caching behavior

A scope of `SELECTION` does not allow the identifier to be used as a caching key. Clients MAY use other mechanisms to determine if and how to cache the object.

An identifier with scope `TYPE` can be combined with the `__typename` field to generate a caching key that's unique for the GraphQL Service.

Identifiers with a scope of `SERVICE` or `GLOBAL` can be directly used as a caching key.

# Alternatives

## Automatic conformance to Identifiable

The code generator could be updated to always emit a conformance to Identifiable if a scalar `id` field is present in the selection set, removing the need for a custom directive. This was suggested in Pull Request [#548](https://github.com/apollographql/apollo-ios-dev/pull/548).

## Apollo Kotlin's @typePolicy directive

Apollo Kotlin has [custom directives](https://www.apollographql.com/docs/kotlin/caching/declarative-ids) that allows for client authors to specify the caching key though pure GraphQL:

```graphql
extend type Book @typePolicy(keyFields: "id")
```

This could be used for Identifiable conformance if a single field is provided, and caching behavior could also be matched with Apollo Kotlin. A disadvantage is that this directive is only used inside type extensions, and can't be used to mark fields directly in a query.
