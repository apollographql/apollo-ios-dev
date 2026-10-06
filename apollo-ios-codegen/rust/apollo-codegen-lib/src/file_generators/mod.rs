//! File generation infrastructure for Apollo iOS code generation.
//!
//! This module provides the core file generation types: the `FileGenerator` trait,
//! `FileTarget` enum with path resolution logic, and helper utilities.
//!
//! Mirrors Swift's `FileGenerator.swift` from
//! `Sources/ApolloCodegenLib/FileGenerators/FileGenerator.swift`.

pub mod custom_scalar;
pub mod enum_;
pub mod file_manager;
pub mod fragment;
pub mod input_object;
pub mod interface;
pub mod manifest;
pub mod mock_interfaces;
pub mod mock_object;
pub mod mock_unions;
pub mod object;
pub mod operation;
pub mod operation_identifier;
pub mod schema_configuration;
pub mod schema_metadata;
pub mod schema_module;
pub mod union_;

pub use custom_scalar::CustomScalarFileGenerator;
pub use enum_::EnumFileGenerator;
pub use file_manager::ApolloFileManager;
pub use fragment::FragmentFileGenerator;
pub use input_object::InputObjectFileGenerator;
pub use interface::InterfaceFileGenerator;
pub use mock_interfaces::MockInterfacesFileGenerator;
pub use mock_object::MockObjectFileGenerator;
pub use mock_unions::MockUnionsFileGenerator;
pub use object::ObjectFileGenerator;
pub use operation::OperationFileGenerator;
pub use schema_configuration::SchemaConfigurationFileGenerator;
pub use schema_metadata::SchemaMetadataFileGenerator;
pub use schema_module::SchemaModuleFileGenerator;
pub use union_::UnionFileGenerator;

use std::path::{Path, PathBuf};

use graphql_compiler::compilation_result::OperationType;

use crate::config::module_type::ModuleType;
use crate::config::operations_file_output::OperationsFileOutput;
use crate::config::test_mock_file_output::TestMockFileOutput;
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::{ConfigurationContext, NonFatalError, TemplateRenderer};

// MARK: - FileTarget

/// The target type for a generated file, determining the output directory path.
///
/// Mirrors Swift's `FileTarget` enum from `FileGenerator.swift` lines 73-230.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileTarget {
    Object,
    Enum,
    Interface,
    Union,
    InputObject,
    CustomScalar,
    Fragment {
        file_path: String,
        is_local_cache_mutation: bool,
    },
    Operation {
        operation_type: OperationType,
        file_path: String,
        is_local_cache_mutation: bool,
    },
    Schema,
    TestMock,
}

impl FileTarget {
    /// Returns the subpath component for this file target.
    ///
    /// Mirrors Swift's `FileTarget.subpath` computed property (lines 86-109).
    fn subpath(&self) -> &str {
        match self {
            FileTarget::Object => "Objects",
            FileTarget::Enum => "Enums",
            FileTarget::Interface => "Interfaces",
            FileTarget::Union => "Unions",
            FileTarget::InputObject => "InputObjects",
            FileTarget::CustomScalar => "CustomScalars",
            FileTarget::Operation {
                is_local_cache_mutation: true,
                ..
            } => "LocalCacheMutations",
            FileTarget::Fragment {
                is_local_cache_mutation: true,
                ..
            } => "LocalCacheMutations",
            FileTarget::Fragment { .. } => "Fragments",
            FileTarget::Operation {
                operation_type,
                is_local_cache_mutation: false,
                ..
            } => match operation_type {
                OperationType::Query => "Queries",
                OperationType::Mutation => "Mutations",
                OperationType::Subscription => "Subscriptions",
            },
            FileTarget::Schema | FileTarget::TestMock => "",
        }
    }

    /// Resolves the output directory path for this file target given the configuration.
    ///
    /// Mirrors Swift's `FileTarget.resolvePath(forConfig:)` method (lines 111-133).
    pub fn resolve_path(&self, config: &ConfigurationContext) -> PathBuf {
        match self {
            FileTarget::Object
            | FileTarget::Enum
            | FileTarget::Interface
            | FileTarget::Union
            | FileTarget::InputObject
            | FileTarget::CustomScalar
            | FileTarget::Schema => self.resolve_schema_path(config),

            FileTarget::Fragment { .. } => self.resolve_fragment_path(config),

            FileTarget::Operation { .. } => self.resolve_operation_path(config),

            FileTarget::TestMock => self.resolve_test_mock_path(config),
        }
    }

