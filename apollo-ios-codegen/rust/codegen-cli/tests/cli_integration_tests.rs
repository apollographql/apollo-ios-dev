//! CLI Integration Tests: Swift-to-Rust CLI test coverage traceability.
//!
//! Mirrors: Tests/CodegenCLITests/
//!
//! Mapping:
//! - Commands/GenerateTests.swift (12 methods) -> mod generate_tests
//! - Commands/InitializeTests.swift (16 methods) -> mod initialize_tests
//! - Commands/GenerateOperationManifestTests.swift (9 methods) -> mod generate_operation_manifest_tests
//! - Commands/FetchSchemaTests.swift (6 methods) -> DOCUMENTED SKIP (v2 scope, schema download)
//! - VersionCheckerTests.swift (11 methods) -> DOCUMENTED SKIP (Swift SPM VersionChecker API)
//! - Matchers/ErrorMatchers.swift (0 test methods) -> N/A (test helper)
//! - Support/MockApolloCodegen.swift (0 test methods) -> N/A (test helper)
//! - Support/MockApolloCodegenConfiguration.swift (0 test methods) -> N/A (test helper)
//! - Support/MockApolloSchemaDownloader.swift (0 test methods) -> N/A (test helper)
//! - Support/MockFileManager.swift (0 test methods) -> N/A (test helper)
//! - Support/MockLogLevelSetter.swift (0 test methods) -> N/A (test helper)
//! - Support/TestSupport.swift (0 test methods) -> N/A (test helper)
//! - swiftpm-test/Package.swift (0 test methods) -> N/A (test fixture)
//! - swiftpm-test/Sources/swiftpm-test/swiftpm_test.swift (0 test methods) -> N/A (test fixture)

use assert_cmd::Command;
use std::fs;
use std::path::PathBuf;
use std::sync::Once;
use tempfile::TempDir;

// Build the CLI binary once for all tests.
// assert_cmd::Command::cargo_bin only works when the binary is in the same
// crate or is a dev-dependency's binary. Since apollo-ios-cli is a separate
// workspace member, we build it via cargo and locate the binary in the target
// profile directory this test binary was built into (so CARGO_TARGET_DIR and
// --target-dir are honored).
static BUILD_ONCE: Once = Once::new();

fn workspace_root() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); // up from codegen-cli to rust/
    path
}

/// `<target-dir>/<profile>` for the running test binary (cargo puts tests in `<profile>/deps`).
fn target_profile_dir() -> PathBuf {
    let exe = std::env::current_exe().expect("current_exe");
    let mut dir = exe.parent().expect("test binary directory").to_path_buf();
    if dir.file_name().map(|n| n == "deps").unwrap_or(false) {
        dir.pop();
    }
    dir
}

fn cli_bin() -> Command {
    let profile_dir = target_profile_dir();
    let bin = profile_dir.join(format!("apollo-ios-cli{}", std::env::consts::EXE_SUFFIX));

    BUILD_ONCE.call_once(|| {
        let target_dir = profile_dir
            .parent()
            .expect("target directory")
            .to_path_buf();
        let mut args = vec!["build", "--bin", "apollo-ios-cli"];
        if profile_dir
            .file_name()
            .map(|n| n == "release")
            .unwrap_or(false)
        {
            args.push("--release");
        }
        let status = std::process::Command::new(env!("CARGO"))
            .args(&args)
            .arg("--target-dir")
            .arg(&target_dir)
            .current_dir(workspace_root())
            .status()
            .expect("failed to build apollo-ios-cli");
        assert!(status.success(), "cargo build --bin apollo-ios-cli failed");
        assert!(
            bin.is_file(),
            "apollo-ios-cli not found at {}",
            bin.display()
        );
    });

    Command::new(bin)
}

// ============================================================================
// DOCUMENTED SKIPS
// ============================================================================

/// Documented skip: VersionCheckerTests.swift
///
/// 11 test methods testing Swift SPM VersionChecker APIs.
/// The VersionChecker reads Package.resolved to compare apollo-ios SPM version
/// against CLI version. This is a Swift-specific mechanism (SPM metadata parsing)
/// that has no Rust equivalent. The Rust CLI does not perform version checking
/// against Swift Package Manager resolved files.
///
/// Skipped methods:
/// - test__cliVersion__matchesApolloProjectVersion
/// - test__matchCLIVersionToApolloVersion__givenNoPackageResolvedFileInProject_returnsNoApolloVersionFound
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInProjectRoot_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInProjectRoot_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspace_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspace_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeProject_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeProject_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspaceAndProject_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch_fromWorkspace
/// - test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspaceAndProject_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMatch_fromWorkspace
/// - testPackageResolvedFile (private helper, not a test method)
#[test]
#[ignore = "Swift-specific: VersionChecker uses SPM Package.resolved parsing. 11 methods in VersionCheckerTests.swift. No Rust equivalent."]
fn skip_version_checker_tests() {}

