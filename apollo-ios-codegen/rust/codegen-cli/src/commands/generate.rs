//! Generate command implementation.
//!
//! Mirrors Swift's `Sources/CodegenCLI/Commands/Generate.swift`.
//! Loads configuration, determines items to generate, and calls
//! `ApolloCodegen::build()` via the `CodegenProvider` trait.
//!
//! When `--bazel-output-dir` is set, generation writes directly into a Bazel
//! tree artifact directory (`schema_types` or `operations` mode) and
//! post-processes it in place (hand-written file removal, import stripping,
//! SchemaMetadata optimization). This enables the Rust CLI to serve as a
//! direct Bazel persistent worker.

use std::path::Path;

use clap::Args;
use regex::Regex;

use apollo_codegen_lib::codegen::{
    ApolloCodegen, CodegenProvider, CompileResult, GenerationFilter, ItemsToGenerate,
};
use apollo_codegen_lib::codegen_logger::CodegenLogger;
use apollo_codegen_lib::config::test_mock_file_output::TestMockScope;
use apollo_codegen_lib::config::ApolloCodegenConfiguration;
use apollo_codegen_lib::templates::ConfigurationContext;

use crate::error::CliError;
use crate::input_options::{self, InputOptions};

/// Generate Swift source code based on a code generation configuration.
#[derive(Args, Debug)]
pub struct Generate {
    #[command(flatten)]
    pub inputs: InputOptions,

    /// Fetch the GraphQL schema before Swift code generation.
    #[arg(short, long)]
    pub fetch_schema: bool,

    /// Bazel tree artifact output directory. When set, generated files are
    /// written directly into this directory instead of the configured output
    /// paths (the config's output paths only select the module layout).
    #[arg(long, help_heading = "Bazel")]
    pub bazel_output_dir: Option<String>,

    /// Bazel output mode. "schema_types" writes the schema types (plus, when
    /// `testMocks` is configured, the test mocks under `TestMocks/`); "operations"
    /// writes operation and fragment files only; "test_mocks" writes only the test
    /// mocks under `TestMocks/` (scoped by the --bazel-mocks-* flags; the
    /// `referenced` scope uses the --bazel-generate-for / --bazel-framework-path
    /// selection).
    #[arg(long, default_value = "schema_types", help_heading = "Bazel")]
    pub bazel_mode: String,

    /// Operations mode: generate the operations and fragments whose file path
    /// starts with this prefix (e.g. "Features/Account"). Ignored when
    /// --bazel-generate-for is given.
    #[arg(long, help_heading = "Bazel")]
    pub bazel_framework_path: Option<String>,

    /// Operations mode: generate exactly the operations and fragments defined
    /// in this file (repeat the flag for each file). Paths are compared after
    /// resolving them against the current directory, so Bazel exec paths work.
    /// Replaces --bazel-framework-path prefix matching when given.
    #[arg(long, value_name = "FILE", action = clap::ArgAction::Append, help_heading = "Bazel")]
    pub bazel_generate_for: Vec<String>,

    /// Strip `import <module>` lines from the generated files (e.g. the schema
    /// module's name when operations are compiled into the same module).
    #[arg(long, value_name = "MODULE", help_heading = "Bazel")]
    pub bazel_strip_import: Option<String>,

    /// Add a fast dictionary lookup to SchemaMetadata's objectType function,
    /// gated behind a `fastObjectTypeLookup` flag. Matches the configured
    /// `schemaNamespace`.
    #[arg(long, help_heading = "Bazel")]
    pub bazel_optimize_schema_metadata: bool,

    /// Keep `SchemaConfiguration.swift` and the `CustomScalars/` directory in
    /// the tree artifact. By default they are removed because they are
    /// user-editable files that a Bazel rule provides itself.
    #[arg(long, help_heading = "Bazel")]
    pub bazel_keep_schema_configuration: bool,

    /// Test mocks: which object types get a `<Type>+Mock.swift` file. "all" (the
    /// config's default) mocks every type referenced by any operation; "referenced"
    /// mocks only the types referenced by the selected operations and fragments
    /// (--bazel-generate-for / --bazel-framework-path), including the types reached
    /// through the interfaces and unions they use. Overrides `testMocks.scope`.
    #[arg(long, value_name = "all|referenced", help_heading = "Bazel test mocks")]
    pub bazel_mocks_scope: Option<String>,