    /// Resolves the output path for schema type files.
    ///
    /// Mirrors Swift's `resolveSchemaPath(forConfig:)` (lines 135-150).
    /// When `output_root` is set, writes directly to `output_root/<subpath>`,
    /// bypassing the config path and SPM/Schema prefixes.
    fn resolve_schema_path(&self, config: &ConfigurationContext) -> PathBuf {
        if let Some(output_root) = config.output_root() {
            let subpath = self.subpath();
            if subpath.is_empty() {
                output_root.to_path_buf()
            } else {
                output_root.join(subpath)
            }
        } else {
            let mut url = resolve_url(&config.output().schema_types.path, config.root_url());
            if matches!(
                config.output().schema_types.module_type,
                ModuleType::SwiftPackage { .. }
            ) {
                url = url.join("Sources");
            }
            if config.output().operations.is_in_module() {
                url = url.join("Schema");
            }
            let subpath = self.subpath();
            if subpath.is_empty() {
                normalize_path(&url)
            } else {
                normalize_path(&url.join(subpath))
            }
        }
    }

    /// Resolves the output path for fragment files.
    ///
    /// Mirrors Swift's `resolveFragmentPath(forConfig:fragment:)` (lines 152-175).
    /// When `output_root` is set, redirects output under the tree artifact directory.
    fn resolve_fragment_path(&self, config: &ConfigurationContext) -> PathBuf {
        let file_path = match self {
            FileTarget::Fragment { file_path, .. } => file_path,
            _ => unreachable!("resolve_fragment_path called on non-fragment target"),
        };

        if let Some(output_root) = config.output_root() {
            match &config.output().operations {
                OperationsFileOutput::Relative { subpath, .. } => {
                    let rel = resolve_relative_path(file_path, subpath.as_deref());
                    if rel.is_absolute() {
                        // Absolute paths (e.g. Bazel execroot) can't be joined
                        // under output_root. Write directly to tree artifact root.
                        output_root.to_path_buf()
                    } else {
                        output_root.join(rel)
                    }
                }
                _ => {
                    let subpath = self.subpath();
                    if subpath.is_empty() {
                        output_root.to_path_buf()
                    } else {
                        output_root.join(subpath)
                    }
                }
            }
        } else {
            match &config.output().operations {
                OperationsFileOutput::InSchemaModule => {
                    let mut url =
                        resolve_url(&config.output().schema_types.path, config.root_url());
                    if matches!(
                        config.output().schema_types.module_type,
                        ModuleType::SwiftPackage { .. }
                    ) {
                        url = url.join("Sources");
                    }
                    url.join(self.subpath())
                }
                OperationsFileOutput::Absolute { path, .. } => {
                    resolve_url(path, config.root_url()).join(self.subpath())
                }
                OperationsFileOutput::Relative { subpath, .. } => {
                    resolve_relative_path(file_path, subpath.as_deref())
                }
            }
        }
    }

    /// Resolves the output path for operation files.
    ///
    /// Mirrors Swift's `resolveOperationPath(forConfig:operation:)` (lines 187-215).
    /// When `output_root` is set, redirects output under the tree artifact directory.
    fn resolve_operation_path(&self, config: &ConfigurationContext) -> PathBuf {
        let (file_path, is_local_cache_mutation) = match self {
            FileTarget::Operation {
                file_path,
                is_local_cache_mutation,
                ..
            } => (file_path, *is_local_cache_mutation),
            _ => unreachable!("resolve_operation_path called on non-operation target"),
        };

        if let Some(output_root) = config.output_root() {
            match &config.output().operations {
                OperationsFileOutput::Relative { subpath, .. } => {
                    let rel = resolve_relative_path(file_path, subpath.as_deref());
                    if rel.is_absolute() {
                        // Absolute paths (e.g. Bazel execroot) can't be joined
                        // under output_root. Write directly to tree artifact root.
                        output_root.to_path_buf()
                    } else {
                        output_root.join(rel)
                    }
                }
                _ => {
                    let mut base = output_root.to_path_buf();
                    if !is_local_cache_mutation {
                        base = base.join("Operations");
                    }
                    base.join(self.subpath())
                }
            }
        } else {
            match &config.output().operations {
                OperationsFileOutput::InSchemaModule => {
                    let mut url =
                        resolve_url(&config.output().schema_types.path, config.root_url());
                    if matches!(
                        config.output().schema_types.module_type,
                        ModuleType::SwiftPackage { .. }
                    ) {
                        url = url.join("Sources");
                    }
                    if !is_local_cache_mutation {
                        url = url.join("Operations");
                    }
                    url.join(self.subpath())
                }
                OperationsFileOutput::Absolute { path, .. } => {
                    resolve_url(path, config.root_url()).join(self.subpath())
                }
                OperationsFileOutput::Relative { subpath, .. } => {
                    resolve_relative_path(file_path, subpath.as_deref())
                }
            }
        }
    }

