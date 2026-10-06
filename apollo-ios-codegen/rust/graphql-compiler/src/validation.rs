//! Operation document validation.
//!
//! Mirrors Swift's `GraphQLJSFrontend.validateDocument(schema:document:validationOptions:)`:
//! every operation file is merged into one document which is validated with graphql-js'
//! `specifiedRules` minus `NoUnusedFragmentsRule`, plus Apollo's own rules from
//! `validationRules.ts` (no anonymous operations, no `__typename` alias, deferred inline
//! fragments need a type condition and a `label`, disallowed field and input parameter
//! names). The JS compiler additionally rejects entity fields whose response key collides
//! with the schema namespace (`compiler/index.ts`, `validateFieldName`).
//!
//! The Rust port validates the merged `ast::Document` with apollo-compiler and reports each
//! diagnostic with graphql-js wording where apollo-compiler provides a compatible message.
//! Errors are rendered as Swift's `GraphQLError.logLines` (`<path>:<line>:error:<message>`),
//! so Xcode can show them inline and callers can compare them with the Swift CLI's output.
//!
//! Nothing in this module panics on malformed input: every problem becomes a
//! [`ValidationError`].

use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use apollo_compiler::ast;
use apollo_compiler::diagnostic::ToCliReport;
use apollo_compiler::executable;
use apollo_compiler::parser::{FileId, Parser, SourceFile, SourceMap, SourceSpan};
use apollo_compiler::schema::{ExtendedType, Schema};
use apollo_compiler::validation::{DiagnosticData, Valid};
use crate::validation_options::ValidationOptions;

/// One operation source file to validate.
#[derive(Debug, Clone, Copy)]
pub struct OperationSource<'a> {
    /// Path the file was discovered at (reported back in error lines).
    pub path: &'a str,
    /// File contents.
    pub text: &'a str,
}

/// A validation error with its source location.
///
/// Mirrors the parts of graphql-js' `GraphQLError` that Swift surfaces (`message` and the
/// first source location).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationError {
    /// Path of the file the error points into, when the error has a location.
    pub file_path: Option<String>,
    /// 1-based line of the first source location, when the error has a location.
    pub line: Option<usize>,
    /// graphql-js compatible message.
    pub message: String,
}

impl ValidationError {
    /// Renders the error the way Swift logs it (`GraphQLError.logLines`), i.e.
    /// `<path>:<line>:error:<message>`. Errors without a location are rendered as
    /// `GraphQLError: <message>` like Swift's fallback for errors without log lines.
    pub fn log_line(&self) -> String {
        match (&self.file_path, self.line) {
            (Some(path), Some(line)) => format!("{}:{}:error:{}", path, line, self.message),
            (None, Some(line)) => format!(":{}:error:{}", line, self.message),
            _ => format!("GraphQLError: {}", self.message),
        }
    }
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.log_line())
    }
}

impl std::error::Error for ValidationError {}

const NO_ANONYMOUS_OPERATIONS: &str = "Apollo does not support anonymous operations because operation names are used during code generation. Please give this operation a name.";
const NO_TYPENAME_ALIAS: &str = "Apollo needs to be able to insert __typename when needed, so using it as an alias is not supported.";
const DEFER_NO_TYPE_CONDITION: &str = "Apollo does not support deferred inline fragments without a type condition. Please add a type condition to this inline fragment.";
const DEFER_MISSING_LABEL: &str = "Apollo does not support deferred inline fragments without a 'label' argument. Please add a 'label' argument to the @defer directive on this inline fragment.";

