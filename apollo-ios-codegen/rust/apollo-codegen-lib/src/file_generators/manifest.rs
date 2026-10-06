//! Operation manifest file generation for persisted queries.
//!
//! Mirrors Swift's `OperationManifestFileGenerator.swift`,
//! `PersistedQueriesOperationManifestTemplate.swift`, and
//! `LegacyAPQOperationManifestTemplate.swift` from
//! `Sources/ApolloCodegenLib/`.
//!
//! Provides:
//! - `OperationManifestItem`: pairs an `OperationDescriptor` with its identifier string.
//! - `OperationManifestTemplate` trait: renders a list of manifest items to JSON.
//! - `PersistedQueriesOperationManifestTemplate`: version-1 persisted queries format.
//! - `LegacyAPQOperationManifestTemplate`: legacy APQ flat hash-keyed format.
//! - `OperationManifestFileGenerator`: selects template by config version and writes to file.

use std::path::{Path, PathBuf};

use crate::config::operation_manifest::Version;
use super::operation_identifier::{OperationDescriptor, SourceFormat};

// MARK: - OperationManifestItem

/// A single entry in an operation manifest, pairing an operation with its identifier.
///
/// Mirrors Swift's `OperationManifestTemplate.OperationManifestItem` typealias.
pub struct OperationManifestItem<'a> {
    pub operation: OperationDescriptor<'a>,
    pub identifier: String,
}

// MARK: - OperationManifestTemplate

/// Trait for rendering an operation manifest to a string.
///
/// Mirrors Swift's `OperationManifestTemplate` protocol.
pub trait OperationManifestTemplate {
    fn render(&self, operations: &[OperationManifestItem]) -> String;
}

// MARK: - PersistedQueriesOperationManifestTemplate

/// Renders the version-1 persisted queries manifest format.
///
/// Output format:
/// ```json
/// {
///   "format": "apollo-persisted-query-manifest",
///   "version": 1,
///   "operations": [
///     {
///       "id": "...",
///       "body": "...",
///       "name": "...",
///       "type": "query"
///     }
///   ]
/// }
/// ```
///
/// Mirrors Swift's `PersistedQueriesOperationManifestTemplate` struct.
pub struct PersistedQueriesOperationManifestTemplate;

impl OperationManifestTemplate for PersistedQueriesOperationManifestTemplate {
    fn render(&self, operations: &[OperationManifestItem]) -> String {
        let mut result = String::new();
        result.push_str("{\n");
        result.push_str("  \"format\": \"apollo-persisted-query-manifest\",\n");
        result.push_str("  \"version\": 1,\n");
        result.push_str("  \"operations\": [\n");
        for (i, item) in operations.iter().enumerate() {
            result.push_str("    {\n");
            result.push_str(&format!("      \"id\": \"{}\",\n", item.identifier));
            result.push_str(&format!(
                "      \"body\": \"{}\",\n",
                item.operation.source_text(SourceFormat::ManifestJsonBody)
            ));
            result.push_str(&format!("      \"name\": \"{}\",\n", item.operation.name()));
            result.push_str(&format!(
                "      \"type\": \"{}\"\n",
                item.operation.operation_type()
            ));
            result.push_str("    }");
            if i < operations.len() - 1 {
                result.push(',');
            }
            result.push('\n');
        }
        result.push_str("  ]\n");
        result.push('}');
        result
    }
}

// MARK: - LegacyAPQOperationManifestTemplate

/// Renders the legacy APQ manifest format with operation hashes as keys.
///
/// Output format:
/// ```json
/// {
///   "hash1" : {
///     "name": "...",
///     "source": "..."
///   }
/// }
/// ```
///
/// Mirrors Swift's `LegacyAPQOperationManifestTemplate` struct.
pub struct LegacyAPQOperationManifestTemplate;