    /// Resolves the output path for test mock files.
    ///
    /// Mirrors Swift's `resolveTestMockPath(forConfig:)` (lines 217-229).
    /// When `output_root` is set (Bazel mode), test mocks are written to their own
    /// subdirectory of the tree artifact: `<output_root>/<targetName>` for a `swiftPackage`
    /// output (default `TestMocks`) and `<output_root>/TestMocks` for an `absolute` one, so
    /// a Bazel rule can split them from the schema types.
    fn resolve_test_mock_path(&self, config: &ConfigurationContext) -> PathBuf {
        if let Some(output_root) = config.output_root() {
            match &config.output().test_mocks {
                TestMockFileOutput::None => PathBuf::new(),
                TestMockFileOutput::SwiftPackage { target_name, .. } => {
                    let name = target_name.as_deref().unwrap_or("TestMocks");
                    output_root.join(name)
                }
                TestMockFileOutput::Absolute { .. } => output_root.join("TestMocks"),
            }
        } else {
            match &config.output().test_mocks {
                TestMockFileOutput::None => PathBuf::new(),
                TestMockFileOutput::SwiftPackage { target_name, .. } => {
                    let name = target_name.as_deref().unwrap_or("TestMocks");
                    resolve_url(&config.output().schema_types.path, config.root_url()).join(name)
                }
                TestMockFileOutput::Absolute { path, .. } => resolve_url(path, config.root_url()),
            }
        }
    }
}

// MARK: - FileGenerator trait

/// A trait for types that generate output files from templates.
///
/// Mirrors Swift's `FileGenerator` protocol from `FileGenerator.swift` lines 7-68.
pub trait FileGenerator {
    /// The name of the file to be generated (without extension).
    fn file_name(&self) -> String;

    /// The file extension for the generated file.
    ///
    /// Defaults to `"graphql.swift"` for overwritable files, `"swift"` for non-overwritable.
    fn file_extension(&self) -> &str {
        if self.overwrite() {
            "graphql.swift"
        } else {
            "swift"
        }
    }

    /// An optional suffix appended to the filename when `appendSchemaTypeFilenameSuffix` is enabled.
    fn file_suffix(&self) -> Option<&str> {
        None
    }

    /// Whether this file should overwrite an existing file at the same path.
    fn overwrite(&self) -> bool {
        true
    }

    /// Returns the template renderer for this file generator.
    fn template(&self) -> Box<dyn TemplateRenderer + '_>;

    /// Returns the file target determining the output directory.
    fn target(&self) -> FileTarget;

    /// Generates the file, writing the rendered template content to the configured output path.
    ///
    /// Mirrors Swift's `FileGenerator.generate(forConfig:fileManager:)` (lines 26-58).
    fn generate(
        &self,
        config: &ConfigurationContext,
        file_manager: &ApolloFileManager,
    ) -> Result<Vec<NonFatalError>, std::io::Error> {
        let filename = self.resolve_filename(config);
        let dir_path = self.target().resolve_path(config);

        // Build full path: dir / filename.extension
        // Use format! for extension to avoid PathBuf::with_extension double-dot issue
        let full_filename = format!("{}.{}", filename, self.file_extension());
        let file_path = normalize_path(&dir_path.join(&full_filename));

        let result = self.template().render();

        // Handle pre-suffix file rename for non-overwrite files (Swift lines 40-49)
        if !self.overwrite() {
            if let Some(_suffix) = self.file_suffix() {
                let pre_suffix_filename = format!(
                    "{}.{}",
                    first_uppercased(&self.file_name()),
                    self.file_extension()
                );
                let pre_suffix_path = normalize_path(&dir_path.join(&pre_suffix_filename));
                file_manager.rename_file(&pre_suffix_path, &file_path)?;
            }
        }

        file_manager.create_file(&file_path, result.body.as_bytes(), self.overwrite())?;
        Ok(result.errors)
    }

