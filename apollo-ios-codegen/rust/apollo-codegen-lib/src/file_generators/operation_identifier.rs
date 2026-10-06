//! Operation identifier generation for persisted queries.
//!
//! Mirrors Swift's `OperationDescriptor.swift` and `OperationIdentifierFactory.swift`
//! from `Sources/ApolloCodegenLib/`.
//!
//! Provides:
//! - `OperationDescriptor`: wraps a `CompilationResult.OperationDefinition` with
//!   source text formatting for raw and manifest JSON body formats.
//! - `compute_identifier`: computes SHA256 hex digest of operation source text.

use std::collections::BTreeSet;

use graphql_compiler::compilation_result::{FragmentDefinition, OperationDefinition, OperationType};
use sha2::{Digest, Sha256};

use crate::templates::rendering_helpers::string_single_line::converted_to_single_line;

// MARK: - SourceFormat

/// The format for operation source text output.
///
/// Mirrors Swift's `OperationDescriptor.SourceFormat` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceFormat {
    /// The source text formatted exactly as it will be sent via network transport.
    /// Used to calculate the operation identifier for a persisted queries manifest.
    ///
    /// Fragments are separated by `\n` (actual newline character).
    RawSource,

    /// The source text formatted for inclusion as the "body" field in a JSON manifest.
    /// Escapes newline characters between fragments as literal `\n` and double quotes
    /// as `\"`.
    ManifestJsonBody,
}

// MARK: - OperationDescriptor

/// Wraps a `CompilationResult.OperationDefinition` with source text formatting.
///
/// Mirrors Swift's `OperationDescriptor` struct from `OperationDescriptor.swift`.
pub struct OperationDescriptor<'a> {
    definition: &'a OperationDefinition,
}

impl<'a> OperationDescriptor<'a> {
    /// Creates a new `OperationDescriptor` wrapping the given operation definition.
    pub fn new(definition: &'a OperationDefinition) -> Self {
        Self { definition }
    }

    /// Returns the operation name.
    pub fn name(&self) -> &str {
        &self.definition.name
    }

    /// Returns the file path of the operation definition.
    pub fn file_path(&self) -> &str {
        &self.definition.file_path
    }

    /// Returns the operation type (query, mutation, subscription).
    pub fn operation_type(&self) -> &OperationType {
        &self.definition.operation_type
    }

    /// The source text formatted as raw source (for identifier computation).
    ///
    /// Mirrors Swift's `OperationDescriptor.rawSourceText` computed property.
    pub fn raw_source_text(&self) -> String {
        self.source_text(SourceFormat::RawSource)
    }

    /// The source text formatted according to the given `SourceFormat`.
    ///
    /// Mirrors Swift's `OperationDescriptor.sourceText(withFormat:)` method.
    ///
    /// For `RawSource`: operation source (single-line) + `\n` + each fragment source (single-line).
    /// For `ManifestJsonBody`: same but with literal `\n` between fragments, and double quotes escaped.
    pub fn source_text(&self, format: SourceFormat) -> String {
        let mut source = converted_to_single_line(&self.definition.source);

        for fragment in self.all_referenced_fragments() {
            match format {
                SourceFormat::RawSource => {
                    source.push('\n');
                    source.push_str(&converted_to_single_line(&fragment.source));
                }
                SourceFormat::ManifestJsonBody => {
                    source.push_str("\\n");
                    source.push_str(&converted_to_single_line(&fragment.source));
                }
            }
        }

        match format {
            SourceFormat::RawSource => source,
            SourceFormat::ManifestJsonBody => source.replace('"', "\\\""),
        }
    }

    /// Recursively collects all transitively referenced fragments, deduplicates by name,
    /// and returns them sorted by name.
    ///
    /// Mirrors Swift's `OperationDescriptor.allReferencedFragments` computed property.
    fn all_referenced_fragments(&self) -> Vec<&FragmentDefinition> {
        fn insert_all<'b>(
            frag: &'b FragmentDefinition,
            seen_names: &mut BTreeSet<String>,
            collected: &mut Vec<&'b FragmentDefinition>,
        ) {
            if seen_names.insert(frag.name.clone()) {
                collected.push(frag);
                for referenced in &frag.referenced_fragments {
                    insert_all(referenced, seen_names, collected);
                }
            }
        }