/// Validates the operation files against the schema.
///
/// Returns every error found, ordered by file (in the order given) and line, or `Ok(())` when
/// the merged document is valid. Syntax errors stop validation of the whole set, like
/// Swift's per-file `parseDocument` does before any validation rule runs.
pub fn validate_operations(
    schema: &Valid<Schema>,
    sources: &[OperationSource<'_>],
    options: &ValidationOptions,
) -> Result<(), Vec<ValidationError>> {
    let file_order: HashMap<&str, usize> = sources
        .iter()
        .enumerate()
        .map(|(i, s)| (s.path, i))
        .collect();

    // 1. Parse every file; syntax errors abort before any rule runs.
    let mut documents = Vec::with_capacity(sources.len());
    let mut syntax_errors = Vec::new();
    for source in sources {
        match Parser::new().parse_ast(source.text, source.path) {
            Ok(doc) => documents.push(doc),
            Err(with_errors) => {
                for diagnostic in with_errors.errors.iter() {
                    syntax_errors.push(diagnostic_error(diagnostic.error, diagnostic.sources));
                }
            }
        }
    }
    if !syntax_errors.is_empty() {
        sort_errors(&mut syntax_errors, &file_order);
        // apollo-compiler reports one diagnostic per missing token; graphql-js reports the
        // first problem once.
        syntax_errors.dedup();
        return Err(syntax_errors);
    }

    // 2. Merge into one document so fragments spread across files resolve, like Swift's
    //    `mergeDocuments`.
    let mut merged = ast::Document::new();
    let mut source_map: apollo_compiler::collections::IndexMap<FileId, Arc<SourceFile>> =
        Default::default();
    for doc in &documents {
        for (id, file) in doc.sources.iter() {
            source_map.insert(*id, Arc::clone(file));
        }
        merged.definitions.extend(doc.definitions.iter().cloned());
    }
    merged.sources = Arc::new(source_map);

    // 3. Apollo's own rules run first (graphql-js runs them in the same visitor pass, before
    //    the specified rules for a given node).
    let mut errors = apollo_rules(&merged, options);

    // 4. graphql-js specified rules minus NoUnusedFragmentsRule.
    match merged.to_executable_validate(schema) {
        Ok(valid) => {
            errors.extend(namespace_conflicts(&valid, schema, options));
        }
        Err(with_errors) => {
            for diagnostic in with_errors.errors.iter() {
                if diagnostic.error.unstable_error_name() == Some("UnusedFragment") {
                    continue;
                }
                errors.push(diagnostic_error(diagnostic.error, diagnostic.sources));
            }
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        sort_errors(&mut errors, &file_order);
        Err(errors)
    }
}

/// Stable sort by (file order, line); errors on the same line keep their reporting order.
fn sort_errors(errors: &mut [ValidationError], file_order: &HashMap<&str, usize>) {
    errors.sort_by_key(|e| {
        let file = e
            .file_path
            .as_deref()
            .and_then(|p| file_order.get(p).copied())
            .unwrap_or(usize::MAX);
        (file, e.line.unwrap_or(0))
    });
}

/// Converts an apollo-compiler diagnostic to a [`ValidationError`] with graphql-js wording
/// when available.
fn diagnostic_error(data: &DiagnosticData, sources: &SourceMap) -> ValidationError {
    let message = match data.unstable_compat_message() {
        Some(message) => message,
        None => {
            let message = data.to_string();
            match message.strip_prefix("syntax error: ") {
                Some(rest) => format!("Syntax Error: {}", rest),
                None => message,
            }
        }
    };
    let (file_path, line) = locate(data.location(), sources);
    ValidationError {
        file_path,
        line,
        message,
    }
}

/// Resolves a source span to (file path, 1-based line).
fn locate(span: Option<SourceSpan>, sources: &SourceMap) -> (Option<String>, Option<usize>) {
    let Some(span) = span else {
        return (None, None);
    };
    let file_path = sources
        .get(&span.file_id())
        .map(|file| file.path().display().to_string());
    let line = span.line_column_range(sources).map(|range| range.start.line);
    (file_path, line)
}

/// `charAt(0).toLowerCase() + slice(1)`, as in `validationRules.ts`.
fn first_lowercased(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().chain(chars).collect(),
        None => String::new(),
    }
}

/// Apollo's custom validation rules from `validationRules.ts`, evaluated on the AST.
fn apollo_rules(document: &ast::Document, options: &ValidationOptions) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    let sources = &document.sources;
    let mut report = |span: Option<SourceSpan>, message: String| {
        let (file_path, line) = locate(span, sources);
        errors.push(ValidationError {
            file_path,
            line,
            message,
        });
    };

    for definition in &document.definitions {
        match definition {
            ast::Definition::OperationDefinition(op) => {
                if op.name.is_none() {
                    report(op.location(), NO_ANONYMOUS_OPERATIONS.to_string());
                }
                for variable in &op.variables {
                    let name = variable.name.as_str();
                    if options
                        .disallowed_input_parameter_names
                        .contains(&first_lowercased(name))
                    {
                        report(
                            variable.location(),
                            format!(
                                "Input Parameter name \"{}\" is not allowed because it conflicts with generated object APIs.",
                                name
                            ),
                        );
                    }
                }
                apollo_selection_rules(&op.selection_set, options, &mut report);
            }
            ast::Definition::FragmentDefinition(fragment) => {
                apollo_selection_rules(&fragment.selection_set, options, &mut report);
            }
            _ => {}
        }
    }
    errors
}