    /// Resolves the filename to use, taking into account any generated filename options.
    ///
    /// Mirrors Swift's `resolveFilename(forConfig:)` (lines 61-68).
    fn resolve_filename(&self, config: &ConfigurationContext) -> String {
        let prefix = first_uppercased(&self.file_name());
        if config.options().append_schema_type_filename_suffix {
            if let Some(suffix) = self.file_suffix() {
                return format!("{}{}", prefix, suffix);
            }
        }
        prefix
    }
}

// MARK: - Helper functions

/// Resolves a path string against an optional root URL.
///
/// Replicates Swift's `URL(fileURLWithPath:relativeTo:)` behavior:
/// - If `path` is absolute, returns it as-is
/// - If `path` is relative and `root_url` is provided, joins them
/// - If `path` is relative and no `root_url`, returns as-is
fn resolve_url(path: &str, root_url: Option<&Path>) -> PathBuf {
    let p = PathBuf::from(path);
    if p.is_absolute() {
        p
    } else if let Some(root) = root_url {
        root.join(path)
    } else {
        p
    }
}

/// Resolves a relative path from a source file's parent directory.
///
/// Mirrors Swift's `resolveRelativePath(sourceURL:withSubpath:)` (lines 177-185).
fn resolve_relative_path(source_file_path: &str, subpath: Option<&str>) -> PathBuf {
    let source = PathBuf::from(source_file_path);
    let parent = source.parent().unwrap_or_else(|| Path::new(""));

    if let Some(sub) = subpath {
        parent.join(sub)
    } else {
        parent.to_path_buf()
    }
}

// MARK: - Concurrent generation

/// Generates files concurrently using rayon's parallel iterator.
///
/// Takes a list of file generators, runs them all in parallel via `par_iter`,
/// and collects any non-fatal errors from all generators.
///
/// Mirrors the concurrent generation pattern from Swift's `ApolloCodegen.swift`.
pub fn generate_files_concurrently(
    generators: &[Box<dyn FileGenerator + Send + Sync>],
    config: &ConfigurationContext,
    file_manager: &ApolloFileManager,
) -> Result<Vec<NonFatalError>, std::io::Error> {
    use rayon::prelude::*;

    let results: Vec<Result<Vec<NonFatalError>, std::io::Error>> = generators
        .par_iter()
        .map(|gen| gen.generate(config, file_manager))
        .collect();

    let mut all_errors = Vec::new();
    for result in results {
        all_errors.extend(result?);
    }
    Ok(all_errors)
}

// MARK: - Stale file pruning

/// Walks directories and collects existing `.graphql.swift` file paths.
///
/// Discovers files in schema_types path, operations path (if absolute),
/// and test_mocks path (if absolute).
///
/// Mirrors Swift's `ApolloCodegen.findExistingGeneratedFilePaths(forConfig:)`.
pub fn find_existing_generated_file_paths(
    config: &ConfigurationContext,
) -> Result<std::collections::BTreeSet<PathBuf>, std::io::Error> {
    use globset::Glob;
    use std::collections::BTreeSet;
    use walkdir::WalkDir;

    let mut paths = BTreeSet::new();
    let glob = Glob::new("*.graphql.swift")
        .expect("valid glob")
        .compile_matcher();

    // Helper closure to walk a directory and collect matching files
    let walk_dir = |dir: &Path, paths: &mut BTreeSet<PathBuf>| {
        if !dir.exists() {
            return;
        }
        for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
            if entry.file_type().is_file() {
                if let Some(name) = entry.path().file_name() {
                    if glob.is_match(name) {
                        paths.insert(normalize_path(entry.path()));
                    }
                }
            }
        }
    };

    // Walk schema types path
    let schema_path = resolve_url(&config.output().schema_types.path, config.root_url());
    walk_dir(&schema_path, &mut paths);

    // Walk operations path if absolute
    if let OperationsFileOutput::Absolute { ref path, .. } = config.output().operations {
        let ops_path = resolve_url(path, config.root_url());
        walk_dir(&ops_path, &mut paths);
    }

    // Walk test mocks path if absolute
    match &config.output().test_mocks {
        TestMockFileOutput::Absolute { ref path, .. } => {
            let mocks_path = resolve_url(path, config.root_url());
            walk_dir(&mocks_path, &mut paths);
        }
        TestMockFileOutput::SwiftPackage { .. } => {
            // SwiftPackage mocks are inside schema_types path, already walked
        }
        TestMockFileOutput::None => {}
    }

    Ok(paths)
}