/// Documented skip: FetchSchemaTests.swift
///
/// 6 test methods testing the fetch-schema CLI command.
/// Schema download is v2 scope (SCDL-*). The Rust CLI has a stub that
/// always returns an error. The Swift tests verify parsing, path/string input,
/// and verbose flag behavior -- all of which share the same InputOptions
/// infrastructure tested by generate_tests and initialize_tests.
///
/// Skipped methods:
/// - test__parsing__givenParameters_none_shouldUseDefaults
/// - test__fetchSchema__givenParameters_pathCustom_shouldBuildWithFileData
/// - test__fetchSchema__givenParameters_stringCustom_shouldBuildWithStringData
/// - test__fetchSchema__givenParameters_bothPathAndString_shouldBuildWithStringData
/// - test__fetchSchema__givenDefaultParameter_verbose_shouldSetLogLevelWarning
/// - test__fetchSchema__givenParameter_verbose_shouldSetLogLevelDebug
#[test]
#[ignore = "v2 scope: FetchSchema is a stub in Rust CLI (SCDL-*). 6 methods in FetchSchemaTests.swift. InputOptions parsing covered by generate/init tests."]
fn skip_fetch_schema_tests() {}

// ============================================================================
// Helper: build a minimal valid config JSON for CLI testing
// ============================================================================

fn minimal_config_json(schema_namespace: &str, output_path: &str) -> String {
    serde_json::json!({
        "schemaNamespace": schema_namespace,
        "input": {
            "schemaSearchPaths": ["**/*.graphqls"],
            "operationSearchPaths": ["**/*.graphql"]
        },
        "output": {
            "schemaTypes": {
                "path": output_path,
                "moduleType": {"swiftPackageManager": {}}
            },
            "operations": {"inSchemaModule": {}},
            "testMocks": {"none": {}}
        }
    })
    .to_string()
}

fn minimal_config_with_manifest(
    schema_namespace: &str,
    output_path: &str,
    manifest_path: &str,
) -> String {
    serde_json::json!({
        "schemaNamespace": schema_namespace,
        "input": {
            "schemaSearchPaths": ["**/*.graphqls"],
            "operationSearchPaths": ["**/*.graphql"]
        },
        "output": {
            "schemaTypes": {
                "path": output_path,
                "moduleType": {"swiftPackageManager": {}}
            },
            "operations": {"inSchemaModule": {}},
            "testMocks": {"none": {}}
        },
        "operationManifest": {
            "path": manifest_path,
            "version": "persistedQueries",
            "generateManifestOnCodeGeneration": false
        }
    })
    .to_string()
}

// ============================================================================
// Generate command tests
// ============================================================================
// Mirrors: Tests/CodegenCLITests/Commands/GenerateTests.swift
mod generate_tests {
    use super::*;

    #[test]
    fn test_generate_with_valid_config_exits_successfully() {
        // Create a temp directory with schema, operation, and config
        let tmp = TempDir::new().unwrap();
        let schema_path = tmp.path().join("schema.graphqls");
        fs::write(&schema_path, "type Query { hello: String }").unwrap();

        let op_path = tmp.path().join("query.graphql");
        fs::write(&op_path, "query HelloQuery { hello }").unwrap();

        let output_path = tmp.path().join("generated");
        fs::create_dir_all(&output_path).unwrap();

        let config = minimal_config_json("TestSchema", output_path.to_str().unwrap());
        let config_path = tmp.path().join("apollo-codegen-config.json");
        fs::write(&config_path, &config).unwrap();

        cli_bin()
            .arg("generate")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .current_dir(tmp.path())
            .assert()
            .success();
    }

    #[test]
    fn test_generate_with_nonexistent_config_exits_with_error() {
        let tmp = TempDir::new().unwrap();
        let fake_path = tmp.path().join("nonexistent-config.json");

        cli_bin()
            .arg("generate")
            .arg("--path")
            .arg(fake_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains("Error"));
    }

    #[test]
    fn test_generate_with_invalid_config_json_exits_with_error() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");
        fs::write(&config_path, "{ invalid json }").unwrap();

        cli_bin()
            .arg("generate")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains("Error"));
    }

    #[test]
    fn test_generate_with_fetch_schema_flag_returns_stub_error() {
        // --fetch-schema is accepted but returns a stub error
        let tmp = TempDir::new().unwrap();
        let config = minimal_config_json("TestSchema", "./generated");
        let config_path = tmp.path().join("apollo-codegen-config.json");
        fs::write(&config_path, &config).unwrap();

        cli_bin()
            .arg("generate")
            .arg("--fetch-schema")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains(
                "Schema downloading is not yet supported",
            ));
    }

    #[test]
    fn test_generate_default_looks_for_config_in_current_directory() {
        // When no --path is given, the CLI should look for apollo-codegen-config.json
        // in the current directory. Without that file, it should fail.
        let tmp = TempDir::new().unwrap();

        cli_bin()
            .arg("generate")
            .current_dir(tmp.path())
            .assert()
            .failure()
            .stderr(predicates::str::contains("Error"));
    }
}

