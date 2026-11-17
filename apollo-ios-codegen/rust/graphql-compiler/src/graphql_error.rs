use std::fmt;

use serde::Serialize;

use crate::graphql_source::GraphQLSourceLocation;

/// A GraphQL error.
/// Mirrors `GraphQLError` from `GraphQLError.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLError {
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_locations: Option<Vec<GraphQLSourceLocation>>,
}

impl GraphQLError {
    /// Log lines for this error in a format that allows Xcode to show errors
    /// inline at the correct location.
    pub fn log_lines(&self) -> Option<Vec<String>> {
        self.source_locations.as_ref().map(|locations| {
            locations
                .iter()
                .map(|loc| {
                    format!(
                        "{}:{}:error:{}",
                        loc.file_path.as_deref().unwrap_or(""),
                        loc.line_number,
                        &self.message,
                    )
                })
                .collect()
        })
    }
}

impl fmt::Display for GraphQLError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for GraphQLError {}

/// A GraphQL schema validation error. This wraps one or more underlying
/// validation errors.
/// Mirrors `GraphQLSchemaValidationError` from `GraphQLError.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLSchemaValidationError {
    pub validation_errors: Vec<GraphQLError>,
}

impl fmt::Display for GraphQLSchemaValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (i, err) in self.validation_errors.iter().enumerate() {
            if i > 0 {
                writeln!(f)?;
            }
            write!(f, "{}", err)?;
        }
        Ok(())
    }
}

impl std::error::Error for GraphQLSchemaValidationError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_graphql_error_stores_message_and_locations() {
        let error = GraphQLError {
            message: "Syntax error".to_string(),
            source_locations: Some(vec![GraphQLSourceLocation {
                file_path: Some("schema.graphql".to_string()),
                line_number: 10,
                column_number: 5,
            }]),
        };
        assert_eq!(error.message, "Syntax error");
        assert_eq!(error.source_locations.as_ref().unwrap().len(), 1);
    }

    #[test]
    fn test_graphql_error_log_lines() {
        let error = GraphQLError {
            message: "Unknown type".to_string(),
            source_locations: Some(vec![
                GraphQLSourceLocation {
                    file_path: Some("a.graphql".to_string()),
                    line_number: 5,
                    column_number: 3,
                },
                GraphQLSourceLocation {
                    file_path: Some("b.graphql".to_string()),
                    line_number: 12,
                    column_number: 1,
                },
            ]),
        };

        let lines = error.log_lines().unwrap();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0], "a.graphql:5:error:Unknown type");
        assert_eq!(lines[1], "b.graphql:12:error:Unknown type");
    }

    #[test]
    fn test_graphql_error_log_lines_none_when_no_locations() {
        let error = GraphQLError {
            message: "Error".to_string(),
            source_locations: None,
        };
        assert!(error.log_lines().is_none());
    }

    #[test]
    fn test_graphql_error_display() {
        let error = GraphQLError {
            message: "Something went wrong".to_string(),
            source_locations: None,
        };
        assert_eq!(format!("{}", error), "Something went wrong");
    }

    #[test]
    fn test_schema_validation_error_display() {
        let error = GraphQLSchemaValidationError {
            validation_errors: vec![
                GraphQLError {
                    message: "Error 1".to_string(),
                    source_locations: None,
                },
                GraphQLError {
                    message: "Error 2".to_string(),
                    source_locations: None,
                },
            ],
        };
        assert_eq!(format!("{}", error), "Error 1\nError 2");
    }
}