/// Deletes files that exist on disk but are not in the file manager's written set.
///
/// Computes set difference: existing_paths - written_files -> delete each.
///
/// Mirrors Swift's `ApolloCodegen.deleteExtraneousGeneratedFiles(from:afterCodeGeneration:)`.
pub fn delete_extraneous_files(
    existing_paths: &std::collections::BTreeSet<PathBuf>,
    file_manager: &ApolloFileManager,
) -> Result<(), std::io::Error> {
    let written = file_manager.written_files();
    for path in existing_paths.difference(&written) {
        file_manager.delete_file(path)?;
    }
    Ok(())
}

/// Walks a single directory and collects `*.graphql.swift` file paths.
///
/// Simplified version of `find_existing_generated_file_paths` for testing.
pub fn find_existing_paths_in_dir(dir: &Path) -> std::collections::BTreeSet<PathBuf> {
    use globset::Glob;
    use std::collections::BTreeSet;
    use walkdir::WalkDir;

    let mut paths = BTreeSet::new();
    let glob = Glob::new("*.graphql.swift")
        .expect("valid glob")
        .compile_matcher();

    if !dir.exists() {
        return paths;
    }

    for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            if let Some(name) = entry.path().file_name() {
                if glob.is_match(name) {
                    paths.insert(normalize_path(entry.path()));
                }
            }
        }
    }

    paths
}

// MARK: - Path helpers

