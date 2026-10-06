//! Code generation orchestration types and pipeline.
//!
//! Defines the `CodegenProvider` trait, `ItemsToGenerate` bitflags,
//! `CodegenError` enum, `NonFatalErrors` aggregation type, and the
//! `ApolloCodegen` struct with the full `build()` pipeline.
//!
//! Mirrors Swift types from:
//! - `Sources/ApolloCodegenLib/ApolloCodegen.swift` (build(), ItemsToGenerate, ConfigurationContext)
//! - `Sources/ApolloCodegenLib/ApolloCodegen+Errors.swift` (Error, NonFatalErrors)
//! - `Sources/CodegenCLI/Protocols/CodegenProvider.swift` (CodegenProvider protocol)

use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use apollo_compiler::{executable, schema, validation::Valid};
use bitflags::bitflags;
use indexmap::IndexMap;

use crate::config::field_merging::FieldMerging;
use crate::config::schema_customization::CustomSchemaTypeName;
use crate::config::test_mock_file_output::TestMockFileOutput;
use crate::config::validation::validate_config_values;
use crate::config::ApolloCodegenConfiguration;
use crate::file_discovery;
use crate::file_generators::manifest::{OperationManifestFileGenerator, OperationManifestItem};
use crate::file_generators::operation_identifier::{compute_identifier, OperationDescriptor};
use crate::file_generators::{
    delete_extraneous_files, find_existing_generated_file_paths, generate_files_concurrently,
    ApolloFileManager, CustomScalarFileGenerator, EnumFileGenerator, FileGenerator,
    FragmentFileGenerator, InputObjectFileGenerator, InterfaceFileGenerator,
    MockInterfacesFileGenerator, MockObjectFileGenerator, MockUnionsFileGenerator,
    ObjectFileGenerator, OperationFileGenerator, SchemaConfigurationFileGenerator,
    SchemaMetadataFileGenerator, SchemaModuleFileGenerator, UnionFileGenerator,
};
use crate::templates::{ConfigurationContext, NonFatalError};

use crate::codegen_logger::{CodegenLogger, LogLevel};
use crate::templates::rendering_helpers::string_casing::first_lowercased;

use graphql_compiler::adapter::{
    self, build_network_request_source, collect_referenced_fragments, collect_referenced_types,
    convert_directives, try_convert_selection_set, TypeRegistry,
};
use graphql_compiler::{
    validate_operations, DisallowedFieldNames, OperationSource, ValidationOptions,
};
// Re-export CompilationResult so worker.rs can reference it without
// depending on graphql-compiler directly.
pub use graphql_compiler::compilation_result::CompilationResult;
use graphql_compiler::compilation_result::{
    FragmentDefinition, OperationDefinition, OperationType, RootTypeDefinition,
};
use graphql_compiler::{GraphQLCompositeType, GraphQLNamedType};

// MARK: - GenerationFilter

/// Selects which operations and fragments a Bazel `operations` request generates.
///
/// Compilation always covers every operation file the config can see (so fragments
/// resolve); the filter picks the definitions that belong to the requesting target.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GenerationFilter {
    /// Definitions whose file path starts with `<prefix>/` (or contains `/<prefix>/` for
    /// absolute execroot paths). Legacy `--bazel-framework-path` selection: nested or
    /// same-suffix packages can collide.
    Prefix(String),
    /// Definitions whose file path is exactly one of the given files
    /// (`--bazel-generate-for`). Paths are compared lexically normalized and made absolute
    /// against the current directory, like discovered files are.
    Files(Vec<String>),
}

impl GenerationFilter {
    /// Whether a definition found in `file_path` is selected.
    pub fn matches(&self, file_path: &str) -> bool {
        match self {
            GenerationFilter::Prefix(prefix) => matches_prefix(file_path, Some(prefix)),
            GenerationFilter::Files(files) => {
                let candidate = normalize_file_path(file_path);
                files.iter().any(|f| normalize_file_path(f) == candidate)
            }
        }
    }
}

/// Makes a path absolute against the current directory (without touching the file system)
/// and removes `.` components so that `./a/b.graphql`, `a/b.graphql` and `<cwd>/a/./b.graphql`
/// compare equal.
fn normalize_file_path(path: &str) -> PathBuf {
    let path = Path::new(path);
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    };
    let mut normalized = PathBuf::new();
    for component in absolute.components() {
        match component {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    normalized
}

use ir::builder::IRBuilder;

// MARK: - ItemsToGenerate

// OptionSet used to configure what items should be generated during code generation.
// Mirrors Swift's `ApolloCodegen.ItemsToGenerate` OptionSet.
bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct ItemsToGenerate: u32 {
        /// Only generate code (Operations, Fragments, Enums, etc).
        const CODE = 1 << 0;
        /// Only generate the operation manifest for persisted queries.
        const OPERATION_MANIFEST = 1 << 1;
        /// Generate all available items during code generation.
        const ALL = Self::CODE.bits() | Self::OPERATION_MANIFEST.bits();
    }
}

// MARK: - CodegenProvider