    /// Test mocks: always generate the mock for this object type (repeatable). The
    /// type must be referenced by some operation. Overrides `testMocks.includeTypes`.
    #[arg(long, value_name = "TYPE", action = clap::ArgAction::Append, help_heading = "Bazel test mocks")]
    pub bazel_mocks_for: Vec<String>,

    /// Test mocks: never generate the mock for this object type (repeatable), e.g.
    /// because a base module provides it. Unknown names are ignored. Overrides
    /// `testMocks.excludeTypes`.
    #[arg(long, value_name = "TYPE", action = clap::ArgAction::Append, help_heading = "Bazel test mocks")]
    pub bazel_mocks_exclude: Vec<String>,

    /// Test mocks: the Swift module holding the shared mocks and the `MockObject`
    /// typealiases. Every generated mock file gets `import <MODULE>` and the
    /// `MockObject+Interfaces` / `MockObject+Unions` files are not generated (unless
    /// --bazel-mocks-typealiases). Overrides `testMocks.baseModule`.
    #[arg(long, value_name = "MODULE", help_heading = "Bazel test mocks")]
    pub bazel_mocks_base_module: Option<String>,

    /// Test mocks: generate the `MockObject+Interfaces` / `MockObject+Unions`
    /// typealias files even with --bazel-mocks-base-module (`true`), or never
    /// (`false`). They list every interface/union of the schema that any operation
    /// references, so exactly one module of a partition must carry them.
    #[arg(long, value_name = "true|false", help_heading = "Bazel test mocks")]
    pub bazel_mocks_typealiases: Option<bool>,
}

impl Generate {
    pub fn run(&self) -> Result<(), CliError> {
        CodegenLogger::set_level(self.inputs.verbose);

        // D-70: --fetch-schema is accepted but errors if used (stub)
        if self.fetch_schema {
            return Err(CliError::Generic {
                description: "Schema downloading is not yet supported in the Rust CLI. \
                              Use the Swift CLI for now."
                    .to_string(),
            });
        }

        let mut configuration = self.inputs.get_codegen_configuration()?;
        self.apply_bazel_mock_overrides(&mut configuration)?;
        let items_to_generate = Self::items_to_generate(&configuration);
        let root_url = input_options::root_output_url(&self.inputs);

        if let Some(ref output_dir) = self.bazel_output_dir {
            // Direct-write mode: set output_root so generation writes
            // directly to the tree artifact directory. The tree artifact starts
            // empty, so there is nothing to prune; pruning would walk the
            // *configured* output paths (relative to the cwd, i.e. the execroot)
            // and delete every `*.graphql.swift` there that this run did not
            // write. The worker switches it off the same way.
            configuration.options.prune_generated_files = false;
            let mut config = ConfigurationContext::new(configuration, root_url);
            let output_root = std::path::PathBuf::from(output_dir);
            std::fs::create_dir_all(&output_root).map_err(|e| CliError::Generic {
                description: format!("Failed to create output dir {}: {}", output_dir, e),
            })?;
            config.set_output_root(Some(output_root));

            let compile_result = ApolloCodegen::compile_schema_and_ir(&config)?;
            self.generate_bazel(&compile_result, &config, items_to_generate)?;
        } else {
            // Standard mode: no output_root, write to configured paths
            ApolloCodegen::build(&configuration, root_url.as_deref(), items_to_generate)?;
        }

        Ok(())
    }

    /// The items the configuration asks for: code, plus the operation manifest when
    /// `generateManifestOnCodeGeneration` is set.
    pub fn items_to_generate(configuration: &ApolloCodegenConfiguration) -> ItemsToGenerate {
        let mut items_to_generate = ItemsToGenerate::CODE;
        if let Some(ref manifest) = configuration.operation_manifest {
            if manifest.generate_manifest_on_code_generation {
                items_to_generate |= ItemsToGenerate::OPERATION_MANIFEST;
            }
        }
        items_to_generate
    }

    /// Whether any `--bazel-mocks-*` flag was given.
    fn has_bazel_mock_flags(&self) -> bool {
        self.bazel_mocks_scope.is_some()
            || !self.bazel_mocks_for.is_empty()
            || !self.bazel_mocks_exclude.is_empty()
            || self.bazel_mocks_base_module.is_some()
            || self.bazel_mocks_typealiases.is_some()
    }