// ============================================================================
// Initialize command tests
// ============================================================================
// Mirrors: Tests/CodegenCLITests/Commands/InitializeTests.swift
mod initialize_tests {
    use super::*;

    #[test]
    fn test_init_creates_config_file() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");

        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("MySchema")
            .arg("--module-type")
            .arg("swiftPackage")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .success();

        assert!(config_path.exists(), "config file should be created");
    }

    #[test]
    fn test_init_creates_valid_json_with_expected_keys() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");

        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("TestSchema")
            .arg("--module-type")
            .arg("swiftPackage")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .success();

        let content = fs::read_to_string(&config_path).unwrap();
        let json: serde_json::Value =
            serde_json::from_str(&content).expect("output should be valid JSON");

        assert!(
            json.get("schemaNamespace").is_some(),
            "should have schemaNamespace"
        );
        assert!(json.get("input").is_some(), "should have input");
        assert!(json.get("output").is_some(), "should have output");
        assert_eq!(
            json["schemaNamespace"].as_str().unwrap(),
            "TestSchema",
            "schemaNamespace should match --schema-namespace argument"
        );
    }

    #[test]
    fn test_init_overwrite_flag_allows_overwriting_existing_file() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");

        // Create initial file
        fs::write(&config_path, "existing content").unwrap();

        // Should fail without --overwrite
        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("MySchema")
            .arg("--module-type")
            .arg("swiftPackage")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .failure();

        // Should succeed with --overwrite
        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("MySchema")
            .arg("--module-type")
            .arg("swiftPackage")
            .arg("--overwrite")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .success();

        // File should now be valid JSON, not "existing content"
        let content = fs::read_to_string(&config_path).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&content).is_ok());
    }

    #[test]
    fn test_init_embedded_in_target_requires_target_name() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");

        // Should fail: embeddedInTarget without --target-name
        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("MySchema")
            .arg("--module-type")
            .arg("embeddedInTarget")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains("Target name is required"));
    }

    #[test]
    fn test_init_embedded_in_target_with_target_name_succeeds() {
        let tmp = TempDir::new().unwrap();
        let config_path = tmp.path().join("apollo-codegen-config.json");

        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("MySchema")
            .arg("--module-type")
            .arg("embeddedInTarget")
            .arg("--target-name")
            .arg("MyTarget")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .success();

        assert!(config_path.exists());
    }

    #[test]
    fn test_init_print_flag_outputs_to_stdout() {
        cli_bin()
            .arg("init")
            .arg("--schema-namespace")
            .arg("PrintSchema")
            .arg("--module-type")
            .arg("swiftPackage")
            .arg("--print")
            .assert()
            .success()
            .stdout(predicates::str::contains("schemaNamespace"))
            .stdout(predicates::str::contains("PrintSchema"));
    }
}

// ============================================================================
// Generate operation manifest command tests
// ============================================================================
// Mirrors: Tests/CodegenCLITests/Commands/GenerateOperationManifestTests.swift
mod generate_operation_manifest_tests {
    use super::*;

    #[test]
    fn test_generate_operation_manifest_with_valid_config_succeeds() {
        let tmp = TempDir::new().unwrap();
        let schema_path = tmp.path().join("schema.graphqls");
        fs::write(&schema_path, "type Query { hello: String }").unwrap();

        let op_path = tmp.path().join("query.graphql");
        fs::write(&op_path, "query HelloQuery { hello }").unwrap();

        let output_path = tmp.path().join("generated");
        fs::create_dir_all(&output_path).unwrap();

        let manifest_path = tmp.path().join("manifest.json");
        let config = minimal_config_with_manifest(
            "TestSchema",
            output_path.to_str().unwrap(),
            manifest_path.to_str().unwrap(),
        );
        let config_path = tmp.path().join("apollo-codegen-config.json");
        fs::write(&config_path, &config).unwrap();

        cli_bin()
            .arg("generate-operation-manifest")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .current_dir(tmp.path())
            .assert()
            .success();
    }

    #[test]
    fn test_generate_operation_manifest_without_manifest_config_fails() {
        let tmp = TempDir::new().unwrap();
        let schema_path = tmp.path().join("schema.graphqls");
        fs::write(&schema_path, "type Query { hello: String }").unwrap();

        // Config WITHOUT operationManifest section
        let config = minimal_config_json("TestSchema", "./generated");
        let config_path = tmp.path().join("apollo-codegen-config.json");
        fs::write(&config_path, &config).unwrap();

        cli_bin()
            .arg("generate-operation-manifest")
            .arg("--path")
            .arg(config_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains("operationManifest"));
    }

    #[test]
    fn test_generate_operation_manifest_with_nonexistent_config_fails() {
        let tmp = TempDir::new().unwrap();
        let fake_path = tmp.path().join("nonexistent.json");

        cli_bin()
            .arg("generate-operation-manifest")
            .arg("--path")
            .arg(fake_path.to_str().unwrap())
            .assert()
            .failure()
            .stderr(predicates::str::contains("Error"));
    }
}