/// Generic representation of a code generation provider.
///
/// Mirrors Swift's `CodegenProvider` protocol from
/// `Sources/CodegenCLI/Protocols/CodegenProvider.swift`.
pub trait CodegenProvider {
    fn build(
        config: &ApolloCodegenConfiguration,
        root_url: Option<&Path>,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError>;
}

// MARK: - CompileResult

/// Intermediate compilation artifacts that can be cached across
/// worker requests. Contains the compiled schema/operations
/// result and built IR.
pub struct CompileResult {
    pub compilation_result: Arc<CompilationResult>,
    pub ir: IRBuilder,
}

/// Cached parsed schema, reusable across requests with different operations.
///
/// The expensive part of compilation is schema parsing (stage 3). This struct
/// holds the parsed schema so it can be shared across multiple
/// `compile_operations_with_schema()` calls in worker mode.
pub struct CompiledSchema {
    parsed_schema: Valid<schema::Schema>,
}

// MARK: - ApolloCodegen

/// The main code generation orchestrator.
///
/// Mirrors Swift's `ApolloCodegen` class from `ApolloCodegen.swift`.
/// Implements `CodegenProvider` trait and provides the full `build()` pipeline
/// connecting config validation through to file generation.
pub struct ApolloCodegen;

impl CodegenProvider for ApolloCodegen {
    fn build(
        config: &ApolloCodegenConfiguration,
        root_url: Option<&Path>,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError> {
        let context = ConfigurationContext::new(config.clone(), root_url.map(PathBuf::from));
        ApolloCodegen::build_with_context(&context, items_to_generate)
    }
}

impl ApolloCodegen {
    /// Executes the full code generation pipeline.
    ///
    /// Mirrors Swift's `ApolloCodegen.build()` internal method.
    ///
    /// Pipeline stages:
    /// 1. Config validation
    /// 2. GraphQL file discovery (schema + operations)
    /// 3. Schema parsing via apollo-compiler
    /// 4. Operation parsing
    /// 5. Build CompilationResult via adapter
    /// 6. Schema-aware validation
    /// 7. IR construction
    /// 8. Schema customizations
    /// 9. Code generation (parallel file generation)
    /// 10. Operation manifest generation
    /// 11. Stale file pruning
    /// 12. Error reporting
    pub fn build_with_context(
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError> {
        let compile_result = Self::compile_schema_and_ir(config)?;
        Self::generate_from_ir(&compile_result, config, items_to_generate)
    }

    /// Runs pipeline stages 1-7: config validation, file discovery, schema
    /// parsing, operation parsing, CompilationResult construction, schema
    /// validation, and IR construction.
    ///
    /// Returns a `CompileResult` containing the parsed schema and built IR,
    /// suitable for caching across worker requests.
    ///
    /// Used by:
    /// - `build_with_context()` for one-shot CLI mode (calls this then generate_from_ir)
    /// - Worker loop for cache-miss path (caches the result)
    pub fn compile_schema_and_ir(
        config: &ConfigurationContext,
    ) -> Result<CompileResult, CodegenError> {
        // Stage 1: Config validation
        validate_config_values(&config.config)?;

        // Stage 2: File discovery
        let (schema_matches, operation_matches) = discover_graphql_files(config)?;

        // Stage 3: Schema parsing
        let parsed_schema = parse_schema(&schema_matches)?;

        // Stage 4-5: Operation parsing + CompilationResult construction
        let compilation_result = compile_graphql(&parsed_schema, &operation_matches, config)?;

        let compilation_result = Arc::new(compilation_result);

        // Stage 6: Schema-aware validation
        // (validates schema namespace doesn't conflict with type names, etc.)
        validate_against_schema(config, &compilation_result)?;

        // Stage 7: IR construction
        let ir = IRBuilder::new(compilation_result.clone());

        Ok(CompileResult {
            compilation_result,
            ir,
        })
    }

    /// Stage 1-2: Config validation and file discovery (cheap, ~ms).
    ///
    /// Returns discovered schema and operation file paths without parsing.
    pub fn discover_files(
        config: &ConfigurationContext,
    ) -> Result<(indexmap::IndexSet<String>, indexmap::IndexSet<String>), CodegenError> {
        validate_config_values(&config.config)?;
        discover_graphql_files(config)
    }

    /// Stage 3: Parse schema files into a `CompiledSchema` (expensive, ~5s).
    ///
    /// The result can be cached and reused across multiple
    /// `compile_operations_with_schema()` calls in worker mode.
    pub fn parse_schema_files(
        schema_matches: &indexmap::IndexSet<String>,
    ) -> Result<CompiledSchema, CodegenError> {
        let parsed_schema = parse_schema(schema_matches)?;
        Ok(CompiledSchema { parsed_schema })
    }

    /// Stages 4-7: Operation parsing, compilation, validation, IR construction.
    ///
    /// Uses a pre-parsed schema from `compile_schema()` to skip the expensive
    /// schema parsing step. Each operation target calls this with its own
    /// operation files but the same cached schema.
    pub fn compile_operations_with_schema(
        schema: &CompiledSchema,
        operation_matches: &indexmap::IndexSet<String>,
        config: &ConfigurationContext,
    ) -> Result<CompileResult, CodegenError> {
        let compilation_result = compile_graphql(&schema.parsed_schema, operation_matches, config)?;
        let compilation_result = Arc::new(compilation_result);
        validate_against_schema(config, &compilation_result)?;
        let ir = IRBuilder::new(compilation_result.clone());
        Ok(CompileResult {
            compilation_result,
            ir,
        })
    }

    /// Constructs a `CompileResult` from a cached `Arc<CompilationResult>`.
    ///
    /// Creates a fresh `IRBuilder` (cheap: Arc bump + IndexSet construction)
    /// to avoid state leakage from `BuiltFragmentStorage`/`FieldCollector`
    /// accumulated during prior generation passes.
    pub fn compile_result_from_cached(compilation_result: Arc<CompilationResult>) -> CompileResult {
        let ir = IRBuilder::new(compilation_result.clone());
        CompileResult {
            compilation_result,
            ir,
        }
    }

    /// Runs pipeline stages 8-12: schema customizations, code generation,
    /// operation manifest generation, stale file pruning, and error reporting.
    ///
    /// Accepts a pre-computed `CompileResult` (from `compile_schema_and_ir()`
    /// or from the worker cache).
    ///
    /// Used by:
    /// - `build_with_context()` for one-shot CLI mode
    /// - Worker loop for every request (warm path uses cached CompileResult)
    pub fn generate_from_ir(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError> {
        Self::generate_from_ir_inner(compile_result, config, items_to_generate, false, None)
    }

    /// Like `generate_from_ir` but skips schema type file generation.
    ///
    /// Used in worker operations mode where schema types go to a throwaway
    /// directory (`_schema_types_unused/`). Generating 5000+ schema type
    /// files per request is wasteful when only operation files are needed.
    pub fn generate_from_ir_operations_only(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError> {
        Self::generate_from_ir_inner(compile_result, config, items_to_generate, true, None)
    }

    /// Like `generate_from_ir` but only generates schema type files,
    /// skipping operations and fragments entirely.
    ///
    /// Used in Bazel schema_types mode with direct-write: only schema type
    /// files should land in the tree artifact. Operations are handled by
    /// separate Bazel targets.
    pub fn generate_from_ir_schema_only(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CodegenError> {
        let file_manager = ApolloFileManager::new();

        // Stage 8: Schema customizations
        let t_custom = std::time::Instant::now();
        process_schema_customizations(&compile_result.ir, config);
        let custom_ms = t_custom.elapsed().as_secs_f64() * 1000.0;
        if custom_ms > 0.5 {
            eprintln!("  [perf:schema_only:customizations] {:.1}ms", custom_ms);
        }

        let mut non_fatal_errors = NonFatalErrors::new();

        if items_to_generate.contains(ItemsToGenerate::CODE) {
            let existing_paths = if config.config.options.prune_generated_files {
                find_existing_generated_file_paths(config)?
            } else {
                std::collections::BTreeSet::new()
            };

            // The test mocks' fields come from the operation IR (see
            // `build_definition_ir_for_mock_fields`); plain generation has built it by
            // the time the schema files are generated, this mode has not.
            if config.config.output.test_mocks != TestMockFileOutput::None {
                build_definition_ir_for_mock_fields(
                    &compile_result.compilation_result,
                    &compile_result.ir,
                    "schema_only",
                );
            }

            let errors = generate_schema_files(
                &compile_result.compilation_result,
                &compile_result.ir,
                config,
                &file_manager,
            )?;
            non_fatal_errors.merge(errors);

            if config.config.options.prune_generated_files {
                delete_extraneous_files(&existing_paths, &file_manager)?;
            }
        }

        if items_to_generate.contains(ItemsToGenerate::OPERATION_MANIFEST) {
            generate_operation_manifest(
                &compile_result.compilation_result.operations,
                config,
                &file_manager,
            )?;
        }

        if !non_fatal_errors.is_empty() {
            return Err(CodegenError::NonFatalErrors(non_fatal_errors));
        }

        Ok(())
    }

    /// Generates only the test mock files (fork extension, Bazel `test_mocks` mode).
    ///
    /// Writes the `<Object>+Mock` files selected by `output.testMocks`'s scoping and,
    /// unless a `baseModule` provides them, the `MockObject+Interfaces` /
    /// `MockObject+Unions` typealias files, into the test mock output path (under
    /// `TestMocks/` in a Bazel tree artifact). `filter` is the Bazel operations
    /// selection the `referencedByOperations` scope is evaluated against.
    pub fn generate_from_ir_test_mocks_only(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        filter: Option<&GenerationFilter>,
    ) -> Result<(), CodegenError> {
        let file_manager = ApolloFileManager::new();
        process_schema_customizations(&compile_result.ir, config);
        build_definition_ir_for_mock_fields(
            &compile_result.compilation_result,
            &compile_result.ir,
            "test_mocks",
        );

        let generators = test_mock_file_generators(
            &compile_result.compilation_result,
            &compile_result.ir,
            config,
            filter,
        )?;
        let errors = generate_files_concurrently(&generators, config, &file_manager)?;

        let mut non_fatal_errors = NonFatalErrors::new();
        collect_non_fatal_errors(&generators, &errors, &mut non_fatal_errors);
        if !non_fatal_errors.is_empty() {
            return Err(CodegenError::NonFatalErrors(non_fatal_errors));
        }
        Ok(())
    }

    /// Like `generate_from_ir_operations_only` but additionally selects the
    /// operations and fragments to generate with a [`GenerationFilter`].
    ///
    /// Used with compile-all caching: compile all operations once, then
    /// generate per-target using the target's framework path or file list.
    pub fn generate_from_ir_filtered(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
        filter: &GenerationFilter,
    ) -> Result<(), CodegenError> {
        Self::generate_from_ir_inner(
            compile_result,
            config,
            items_to_generate,
            true,
            Some(filter),
        )
    }

    fn generate_from_ir_inner(
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
        skip_schema_types: bool,
        filter: Option<&GenerationFilter>,
    ) -> Result<(), CodegenError> {
        let file_manager = ApolloFileManager::new();

        // Stage 8: Schema customizations
        let t_custom = std::time::Instant::now();
        process_schema_customizations(&compile_result.ir, config);
        let custom_ms = t_custom.elapsed().as_secs_f64() * 1000.0;
        if custom_ms > 0.5 {
            eprintln!("  [perf:customizations] {:.1}ms", custom_ms);
        }

        // Stage 9: Code generation (if items_to_generate contains CODE)
        let mut non_fatal_errors = NonFatalErrors::new();

        if items_to_generate.contains(ItemsToGenerate::CODE) {
            // Collect existing file paths BEFORE generation (for pruning)
            let existing_paths = if config.config.options.prune_generated_files {
                find_existing_generated_file_paths(config)?
            } else {
                std::collections::BTreeSet::new()
            };

            // Generate files
            let errors = if skip_schema_types {
                generate_graph_ql_definition_files(
                    &compile_result.compilation_result,
                    &compile_result.ir,
                    config,
                    &file_manager,
                    filter,
                )?
            } else {
                generate_all_files(
                    &compile_result.compilation_result,
                    &compile_result.ir,
                    config,
                    &file_manager,
                )?
            };
            non_fatal_errors.merge(errors);

            // Stage 11: Stale file pruning (after all generation)
            if config.config.options.prune_generated_files {
                delete_extraneous_files(&existing_paths, &file_manager)?;
            }
        }

        // Stage 10: Operation manifest generation
        if items_to_generate.contains(ItemsToGenerate::OPERATION_MANIFEST) {
            generate_operation_manifest(
                &compile_result.compilation_result.operations,
                config,
                &file_manager,
            )?;
        }

        // Stage 12: Error reporting
        if !non_fatal_errors.is_empty() {
            return Err(CodegenError::NonFatalErrors(non_fatal_errors));
        }

        Ok(())
    }
}

// MARK: - Pipeline stages

/// Stage 2: Discovers GraphQL schema and operation files using configured search paths.
///
/// Returns (schema_matches, operation_matches) as ordered sets of file paths.
///
/// Mirrors Swift's `createSchema`/`createOperationsDocument` file matching.
fn discover_graphql_files(
    config: &ConfigurationContext,
) -> Result<(indexmap::IndexSet<String>, indexmap::IndexSet<String>), CodegenError> {
    let schema_matches = file_discovery::match_search_paths(
        &config.config.input.schema_search_paths,
        config.root_url(),
    )?;

    if schema_matches.is_empty() {
        return Err(CodegenError::CannotLoadSchema);
    }

    let operation_matches = file_discovery::match_search_paths(
        &config.config.input.operation_search_paths,
        config.root_url(),
    )?;

    if operation_matches.is_empty() {
        return Err(CodegenError::CannotLoadOperations);
    }

    Ok((schema_matches, operation_matches))
}

/// Stage 3: Parses and validates GraphQL schema files.
///
/// Follows the pattern from `ir_compare.rs`: reads all schema files, concatenates SDL,
/// prepends custom directive stubs, parses via `schema::Schema::parse_and_validate()`.
fn parse_schema(
    schema_matches: &indexmap::IndexSet<String>,
) -> Result<Valid<schema::Schema>, CodegenError> {
    let mut combined_sdl = String::new();
    for path in schema_matches {
        let content = std::fs::read_to_string(path).map_err(|e| {
            CodegenError::Io(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("Failed to read schema file '{}': {}", path, e),
            ))
        })?;
        if !combined_sdl.is_empty() {
            combined_sdl.push('\n');
        }
        combined_sdl.push_str(&content);
    }

    // Prepend custom directive stubs for directives that Swift's graphql-js
    // accepts but apollo-compiler requires explicit definitions for.
    let combined_sdl = prepend_custom_directive_stubs(&combined_sdl);

    let first_path = schema_matches
        .iter()
        .next()
        .map(|s| s.as_str())
        .unwrap_or("schema.graphql");

    schema::Schema::parse_and_validate(&combined_sdl, first_path).map_err(|diag| {
        // graphql-js wording where apollo-compiler provides it (e.g. `Unknown type "X".`),
        // otherwise apollo-compiler's own message.
        let messages: Vec<String> = diag
            .errors
            .iter()
            .map(|d| {
                d.error
                    .unstable_compat_message()
                    .unwrap_or_else(|| d.error.to_string())
            })
            .collect();
        CodegenError::SchemaValidationFailure { messages }
    })
}

/// Builds the `ValidationOptions` Swift derives from the configuration
/// (`ValidationOptions+ConfigInitializer.swift`): entity fields must not be named after the
/// schema namespace (singular for entities, the other number for entity lists) and input
/// parameters must not be named after Swift keywords or the namespace.
fn validation_options(config: &ConfigurationContext) -> ValidationOptions {
    let namespace = config.config.schema_namespace.as_str();
    let singular = config.pluralizer.singularize(namespace);
    let plural = config.pluralizer.pluralize(namespace);
    // Swift traps when the namespace is neither its singular nor its plural form; the
    // plural is the sensible disallowed list name in that case.
    let entity_list_name = if namespace == plural && namespace != singular {
        singular
    } else {
        plural
    };
    ValidationOptions {
        schema_namespace: namespace.to_string(),
        disallowed_field_names: DisallowedFieldNames {
            all_fields: crate::config::swift_keywords::SwiftKeywords::DISALLOWED_FIELD_NAMES
                .iter()
                .map(|s| s.to_string())
                .collect(),
            entity: std::iter::once(first_lowercased(namespace)).collect(),
            entity_list: std::iter::once(first_lowercased(&entity_list_name)).collect(),
        },
        disallowed_input_parameter_names:
            crate::config::swift_keywords::SwiftKeywords::DISALLOWED_INPUT_PARAMETER_NAMES
                .iter()
                .map(|s| s.to_string())
                .chain(std::iter::once(first_lowercased(namespace)))
                .collect(),
    }
}

/// Validates the operation documents against the schema before compiling them.
///
/// Mirrors Swift's `validateDocument` call in `ApolloCodegen.compileGraphQLResult()`: the
/// errors are logged as `<path>:<line>:error:<message>` lines and the run fails with
/// `GraphQLSourceValidationFailure`.
fn validate_operation_documents(
    schema: &Valid<schema::Schema>,
    files: &[(String, String)],
    config: &ConfigurationContext,
) -> Result<(), CodegenError> {
    let sources: Vec<OperationSource<'_>> = files
        .iter()
        .map(|(path, text)| OperationSource { path, text })
        .collect();
    match validate_operations(schema, &sources, &validation_options(config)) {
        Ok(()) => Ok(()),
        Err(errors) => {
            let lines: Vec<String> = errors.iter().map(|e| e.log_line()).collect();
            CodegenLogger::log(
                &lines.join("\n"),
                LogLevel::Error,
                "ApolloCodegen.swift",
                185,
            );
            Err(CodegenError::GraphQLSourceValidationFailure { lines })
        }
    }
}

/// Prepends stub definitions for custom directives that Swift's graphql-js
/// accepts but apollo-compiler's strict validation rejects.
///
/// Mirrors the same function from `ir_compare.rs`.
fn prepend_custom_directive_stubs(schema_sdl: &str) -> String {
    let mut stubs = Vec::new();

    if schema_sdl.contains("@oneOf") && !schema_sdl.contains("directive @oneOf") {
        stubs.push("directive @oneOf on INPUT_OBJECT");
    }
    if schema_sdl.contains("@typePolicy") && !schema_sdl.contains("directive @typePolicy") {
        stubs.push("directive @typePolicy(keyFields: String!) on OBJECT | INTERFACE");
    }
    // Client directives Swift's frontend adds to every schema
    // (`apolloCodegenSchemaExtension.ts`, `experimentalDeferDirective.ts`); operation
    // validation needs their definitions.
    if !schema_sdl.contains("directive @apollo_client_ios_localCacheMutation") {
        stubs.push("directive @apollo_client_ios_localCacheMutation on QUERY | MUTATION | SUBSCRIPTION | FRAGMENT_DEFINITION");
    }
    if !schema_sdl.contains("directive @import") {
        stubs.push("directive @import(module: String!) repeatable on QUERY | MUTATION | SUBSCRIPTION | FRAGMENT_DEFINITION");
    }
    if !schema_sdl.contains("directive @defer") {
        stubs.push("directive @defer(label: String, if: Boolean! = true) on FRAGMENT_SPREAD | INLINE_FRAGMENT");
    }

    if stubs.is_empty() {
        schema_sdl.to_string()
    } else {
        format!("{}\n\n{}", stubs.join("\n"), schema_sdl)
    }
}

/// Stages 4-5: Parses operation files and builds a `CompilationResult`.
///
/// Follows the pattern from `ir_compare.rs`: parse each operation file individually,
/// build fragment definitions (two-pass for cross-references), build operation definitions,
/// collect referenced types, assemble into CompilationResult.
fn compile_graphql(
    schema: &Valid<schema::Schema>,
    operation_matches: &indexmap::IndexSet<String>,
    config: &ConfigurationContext,
) -> Result<CompilationResult, CodegenError> {
    let legacy_safelisting = config
        .config
        .experimental_features
        .legacy_safelisting_compatible_operations;
    // Read every operation file
    let file_contents: Vec<(String, String)> = operation_matches
        .iter()
        .map(|path| {
            let content = std::fs::read_to_string(path).map_err(|e| {
                CodegenError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    format!("Failed to read operation file '{}': {}", path, e),
                ))
            })?;
            Ok((path.clone(), content))
        })
        .collect::<Result<Vec<_>, CodegenError>>()?;

    // Validate the merged document first (unknown fragments/types/fields, directive usage,
    // Apollo's own rules). Everything after this point only sees valid documents.
    validate_operation_documents(schema, &file_contents, config)?;

    // Parse each operation file on its own (definitions keep their file path)
    let parsed_files: Vec<ParsedFile> = file_contents
        .iter()
        .map(|(path, content)| {
            let doc =
                executable::ExecutableDocument::parse(schema, content, path).map_err(|diag| {
                    CodegenError::GraphQLSourceValidationFailure {
                        lines: diag.errors.iter().map(|d| d.error.to_string()).collect(),
                    }
                })?;

            Ok(ParsedFile {
                abs_path: path.clone(),
                doc,
            })
        })
        .collect::<Result<Vec<_>, CodegenError>>()?;

    // Build TypeRegistry
    let registry = TypeRegistry::from_schema(schema);

    // Build root type definitions
    let schema_root_types = build_root_types(schema, &registry)?;

    // Build fragment definitions (two-pass: stubs then full)
    let fragment_defs = build_fragment_definitions(&parsed_files, &registry, legacy_safelisting)?;

    // Build operation definitions
    let operation_defs = build_operation_definitions(
        &parsed_files,
        &registry,
        schema,
        &fragment_defs,
        legacy_safelisting,
    )?;

    // Collect referenced types
    let fragment_defs_vec: Vec<FragmentDefinition> =
        fragment_defs.values().map(|f| (**f).clone()).collect();
    let all_types = collect_referenced_types(
        &registry,
        &operation_defs,
        &fragment_defs_vec,
        config.config.options.reduce_generated_schema_types,
    );

    // Assemble CompilationResult
    Ok(CompilationResult {
        schema_root_types,
        referenced_types: all_types,
        operations: operation_defs,
        fragments: fragment_defs_vec,
        schema_documentation: schema
            .schema_definition
            .description
            .as_ref()
            .map(|d| d.to_string()),
    })
}

/// Builds root type definitions from the schema.
fn build_root_types(
    schema: &Valid<schema::Schema>,
    registry: &TypeRegistry,
) -> Result<RootTypeDefinition, CodegenError> {
    let query_name = schema
        .schema_definition
        .query
        .as_ref()
        .map(|n| n.as_str().to_string())
        .unwrap_or_else(|| "Query".to_string());

    let mutation_name = schema
        .schema_definition
        .mutation
        .as_ref()
        .map(|n| n.as_str().to_string());

    let subscription_name = schema
        .schema_definition
        .subscription
        .as_ref()
        .map(|n| n.as_str().to_string());

    let query_type =
        registry
            .get(&query_name)
            .cloned()
            .ok_or_else(|| CodegenError::InvalidConfiguration {
                message: format!("Query type '{}' not found in schema", query_name),
            })?;

    let mutation_type = mutation_name.and_then(|name| registry.get(&name).cloned());
    let subscription_type = subscription_name.and_then(|name| registry.get(&name).cloned());

    Ok(RootTypeDefinition {
        query_type,
        mutation_type,
        subscription_type,
    })
}

/// Builds fragment definitions from all parsed files (two-pass for cross-references).
fn build_fragment_definitions(
    parsed_files: &[impl HasAbsPathAndDoc],
    registry: &TypeRegistry,
    legacy_safelisting: bool,
) -> Result<IndexMap<String, Arc<FragmentDefinition>>, CodegenError> {
    let mut fragment_defs: IndexMap<String, Arc<FragmentDefinition>> = IndexMap::new();

    // First pass: stubs
    for pf in parsed_files {
        for (name, frag) in &pf.doc().fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, registry)?;

            let stub = Arc::new(FragmentDefinition {
                name: name.as_str().to_string(),
                type_: parent_type.clone(),
                selection_set: graphql_compiler::compilation_result::SelectionSet {
                    parent_type,
                    selections: vec![],
                },
                directives: None,
                referenced_fragments: vec![],
                source: build_network_request_source(&frag.to_string(), legacy_safelisting),
                file_path: pf.abs_path().to_string(),
            });
            fragment_defs.insert(name.as_str().to_string(), stub);
        }
    }