    /// Applies the `--bazel-mocks-*` flags on top of the config's `output.testMocks`
    /// scoping (each flag replaces the corresponding config key). `--bazel-mode
    /// test_mocks` and the flags require a configured (`absolute` or `swiftPackage`)
    /// test mock output.
    pub fn apply_bazel_mock_overrides(
        &self,
        configuration: &mut ApolloCodegenConfiguration,
    ) -> Result<(), CliError> {
        let wants_mocks = self.has_bazel_mock_flags() || self.bazel_mode == "test_mocks";
        if !wants_mocks {
            return Ok(());
        }
        if self.bazel_output_dir.is_none() {
            return Err(CliError::Generic {
                description: "--bazel-mode test_mocks and the --bazel-mocks-* flags require --bazel-output-dir".to_string(),
            });
        }
        let Some(scoping) = configuration.output.test_mocks.scoping_mut() else {
            return Err(CliError::Generic {
                description: "--bazel-mode test_mocks and the --bazel-mocks-* flags require 'output.testMocks' to be 'absolute' or 'swiftPackage' (it is 'none')".to_string(),
            });
        };
        if let Some(ref scope) = self.bazel_mocks_scope {
            scoping.scope = match scope.as_str() {
                "all" => TestMockScope::All,
                "referenced" | "referencedByOperations" => TestMockScope::ReferencedByOperations,
                other => {
                    return Err(CliError::Generic {
                        description: format!(
                            "Unknown --bazel-mocks-scope: {} (expected 'all' or 'referenced')",
                            other
                        ),
                    })
                }
            };
        }
        if !self.bazel_mocks_for.is_empty() {
            scoping.include_types = self.bazel_mocks_for.clone();
        }
        if !self.bazel_mocks_exclude.is_empty() {
            scoping.exclude_types = self.bazel_mocks_exclude.clone();
        }
        if let Some(ref module) = self.bazel_mocks_base_module {
            scoping.base_module = Some(module.clone());
        }
        if let Some(typealiases) = self.bazel_mocks_typealiases {
            scoping.include_typealiases = Some(typealiases);
        }
        Ok(())
    }

    /// Whether `--bazel-mode operations` was requested.
    pub fn is_operations_mode(&self) -> bool {
        self.bazel_mode == "operations"
    }

    /// The operations-mode selection: exact files when `--bazel-generate-for` is
    /// given, otherwise the `--bazel-framework-path` prefix, otherwise everything.
    pub fn generation_filter(&self) -> Option<GenerationFilter> {
        if !self.bazel_generate_for.is_empty() {
            Some(GenerationFilter::Files(self.bazel_generate_for.clone()))
        } else {
            self.bazel_framework_path
                .as_ref()
                .map(|prefix| GenerationFilter::Prefix(prefix.clone()))
        }
    }

    /// Generates into the tree artifact (`config.output_root()`) according to
    /// `--bazel-mode` and post-processes it. Shared by the one-shot CLI and the
    /// persistent worker.
    pub fn generate_bazel(
        &self,
        compile_result: &CompileResult,
        config: &ConfigurationContext,
        items_to_generate: ItemsToGenerate,
    ) -> Result<(), CliError> {
        match self.bazel_mode.as_str() {
            "operations" => match self.generation_filter() {
                Some(filter) => ApolloCodegen::generate_from_ir_filtered(
                    compile_result,
                    config,
                    items_to_generate,
                    &filter,
                )?,
                None => ApolloCodegen::generate_from_ir_operations_only(
                    compile_result,
                    config,
                    items_to_generate,
                )?,
            },
            "schema_types" => ApolloCodegen::generate_from_ir_schema_only(
                compile_result,
                config,
                items_to_generate,
            )?,
            "test_mocks" => ApolloCodegen::generate_from_ir_test_mocks_only(
                compile_result,
                config,
                self.generation_filter().as_ref(),
            )?,
            other => {
                return Err(CliError::Generic {
                    description: format!("Unknown --bazel-mode: {}", other),
                })
            }
        }

        let output_dir = match config.output_root() {
            Some(root) => root.to_path_buf(),
            None => {
                return Err(CliError::Generic {
                    description: "--bazel-output-dir is required for Bazel generation".to_string(),
                })
            }
        };
        self.postprocess_tree_artifact(&output_dir, &config.config.schema_namespace)
    }

