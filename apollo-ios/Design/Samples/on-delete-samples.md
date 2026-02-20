# `@onDelete` Examples

## Example 1

In this example, the `book` field referenced by the `Author` type is not deleted from the cache when the `Author` is deleted. This is because by default, composite types aren't deleted from the cache when an object that references them is deleted. Only scalar fields are deleted by default.

```graphql
type Author {
  id: ID!
  firstName: String!
  lastName: String!
  book: Book!
}

type Book {
  id: ID!
  title: String!
}
```

## Example 2

In this example, the `@onDelete` directive is used on the `book` field to say that the `Book` object associated with the `Author` should be deleted from the cache whenever the `Author` is deleted.

```graphql
type Author {
  id: ID!
  firstName: String!
  lastName: String!
  book: Book! @onDelete(cascade: true)
}

type Book {
  id: ID!
  title: String!
}
```