    // Second pass: fill in selection sets and referenced fragments
    for pf in parsed_files {
        for (name, frag) in &pf.doc().fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, registry)?;

            let selection_set = try_convert_selection_set(
                &frag.selection_set.selections,
                &parent_type,
                registry,
                &fragment_defs,
            )
            .map_err(|e| adapter_error(pf.abs_path(), e))?;

            let referenced =
                collect_referenced_fragments(&frag.selection_set.selections, &fragment_defs);

            let full = Arc::new(FragmentDefinition {
                name: name.as_str().to_string(),
                type_: parent_type,
                selection_set,
                directives: convert_directives(&frag.directives),
                referenced_fragments: referenced,
                source: build_network_request_source(&frag.to_string(), legacy_safelisting),
                file_path: pf.abs_path().to_string(),
            });
            fragment_defs.insert(name.as_str().to_string(), full);
        }
    }

    // Third pass: re-resolve referenced_fragments now that all fragments are finalized.
    // In the second pass, fragment A's referenced_fragments may point to stubs of
    // fragments that hadn't been processed yet. Iterate until no more stale refs.
    let all_names: Vec<String> = fragment_defs.keys().cloned().collect();
    loop {
        let mut changed = false;
        for name in &all_names {
            let frag = fragment_defs.get(name).unwrap().clone();
            let mut needs_update = false;
            let mut updated_refs = Vec::new();
            for rf in &frag.referenced_fragments {
                if let Some(current) = fragment_defs.get(&rf.name) {
                    if !Arc::ptr_eq(current, rf) {
                        needs_update = true;
                    }
                    updated_refs.push(Arc::clone(current));
                } else {
                    updated_refs.push(Arc::clone(rf));
                }
            }
            if needs_update {
                let updated = Arc::new(FragmentDefinition {
                    name: frag.name.clone(),
                    type_: frag.type_.clone(),
                    selection_set: frag.selection_set.clone(),
                    directives: frag.directives.clone(),
                    referenced_fragments: updated_refs,
                    source: frag.source.clone(),
                    file_path: frag.file_path.clone(),
                });
                fragment_defs.insert(name.clone(), updated);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }

    Ok(fragment_defs)
}

/// Builds operation definitions from all parsed files.
fn build_operation_definitions(
    parsed_files: &[impl HasAbsPathAndDoc],
    registry: &TypeRegistry,
    schema: &Valid<schema::Schema>,
    fragment_defs: &IndexMap<String, Arc<FragmentDefinition>>,
    legacy_safelisting: bool,
) -> Result<Vec<OperationDefinition>, CodegenError> {
    let mut operations = Vec::new();

    for pf in parsed_files {
        // Collect all operations from this file
        let mut all_ops: Vec<(&executable::Operation, String)> = Vec::new();
        if let Some(ref anon) = pf.doc().operations.anonymous {
            all_ops.push((anon, "AnonymousOperation".to_string()));
        }
        for (name, op) in &pf.doc().operations.named {
            all_ops.push((op, name.as_str().to_string()));
        }

        for (op, op_name) in &all_ops {
            let op_type = match op.operation_type {
                executable::OperationType::Query => OperationType::Query,
                executable::OperationType::Mutation => OperationType::Mutation,
                executable::OperationType::Subscription => OperationType::Subscription,
            };

            let root_type_name = match op.operation_type {
                executable::OperationType::Query => schema
                    .schema_definition
                    .query
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Query".to_string()),
                executable::OperationType::Mutation => schema
                    .schema_definition
                    .mutation
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Mutation".to_string()),
                executable::OperationType::Subscription => schema
                    .schema_definition
                    .subscription
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Subscription".to_string()),
            };

            let root_type = resolve_composite_type(&root_type_name, registry)?;

            let selection_set = try_convert_selection_set(
                &op.selection_set.selections,
                &root_type,
                registry,
                fragment_defs,
            )
            .map_err(|e| adapter_error(pf.abs_path(), e))?;

            let variables = op
                .variables
                .iter()
                .map(|var| {
                    Ok(graphql_compiler::compilation_result::VariableDefinition {
                        name: var.name.as_str().to_string(),
                        type_: adapter::try_convert_type(&var.ty, registry)
                            .map_err(|e| adapter_error(pf.abs_path(), e))?,
                        default_value: var
                            .default_value
                            .as_ref()
                            .map(|v| adapter::convert_value(v)),
                    })
                })
                .collect::<Result<Vec<_>, CodegenError>>()?;

            let referenced =
                collect_referenced_fragments(&op.selection_set.selections, fragment_defs);

            operations.push(OperationDefinition {
                name: op_name.clone(),
                operation_type: op_type,
                variables,
                root_type,
                selection_set,
                directives: convert_directives(&op.directives),
                referenced_fragments: referenced,
                source: build_network_request_source(&op.to_string(), legacy_safelisting),
                file_path: pf.abs_path().to_string(),
            });
        }
    }

    Ok(operations)
}

/// Reports a conversion error the way a validation error is reported (the document passed
/// validation, so this only happens for inputs the validator does not cover).
fn adapter_error(file_path: &str, error: adapter::AdapterError) -> CodegenError {
    let line = format!("{}:error:{}", file_path, error.message);
    CodegenLogger::log(&line, LogLevel::Error, "ApolloCodegen.swift", 185);
    CodegenError::GraphQLSourceValidationFailure { lines: vec![line] }
}

/// Trait for abstracting parsed file access (used by fragment/operation builders).
trait HasAbsPathAndDoc {
    fn abs_path(&self) -> &str;
    fn doc(&self) -> &executable::ExecutableDocument;
}

/// Internal parsed file struct (implements HasAbsPathAndDoc).
struct ParsedFile {
    abs_path: String,
    doc: executable::ExecutableDocument,
}

impl HasAbsPathAndDoc for ParsedFile {
    fn abs_path(&self) -> &str {
        &self.abs_path
    }
    fn doc(&self) -> &executable::ExecutableDocument {
        &self.doc
    }
}

/// Resolves a type name to a composite type from the registry.
fn resolve_composite_type(
    name: &str,
    registry: &TypeRegistry,
) -> Result<GraphQLCompositeType, CodegenError> {
    match registry.get(name) {
        Some(GraphQLNamedType::Object(obj)) => Ok(GraphQLCompositeType::Object(Arc::clone(obj))),
        Some(GraphQLNamedType::Interface(iface)) => {
            Ok(GraphQLCompositeType::Interface(Arc::clone(iface)))
        }
        Some(GraphQLNamedType::Union(union_)) => {
            Ok(GraphQLCompositeType::Union(Arc::clone(union_)))
        }
        Some(other) => Err(CodegenError::InvalidConfiguration {
            message: format!(
                "Type '{}' is not a composite type: {:?}",
                name,
                other.name()
            ),
        }),
        None => Err(CodegenError::InvalidConfiguration {
            message: format!("Type '{}' not found in registry", name),
        }),
    }
}

/// Stage 6: Validates configuration against the compiled schema.
///
/// Checks for schema namespace conflicts with actual type names in the schema.
fn validate_against_schema(
    config: &ConfigurationContext,
    compilation_result: &CompilationResult,
) -> Result<(), CodegenError> {
    // Check if schema namespace conflicts with any type name in the schema
    let schema_namespace = &config.config.schema_namespace;
    for named_type in &compilation_result.referenced_types {
        if named_type
            .name()
            .schema_name
            .eq_ignore_ascii_case(schema_namespace)
        {
            return Err(CodegenError::SchemaNameConflict {
                name: schema_namespace.clone(),
            });
        }
    }
    Ok(())
}

/// Stage 8: Applies schema customizations from config to the IR types.
///
/// Mirrors Swift's `processSchemaCustomizations(ir:)` method.
///
/// Iterates `config.options.schema_customization.custom_type_names`, matches against
/// IR schema types, and sets `custom_name` fields on matched types.
///
/// # Safety
/// Uses `unsafe` to mutate `GraphQLName.custom_name` through `Arc`. This mirrors Swift's
/// reference-type mutation semantics where all references to a type share the same identity.
/// This is safe because: (1) called single-threaded before parallel file generation,
/// (2) no concurrent readers exist at this point.
fn process_schema_customizations(ir: &IRBuilder, config: &ConfigurationContext) {
    for (name, customization) in &config.config.options.schema_customization.custom_type_names {
        // Find the type in the IR schema's all_types set
        let matched_type = ir
            .schema
            .referenced_types
            .all_types
            .iter()
            .find(|t| t.name().schema_name == *name);

        if let Some(named_type) = matched_type {
            match named_type {
                GraphQLNamedType::Object(obj) => {
                    if let CustomSchemaTypeName::Type { name: custom_name } = customization {
                        set_custom_name_on_arc(obj, custom_name);
                    }
                }
                GraphQLNamedType::Interface(iface) => {
                    if let CustomSchemaTypeName::Type { name: custom_name } = customization {
                        set_custom_name_on_arc(iface, custom_name);
                    }
                }
                GraphQLNamedType::Union(union_) => {
                    if let CustomSchemaTypeName::Type { name: custom_name } = customization {
                        set_custom_name_on_arc(union_, custom_name);
                    }
                }
                GraphQLNamedType::Scalar(scalar) => {
                    if !scalar.is_custom_scalar() {
                        continue;
                    }
                    if let CustomSchemaTypeName::Type { name: custom_name } = customization {
                        set_custom_name_on_arc(scalar, custom_name);
                    }
                }
                GraphQLNamedType::Enum(enum_type) => match customization {
                    CustomSchemaTypeName::Type { name: custom_name } => {
                        set_custom_name_on_arc(enum_type, custom_name);
                    }
                    CustomSchemaTypeName::Enum {
                        name: custom_name,
                        cases,
                    } => {
                        if let Some(custom_name) = custom_name {
                            set_custom_name_on_arc(enum_type, custom_name);
                        }
                        if let Some(cases) = cases {
                            // Set custom names on enum values
                            // Safety: same single-threaded mutation rationale as above
                            unsafe {
                                let ptr = Arc::as_ptr(enum_type)
                                    as *mut graphql_compiler::GraphQLEnumType;
                                let enum_mut = &mut *ptr;
                                for value in &mut enum_mut.values {
                                    if let Some(case_name) = cases.get(&value.name.schema_name) {
                                        value.name.custom_name = Some(case_name.clone());
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                },
                GraphQLNamedType::InputObject(input) => match customization {
                    CustomSchemaTypeName::Type { name: custom_name } => {
                        set_custom_name_on_arc(input, custom_name);
                    }
                    CustomSchemaTypeName::InputObject {
                        name: custom_name,
                        fields,
                    } => {
                        if let Some(custom_name) = custom_name {
                            set_custom_name_on_arc(input, custom_name);
                        }
                        if let Some(fields) = fields {
                            // Set custom names on input fields
                            // Safety: same single-threaded mutation rationale as above
                            unsafe {
                                let ptr = Arc::as_ptr(input)
                                    as *mut graphql_compiler::GraphQLInputObjectType;
                                let input_mut = &mut *ptr;
                                for (_, field) in &mut input_mut.fields {
                                    if let Some(field_name) = fields.get(&field.name.schema_name) {
                                        field.name.custom_name = Some(field_name.clone());
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                },
            }
        }
    }
}

/// Sets `custom_name` on a type's `GraphQLName` via the `name` field.
///
/// # Safety
/// Mutates through Arc using raw pointer. Safe because:
/// - Called single-threaded before parallel file generation
/// - Only `custom_name` (an Option<String>) is modified
/// - The Arc's strong count doesn't change
fn set_custom_name_on_arc<T: HasNameField>(arc: &Arc<T>, custom_name: &str) {
    unsafe {
        let ptr = Arc::as_ptr(arc) as *mut T;
        (*ptr).name_mut().custom_name = Some(custom_name.to_string());
    }
}

/// Trait for types that have a mutable `name: GraphQLName` field.
///
/// Safety: implementations must provide access to a real GraphQLName field.
trait HasNameField {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName;
}

impl HasNameField for graphql_compiler::GraphQLObjectType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

impl HasNameField for graphql_compiler::GraphQLInterfaceType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

impl HasNameField for graphql_compiler::GraphQLUnionType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

impl HasNameField for graphql_compiler::GraphQLScalarType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

impl HasNameField for graphql_compiler::GraphQLEnumType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

impl HasNameField for graphql_compiler::GraphQLInputObjectType {
    fn name_mut(&mut self) -> &mut graphql_compiler::graphql_name::GraphQLName {
        &mut self.name
    }
}

/// Stage 9: Generates all code files (operations, fragments, schema types).
///
/// Mirrors Swift's `generateFiles()` + `generateGraphQLDefinitionFiles()` + `generateSchemaFiles()`.
fn generate_all_files(
    compilation_result: &CompilationResult,
    ir: &IRBuilder,
    config: &ConfigurationContext,
    file_manager: &ApolloFileManager,
) -> Result<NonFatalErrors, CodegenError> {
    let mut non_fatal_errors = NonFatalErrors::new();

    // Generate operation and fragment files
    let definition_errors =
        generate_graph_ql_definition_files(compilation_result, ir, config, file_manager, None)?;
    non_fatal_errors.merge(definition_errors);

    // Generate schema type files
    let schema_errors = generate_schema_files(compilation_result, ir, config, file_manager)?;
    non_fatal_errors.merge(schema_errors);

    Ok(non_fatal_errors)
}

/// Returns true if `file_path` matches `prefix` as a path component boundary.
///
/// Used by filtered generation to select only operations/fragments
/// belonging to a specific framework path.
///
/// Handles two cases:
/// - Relative paths: `file_path` starts with `prefix/`
/// - Absolute paths (e.g. Bazel execroot): `file_path` contains `/<prefix>/`
fn matches_prefix(file_path: &str, filter_prefix: Option<&str>) -> bool {
    match filter_prefix {
        None => true,
        Some(prefix) => {
            // Relative path: starts_with + next char is /
            (file_path.starts_with(prefix)
                && file_path.as_bytes().get(prefix.len()) == Some(&b'/'))
            // Absolute path: contains /<prefix>/
            || file_path.contains(&format!("/{}/", prefix))
        }
    }
}

/// Generates files for GraphQL operations and fragments.
///
/// Mirrors Swift's `generateGraphQLDefinitionFiles()`.
///
/// For local cache mutations, uses a cloned config with `field_merging` overridden to `All`.
/// When `filter` is `Some`, only the operations/fragments it selects are generated.
fn generate_graph_ql_definition_files(
    compilation_result: &CompilationResult,
    ir: &IRBuilder,
    config: &ConfigurationContext,
    file_manager: &ApolloFileManager,
    filter: Option<&GenerationFilter>,
) -> Result<NonFatalErrors, CodegenError> {
    let t_start = std::time::Instant::now();

    let _merge_named_fragment_fields = config
        .config
        .experimental_features
        .field_merging
        .contains(FieldMerging::NAMED_FRAGMENTS);

    // A ConfigurationContext for local cache mutations with field_merging overridden to All.
    // Mirrors Swift's lazy `cacheMutationContext`.
    let cache_mutation_config = {
        let mut cache_config = config.config.clone();
        cache_config.experimental_features.field_merging = FieldMerging::ALL;
        let mut ctx = ConfigurationContext::new(cache_config, config.root_url.clone());
        ctx.set_output_root(config.output_root.clone());
        ctx
    };

    let mut generators: Vec<Box<dyn FileGenerator + Send + Sync>> = Vec::new();

    let t_ir = std::time::Instant::now();
    let mut fragment_count = 0u32;
    let mut operation_count = 0u32;

    // Build fragment file generators
    for fragment in &compilation_result.fragments {
        if !filter.is_none_or(|f| f.matches(&fragment.file_path)) {
            continue;
        }

        let is_lcm = fragment.is_local_cache_mutation();
        let fragment_config = if is_lcm {
            cache_mutation_config.clone()
        } else {
            config.clone()
        };

        let frag_arc = Arc::new(fragment.clone());
        let ir_fragment = ir.build_fragment(&frag_arc);

        generators.push(Box::new(FragmentFileGenerator {
            ir_fragment,
            config: fragment_config,
        }));
        fragment_count += 1;
    }

    // Build operation file generators
    for operation in &compilation_result.operations {
        if !filter.is_none_or(|f| f.matches(&operation.file_path)) {
            continue;
        }

        let is_lcm = operation.is_local_cache_mutation();
        let operation_config = if is_lcm {
            cache_mutation_config.clone()
        } else {
            config.clone()
        };

        let op_arc = Arc::new(operation.clone());
        let ir_operation = Arc::new(ir.build_operation(&op_arc));

        // Compute operation identifier for the generated file
        let descriptor = OperationDescriptor::new(operation);
        let identifier = compute_identifier(&descriptor);

        generators.push(Box::new(OperationFileGenerator {
            ir_operation,
            operation_identifier: Some(identifier),
            config: operation_config,
            referenced_types: Arc::clone(&ir.schema.referenced_types),
        }));
        operation_count += 1;
    }
    let ir_ms = t_ir.elapsed().as_secs_f64() * 1000.0;

    // Generate all files concurrently (template rendering + file I/O)
    let t_render = std::time::Instant::now();
    let errors = generate_files_concurrently(&generators, config, file_manager)?;
    let render_ms = t_render.elapsed().as_secs_f64() * 1000.0;

    let total_ms = t_start.elapsed().as_secs_f64() * 1000.0;
    eprintln!(
        "  [perf:gen] ops={} frags={} ir_build={:.1}ms render+write={:.1}ms total={:.1}ms",
        operation_count, fragment_count, ir_ms, render_ms, total_ms
    );

    // Aggregate errors by file name
    let mut non_fatal_errors = NonFatalErrors::new();
    collect_non_fatal_errors(&generators, &errors, &mut non_fatal_errors);

    Ok(non_fatal_errors)
}

/// Builds the IR of every compiled fragment and operation without rendering anything.
///
/// A test mock's `MockFields` are the fields selected on that type by *every*
/// operation the CLI compiled: Swift collects them app-wide in `IR.FieldCollector` as
/// a side effect of building each definition's IR, and `generateGraphQLDefinitionFiles`
/// always runs before `generateSchemaFiles`, so plain `generate` has the complete
/// collection when the mocks are rendered. The Bazel modes that do not render
/// operations (`schema_types`, `test_mocks`) call this first so that their mock files
/// are byte-identical to plain generation. The Bazel operations selection is
/// deliberately not applied: the fields must be the union over all operations, the
/// selection only decides which mock *files* a scoped module gets. Same order as plain
/// generation (fragments, then operations, in compilation order), so that a response
/// key seen with two types keeps the same first-seen type.
fn build_definition_ir_for_mock_fields(
    compilation_result: &CompilationResult,
    ir: &IRBuilder,
    mode: &str,
) {
    let t_ir = std::time::Instant::now();
    for fragment in &compilation_result.fragments {
        let _ = ir.build_fragment(&Arc::new(fragment.clone()));
    }
    for operation in &compilation_result.operations {
        let _ = ir.build_operation(&Arc::new(operation.clone()));
    }
    eprintln!(
        "  [perf:{}:mock_fields] ops={} frags={} ir_build={:.1}ms",
        mode,
        compilation_result.operations.len(),
        compilation_result.fragments.len(),
        t_ir.elapsed().as_secs_f64() * 1000.0
    );
}

/// The test mock file generators for `config`'s `output.testMocks`: one
/// `<Object>+Mock` file per selected object type (see
/// [`crate::test_mock_scope::select_mock_object_types`]) plus the
/// `MockObject+Interfaces` / `MockObject+Unions` typealias files unless a `baseModule`
/// provides them.
///
/// `filter` is the Bazel operations selection used by the `referencedByOperations`
/// scope; `None` selects every compiled definition. The typealias files always cover
/// every interface and union the configuration references, so a partition's base
/// module carries exactly Apollo's unscoped typealias files.
///
/// Mirrors the test mock part of Swift's `generateSchemaFiles()`; with the default
/// scoping the generators are the same as Apollo's.
fn test_mock_file_generators(
    compilation_result: &CompilationResult,
    ir: &IRBuilder,
    config: &ConfigurationContext,
    filter: Option<&GenerationFilter>,
) -> Result<Vec<Box<dyn FileGenerator + Send + Sync>>, CodegenError> {
    let Some(scoping) = config.config.output.test_mocks.scoping() else {
        return Err(CodegenError::TestMocksNotConfigured);
    };
    let selected =
        crate::test_mock_scope::select_mock_object_types(compilation_result, scoping, filter)?;

    let mut generators: Vec<Box<dyn FileGenerator + Send + Sync>> = Vec::new();
    for graphql_object in &ir.schema.referenced_types.objects {
        if !selected.contains(graphql_object.name.schema_name.as_str()) {
            continue;
        }
        let obj_type = GraphQLCompositeType::Object(Arc::clone(graphql_object));
        let fields = ir.field_collector.collected_fields_for(&obj_type);
        generators.push(Box::new(MockObjectFileGenerator {
            graphql_object: Arc::clone(graphql_object),
            fields,
            referenced_types: Arc::clone(&ir.schema.referenced_types),
            config: config.clone(),
        }));
    }

    if scoping.generates_typealiases() {
        if !ir.schema.referenced_types.unions.is_empty() {
            generators.push(Box::new(MockUnionsFileGenerator {
                graphql_unions: ir.schema.referenced_types.unions.clone(),
                config: config.clone(),
            }));
        }

        if !ir.schema.referenced_types.interfaces.is_empty() {
            generators.push(Box::new(MockInterfacesFileGenerator {
                graphql_interfaces: ir.schema.referenced_types.interfaces.clone(),
                config: config.clone(),
            }));
        }
    }

    Ok(generators)
}

/// Generates schema type files (objects, enums, interfaces, unions, etc.).
///
/// Mirrors Swift's `generateSchemaFiles()`.
fn generate_schema_files(
    compilation_result: &CompilationResult,
    ir: &IRBuilder,
    config: &ConfigurationContext,
    file_manager: &ApolloFileManager,
) -> Result<NonFatalErrors, CodegenError> {
    let t_start = std::time::Instant::now();
    let mut generators: Vec<Box<dyn FileGenerator + Send + Sync>> = Vec::new();

    // Object types
    for graphql_object in &ir.schema.referenced_types.objects {
        generators.push(Box::new(ObjectFileGenerator {
            graphql_object: Arc::clone(graphql_object),
            config: config.clone(),
        }));
    }

    // Mock objects (scoped by `output.testMocks`; everything by default)
    if config.config.output.test_mocks != TestMockFileOutput::None {
        generators.extend(test_mock_file_generators(
            compilation_result,
            ir,
            config,
            None,
        )?);
    }

    // Enum types
    for graphql_enum in &ir.schema.referenced_types.enums {
        generators.push(Box::new(EnumFileGenerator {
            graphql_enum: Arc::clone(graphql_enum),
            config: config.clone(),
        }));
    }

    // Interface types
    for graphql_interface in &ir.schema.referenced_types.interfaces {
        generators.push(Box::new(InterfaceFileGenerator {
            graphql_interface: Arc::clone(graphql_interface),
            config: config.clone(),
        }));
    }

    // Union types
    for graphql_union in &ir.schema.referenced_types.unions {
        generators.push(Box::new(UnionFileGenerator {
            graphql_union: Arc::clone(graphql_union),
            config: config.clone(),
        }));
    }

    // Input object types
    for graphql_input_object in &ir.schema.referenced_types.input_objects {
        generators.push(Box::new(InputObjectFileGenerator {
            graphql_input_object: Arc::clone(graphql_input_object),
            config: config.clone(),
        }));
    }

    // Custom scalar types
    for graphql_scalar in &ir.schema.referenced_types.custom_scalars {
        generators.push(Box::new(CustomScalarFileGenerator {
            graphql_scalar: Arc::clone(graphql_scalar),
            config: config.clone(),
        }));
    }

    // Schema metadata, configuration, and module files
    generators.push(Box::new(SchemaMetadataFileGenerator {
        schema: Arc::new(ir::Schema::new(
            ir.schema.referenced_types.clone(),
            ir.schema.documentation.clone(),
        )),
        config: config.clone(),
    }));

    generators.push(Box::new(SchemaConfigurationFileGenerator {
        config: config.clone(),
    }));

    let setup_ms = t_start.elapsed().as_secs_f64() * 1000.0;

    // Generate all schema files concurrently
    let t_render = std::time::Instant::now();
    let errors = generate_files_concurrently(&generators, config, file_manager)?;
    let render_ms = t_render.elapsed().as_secs_f64() * 1000.0;

    // Generate schema module file (not a FileGenerator trait impl)
    let module_errors = SchemaModuleFileGenerator::generate(config, file_manager)?;

    eprintln!(
        "  [perf:schema] generators={} setup={:.1}ms render+write={:.1}ms total={:.1}ms",
        generators.len(),
        setup_ms,
        render_ms,
        t_start.elapsed().as_secs_f64() * 1000.0
    );

    let mut non_fatal_errors = NonFatalErrors::new();
    collect_non_fatal_errors(&generators, &errors, &mut non_fatal_errors);

    // Add module generation errors
    if !module_errors.is_empty() {
        non_fatal_errors
            .errors_by_file
            .entry("SchemaModule".to_string())
            .or_default()
            .extend(module_errors);
    }

    Ok(non_fatal_errors)
}

/// Collects non-fatal errors from generators, grouping by file name.
fn collect_non_fatal_errors(
    _generators: &[Box<dyn FileGenerator + Send + Sync>],
    errors: &[NonFatalError],
    target: &mut NonFatalErrors,
) {
    // Since generate_files_concurrently returns a flat Vec of errors from all generators,
    // and individual generators may produce errors, we cannot directly map errors back to
    // specific generators. The errors are aggregated as a flat list.
    if !errors.is_empty() {
        // Group all errors under a generic key since we don't have per-generator tracking
        // from the flat error list. In practice, NonFatalError contains enough context.
        target
            .errors_by_file
            .entry("_codegen".to_string())
            .or_default()
            .extend(errors.iter().cloned());
    }
}

/// Stage 10: Generates the operation manifest file for persisted queries.
///
/// Mirrors Swift's `generateOperationManifest()`.
fn generate_operation_manifest(
    operations: &[OperationDefinition],
    config: &ConfigurationContext,
    _file_manager: &ApolloFileManager,
) -> Result<(), CodegenError> {
    let manifest_config = match &config.config.operation_manifest {
        Some(mc) => mc,
        None => return Ok(()), // No manifest configuration = nothing to do
    };

    let manifest_items: Vec<OperationManifestItem> = operations
        .iter()
        .map(|op| {
            let descriptor = OperationDescriptor::new(op);
            let identifier = compute_identifier(&descriptor);
            OperationManifestItem {
                operation: OperationDescriptor::new(op),
                identifier,
            }
        })
        .collect();

    let generator = OperationManifestFileGenerator::new(
        &manifest_config.path,
        manifest_config.version,
        config.root_url(),
    );

    generator
        .generate_and_write(&manifest_items)
        .map_err(CodegenError::Io)
}

// MARK: - CodegenError

/// Fatal errors that prevent code generation from continuing execution.
///
/// Mirrors Swift's `ApolloCodegen.Error` from `ApolloCodegen+Errors.swift`.
#[derive(Debug)]
pub enum CodegenError {
    /// Operation validation failed; `lines` are Swift's `GraphQLError.logLines`
    /// (`<path>:<line>:error:<message>`).
    GraphQLSourceValidationFailure {
        lines: Vec<String>,
    },
    /// The schema could not be parsed or is invalid (Swift: `GraphQLSchemaValidationError`).
    SchemaValidationFailure {
        messages: Vec<String>,
    },
    TestMocksInvalidSwiftPackageConfiguration,
    /// `output.testMocks.includeTypes` (or `--bazel-mocks-for`) names a type that no
    /// operation references, so there is nothing to mock.
    TestMocksUnknownIncludeType {
        name: String,
    },
    /// Test mocks were requested (`--bazel-mode test_mocks`, `--bazel-mocks-*`) but
    /// `output.testMocks` is `none`.
    TestMocksNotConfigured,
    InputSearchPathInvalid {
        path: String,
    },
    SchemaNameConflict {
        name: String,
    },
    CannotLoadSchema,
    CannotLoadOperations,
    InvalidConfiguration {
        message: String,
    },
    InvalidSchemaName {
        name: String,
        message: String,
    },
    TargetNameConflict {
        name: String,
    },
    FieldMergingIncompatibility,
    NonFatalErrors(NonFatalErrors),
    Io(std::io::Error),
    ConfigValidation(crate::config::validation::ConfigError),
}

impl fmt::Display for CodegenError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CodegenError::GraphQLSourceValidationFailure { lines } => {
                // Swift's `Error.graphQLSourceValidationFailure(atLines:)` description,
                // including the original misspelling and the `[String]` array rendering.
                write!(
                    f,
                    "An error occured during validation of the GraphQL schema or operations! Check {}",
                    swift_string_array(lines)
                )
            }
            CodegenError::SchemaValidationFailure { messages } => {
                write!(
                    f,
                    "JavaScriptError: GraphQLSchemaValidationError-{}",
                    messages.join("\n")
                )
            }
            CodegenError::TestMocksInvalidSwiftPackageConfiguration => {
                write!(
                    f,
                    "Schema Types must be generated with module type 'swiftPackageManager' to generate a swift package for test mocks."
                )
            }
            CodegenError::TestMocksUnknownIncludeType { name } => {
                write!(
                    f,
                    "Test mocks: includeTypes names '{}', which is not an object type referenced by any operation of this configuration.",
                    name
                )
            }
            CodegenError::TestMocksNotConfigured => {
                write!(
                    f,
                    "Test mocks were requested but 'output.testMocks' is 'none'. Configure an 'absolute' or 'swiftPackage' test mock output."
                )
            }
            CodegenError::InputSearchPathInvalid { path } => {
                write!(
                    f,
                    "Input search path '{}' is invalid. Input search paths must include a file extension component. (eg. '.graphql')",
                    path
                )
            }
            CodegenError::SchemaNameConflict { name } => {
                write!(
                    f,
                    "Schema namespace '{}' conflicts with name of a type in the generated code. Please choose a different schema name. Suggestions: {}Schema, {}GraphQL, {}API.",
                    name, name, name, name
                )
            }
            CodegenError::CannotLoadSchema => {
                write!(
                    f,
                    "A GraphQL schema could not be found. Please verify the schema search paths."
                )
            }
            CodegenError::CannotLoadOperations => {
                write!(
                    f,
                    "No GraphQL operations could be found. Please verify the operation search paths."
                )
            }
            CodegenError::InvalidConfiguration { message } => {
                write!(
                    f,
                    "The codegen configuration has conflicting values: {}",
                    message
                )
            }
            CodegenError::InvalidSchemaName { name, message } => {
                write!(f, "The schema namespace `{}` is invalid: {}", name, message)
            }
            CodegenError::TargetNameConflict { name } => {
                write!(
                    f,
                    "Target name '{}' conflicts with a reserved library name. Please choose a different target name.",
                    name
                )
            }
            CodegenError::FieldMergingIncompatibility => {
                write!(
                    f,
                    "Options for disabling 'fieldMerging' and enabling 'selectionSetInitializers' are\nincompatible.\n\nPlease set either 'fieldMerging' to 'all' or 'selectionSetInitializers' to be empty."
                )
            }
            CodegenError::NonFatalErrors(errors) => {
                write!(f, "{}", errors)
            }
            CodegenError::Io(e) => write!(f, "{}", e),
            CodegenError::ConfigValidation(e) => write!(f, "{}", e),
        }
    }
}

impl std::error::Error for CodegenError {}

/// Renders strings like Swift's `[String]` description: `["a", "b"]` with `\` and `"`
/// escaped and control characters as `\n`, `\t`, `\r`.
fn swift_string_array(items: &[String]) -> String {
    let mut out = String::from("[");
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push_str(", ");
        }
        out.push('"');
        for c in item.chars() {
            match c {
                '\\' => out.push_str("\\\\"),
                '"' => out.push_str("\\\""),
                '\n' => out.push_str("\\n"),
                '\t' => out.push_str("\\t"),
                '\r' => out.push_str("\\r"),
                other => out.push(other),
            }
        }
        out.push('"');
    }
    out.push(']');
    out
}

impl From<std::io::Error> for CodegenError {
    fn from(e: std::io::Error) -> Self {
        CodegenError::Io(e)
    }
}

impl From<crate::config::validation::ConfigError> for CodegenError {
    fn from(e: crate::config::validation::ConfigError) -> Self {
        CodegenError::ConfigValidation(e)
    }
}

// MARK: - NonFatalErrors

/// Aggregation of non-fatal errors by file name.
///
/// Mirrors Swift's `ApolloCodegen.NonFatalErrors` from `ApolloCodegen+Errors.swift`.
/// Uses `BTreeMap` for deterministic ordering.
#[derive(Debug)]
pub struct NonFatalErrors {
    pub errors_by_file: BTreeMap<String, Vec<NonFatalError>>,
}

impl NonFatalErrors {
    pub fn new() -> Self {
        Self {
            errors_by_file: BTreeMap::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.errors_by_file.is_empty()
    }

    pub fn merge(&mut self, other: NonFatalErrors) {
        for (key, value) in other.errors_by_file {
            self.errors_by_file.entry(key).or_default().extend(value);
        }
    }
}

impl Default for NonFatalErrors {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for NonFatalErrors {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (file_name, errors) in &self.errors_by_file {
            writeln!(f, "- {}:", file_name)?;
            for error in errors {
                writeln!(f, "  - {}", error.error_description())?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
#[allow(non_snake_case)] // test names mirror the Swift test suite
mod tests {
    use super::*;

    #[test]
    fn test_items_to_generate_code() {
        assert_eq!(ItemsToGenerate::CODE.bits(), 1);
    }

    #[test]
    fn test_items_to_generate_manifest() {
        assert_eq!(ItemsToGenerate::OPERATION_MANIFEST.bits(), 2);
    }

    #[test]
    fn test_items_to_generate_all() {
        assert_eq!(
            ItemsToGenerate::ALL,
            ItemsToGenerate::CODE | ItemsToGenerate::OPERATION_MANIFEST
        );
    }

    #[test]
    fn test_items_to_generate_contains() {
        let all = ItemsToGenerate::ALL;
        assert!(all.contains(ItemsToGenerate::CODE));
        assert!(all.contains(ItemsToGenerate::OPERATION_MANIFEST));

        let code_only = ItemsToGenerate::CODE;
        assert!(code_only.contains(ItemsToGenerate::CODE));
        assert!(!code_only.contains(ItemsToGenerate::OPERATION_MANIFEST));
    }

    #[test]
    fn test_items_to_generate_code_only() {
        let code = ItemsToGenerate::CODE;
        assert!(!code.contains(ItemsToGenerate::OPERATION_MANIFEST));
    }

    #[test]
    fn test_items_to_generate_all_contains_both() {
        let all = ItemsToGenerate::ALL;
        assert!(all.contains(ItemsToGenerate::CODE));
        assert!(all.contains(ItemsToGenerate::OPERATION_MANIFEST));
    }

    #[test]
    fn test_non_fatal_errors_new_is_empty() {
        let errors = NonFatalErrors::new();
        assert!(errors.is_empty());
    }

    #[test]
    fn test_non_fatal_errors_merge() {
        let mut errors1 = NonFatalErrors::new();
        errors1.errors_by_file.insert(
            "FileA.swift".to_string(),
            vec![NonFatalError::TypeNameConflict {
                name: "field1".to_string(),
                conflicting_name: "field2".to_string(),
                containing_object: "MyObject".to_string(),
            }],
        );

        let mut errors2 = NonFatalErrors::new();
        errors2.errors_by_file.insert(
            "FileB.swift".to_string(),
            vec![NonFatalError::TypeNameConflict {
                name: "field3".to_string(),
                conflicting_name: "field4".to_string(),
                containing_object: "OtherObject".to_string(),
            }],
        );

        errors1.merge(errors2);
        assert_eq!(errors1.errors_by_file.len(), 2);
        assert!(errors1.errors_by_file.contains_key("FileA.swift"));
        assert!(errors1.errors_by_file.contains_key("FileB.swift"));
    }

    #[test]
    fn test_non_fatal_errors_merge_same_file() {
        let mut errors1 = NonFatalErrors::new();
        errors1.errors_by_file.insert(
            "FileA.swift".to_string(),
            vec![NonFatalError::TypeNameConflict {
                name: "field1".to_string(),
                conflicting_name: "field2".to_string(),
                containing_object: "MyObject".to_string(),
            }],
        );

        let mut errors2 = NonFatalErrors::new();
        errors2.errors_by_file.insert(
            "FileA.swift".to_string(),
            vec![NonFatalError::TypeNameConflict {
                name: "field3".to_string(),
                conflicting_name: "field4".to_string(),
                containing_object: "OtherObject".to_string(),
            }],
        );

        errors1.merge(errors2);
        assert_eq!(errors1.errors_by_file.len(), 1);
        assert_eq!(errors1.errors_by_file["FileA.swift"].len(), 2);
    }

    #[test]
    fn test_non_fatal_errors_display() {
        let mut errors = NonFatalErrors::new();
        errors.errors_by_file.insert(
            "FileA.swift".to_string(),
            vec![NonFatalError::TypeNameConflict {
                name: "species".to_string(),
                conflicting_name: "Species".to_string(),
                containing_object: "Animal".to_string(),
            }],
        );

        let display = format!("{}", errors);
        assert!(display.contains("- FileA.swift:"));
        assert!(display.contains("TypeNameConflict:"));
        assert!(display.contains("Field 'Species' conflicts with field 'species'"));
    }

    #[test]
    fn test_codegen_error_display_graphql_validation() {
        let err = CodegenError::GraphQLSourceValidationFailure {
            lines: vec!["error1".to_string(), "error2".to_string()],
        };
        let msg = format!("{}", err);
        assert_eq!(
            msg,
            "An error occured during validation of the GraphQL schema or operations! Check [\"error1\", \"error2\"]"
        );
    }

    #[test]
    fn test_swift_string_array_escapes_like_swift() {
        assert_eq!(swift_string_array(&[]), "[]");
        assert_eq!(
            swift_string_array(&["a/b.graphql:1:error:Unknown fragment \"X\".".to_string()]),
            "[\"a/b.graphql:1:error:Unknown fragment \\\"X\\\".\"]"
        );
        assert_eq!(
            swift_string_array(&["x\\y\n".to_string()]),
            "[\"x\\\\y\\n\"]"
        );
    }

    #[test]
    fn test_generation_filter_files_matches_exact_paths_only() {
        let cwd = std::env::current_dir().unwrap();
        let filter = GenerationFilter::Files(vec![
            "Features/Account/Query.graphql".to_string(),
            "./Features/Shared/Frag.graphql".to_string(),
        ]);
        // relative, absolute and `./`-prefixed spellings of the same file all match
        assert!(filter.matches("Features/Account/Query.graphql"));
        assert!(filter.matches(&cwd.join("Features/Account/Query.graphql").to_string_lossy()));
        assert!(filter.matches(&cwd.join("./Features/Shared/Frag.graphql").to_string_lossy()));
        assert!(filter.matches("Features/Shared/Frag.graphql"));
        // prefix and suffix relatives of a selected file do not match
        assert!(!filter.matches("Features/Account/Other.graphql"));
        assert!(!filter.matches("Features/Account/Query.graphql.bak"));
        assert!(!filter.matches("Nested/Features/Account/Query.graphql"));
        assert!(!filter.matches("Features/Account"));
    }

    #[test]
    fn test_generation_filter_prefix_delegates_to_matches_prefix() {
        let filter = GenerationFilter::Prefix("Features/Account".to_string());
        assert!(filter.matches("Features/Account/Query.graphql"));
        assert!(!filter.matches("Features/AccountInfo/Query.graphql"));
    }

    #[test]
    fn test_codegen_error_display_test_mocks_invalid() {
        let err = CodegenError::TestMocksInvalidSwiftPackageConfiguration;
        let msg = format!("{}", err);
        assert!(
            msg.contains("Schema Types must be generated with module type 'swiftPackageManager'")
        );
    }

    #[test]
    fn test_codegen_error_display_input_search_path_invalid() {
        let err = CodegenError::InputSearchPathInvalid {
            path: "/bad/path".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("Input search path '/bad/path' is invalid"));
        assert!(msg.contains("'.graphql'"));
    }

    #[test]
    fn test_codegen_error_display_schema_name_conflict() {
        let err = CodegenError::SchemaNameConflict {
            name: "Query".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("Schema namespace 'Query' conflicts"));
        assert!(msg.contains("QuerySchema, QueryGraphQL, QueryAPI"));
    }

    #[test]
    fn test_codegen_error_display_cannot_load_schema() {
        let err = CodegenError::CannotLoadSchema;
        let msg = format!("{}", err);
        assert!(msg.contains("A GraphQL schema could not be found"));
    }

    #[test]
    fn test_codegen_error_display_cannot_load_operations() {
        let err = CodegenError::CannotLoadOperations;
        let msg = format!("{}", err);
        assert!(msg.contains("No GraphQL operations could be found"));
    }

    #[test]
    fn test_codegen_error_display_invalid_configuration() {
        let err = CodegenError::InvalidConfiguration {
            message: "bad config".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("The codegen configuration has conflicting values: bad config"));
    }

    #[test]
    fn test_codegen_error_display_invalid_schema_name() {
        let err = CodegenError::InvalidSchemaName {
            name: "123bad".to_string(),
            message: "must start with letter".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("The schema namespace `123bad` is invalid: must start with letter"));
    }

    #[test]
    fn test_codegen_error_display_target_name_conflict() {
        let err = CodegenError::TargetNameConflict {
            name: "Apollo".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("Target name 'Apollo' conflicts with a reserved library name"));
    }

    #[test]
    fn test_codegen_error_display_field_merging_incompatibility() {
        let err = CodegenError::FieldMergingIncompatibility;
        let msg = format!("{}", err);
        assert!(msg.contains("Options for disabling 'fieldMerging'"));
        assert!(msg.contains("incompatible"));
    }

    #[test]
    fn test_codegen_error_from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let codegen_err: CodegenError = io_err.into();
        assert!(matches!(codegen_err, CodegenError::Io(_)));
    }

    #[test]
    fn test_prepend_custom_directive_stubs_oneOf() {
        let sdl = "type Query { id: ID }\ninput OneOfInput @oneOf { a: String }";
        let result = prepend_custom_directive_stubs(sdl);
        assert!(result.contains("directive @oneOf on INPUT_OBJECT"));
    }

    #[test]
    fn test_prepend_custom_directive_stubs_always_adds_client_directives() {
        let sdl = "type Query { id: ID }";
        let result = prepend_custom_directive_stubs(sdl);
        assert!(result.ends_with(sdl));
        assert!(result.contains("directive @apollo_client_ios_localCacheMutation on QUERY | MUTATION | SUBSCRIPTION | FRAGMENT_DEFINITION"));
        assert!(result.contains("directive @import(module: String!) repeatable on QUERY | MUTATION | SUBSCRIPTION | FRAGMENT_DEFINITION"));
        assert!(result.contains("directive @defer(label: String, if: Boolean! = true) on FRAGMENT_SPREAD | INLINE_FRAGMENT"));
        // schema-only directives are still conditional
        assert!(!result.contains("directive @oneOf"));
        assert!(!result.contains("directive @typePolicy"));
        // user definitions win
        let own = "directive @defer(label: String!) on INLINE_FRAGMENT\ntype Query { id: ID }";
        assert_eq!(
            prepend_custom_directive_stubs(own)
                .matches("directive @defer")
                .count(),
            1
        );
    }

    #[test]
    fn test_prepend_custom_directive_stubs_existing_directive_not_duplicated() {
        let sdl =
            "directive @oneOf on INPUT_OBJECT\ntype Query { id: ID }\ninput I @oneOf { a: String }";
        let result = prepend_custom_directive_stubs(sdl);
        // Should not add a duplicate
        assert_eq!(
            result.matches("directive @oneOf").count(),
            1,
            "Should not duplicate existing directive"
        );
    }

    #[test]
    fn test_matches_prefix_none_always_matches() {
        assert!(matches_prefix("Features/Account/Query.graphql", None));
        assert!(matches_prefix("", None));
    }

    #[test]
    fn test_matches_prefix_exact_with_slash() {
        assert!(matches_prefix(
            "Features/Account/Query.graphql",
            Some("Features/Account")
        ));
        assert!(matches_prefix(
            "Shared/Fragments/Foo.graphql",
            Some("Shared/Fragments")
        ));
    }

    #[test]
    fn test_matches_prefix_rejects_partial() {
        // "Features/AccountInfo" should NOT match prefix "Features/Account"
        assert!(!matches_prefix(
            "Features/AccountInfo/Query.graphql",
            Some("Features/Account")
        ));
    }

    #[test]
    fn test_matches_prefix_rejects_no_slash() {
        // Exact match without trailing slash should not match
        assert!(!matches_prefix(
            "Features/Account",
            Some("Features/Account")
        ));
    }

    #[test]
    fn test_matches_prefix_rejects_different_path() {
        assert!(!matches_prefix(
            "Shared/Fragments/Foo.graphql",
            Some("Features/Account")
        ));
    }

    #[test]
    fn test_matches_prefix_absolute_execroot_path() {
        // Bazel worker mode produces absolute execroot paths
        assert!(matches_prefix(
            "/private/var/tmp/_bazel_user/abc123/execroot/_main/Features/AuthUtilities/AuthUtilities.graphql",
            Some("Features/AuthUtilities")
        ));
    }

    #[test]
    fn test_matches_prefix_absolute_rejects_partial() {
        assert!(!matches_prefix(
            "/private/var/tmp/_bazel_user/abc123/execroot/_main/Features/AuthUtilitiesExtra/Query.graphql",
            Some("Features/AuthUtilities")
        ));
    }

    #[test]
    fn test_matches_prefix_absolute_rejects_different_path() {
        assert!(!matches_prefix(
            "/private/var/tmp/_bazel_user/abc123/execroot/_main/Carrot/ProductVariants.graphql",
            Some("Features/AuthUtilities")
        ));
    }
}