    /// Post-processes files already written directly to a Bazel tree artifact.
    /// Removes the user-editable files (unless `--bazel-keep-schema-configuration`),
    /// strips imports and optimizes SchemaMetadata in place.
    pub fn postprocess_tree_artifact(
        &self,
        output_dir: &Path,
        schema_namespace: &str,
    ) -> Result<(), CliError> {
        let out = output_dir;

        // SchemaConfiguration.swift and CustomScalars/ are generated with overwrite:false
        // into the (empty) tree artifact; a rule normally provides them itself.
        if !self.bazel_keep_schema_configuration {
            let schema_config = out.join("SchemaConfiguration.swift");
            if schema_config.exists() {
                std::fs::remove_file(&schema_config).ok();
            }
            let custom_scalars = out.join("CustomScalars");
            if custom_scalars.is_dir() {
                std::fs::remove_dir_all(&custom_scalars).ok();
            }
        }

        // Strip imports if requested
        if let Some(ref module) = self.bazel_strip_import {
            strip_import_from_dir_recursive(out, module)?;
        }

        // Optimize SchemaMetadata if requested
        if self.bazel_optimize_schema_metadata {
            let metadata_file = out.join("SchemaMetadata.graphql.swift");
            if metadata_file.exists() {
                optimize_schema_metadata(&metadata_file, schema_namespace)?;
            }
        }

        eprintln!("Bazel direct-write post-processed: {}", out.display());
        Ok(())
    }
}

/// Recursively walks a directory, calling `visitor` for each file.
fn walk_dir_recursive(
    dir: &Path,
    visitor: &mut dyn FnMut(&Path) -> Result<(), CliError>,
) -> Result<(), CliError> {
    if !dir.is_dir() {
        return Ok(());
    }
    let entries = std::fs::read_dir(dir).map_err(|e| CliError::Generic {
        description: format!("read_dir {}: {}", dir.display(), e),
    })?;
    for entry in entries {
        let entry = entry.map_err(|e| CliError::Generic {
            description: format!("dir entry error: {}", e),
        })?;
        let path = entry.path();
        if path.is_dir() {
            walk_dir_recursive(&path, visitor)?;
        } else {
            visitor(&path)?;
        }
    }
    Ok(())
}

/// Recursively strips `import <module>\n` from all .graphql.swift files in a directory tree.
fn strip_import_from_dir_recursive(dir: &Path, module: &str) -> Result<(), CliError> {
    let import_line = format!("import {}", module);
    walk_dir_recursive(dir, &mut |entry_path| {
        let name = entry_path
            .file_name()
            .and_then(|f| f.to_str())
            .unwrap_or("");
        if !name.ends_with(".graphql.swift") {
            return Ok(());
        }
        let content = std::fs::read_to_string(entry_path).map_err(|e| CliError::Generic {
            description: format!("read {}: {}", entry_path.display(), e),
        })?;
        let new_content = content.replace(&format!("{}\n", import_line), "");
        if new_content != content {
            std::fs::write(entry_path, new_content).map_err(|e| CliError::Generic {
                description: format!("write {}: {}", entry_path.display(), e),
            })?;
        }
        Ok(())
    })
}