        let mut collected = Vec::new();
        let mut seen = BTreeSet::new();
        for frag in &self.definition.referenced_fragments {
            insert_all(frag, &mut seen, &mut collected);
        }
        collected.sort_by(|a, b| a.name.cmp(&b.name));
        collected
    }
}

// MARK: - compute_identifier

/// Computes the SHA256 operation identifier for an `OperationDescriptor`.
///
/// Returns a 64-character lowercase hex string matching Swift's CryptoKit SHA256 output
/// (via `String(format: "%02x", $0)`).
///
/// Mirrors Swift's `DefaultOperationIdentifierProvider` closure from
/// `OperationIdentifierFactory.swift`.
pub fn compute_identifier(descriptor: &OperationDescriptor) -> String {
    let source = descriptor.source_text(SourceFormat::RawSource);
    let mut hasher = Sha256::new();
    hasher.update(source.as_bytes());
    let digest = hasher.finalize();
    digest.iter().map(|b| format!("{:02x}", b)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::compilation_result::{OperationType, SelectionSet};
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
        fragments: Vec<Arc<FragmentDefinition>>,
    ) -> OperationDefinition {
        OperationDefinition {
            name: name.to_string(),
            operation_type: OperationType::Query,
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

    fn make_fragment(
        name: &str,
        source: &str,
        referenced: Vec<Arc<FragmentDefinition>>,
    ) -> Arc<FragmentDefinition> {
        Arc::new(FragmentDefinition {
            name: name.to_string(),
            type_: make_composite_object("Animal"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("Animal"),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: referenced,
            source: source.to_string(),
            file_path: "test.graphql".to_string(),
        })
    }

    // Test 1: compute_identifier returns 64-char hex string
    #[test]
    fn test_compute_identifier_returns_64_char_hex_string() {
        let op = make_operation("TestQuery", "query TestQuery { allAnimals { species } }", vec![]);
        let descriptor = OperationDescriptor::new(&op);
        let id = compute_identifier(&descriptor);
        assert_eq!(id.len(), 64, "SHA256 hex should be 64 characters");
        assert!(
            id.chars().all(|c| c.is_ascii_hexdigit()),
            "Should only contain hex digits"
        );
        // Should be lowercase
        assert_eq!(id, id.to_lowercase(), "Should be lowercase hex");
    }

    // Test 2: same input produces same hash (determinism)
    #[test]
    fn test_compute_identifier_is_deterministic() {
        let op = make_operation("TestQuery", "query TestQuery { allAnimals { species } }", vec![]);
        let descriptor1 = OperationDescriptor::new(&op);
        let descriptor2 = OperationDescriptor::new(&op);
        let id1 = compute_identifier(&descriptor1);
        let id2 = compute_identifier(&descriptor2);
        assert_eq!(id1, id2, "Same input should produce same hash");
    }

    // Test 3: source_text RawSource has "\n" between fragments
    #[test]
    fn test_source_text_raw_source_has_newline_between_fragments() {
        let frag_a = make_fragment(
            "FragA",
            "fragment FragA on Animal {\n  species\n}",
            vec![],
        );
        let op = make_operation(
            "TestQuery",
            "query TestQuery {\n  ...FragA\n}",
            vec![frag_a],
        );
        let descriptor = OperationDescriptor::new(&op);
        let source = descriptor.source_text(SourceFormat::RawSource);
        // Should contain actual newline between operation and fragment
        assert!(
            source.contains("\nfragment FragA on Animal"),
            "RawSource should have actual newline between op and fragment. Got: {}",
            source
        );
    }

    // Test 4: source_text ManifestJsonBody has "\\n" and escaped quotes
    #[test]
    fn test_source_text_manifest_json_body_has_escaped_newline_and_quotes() {
        let frag_a = make_fragment(
            "FragA",
            "fragment FragA on Animal {\n  species\n}",
            vec![],
        );
        let op = make_operation(
            "TestQuery",
            "query TestQuery {\n  ...FragA\n}",
            vec![frag_a],
        );
        let descriptor = OperationDescriptor::new(&op);
        let source = descriptor.source_text(SourceFormat::ManifestJsonBody);
        // Should contain literal \n (two chars: backslash + n) between op and fragment
        assert!(
            source.contains("\\nfragment FragA on Animal"),
            "ManifestJsonBody should have escaped \\n. Got: {}",
            source
        );
        // Should NOT contain actual newline
        assert!(
            !source.contains('\n'),
            "ManifestJsonBody should not contain actual newlines. Got: {}",
            source
        );
    }

    // Test 5: all_referenced_fragments deduplicates and sorts by name
    #[test]
    fn test_all_referenced_fragments_deduplicates_and_sorts() {
        // Create fragment C (leaf)
        let frag_c = make_fragment(
            "FragC",
            "fragment FragC on Animal { height }",
            vec![],
        );
        // Create fragment B that references C
        let frag_b = make_fragment(
            "FragB",
            "fragment FragB on Animal { weight }",
            vec![Arc::clone(&frag_c)],
        );
        // Create fragment A that also references C (creating a diamond)
        let frag_a = make_fragment(
            "FragA",
            "fragment FragA on Animal { species }",
            vec![Arc::clone(&frag_c)],
        );
        // Operation references A and B (both reference C)
        let op = make_operation(
            "TestQuery",
            "query TestQuery { ...FragA ...FragB }",
            vec![frag_a, frag_b],
        );
        let descriptor = OperationDescriptor::new(&op);
        let source = descriptor.source_text(SourceFormat::RawSource);
        // Count occurrences of "fragment FragC" -- should be exactly 1 (deduplicated)
        let count = source.matches("fragment FragC").count();
        assert_eq!(count, 1, "FragC should appear exactly once (deduplicated)");
        // Fragments should be sorted: FragA, FragB, FragC
        let pos_a = source.find("fragment FragA").unwrap();
        let pos_b = source.find("fragment FragB").unwrap();
        let pos_c = source.find("fragment FragC").unwrap();
        assert!(
            pos_a < pos_b && pos_b < pos_c,
            "Fragments should be sorted by name: A < B < C"
        );
    }

    // Test 6: operation with no fragments returns just the operation source
    #[test]
    fn test_operation_with_no_fragments_returns_just_operation_source() {
        let op = make_operation(
            "SimpleQuery",
            "query SimpleQuery {\n  allAnimals {\n    species\n  }\n}",
            vec![],
        );
        let descriptor = OperationDescriptor::new(&op);
        let source = descriptor.source_text(SourceFormat::RawSource);
        assert_eq!(
            source,
            "query SimpleQuery { allAnimals { species } }",
            "Should be single-line operation source with no fragment appendage"
        );
    }

    // Test 7: known SHA256 value for a simple operation string
    #[test]
    fn test_known_sha256_value() {
        // Compute the expected SHA256 directly
        let input = "query TestQuery { allAnimals { species } }";
        let expected = {
            let mut h = Sha256::new();
            h.update(input.as_bytes());
            let d = h.finalize();
            d.iter().map(|b| format!("{:02x}", b)).collect::<String>()
        };

        let op = make_operation("TestQuery", input, vec![]);
        let descriptor = OperationDescriptor::new(&op);
        let id = compute_identifier(&descriptor);
        assert_eq!(
            id, expected,
            "compute_identifier should match direct SHA256 computation"
        );
    }

    // Test 8: name(), file_path(), and operation_type() accessors
    #[test]
    fn test_descriptor_accessors() {
        let op = make_operation("MyQuery", "query MyQuery { id }", vec![]);
        let descriptor = OperationDescriptor::new(&op);
        assert_eq!(descriptor.name(), "MyQuery");
        assert_eq!(descriptor.file_path(), "test.graphql");
        assert_eq!(descriptor.operation_type(), &OperationType::Query);
    }

    // Test 9: ManifestJsonBody escapes double quotes in source
    #[test]
    fn test_manifest_json_body_escapes_double_quotes() {
        let op = make_operation(
            "TestQuery",
            r#"query TestQuery { field(arg: "value") }"#,
            vec![],
        );
        let descriptor = OperationDescriptor::new(&op);
        let source = descriptor.source_text(SourceFormat::ManifestJsonBody);
        assert!(
            source.contains(r#"\""#),
            "ManifestJsonBody should escape double quotes. Got: {}",
            source
        );
        // The original unescaped quote should not appear (they should all be escaped)
        // Note: the source itself has quotes, but they should be escaped
        assert!(
            !source.contains(r#"arg: "value")"#),
            "Original unescaped quotes should not appear"
        );
    }
}
