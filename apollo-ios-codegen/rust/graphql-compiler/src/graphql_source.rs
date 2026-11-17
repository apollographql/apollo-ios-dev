use serde::Serialize;

/// A representation of source input to GraphQL parsing.
/// Mirrors `GraphQLSource` from `GraphQLSource.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct GraphQLSource {
    pub file_path: String,
    pub body: String,
}

/// Represents a location in a GraphQL source file.
/// Mirrors `GraphQLSourceLocation` from `GraphQLSource.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct GraphQLSourceLocation {
    pub file_path: Option<String>,
    pub line_number: usize,
    pub column_number: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_graphql_source_stores_file_path_and_body() {
        let source = GraphQLSource {
            file_path: "schema.graphql".to_string(),
            body: "type Query { hello: String }".to_string(),
        };
        assert_eq!(source.file_path, "schema.graphql");
        assert_eq!(source.body, "type Query { hello: String }");
    }

    #[test]
    fn test_graphql_source_location_stores_fields() {
        let loc = GraphQLSourceLocation {
            file_path: Some("schema.graphql".to_string()),
            line_number: 10,
            column_number: 5,
        };
        assert_eq!(loc.file_path, Some("schema.graphql".to_string()));
        assert_eq!(loc.line_number, 10);
        assert_eq!(loc.column_number, 5);
    }

    #[test]
    fn test_graphql_source_location_optional_file_path() {
        let loc = GraphQLSourceLocation {
            file_path: None,
            line_number: 1,
            column_number: 1,
        };
        assert!(loc.file_path.is_none());
    }
}