/// Adds a fast O(1) dictionary lookup to SchemaMetadata's objectType function,
/// gated behind a `fastObjectTypeLookup` flag.
///
/// The switch cases are `case "Name": return <Namespace>.Objects.Name` when the
/// schema types live in their own module and `case "Name": return Objects.Name`
/// when they are embedded, so both spellings are matched for the configured
/// `schema_namespace`. The function signature may carry attributes
/// (`@_spi(Execution)` from Apollo iOS 2.0) which are preserved.
fn optimize_schema_metadata(path: &Path, schema_namespace: &str) -> Result<(), CliError> {
    let content = std::fs::read_to_string(path).map_err(|e| CliError::Generic {
        description: format!("read {}: {}", path.display(), e),
    })?;

    // Match the objectType switch statement
    let func_re = Regex::new(
        r"(?s)( {2}(?:@\w+(?:\([^)]*\))? )*public static func objectType\(forTypename typename: String\) -> ApolloAPI\.Object\? \{\n)(    switch typename \{\n(.*?)    default: return nil\n    \}\n  \})"
    ).unwrap();

    let caps = match func_re.captures(&content) {
        Some(c) => c,
        None => return Ok(()), // No match, nothing to optimize
    };

    let cases_block = &caps[3];
    let case_re = Regex::new(&format!(
        r#"^ {{4}}case (".*?"): return ((?:{}\.)?Objects\.\w+)$"#,
        regex::escape(schema_namespace)
    ))
    .map_err(|e| CliError::Generic {
        description: format!("invalid schema namespace '{}': {}", schema_namespace, e),
    })?;

    let entries: Vec<(String, String)> = cases_block
        .lines()
        .filter_map(|line| {
            case_re.captures(line).map(|c| {
                (c[1].to_string(), c[2].to_string())
            })
        })
        .collect();

    if entries.is_empty() {
        return Ok(());
    }

    let dict_entries = entries
        .iter()
        .map(|(key, value)| format!("    {}: {}", key, value))
        .collect::<Vec<_>>()
        .join(",\n");

    let original_switch = &caps[2];
    let signature = caps[1].trim_end_matches('\n');

    let replacement = [
        "  public static var fastObjectTypeLookup = false",
        "",
        "  static let objectTypeMap: [String: ApolloAPI.Object] = [",
        &format!("{},", dict_entries),
        "  ]",
        "",
        signature,
        "    if fastObjectTypeLookup {",
        "      return objectTypeMap[typename]",
        "    }",
        original_switch,
    ]
    .join("\n");

    let new_content = func_re.replace(&content, &replacement);
    std::fs::write(path, new_content.as_ref()).map_err(|e| CliError::Generic {
        description: format!("write {}: {}", path.display(), e),
    })?;

    eprintln!(
        "Optimized SchemaMetadata with {} type entries",
        entries.len()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    /// Wrapper struct for testing Generate arg parsing.
    #[derive(Parser)]
    struct TestCli {
        #[command(flatten)]
        cmd: Generate,
    }

    fn generate(bazel_mode: &str) -> Generate {
        Generate {
            inputs: InputOptions {
                path: "./config.json".to_string(),
                string: None,
                verbose: false,
            },
            fetch_schema: false,
            bazel_output_dir: None,
            bazel_mode: bazel_mode.to_string(),
            bazel_framework_path: None,
            bazel_generate_for: vec![],
            bazel_strip_import: None,
            bazel_optimize_schema_metadata: false,
            bazel_keep_schema_configuration: false,
            bazel_mocks_scope: None,
            bazel_mocks_for: vec![],
            bazel_mocks_exclude: vec![],
            bazel_mocks_base_module: None,
            bazel_mocks_typealiases: None,
        }
    }

    #[test]
    fn test_generate_parses_fetch_schema_flag() {
        let cli = TestCli::try_parse_from(["test", "--fetch-schema"]).unwrap();
        assert!(cli.cmd.fetch_schema);
    }

    #[test]
    fn test_generate_default_no_fetch_schema() {
        let cli = TestCli::try_parse_from(["test"]).unwrap();
        assert!(!cli.cmd.fetch_schema);
    }

    #[test]
    fn test_generate_verbose_flag() {
        let cli = TestCli::try_parse_from(["test", "--verbose"]).unwrap();
        assert!(cli.cmd.inputs.verbose);
    }

    #[test]
    fn test_generate_fetch_schema_returns_stub_error() {
        let mut cmd = generate("schema_types");
        cmd.fetch_schema = true;
        let result = cmd.run();
        assert!(result.is_err());
        let err = result.unwrap_err();
        let msg = format!("{}", err);
        assert!(msg.contains("Schema downloading is not yet supported"));
    }

    #[test]
    fn test_bazel_args_parsing() {
        let cli = TestCli::try_parse_from([
            "test",
            "--bazel-output-dir",
            "/tmp/out",
            "--bazel-mode",
            "operations",
            "--bazel-framework-path",
            "Features/Account",
            "--bazel-strip-import",
            "MySchemaAPI",
            "--bazel-optimize-schema-metadata",
            "--bazel-keep-schema-configuration",
            "--bazel-generate-for",
            "Features/Account/A.graphql",
            "--bazel-generate-for",
            "Features/Account/B.graphql",
        ])
        .unwrap();
        assert_eq!(cli.cmd.bazel_output_dir.as_deref(), Some("/tmp/out"));
        assert_eq!(cli.cmd.bazel_mode, "operations");
        assert_eq!(
            cli.cmd.bazel_framework_path.as_deref(),
            Some("Features/Account")
        );
        assert_eq!(cli.cmd.bazel_strip_import.as_deref(), Some("MySchemaAPI"));
        assert!(cli.cmd.bazel_optimize_schema_metadata);
        assert!(cli.cmd.bazel_keep_schema_configuration);
        assert_eq!(
            cli.cmd.bazel_generate_for,
            vec!["Features/Account/A.graphql", "Features/Account/B.graphql"]
        );
    }

    #[test]
    fn test_bazel_mock_flags_parsing_and_overrides() {
        let cli = TestCli::try_parse_from([
            "test",
            "--bazel-output-dir", "/tmp/out",
            "--bazel-mode", "test_mocks",
            "--bazel-mocks-scope", "referenced",
            "--bazel-mocks-for", "Dog",
            "--bazel-mocks-for", "Cat",
            "--bazel-mocks-exclude", "Query",
            "--bazel-mocks-base-module", "BaseMocks",
            "--bazel-mocks-typealiases", "true",
        ])
        .unwrap();
        assert_eq!(cli.cmd.bazel_mode, "test_mocks");
        assert_eq!(cli.cmd.bazel_mocks_scope.as_deref(), Some("referenced"));
        assert_eq!(cli.cmd.bazel_mocks_for, vec!["Dog", "Cat"]);
        assert_eq!(cli.cmd.bazel_mocks_exclude, vec!["Query"]);
        assert_eq!(cli.cmd.bazel_mocks_base_module.as_deref(), Some("BaseMocks"));
        assert_eq!(cli.cmd.bazel_mocks_typealiases, Some(true));

        let mut configuration: ApolloCodegenConfiguration = serde_json::from_str(
            r#"{"schemaNamespace":"S","input":{},"output":{"schemaTypes":{"path":".","moduleType":{"other":{}}},
                "testMocks":{"absolute":{"path":"Mocks","excludeTypes":["User"]}}}}"#,
        )
        .unwrap();
        cli.cmd.apply_bazel_mock_overrides(&mut configuration).unwrap();
        let scoping = configuration.output.test_mocks.scoping().unwrap();
        assert_eq!(scoping.scope, TestMockScope::ReferencedByOperations);
        assert_eq!(scoping.include_types, vec!["Dog", "Cat"]);
        assert_eq!(scoping.exclude_types, vec!["Query"], "flags replace the config key");
        assert_eq!(scoping.base_module.as_deref(), Some("BaseMocks"));
        assert_eq!(scoping.include_typealiases, Some(true));
        assert!(scoping.generates_typealiases());
    }

    #[test]
    fn test_bazel_mock_flags_require_configured_mocks_and_output_dir() {
        let mut none: ApolloCodegenConfiguration = serde_json::from_str(
            r#"{"schemaNamespace":"S","input":{},"output":{"schemaTypes":{"path":".","moduleType":{"other":{}}}}}"#,
        )
        .unwrap();
        let mut cmd = generate("test_mocks");
        cmd.bazel_output_dir = Some("/tmp/out".to_string());
        let err = cmd.apply_bazel_mock_overrides(&mut none).unwrap_err().to_string();
        assert!(err.contains("'output.testMocks'"), "{err}");

        let mut mocks: ApolloCodegenConfiguration = serde_json::from_str(
            r#"{"schemaNamespace":"S","input":{},"output":{"schemaTypes":{"path":".","moduleType":{"other":{}}},
                "testMocks":{"absolute":{"path":"Mocks"}}}}"#,
        )
        .unwrap();
        let mut cmd = generate("schema_types");
        cmd.bazel_mocks_scope = Some("referenced".to_string());
        let err = cmd.apply_bazel_mock_overrides(&mut mocks).unwrap_err().to_string();
        assert!(err.contains("--bazel-output-dir"), "{err}");

        cmd.bazel_output_dir = Some("/tmp/out".to_string());
        cmd.bazel_mocks_scope = Some("bogus".to_string());
        let err = cmd.apply_bazel_mock_overrides(&mut mocks).unwrap_err().to_string();
        assert!(err.contains("Unknown --bazel-mocks-scope: bogus"), "{err}");

        // No flags, no test_mocks mode: the configuration is left alone.
        let before = mocks.clone();
        generate("schema_types").apply_bazel_mock_overrides(&mut mocks).unwrap();
        assert_eq!(mocks, before);
    }

    #[test]
    fn test_bazel_mode_defaults_to_schema_types() {
        let cli = TestCli::try_parse_from(["test"]).unwrap();
        assert_eq!(cli.cmd.bazel_mode, "schema_types");
        assert!(cli.cmd.bazel_output_dir.is_none());
        assert!(!cli.cmd.bazel_optimize_schema_metadata);
        assert!(!cli.cmd.bazel_keep_schema_configuration);
        assert!(cli.cmd.bazel_generate_for.is_empty());
    }

    #[test]
    fn test_generation_filter_prefers_exact_files_over_prefix() {
        let mut cmd = generate("operations");
        assert_eq!(cmd.generation_filter(), None);
        cmd.bazel_framework_path = Some("Features/Account".to_string());
        assert_eq!(
            cmd.generation_filter(),
            Some(GenerationFilter::Prefix("Features/Account".to_string()))
        );
        cmd.bazel_generate_for = vec!["Features/Account/A.graphql".to_string()];
        assert_eq!(
            cmd.generation_filter(),
            Some(GenerationFilter::Files(vec!["Features/Account/A.graphql".to_string()]))
        );
    }

    #[test]
    fn test_strip_import_from_dir_recursive() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("Operations")).unwrap();
        let file1 = dir.path().join("Operations/Query.graphql.swift");
        let file2 = dir.path().join("Fragment.graphql.swift");
        let file3 = dir.path().join("Other.txt");
        std::fs::write(
            &file1,
            "import ApolloAPI\nimport MySchemaAPI\n\npublic struct Query {}\n",
        )
        .unwrap();
        std::fs::write(
            &file2,
            "import ApolloAPI\n\npublic struct Fragment {}\n",
        )
        .unwrap();
        std::fs::write(&file3, "import MySchemaAPI\nshould not be touched\n").unwrap();

        strip_import_from_dir_recursive(dir.path(), "MySchemaAPI").unwrap();

        let content1 = std::fs::read_to_string(&file1).unwrap();
        assert!(!content1.contains("import MySchemaAPI"));
        assert!(content1.contains("import ApolloAPI"));
        assert!(content1.contains("public struct Query"));

        // file2 had no "import MySchemaAPI" -- should be unchanged
        let content2 = std::fs::read_to_string(&file2).unwrap();
        assert!(content2.contains("import ApolloAPI"));

        // file3 is not .graphql.swift -- should be untouched
        let content3 = std::fs::read_to_string(&file3).unwrap();
        assert!(content3.contains("import MySchemaAPI"));
    }

    const METADATA: &str = r#"import ApolloAPI

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "Cat": return MySchemaAPI.Objects.Cat
    case "Dog": return MySchemaAPI.Objects.Dog
    case "Bird": return MySchemaAPI.Objects.Bird
    default: return nil
    }
  }
}
"#;

    #[test]
    fn test_optimize_schema_metadata() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("SchemaMetadata.graphql.swift");
        std::fs::write(&file, METADATA).unwrap();

        optimize_schema_metadata(&file, "MySchemaAPI").unwrap();

        let result = std::fs::read_to_string(&file).unwrap();
        // Check 2-space indentation for declarations (matching enum body)
        assert!(result.contains("  public static var fastObjectTypeLookup = false"));
        assert!(result.contains("  static let objectTypeMap: [String: ApolloAPI.Object] = ["));
        // Check 4-space indentation for dictionary entries
        assert!(result.contains(r#"    "Cat": MySchemaAPI.Objects.Cat"#));
        assert!(result.contains(r#"    "Dog": MySchemaAPI.Objects.Dog"#));
        assert!(result.contains(r#"    "Bird": MySchemaAPI.Objects.Bird"#));
        // Check if-guard with correct indentation
        assert!(result.contains("    if fastObjectTypeLookup {"));
        assert!(result.contains("      return objectTypeMap[typename]"));
        // Original switch should still be present (gated behind !fastObjectTypeLookup)
        assert!(result.contains("switch typename"));
        assert!(result.contains("default: return nil"));
    }

    #[test]
    fn test_optimize_schema_metadata_keeps_signature_attributes() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("SchemaMetadata.graphql.swift");
        std::fs::write(
            &file,
            METADATA.replace("  public static func objectType", "  @_spi(Execution) public static func objectType"),
        )
        .unwrap();

        optimize_schema_metadata(&file, "MySchemaAPI").unwrap();

        let result = std::fs::read_to_string(&file).unwrap();
        assert!(result.contains("  @_spi(Execution) public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {\n    if fastObjectTypeLookup {"), "{}", result);
        assert!(result.contains(r#"    "Cat": MySchemaAPI.Objects.Cat"#), "{}", result);
        assert_eq!(result.matches("func objectType").count(), 1, "{}", result);
    }

    #[test]
    fn test_optimize_schema_metadata_requires_configured_namespace() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("SchemaMetadata.graphql.swift");
        std::fs::write(&file, METADATA).unwrap();

        // Another namespace matches no case: the file is left as is.
        optimize_schema_metadata(&file, "OtherAPI").unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), METADATA);
    }

    #[test]
    fn test_optimize_schema_metadata_embedded_objects_without_namespace() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("SchemaMetadata.graphql.swift");
        std::fs::write(&file, METADATA.replace("MySchemaAPI.Objects", "Objects")).unwrap();

        optimize_schema_metadata(&file, "MySchemaAPI").unwrap();
        let result = std::fs::read_to_string(&file).unwrap();
        assert!(result.contains(r#"    "Cat": Objects.Cat"#), "{}", result);
        assert!(result.contains("fastObjectTypeLookup"));
    }

    #[test]
    fn test_optimize_schema_metadata_no_match() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("SchemaMetadata.graphql.swift");
        let input = "// No objectType function here\npublic enum SchemaMetadata {}\n";
        std::fs::write(&file, input).unwrap();

        optimize_schema_metadata(&file, "MySchemaAPI").unwrap();

        let result = std::fs::read_to_string(&file).unwrap();
        assert_eq!(result, input); // unchanged
    }

    #[test]
    fn test_postprocess_removes_hand_written_files_unless_kept() {
        for keep in [false, true] {
            let dir = tempfile::tempdir().unwrap();
            std::fs::create_dir_all(dir.path().join("CustomScalars")).unwrap();
            std::fs::create_dir_all(dir.path().join("Objects")).unwrap();
            std::fs::write(dir.path().join("SchemaConfiguration.swift"), "config").unwrap();
            std::fs::write(dir.path().join("CustomScalars/Date.swift"), "date").unwrap();
            std::fs::write(dir.path().join("Objects/Cat.graphql.swift"), "cat").unwrap();

            let mut cmd = generate("schema_types");
            cmd.bazel_keep_schema_configuration = keep;
            cmd.postprocess_tree_artifact(dir.path(), "MySchemaAPI").unwrap();

            assert_eq!(dir.path().join("SchemaConfiguration.swift").exists(), keep);
            assert_eq!(dir.path().join("CustomScalars").is_dir(), keep);
            assert!(dir.path().join("Objects/Cat.graphql.swift").exists());
        }
    }

    #[test]
    fn test_unknown_bazel_mode_errors() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("schema.graphqls"), "type Query { a: Int }").unwrap();
        std::fs::write(dir.path().join("Q.graphql"), "query Q { a }").unwrap();
        let config_json = format!(
            r#"{{"schemaNamespace":"Inv","input":{{"schemaSearchPaths":["{d}/schema.graphqls"],"operationSearchPaths":["{d}/*.graphql"]}},"output":{{"schemaTypes":{{"path":"Out","moduleType":{{"other":{{}}}}}},"operations":{{"inSchemaModule":{{}}}},"testMocks":{{"none":{{}}}}}}}}"#,
            d = dir.path().display()
        );
        let configuration: ApolloCodegenConfiguration = serde_json::from_str(&config_json).unwrap();
        let mut config = ConfigurationContext::new(configuration, None);
        config.set_output_root(Some(dir.path().join("out")));
        let compile_result = ApolloCodegen::compile_schema_and_ir(&config).unwrap();
        let result = generate("invalid").generate_bazel(&compile_result, &config, ItemsToGenerate::CODE);
        let err = format!("{}", result.unwrap_err());
        assert!(err.contains("Unknown --bazel-mode: invalid"));
    }
}