/// Pure-path normalization that strips `.` and `..` components without filesystem access.
///
/// Unlike `std::fs::canonicalize()`, this works on paths that don't exist on disk.
fn normalize_path(path: &Path) -> PathBuf {
    let mut components = Vec::new();
    for component in path.components() {
        match component {
            std::path::Component::CurDir => {} // skip "."
            std::path::Component::ParentDir => {
                components.pop();
            }
            other => components.push(other),
        }
    }
    components.iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;

    // MARK: - Test helpers

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    fn make_config_with_root(json: &str, root: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, Some(PathBuf::from(root)))
    }

    fn spm_in_schema_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    fn spm_relative_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"relative": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    fn embedded_in_schema_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"embeddedInTarget": {"name": "MyApp"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    fn embedded_relative_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"embeddedInTarget": {"name": "MyApp"}} },
                "operations": {"relative": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    fn other_in_schema_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"other": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    fn other_relative_config(root: &str) -> ConfigurationContext {
        make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"other": {}} },
                "operations": {"relative": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            root,
        )
    }

    // MARK: - Schema path resolution tests

    #[test]
    fn test_resolve_schema_path_spm_in_schema_object() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::Object.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/Objects")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_enum() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::Enum.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/Enums")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_interface() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::Interface.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/Interfaces")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_union() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::Union.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/Unions")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_input_object() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::InputObject.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/InputObjects")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_custom_scalar() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::CustomScalar.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Schema/CustomScalars")
        );
    }

    #[test]
    fn test_resolve_schema_path_spm_in_schema_schema() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::Schema.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Sources/Schema"));
    }

    #[test]
    fn test_resolve_schema_path_spm_relative_object() {
        // SPM + relative operations => no Schema/ prefix for schema types
        let config = spm_relative_config("/root");
        let path = FileTarget::Object.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Sources/Objects"));
    }

    #[test]
    fn test_resolve_schema_path_embedded_in_schema_object() {
        let config = embedded_in_schema_config("/root");
        let path = FileTarget::Object.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Schema/Objects"));
    }

    #[test]
    fn test_resolve_schema_path_embedded_relative_object() {
        let config = embedded_relative_config("/root");
        let path = FileTarget::Object.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Objects"));
    }

    #[test]
    fn test_resolve_schema_path_other_in_schema_interface() {
        let config = other_in_schema_config("/root");
        let path = FileTarget::Interface.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Schema/Interfaces"));
    }

    #[test]
    fn test_resolve_schema_path_other_relative_custom_scalar() {
        let config = other_relative_config("/root");
        let path = FileTarget::CustomScalar.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/CustomScalars"));
    }

    // MARK: - Operation path resolution tests

    #[test]
    fn test_resolve_operation_path_in_schema_spm_query() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Operation {
            operation_type: OperationType::Query,
            file_path: "/src/MyQuery.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Operations/Queries")
        );
    }

    #[test]
    fn test_resolve_operation_path_in_schema_spm_mutation() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Operation {
            operation_type: OperationType::Mutation,
            file_path: "/src/MyMutation.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Operations/Mutations")
        );
    }

    #[test]
    fn test_resolve_operation_path_in_schema_spm_subscription() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Operation {
            operation_type: OperationType::Subscription,
            file_path: "/src/MySub.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/Operations/Subscriptions")
        );
    }

    #[test]
    fn test_resolve_operation_path_in_schema_spm_local_cache_mutation() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Operation {
            operation_type: OperationType::Query,
            file_path: "/src/MyLCM.graphql".to_string(),
            is_local_cache_mutation: true,
        };
        let path = target.resolve_path(&config);
        // LCM: no Operations/ prefix
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/LocalCacheMutations")
        );
    }

    #[test]
    fn test_resolve_operation_path_absolute_query() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"absolute": {"path": "/abs/ops"}},
                "testMocks": {"none": {}}
            }
        }"#,
            "/root",
        );
        let target = FileTarget::Operation {
            operation_type: OperationType::Query,
            file_path: "/src/MyQuery.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/abs/ops/Queries"));
    }

    #[test]
    fn test_resolve_operation_path_relative_no_subpath() {
        let config = spm_relative_config("/root");
        let target = FileTarget::Operation {
            operation_type: OperationType::Query,
            file_path: "/src/graphql/MyQuery.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/src/graphql"));
    }

    #[test]
    fn test_resolve_operation_path_relative_with_subpath() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"relative": {"subpath": "Generated"}},
                "testMocks": {"none": {}}
            }
        }"#,
            "/root",
        );
        let target = FileTarget::Operation {
            operation_type: OperationType::Query,
            file_path: "/src/graphql/MyQuery.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/src/graphql/Generated"));
    }

    // MARK: - Fragment path resolution tests

    #[test]
    fn test_resolve_fragment_path_in_schema_spm() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Fragment {
            file_path: "/src/MyFragment.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/Sources/Fragments"));
    }

    #[test]
    fn test_resolve_fragment_path_in_schema_spm_local_cache_mutation() {
        let config = spm_in_schema_config("/root");
        let target = FileTarget::Fragment {
            file_path: "/src/MyLCMFragment.graphql".to_string(),
            is_local_cache_mutation: true,
        };
        let path = target.resolve_path(&config);
        assert_eq!(
            path,
            PathBuf::from("/root/SchemaModule/Sources/LocalCacheMutations")
        );
    }

    #[test]
    fn test_resolve_fragment_path_absolute() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"absolute": {"path": "/abs/ops"}},
                "testMocks": {"none": {}}
            }
        }"#,
            "/root",
        );
        let target = FileTarget::Fragment {
            file_path: "/src/MyFragment.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/abs/ops/Fragments"));
    }

    #[test]
    fn test_resolve_fragment_path_relative_no_subpath() {
        let config = spm_relative_config("/root");
        let target = FileTarget::Fragment {
            file_path: "/src/graphql/MyFragment.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/src/graphql"));
    }

    #[test]
    fn test_resolve_fragment_path_relative_with_subpath() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"relative": {"subpath": "GeneratedFragments"}},
                "testMocks": {"none": {}}
            }
        }"#,
            "/root",
        );
        let target = FileTarget::Fragment {
            file_path: "/src/graphql/MyFragment.graphql".to_string(),
            is_local_cache_mutation: false,
        };
        let path = target.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/src/graphql/GeneratedFragments"));
    }

    // MARK: - Test mock path resolution tests

    #[test]
    fn test_resolve_test_mock_path_none() {
        let config = spm_in_schema_config("/root");
        let path = FileTarget::TestMock.resolve_path(&config);
        assert_eq!(path, PathBuf::new());
    }

    #[test]
    fn test_resolve_test_mock_path_swift_package_default_name() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"swiftPackage": {"targetName": null}}
            }
        }"#,
            "/root",
        );
        let path = FileTarget::TestMock.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/TestMocks"));
    }

    #[test]
    fn test_resolve_test_mock_path_swift_package_custom_name() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"swiftPackage": {"targetName": "MyMocks"}}
            }
        }"#,
            "/root",
        );
        let path = FileTarget::TestMock.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/root/SchemaModule/MyMocks"));
    }

    #[test]
    fn test_resolve_test_mock_path_absolute() {
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "SchemaModule", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"absolute": {"path": "/abs/mocks"}}
            }
        }"#,
            "/root",
        );
        let path = FileTarget::TestMock.resolve_path(&config);
        assert_eq!(path, PathBuf::from("/abs/mocks"));
    }

    // MARK: - Filename resolution tests

    #[test]
    fn test_resolve_filename_no_suffix() {
        let config = make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );

        struct TestGen;
        impl FileGenerator for TestGen {
            fn file_name(&self) -> String {
                "dog".to_string()
            }
            fn template(&self) -> Box<dyn TemplateRenderer + '_> {
                unimplemented!()
            }
            fn target(&self) -> FileTarget {
                FileTarget::Object
            }
        }

        let gen = TestGen;
        assert_eq!(gen.resolve_filename(&config), "Dog");
    }

    #[test]
    fn test_resolve_filename_with_suffix_disabled() {
        // append_schema_type_filename_suffix defaults to false
        let config = make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );

        struct TestGen;
        impl FileGenerator for TestGen {
            fn file_name(&self) -> String {
                "dog".to_string()
            }
            fn file_suffix(&self) -> Option<&str> {
                Some(".object")
            }
            fn template(&self) -> Box<dyn TemplateRenderer + '_> {
                unimplemented!()
            }
            fn target(&self) -> FileTarget {
                FileTarget::Object
            }
        }

        let gen = TestGen;
        // Even with suffix defined, config has it disabled
        assert_eq!(gen.resolve_filename(&config), "Dog");
    }

    #[test]
    fn test_resolve_filename_with_suffix_enabled() {
        let config = make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            },
            "options": {
                "appendSchemaTypeFilenameSuffix": true
            }
        }"#,
        );

        struct TestGen;
        impl FileGenerator for TestGen {
            fn file_name(&self) -> String {
                "dog".to_string()
            }
            fn file_suffix(&self) -> Option<&str> {
                Some(".object")
            }
            fn template(&self) -> Box<dyn TemplateRenderer + '_> {
                unimplemented!()
            }
            fn target(&self) -> FileTarget {
                FileTarget::Object
            }
        }

        let gen = TestGen;
        assert_eq!(gen.resolve_filename(&config), "Dog.object");
    }

    #[test]
    fn test_resolve_filename_with_suffix_enabled_but_no_suffix() {
        let config = make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            },
            "options": {
                "appendSchemaTypeFilenameSuffix": true
            }
        }"#,
        );

        struct TestGen;
        impl FileGenerator for TestGen {
            fn file_name(&self) -> String {
                "allAnimalsQuery".to_string()
            }
            fn template(&self) -> Box<dyn TemplateRenderer + '_> {
                unimplemented!()
            }
            fn target(&self) -> FileTarget {
                FileTarget::Operation {
                    operation_type: OperationType::Query,
                    file_path: String::new(),
                    is_local_cache_mutation: false,
                }
            }
        }

        let gen = TestGen;
        // Operations have no suffix, so even with config enabled, no suffix appended
        assert_eq!(gen.resolve_filename(&config), "AllAnimalsQuery");
    }

    // MARK: - Helper function tests

    #[test]
    fn test_resolve_url_absolute_path() {
        let result = resolve_url("/absolute/path", Some(Path::new("/root")));
        assert_eq!(result, PathBuf::from("/absolute/path"));
    }

    #[test]
    fn test_resolve_url_relative_with_root() {
        let result = resolve_url("relative/path", Some(Path::new("/root")));
        assert_eq!(result, PathBuf::from("/root/relative/path"));
    }

    #[test]
    fn test_resolve_url_relative_without_root() {
        let result = resolve_url("relative/path", None);
        assert_eq!(result, PathBuf::from("relative/path"));
    }

    #[test]
    fn test_normalize_path_strips_dot() {
        let path = PathBuf::from("/a/./b/c");
        assert_eq!(normalize_path(&path), PathBuf::from("/a/b/c"));
    }

    #[test]
    fn test_normalize_path_strips_dotdot() {
        let path = PathBuf::from("/a/b/../c");
        assert_eq!(normalize_path(&path), PathBuf::from("/a/c"));
    }

    #[test]
    fn test_normalize_path_no_change_needed() {
        let path = PathBuf::from("/a/b/c");
        assert_eq!(normalize_path(&path), PathBuf::from("/a/b/c"));
    }

    // MARK: - Path traversal safety test

    #[test]
    fn test_path_traversal_constrained_by_root_url() {
        // Config with path that tries to traverse up
        let config = make_config_with_root(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "../../etc", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
            "/root/project",
        );
        let path = FileTarget::Object.resolve_path(&config);
        // After normalization, ".." should be resolved relative to root
        // /root/project/../../etc -> /etc (normalized)
        // The path should NOT escape beyond filesystem root
        assert_eq!(path, PathBuf::from("/etc/Sources/Schema/Objects"));
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_file_manager_creates_parent_directories() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();
        let path = dir.path().join("sub/dir/file.graphql.swift");
        fm.create_file(&path, b"content", true).unwrap();
        assert!(path.exists());
        assert!(fm.written_files().contains(&path));
    }

    #[test]
    fn test_file_manager_no_overwrite_preserves_existing() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();
        let path = dir.path().join("existing.swift");
        std::fs::write(&path, b"original").unwrap();
        fm.create_file(&path, b"new content", false).unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "original");
    }

    #[test]
    fn test_prune_deletes_stale_files() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();

        // Create "current" file via file manager
        let current = dir.path().join("Current.graphql.swift");
        fm.create_file(&current, b"current", true).unwrap();

        // Create "stale" file directly on disk (not tracked by file manager)
        let stale = dir.path().join("Stale.graphql.swift");
        std::fs::write(&stale, b"stale").unwrap();

        // Both exist on disk
        let existing = find_existing_paths_in_dir(dir.path());
        assert!(existing.contains(&normalize_path(&current)));
        assert!(existing.contains(&normalize_path(&stale)));

        // Prune: should delete stale, keep current
        delete_extraneous_files(&existing, &fm).unwrap();

        // Stale deleted, current preserved
        assert!(current.exists());
        assert!(!stale.exists());
    }

    #[test]
    fn test_written_files_uses_btreeset() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();
        fm.create_file(&dir.path().join("b.swift"), b"b", true)
            .unwrap();
        fm.create_file(&dir.path().join("a.swift"), b"a", true)
            .unwrap();
        let written: Vec<_> = fm.written_files().into_iter().collect();
        // BTreeSet is sorted -- 'a' before 'b'
        assert!(
            written[0].file_name().unwrap().to_str().unwrap()
                < written[1].file_name().unwrap().to_str().unwrap()
        );
    }

    #[test]
    fn test_find_existing_paths_in_dir_nested() {
        let dir = tempdir().unwrap();

        // Create files in nested directories
        let sub = dir.path().join("Objects");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(sub.join("Dog.graphql.swift"), b"dog").unwrap();
        std::fs::write(sub.join("Cat.graphql.swift"), b"cat").unwrap();
        // Non-matching file should be excluded
        std::fs::write(sub.join("README.md"), b"readme").unwrap();

        let paths = find_existing_paths_in_dir(dir.path());
        assert_eq!(paths.len(), 2);
        assert!(paths.iter().any(|p| p.ends_with("Dog.graphql.swift")));
        assert!(paths.iter().any(|p| p.ends_with("Cat.graphql.swift")));
    }

    #[test]
    fn test_find_existing_paths_in_nonexistent_dir() {
        let paths = find_existing_paths_in_dir(std::path::Path::new("/nonexistent/path"));
        assert!(paths.is_empty());
    }

    #[test]
    fn test_delete_extraneous_no_written_files_deletes_all() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();

        // Create files directly on disk (none tracked)
        let file1 = dir.path().join("A.graphql.swift");
        let file2 = dir.path().join("B.graphql.swift");
        std::fs::write(&file1, b"a").unwrap();
        std::fs::write(&file2, b"b").unwrap();

        let existing = find_existing_paths_in_dir(dir.path());
        assert_eq!(existing.len(), 2);

        delete_extraneous_files(&existing, &fm).unwrap();

        assert!(!file1.exists());
        assert!(!file2.exists());
    }

    #[test]
    fn test_delete_extraneous_all_tracked_deletes_none() {
        let dir = tempdir().unwrap();
        let fm = ApolloFileManager::new();

        // Create files via file manager (all tracked)
        let file1 = dir.path().join("A.graphql.swift");
        let file2 = dir.path().join("B.graphql.swift");
        fm.create_file(&file1, b"a", true).unwrap();
        fm.create_file(&file2, b"b", true).unwrap();

        let existing = find_existing_paths_in_dir(dir.path());
        assert_eq!(existing.len(), 2);

        delete_extraneous_files(&existing, &fm).unwrap();

        // Both should still exist
        assert!(file1.exists());
        assert!(file2.exists());
    }
}