fn apollo_selection_rules(
    selections: &[ast::Selection],
    options: &ValidationOptions,
    report: &mut impl FnMut(Option<SourceSpan>, String),
) {
    for selection in selections {
        match selection {
            ast::Selection::Field(field) => {
                if field.alias.as_ref().map(|a| a.as_str()) == Some("__typename") {
                    report(field.location(), NO_TYPENAME_ALIAS.to_string());
                }
                let response_key = field
                    .alias
                    .as_ref()
                    .map(|a| a.as_str())
                    .unwrap_or(field.name.as_str());
                if options
                    .disallowed_field_names
                    .all_fields
                    .contains(&first_lowercased(response_key))
                {
                    report(
                        field.location(),
                        format!(
                            "Field name \"{}\" is not allowed because it conflicts with generated object APIs. Please use an alias to change the field name.",
                            response_key
                        ),
                    );
                }
                apollo_selection_rules(&field.selection_set, options, report);
            }
            ast::Selection::InlineFragment(inline) => {
                for directive in inline.directives.iter() {
                    if directive.name.as_str() != "defer" {
                        continue;
                    }
                    if inline.type_condition.is_none() {
                        report(inline.location(), DEFER_NO_TYPE_CONDITION.to_string());
                    }
                    if !directive.arguments.iter().any(|a| a.name.as_str() == "label") {
                        report(inline.location(), DEFER_MISSING_LABEL.to_string());
                    }
                }
                apollo_selection_rules(&inline.selection_set, options, report);
            }
            ast::Selection::FragmentSpread(_) => {}
        }
    }
}