impl OperationManifestTemplate for LegacyAPQOperationManifestTemplate {
    fn render(&self, operations: &[OperationManifestItem]) -> String {
        let mut result = String::new();
        result.push_str("{\n");
        for (i, item) in operations.iter().enumerate() {
            result.push_str(&format!("  \"{}\" : {{\n", item.identifier));
            result.push_str(&format!("    \"name\": \"{}\",\n", item.operation.name()));
            result.push_str(&format!(
                "    \"source\": \"{}\"\n",
                item.operation.source_text(SourceFormat::ManifestJsonBody)
            ));
            result.push_str("  }");
            if i < operations.len() - 1 {
                result.push(',');
            }
            result.push('\n');
        }
        result.push('}');
        result
    }
}

// MARK: - OperationManifestFileGenerator

/// Generates an operation manifest file, selecting the template based on configuration.
///
/// Mirrors Swift's `OperationManifestFileGenerator` struct from
/// `FileGenerators/OperationManifestFileGenerator.swift`.
pub struct OperationManifestFileGenerator {
    manifest_path: String,
    version: Version,
}

impl OperationManifestFileGenerator {
    /// Creates a new `OperationManifestFileGenerator`.
    ///
    /// # Arguments
    /// * `manifest_path` - The path from the operation manifest configuration.
    /// * `version` - The manifest version format to use.
    /// * `root_url` - Optional root URL for resolving relative paths (paths starting with "./").
    ///
    /// # Panics
    /// This mirrors Swift's `preconditionFailure` -- callers must ensure config has
    /// `operation_manifest` before constructing this.
    pub fn new(manifest_path: &str, version: Version, root_url: Option<&Path>) -> Self {
        let resolved_path = resolve_manifest_path(manifest_path, root_url);
        Self {
            manifest_path: resolved_path,
            version,
        }
    }

    /// Returns the resolved manifest file path.
    pub fn manifest_path(&self) -> &str {
        &self.manifest_path
    }

    /// Returns the version format being used.
    pub fn version(&self) -> Version {
        self.version
    }

    /// Generates the manifest content as a string.
    ///
    /// This renders the manifest using the appropriate template but does not write to disk.
    /// Callers can use a file manager to write the result.
    pub fn generate(&self, manifest_items: &[OperationManifestItem]) -> String {
        let template: Box<dyn OperationManifestTemplate> = match self.version {
            Version::PersistedQueries => Box::new(PersistedQueriesOperationManifestTemplate),
            Version::Legacy => Box::new(LegacyAPQOperationManifestTemplate),
        };
        template.render(manifest_items)
    }

    /// Generates the manifest and writes it to the resolved path.
    ///
    /// Creates parent directories if they don't exist.
    pub fn generate_and_write(
        &self,
        manifest_items: &[OperationManifestItem],
    ) -> Result<(), std::io::Error> {
        let rendered = self.generate(manifest_items);
        let path = PathBuf::from(&self.manifest_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, rendered.as_bytes())?;
        Ok(())
    }
}

// MARK: - Path resolution

/// Resolves a manifest path, handling relative "./" prefix and ".json" suffix.
///
/// If the path starts with "./", it is resolved relative to `root_url`.
/// If the path does not end with ".json", ".json" is appended.
///
/// Mirrors the path resolution logic in Swift's
/// `OperationManifestFileGenerator.generate(operationManifest:fileManager:)`.
fn resolve_manifest_path(manifest_path: &str, root_url: Option<&Path>) -> String {
    let relative_prefix = "./";
    let mut resolved = if manifest_path.starts_with(relative_prefix) {
        let relative_part = &manifest_path[relative_prefix.len()..];
        if let Some(root) = root_url {
            let joined = root.join(relative_part);
            // Normalize the path (resolve ".." components)
            normalize_path(&joined).to_string_lossy().to_string()
        } else {
            relative_part.to_string()
        }
    } else {
        manifest_path.to_string()
    };

    if !resolved.ends_with(".json") {
        resolved.push_str(".json");
    }

    resolved
}