/// The JS compiler's `validateFieldName` check: an entity (or entity list) field whose
/// response key equals the (singular/plural) schema namespace would collide with the
/// generated `<Namespace>` enum, so Swift throws a `GraphQLError` while compiling.
fn namespace_conflicts(
    document: &Valid<executable::ExecutableDocument>,
    schema: &Valid<Schema>,
    options: &ValidationOptions,
) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    let sources = &document.sources;
    let message = || {
        let ns = &options.schema_namespace;
        format!(
            "Schema name \"{ns}\" conflicts with name of a generated object API. Please choose a different schema name. Suggestions: \"{ns}Schema\", \"{ns}GraphQL\", \"{ns}API\""
        )
    };

    fn walk(
        selections: &[executable::Selection],
        schema: &Valid<Schema>,
        options: &ValidationOptions,
        sources: &SourceMap,
        message: &dyn Fn() -> String,
        errors: &mut Vec<ValidationError>,
    ) {
        for selection in selections {
            match selection {
                executable::Selection::Field(field) => {
                    let response_key = first_lowercased(field.response_key().as_str());
                    let ty = &field.definition.ty;
                    let is_list = ty.is_list();
                    let is_composite = matches!(
                        schema.types.get(ty.inner_named_type()),
                        Some(ExtendedType::Object(_))
                            | Some(ExtendedType::Interface(_))
                            | Some(ExtendedType::Union(_))
                    );
                    let conflicts = if is_list {
                        options.disallowed_field_names.entity_list.contains(&response_key)
                    } else if is_composite {
                        options.disallowed_field_names.entity.contains(&response_key)
                    } else {
                        false
                    };
                    if conflicts {
                        let (file_path, line) = locate(field.location(), sources);
                        errors.push(ValidationError {
                            file_path,
                            line,
                            message: message(),
                        });
                    }
                    walk(
                        &field.selection_set.selections,
                        schema,
                        options,
                        sources,
                        message,
                        errors,
                    );
                }
                executable::Selection::InlineFragment(inline) => walk(
                    &inline.selection_set.selections,
                    schema,
                    options,
                    sources,
                    message,
                    errors,
                ),
                executable::Selection::FragmentSpread(_) => {}
            }
        }
    }

    for operation in document.operations.iter() {
        walk(
            &operation.selection_set.selections,
            schema,
            options,
            sources,
            &message,
            &mut errors,
        );
    }
    for fragment in document.fragments.values() {
        walk(
            &fragment.selection_set.selections,
            schema,
            options,
            sources,
            &message,
            &mut errors,
        );
    }
    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::validation_options::DisallowedFieldNames;
    use indexmap::IndexSet;

    const SCHEMA: &str = r#"
        directive @defer(label: String, if: Boolean! = true) on FRAGMENT_SPREAD | INLINE_FRAGMENT
        directive @import(module: String!) repeatable on QUERY | MUTATION | SUBSCRIPTION | FRAGMENT_DEFINITION
        type Query { pet(id: ID!): Pet, pets: [Pet!]!, me: User }
        interface Pet { id: ID!, name: String! }
        type Dog implements Pet { id: ID!, name: String!, bark: Boolean }
        type User { id: ID!, name: String, friends(first: Int): [User!] }
        enum Color { RED, GREEN }
        input PetFilter { color: Color, name: String }
    "#;

    fn schema() -> Valid<Schema> {
        Schema::parse_and_validate(SCHEMA, "schema.graphqls").expect("test schema is valid")
    }

    fn options() -> ValidationOptions {
        ValidationOptions {
            schema_namespace: "Inv".to_string(),
            disallowed_field_names: DisallowedFieldNames {
                all_fields: ["__data", "fragments"].into_iter().map(String::from).collect(),
                entity: IndexSet::from(["inv".to_string()]),
                entity_list: IndexSet::from(["invs".to_string()]),
            },
            disallowed_input_parameter_names: ["self", "_", "inv"]
                .into_iter()
                .map(String::from)
                .collect(),
        }
    }

    fn validate(files: &[(&str, &str)]) -> Result<(), Vec<ValidationError>> {
        let sources: Vec<OperationSource<'_>> = files
            .iter()
            .map(|(path, text)| OperationSource { path, text })
            .collect();
        validate_operations(&schema(), &sources, &options())
    }

    fn lines(files: &[(&str, &str)]) -> Vec<String> {
        validate(files)
            .expect_err("expected validation errors")
            .iter()
            .map(ValidationError::log_line)
            .collect()
    }

    #[test]
    fn valid_document_passes() {
        assert_eq!(validate(&[("q.graphql", "query Q { pets { id name } }")]), Ok(()));
    }

    #[test]
    fn fragments_resolve_across_files() {
        assert_eq!(
            validate(&[
                ("q.graphql", "query Q { pets { ...Bits } }"),
                ("f.graphql", "fragment Bits on Pet { id }"),
            ]),
            Ok(())
        );
    }

    #[test]
    fn unused_fragments_are_allowed() {
        assert_eq!(
            validate(&[
                ("q.graphql", "query Q { pets { id } }"),
                ("f.graphql", "fragment Unused on Dog { bark }"),
            ]),
            Ok(())
        );
    }

    #[test]
    fn unknown_fragment_is_an_error_line() {
        assert_eq!(
            lines(&[("q.graphql", "query Q {\n  pets { ...PetDetails }\n}")]),
            vec!["q.graphql:2:error:Unknown fragment \"PetDetails\".".to_string()]
        );
    }

    #[test]
    fn unknown_field_type_directive_and_argument() {
        let errors = lines(&[(
            "q.graphql",
            "query Q($c: Nope) { pets @nope { nope } pet(nope: 1) { id } }",
        )]);
        assert!(errors.iter().any(|l| l.contains("Unknown type \"Nope\".")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Unknown directive \"@nope\".")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Cannot query field \"nope\" on type \"Pet\".")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Unknown argument \"nope\" on field \"Query.pet\".")), "{:?}", errors);
        assert!(errors.iter().all(|l| l.starts_with("q.graphql:1:error:")), "{:?}", errors);
    }

    #[test]
    fn fragment_cycle_is_an_error() {
        let errors = lines(&[(
            "q.graphql",
            "fragment A on Dog { ...B } fragment B on Dog { ...A } query Q { pets { ...A } }",
        )]);
        assert!(errors.iter().any(|l| l.contains("Cannot spread fragment \"A\" within itself")), "{:?}", errors);
    }

    #[test]
    fn syntax_error_is_reported_with_graphql_js_prefix() {
        let errors = lines(&[("q.graphql", "query Q { pets { id ")]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        assert!(errors[0].starts_with("q.graphql:1:error:Syntax Error: "), "{:?}", errors);
    }

    #[test]
    fn anonymous_operation_is_rejected() {
        assert_eq!(
            lines(&[("q.graphql", "{ pets { id } }")]),
            vec![format!("q.graphql:1:error:{}", NO_ANONYMOUS_OPERATIONS)]
        );
    }

    #[test]
    fn typename_alias_is_rejected() {
        assert_eq!(
            lines(&[("q.graphql", "query Q { pets { __typename: name } }")]),
            vec![format!("q.graphql:1:error:{}", NO_TYPENAME_ALIAS)]
        );
    }

    #[test]
    fn deferred_inline_fragment_rules() {
        assert_eq!(
            lines(&[("q.graphql", "query Q { pets { ... @defer { id } } }")]),
            vec![
                format!("q.graphql:1:error:{}", DEFER_NO_TYPE_CONDITION),
                format!("q.graphql:1:error:{}", DEFER_MISSING_LABEL),
            ]
        );
        assert_eq!(
            validate(&[("q.graphql", "query Q { pets { ... on Dog @defer(label: \"x\") { bark } } }")]),
            Ok(())
        );
        let errors = lines(&[("q.graphql", "query Q { pets { ... on Dog @defer(label: \"x\", if: 3) { bark } } }")]);
        assert!(errors.iter().any(|l| l.contains("Boolean cannot represent value: 3")), "{:?}", errors);
    }

    #[test]
    fn disallowed_field_and_parameter_names() {
        let errors = lines(&[(
            "q.graphql",
            "query Q($self: Int, $inv: Int) { me { fragments: name __data: id friends(first: $self) { id } friends(first: $inv) { id } } }",
        )]);
        assert!(errors.iter().any(|l| l.contains("Input Parameter name \"self\" is not allowed")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Input Parameter name \"inv\" is not allowed")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Field name \"fragments\" is not allowed")), "{:?}", errors);
        assert!(errors.iter().any(|l| l.contains("Field name \"__data\" is not allowed")), "{:?}", errors);
    }

    #[test]
    fn schema_namespace_conflicts_with_entity_fields() {
        let errors = lines(&[("q.graphql", "query Q { inv: me { id } }")]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        assert!(errors[0].contains("Schema name \"Inv\" conflicts with name of a generated object API"), "{:?}", errors);
        let errors = lines(&[("q.graphql", "query Q { invs: pets { id } }")]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        // Scalar fields never conflict.
        assert_eq!(validate(&[("q.graphql", "query Q { me { inv: name } }")]), Ok(()));
    }

    #[test]
    fn errors_are_ordered_by_file_then_line() {
        let errors = lines(&[
            ("a.graphql", "query A {\n pets { ...Nope } }"),
            ("b.graphql", "query B { pets { nope } }"),
        ]);
        assert!(errors[0].starts_with("a.graphql:2:"), "{:?}", errors);
        assert!(errors[1].starts_with("b.graphql:1:"), "{:?}", errors);
    }

    #[test]
    fn log_line_without_location() {
        let error = ValidationError {
            file_path: None,
            line: None,
            message: "boom".to_string(),
        };
        assert_eq!(error.log_line(), "GraphQLError: boom");
    }
}