/// Normalizes a path by resolving ".." and "." components lexically.
///
/// Unlike `std::fs::canonicalize`, this does not require the path to exist.
fn normalize_path(path: &Path) -> PathBuf {
    let mut components = Vec::new();
    for component in path.components() {
        match component {
            std::path::Component::ParentDir => {
                if !components.is_empty() {
                    components.pop();
                }
            }
            std::path::Component::CurDir => {}
            _ => {
                components.push(component);
            }
        }
    }
    components.iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::compilation_result::{
        FragmentDefinition, OperationDefinition, OperationType, SelectionSet,
    };
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::{GraphQLCompositeType, GraphQLObjectType};
    use indexmap::IndexMap;
    use std::sync::Arc;

    fn make_composite_object(name: &str) -> GraphQLCompositeType {
        GraphQLCompositeType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }))
    }

    fn make_operation(
        name: &str,
        source: &str,
        op_type: OperationType,
        fragments: Vec<Arc<FragmentDefinition>>,
    ) -> OperationDefinition {
        OperationDefinition {
            name: name.to_string(),
            operation_type: op_type,
            variables: vec![],
            root_type: make_composite_object("Query"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("Query"),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: fragments,
            source: source.to_string(),
            file_path: "test.graphql".to_string(),
        }
    }

    fn make_manifest_item<'a>(
        op: &'a OperationDefinition,
        id: &str,
    ) -> OperationManifestItem<'a> {
        OperationManifestItem {
            operation: OperationDescriptor::new(op),
            identifier: id.to_string(),
        }
    }

    // Test 1: Persisted queries template renders correct JSON with 1 operation
    #[test]
    fn test_persisted_queries_template_single_operation() {
        let op = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let items = vec![make_manifest_item(&op, "abc123hash")];
        let template = PersistedQueriesOperationManifestTemplate;
        let rendered = template.render(&items);

        assert!(rendered.contains("\"format\": \"apollo-persisted-query-manifest\""));
        assert!(rendered.contains("\"version\": 1"));
        assert!(rendered.contains("\"id\": \"abc123hash\""));
        assert!(rendered.contains("\"body\": \"query GetDog { dog { name } }\""));
        assert!(rendered.contains("\"name\": \"GetDog\""));
        assert!(rendered.contains("\"type\": \"query\""));
        // Should be valid-looking JSON structure
        assert!(rendered.starts_with('{'));
        assert!(rendered.ends_with('}'));
    }

    // Test 2: Persisted queries template with 2+ operations (commas between items)
    #[test]
    fn test_persisted_queries_template_multiple_operations() {
        let op1 = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let op2 = make_operation(
            "AddPet",
            "mutation AddPet { addPet { id } }",
            OperationType::Mutation,
            vec![],
        );
        let items = vec![
            make_manifest_item(&op1, "hash1"),
            make_manifest_item(&op2, "hash2"),
        ];
        let template = PersistedQueriesOperationManifestTemplate;
        let rendered = template.render(&items);

        // Should have comma between first and second operation
        assert!(rendered.contains("},\n    {"));
        // Should have both operations
        assert!(rendered.contains("\"name\": \"GetDog\""));
        assert!(rendered.contains("\"name\": \"AddPet\""));
        assert!(rendered.contains("\"type\": \"query\""));
        assert!(rendered.contains("\"type\": \"mutation\""));
    }

    // Test 3: Legacy template renders correct JSON structure
    #[test]
    fn test_legacy_template_renders_correct_json() {
        let op = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let items = vec![make_manifest_item(&op, "abc123hash")];
        let template = LegacyAPQOperationManifestTemplate;
        let rendered = template.render(&items);

        assert!(rendered.contains("\"abc123hash\" : {"));
        assert!(rendered.contains("\"name\": \"GetDog\""));
        assert!(rendered.contains("\"source\": \"query GetDog { dog { name } }\""));
        assert!(rendered.starts_with('{'));
        assert!(rendered.ends_with('}'));
    }

    // Test 4: Legacy template with multiple operations
    #[test]
    fn test_legacy_template_multiple_operations() {
        let op1 = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let op2 = make_operation(
            "GetCat",
            "query GetCat { cat { name } }",
            OperationType::Query,
            vec![],
        );
        let items = vec![
            make_manifest_item(&op1, "hash1"),
            make_manifest_item(&op2, "hash2"),
        ];
        let template = LegacyAPQOperationManifestTemplate;
        let rendered = template.render(&items);

        // Both operations present
        assert!(rendered.contains("\"hash1\" : {"));
        assert!(rendered.contains("\"hash2\" : {"));
        // Comma between items
        assert!(rendered.contains("},\n  \"hash2\""));
    }

    // Test 5: Manifest path with "./" resolves relative to root_url
    #[test]
    fn test_manifest_path_relative_to_root_url() {
        let root = Path::new("/Users/test/project");
        let resolved = resolve_manifest_path("./output/manifest", Some(root));
        assert_eq!(resolved, "/Users/test/project/output/manifest.json");
    }

    // Test 6: Manifest path without ".json" gets ".json" appended
    #[test]
    fn test_manifest_path_appends_json_suffix() {
        let resolved = resolve_manifest_path("/absolute/path/manifest", None);
        assert_eq!(resolved, "/absolute/path/manifest.json");
    }

    // Test 7: Manifest path already ending in ".json" is not double-suffixed
    #[test]
    fn test_manifest_path_no_double_json_suffix() {
        let resolved = resolve_manifest_path("/absolute/path/manifest.json", None);
        assert_eq!(resolved, "/absolute/path/manifest.json");
    }

    // Test 8: OperationManifestFileGenerator selects correct template for PersistedQueries
    #[test]
    fn test_generator_selects_persisted_queries_template() {
        let generator = OperationManifestFileGenerator::new(
            "/tmp/manifest.json",
            Version::PersistedQueries,
            None,
        );
        let op = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let items = vec![make_manifest_item(&op, "hash123")];
        let rendered = generator.generate(&items);
        // Persisted queries format has "format" and "version" fields
        assert!(rendered.contains("\"format\": \"apollo-persisted-query-manifest\""));
        assert!(rendered.contains("\"version\": 1"));
    }

    // Test 9: OperationManifestFileGenerator selects correct template for Legacy
    #[test]
    fn test_generator_selects_legacy_template() {
        let generator = OperationManifestFileGenerator::new(
            "/tmp/manifest.json",
            Version::Legacy,
            None,
        );
        let op = make_operation(
            "GetDog",
            "query GetDog { dog { name } }",
            OperationType::Query,
            vec![],
        );
        let items = vec![make_manifest_item(&op, "hash123")];
        let rendered = generator.generate(&items);
        // Legacy format has hash as key, no "format"/"version" fields
        assert!(rendered.contains("\"hash123\" : {"));
        assert!(!rendered.contains("\"format\""));
    }

    // Test 10: Path resolution with ".." traversal is handled safely
    #[test]
    fn test_manifest_path_traversal_handled_safely() {
        let root = Path::new("/Users/test/project");
        let resolved = resolve_manifest_path("./../../secret", Some(root));
        // Should normalize the ".." components -- resolves to /Users/secret.json
        // The key behavior is that normalize_path handles ".." lexically
        assert!(resolved.ends_with(".json"));
        assert!(!resolved.contains(".."));
    }

    // Test 11: Subscription operation type renders correctly
    #[test]
    fn test_subscription_type_renders_correctly() {
        let op = make_operation(
            "OnMessage",
            "subscription OnMessage { messageAdded { text } }",
            OperationType::Subscription,
            vec![],
        );
        let items = vec![make_manifest_item(&op, "subhash")];
        let template = PersistedQueriesOperationManifestTemplate;
        let rendered = template.render(&items);
        assert!(rendered.contains("\"type\": \"subscription\""));
    }

    // Test 12: Empty operations list renders valid JSON
    #[test]
    fn test_empty_operations_renders_valid_json() {
        let template = PersistedQueriesOperationManifestTemplate;
        let rendered = template.render(&[]);
        assert!(rendered.contains("\"operations\": [\n  ]"));

        let legacy = LegacyAPQOperationManifestTemplate;
        let rendered_legacy = legacy.render(&[]);
        assert_eq!(rendered_legacy, "{\n}");
    }

    // Test 13: Generator stores resolved path
    #[test]
    fn test_generator_stores_resolved_path() {
        let root = Path::new("/Users/test/project");
        let generator = OperationManifestFileGenerator::new(
            "./output/ops",
            Version::PersistedQueries,
            Some(root),
        );
        assert_eq!(
            generator.manifest_path(),
            "/Users/test/project/output/ops.json"
        );
        assert_eq!(generator.version(), Version::PersistedQueries);
    }
}
