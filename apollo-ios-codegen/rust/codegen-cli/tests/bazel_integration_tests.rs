//! Bazel-mode integration tests for the `apollo-ios-cli` binary.
//!
//! Covers `--bazel-output-dir` in `schema_types` and `operations` mode
//! (framework-path prefix and exact `--bazel-generate-for` selection),
//! `--bazel-keep-schema-configuration`, test mocks in the tree artifact,
//! symlinked inputs, validation errors (no panics, Swift-like messages) and the
//! persistent worker protocol (singleplex and multiplex) including an
//! invalid-input request that must not kill the worker.
//!
//! The worker protocol messages are hand-encoded protobuf (the proto types are
//! private to the binary crate).

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command as StdCommand, Stdio};
use std::sync::Once;

use assert_cmd::Command;
use predicates::prelude::*;
use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Binary location (same scheme as cli_integration_tests.rs)
// ---------------------------------------------------------------------------

static BUILD_ONCE: Once = Once::new();

fn workspace_root() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); // up from codegen-cli to rust/
    path
}

fn target_profile_dir() -> PathBuf {
    let exe = std::env::current_exe().expect("current_exe");
    let mut dir = exe.parent().expect("test binary directory").to_path_buf();
    if dir.file_name().map(|n| n == "deps").unwrap_or(false) {
        dir.pop();
    }
    dir
}

fn cli_path() -> PathBuf {
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
        let status = StdCommand::new(env!("CARGO"))
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
    bin
}

fn cli_bin() -> Command {
    Command::new(cli_path())
}

// ---------------------------------------------------------------------------
// Fixture: a small schema and operations spread over "packages"
// ---------------------------------------------------------------------------

const SCHEMA: &str = r#"
scalar Date
type Query { pets: [Pet!]!, me: User }
interface Pet { id: ID!, name: String! }
type Dog implements Pet { id: ID!, name: String!, bark: Boolean, born: Date }
type Cat implements Pet { id: ID!, name: String! }
type User { id: ID!, name: String }
"#;

/// Writes the fixture into `root` and returns the relative paths of the
/// operation files, in the layout:
///   Schema/schema.graphqls
///   Shared/PetBits.graphql                 fragment PetBits
///   Features/Account/AccountQuery.graphql  uses PetBits
///   Features/AccountInfo/InfoQuery.graphql (same-prefix package)
///   Nested/Features/Account/NestedQuery.graphql (same-suffix package)
fn write_fixture(root: &Path) {
    let files: &[(&str, &str)] = &[
        ("Schema/schema.graphqls", SCHEMA),
        (
            "Shared/PetBits.graphql",
            "fragment PetBits on Pet { id name }",
        ),
        (
            "Features/Account/AccountQuery.graphql",
            "query AccountQuery { pets { ...PetBits ... on Dog { bark born } } }",
        ),
        (
            "Features/AccountInfo/InfoQuery.graphql",
            "query InfoQuery { me { id name } }",
        ),
        (
            "Nested/Features/Account/NestedQuery.graphql",
            "query NestedQuery { me { id } }",
        ),
    ];
    for (path, content) in files {
        let full = root.join(path);
        fs::create_dir_all(full.parent().unwrap()).unwrap();
        fs::write(full, content).unwrap();
    }
}

const OPERATION_FILES: &[&str] = &[
    "Shared/PetBits.graphql",
    "Features/Account/AccountQuery.graphql",
    "Features/AccountInfo/InfoQuery.graphql",
    "Nested/Features/Account/NestedQuery.graphql",
];

/// A rules_apollo-style config: exact input paths (relative to the cwd, like
/// Bazel exec paths), `other` module type, absolute operations output.
fn config_json(test_mocks: serde_json::Value) -> String {
    config_json_with_module_type(test_mocks, serde_json::json!({"other": {}}))
}

fn config_json_with_module_type(
    test_mocks: serde_json::Value,
    module_type: serde_json::Value,
) -> String {
    serde_json::json!({
        "schemaNamespace": "PetsAPI",
        "input": {
            "schemaSearchPaths": ["Schema/schema.graphqls"],
            "operationSearchPaths": OPERATION_FILES
        },
        "output": {
            "schemaTypes": {"path": ".", "moduleType": module_type},
            "operations": {"absolute": {"path": "."}},
            "testMocks": test_mocks
        }
    })
    .to_string()
}

fn no_mocks() -> serde_json::Value {
    serde_json::json!({"none": {}})
}

fn list_files(dir: &Path) -> Vec<String> {
    fn walk(dir: &Path, base: &Path, out: &mut Vec<String>) {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    walk(&path, base, out);
                } else {
                    out.push(
                        path.strip_prefix(base)
                            .unwrap()
                            .to_string_lossy()
                            .to_string(),
                    );
                }
            }
        }
    }
    let mut out = Vec::new();
    walk(dir, dir, &mut out);
    out.sort();
    out
}

fn generate_args<'a>(config: &'a str, out: &'a str, mode: &'a str) -> Vec<&'a str> {
    vec![
        "generate",
        "--string",
        config,
        "--bazel-output-dir",
        out,
        "--bazel-mode",
        mode,
    ]
}

// ---------------------------------------------------------------------------
// schema_types mode
// ---------------------------------------------------------------------------

#[test]
fn schema_types_mode_writes_schema_types_only_and_drops_hand_written_files() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "schema_types"))
        .current_dir(tmp.path())
        .assert()
        .success();

    let files = list_files(&tmp.path().join("out"));
    assert!(
        files.contains(&"Objects/Dog.graphql.swift".to_string()),
        "{:?}",
        files
    );
    assert!(
        files.contains(&"Interfaces/Pet.graphql.swift".to_string()),
        "{:?}",
        files
    );
    assert!(
        files.contains(&"SchemaMetadata.graphql.swift".to_string()),
        "{:?}",
        files
    );
    assert!(
        !files
            .iter()
            .any(|f| f.contains("SchemaConfiguration.swift")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.starts_with("CustomScalars/")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.contains("AccountQuery")
            || f.contains("InfoQuery")
            || f.contains("NestedQuery")
            || f.contains("PetBits")),
        "no operations: {:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.starts_with("TestMocks/")),
        "{:?}",
        files
    );
    // nothing was written next to the sources
    assert!(!tmp.path().join("Objects").exists());
}

#[test]
fn keep_schema_configuration_keeps_hand_written_files() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "schema_types"))
        .arg("--bazel-keep-schema-configuration")
        .current_dir(tmp.path())
        .assert()
        .success();

    let files = list_files(&tmp.path().join("out"));
    assert!(
        files.contains(&"SchemaConfiguration.swift".to_string()),
        "{:?}",
        files
    );
    assert!(
        files.contains(&"CustomScalars/Date.swift".to_string()),
        "{:?}",
        files
    );
    assert!(
        files.contains(&"Objects/Dog.graphql.swift".to_string()),
        "{:?}",
        files
    );
}

#[test]
fn test_mocks_are_written_under_test_mocks_in_schema_types_mode() {
    // `swiftPackage` test mocks require the swiftPackageManager module type (config
    // validation, as in Swift); `absolute` is what a rule with `other` uses.
    let spm = serde_json::json!({"swiftPackageManager": {}});
    let other = serde_json::json!({"other": {}});
    for (mocks, module_type, expected_dir) in [
        (
            serde_json::json!({"swiftPackage": {}}),
            spm.clone(),
            "TestMocks",
        ),
        (
            serde_json::json!({"swiftPackage": {"targetName": "PetMocks"}}),
            spm,
            "PetMocks",
        ),
        (
            serde_json::json!({"absolute": {"path": "/elsewhere/Mocks"}}),
            other,
            "TestMocks",
        ),
    ] {
        let tmp = TempDir::new().unwrap();
        write_fixture(tmp.path());
        let config = config_json_with_module_type(mocks, module_type);

        cli_bin()
            .args(generate_args(&config, "out", "schema_types"))
            .current_dir(tmp.path())
            .assert()
            .success();

        let files = list_files(&tmp.path().join("out"));
        assert!(
            files.contains(&format!("{}/Dog+Mock.graphql.swift", expected_dir)),
            "{:?}",
            files
        );
        assert!(
            files.contains(&format!("{}/Cat+Mock.graphql.swift", expected_dir)),
            "{:?}",
            files
        );
        assert!(
            files.contains(&format!(
                "{}/MockObject+Interfaces.graphql.swift",
                expected_dir
            )),
            "{:?}",
            files
        );
        assert!(
            files.contains(&"Objects/Dog.graphql.swift".to_string()),
            "{:?}",
            files
        );
        assert!(!Path::new("/elsewhere/Mocks").exists());
    }
}

#[test]
fn optimize_schema_metadata_uses_configured_namespace() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "schema_types"))
        .arg("--bazel-optimize-schema-metadata")
        .current_dir(tmp.path())
        .assert()
        .success();

    let metadata = fs::read_to_string(tmp.path().join("out/SchemaMetadata.graphql.swift")).unwrap();
    assert!(
        metadata.contains("\"Dog\": PetsAPI.Objects.Dog"),
        "{}",
        metadata
    );
    if metadata.contains("switch typename {") {
        // switch-based objectType (Apollo iOS < 1.25.4): the lookup table is added
        assert!(metadata.contains("fastObjectTypeLookup"), "{}", metadata);
    } else {
        // Apollo iOS 1.25.4+ already renders a dictionary; nothing to optimize
        assert!(metadata.contains("objectTypeMap"), "{}", metadata);
        assert!(!metadata.contains("fastObjectTypeLookup"), "{}", metadata);
    }
}

// ---------------------------------------------------------------------------
// operations mode
// ---------------------------------------------------------------------------

#[test]
fn operations_mode_with_framework_path_selects_by_prefix() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "operations"))
        .args([
            "--bazel-framework-path",
            "Features/Account",
            "--bazel-strip-import",
            "PetsAPI",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();

    let files = list_files(&tmp.path().join("out"));
    assert!(
        files
            .iter()
            .any(|f| f.ends_with("AccountQuery.graphql.swift")),
        "{:?}",
        files
    );
    // the same-prefix package is not selected ...
    assert!(
        !files.iter().any(|f| f.contains("InfoQuery")),
        "{:?}",
        files
    );
    assert!(!files.iter().any(|f| f.contains("PetBits")), "{:?}", files);
    // ... but a same-suffix package is (prefix matching also matches `/<prefix>/`)
    assert!(
        files
            .iter()
            .any(|f| f.ends_with("NestedQuery.graphql.swift")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.starts_with("Objects/")),
        "no schema types: {:?}",
        files
    );

    let account = files
        .iter()
        .find(|f| f.ends_with("AccountQuery.graphql.swift"))
        .unwrap();
    let content = fs::read_to_string(tmp.path().join("out").join(account)).unwrap();
    assert!(!content.contains("import PetsAPI\n"), "{}", content);
}

#[test]
fn operations_mode_with_generate_for_selects_exact_files() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "operations"))
        // the framework path would also select NestedQuery; exact selection wins
        .args(["--bazel-framework-path", "Features/Account"])
        .args([
            "--bazel-generate-for",
            "Features/Account/AccountQuery.graphql",
        ])
        .args(["--bazel-generate-for", "./Shared/PetBits.graphql"])
        .current_dir(tmp.path())
        .assert()
        .success();

    let files = list_files(&tmp.path().join("out"));
    assert!(
        files
            .iter()
            .any(|f| f.ends_with("AccountQuery.graphql.swift")),
        "{:?}",
        files
    );
    assert!(
        files.iter().any(|f| f.ends_with("PetBits.graphql.swift")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.contains("NestedQuery")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.contains("InfoQuery")),
        "{:?}",
        files
    );
}

#[test]
fn operations_mode_without_selection_generates_everything() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "operations"))
        .current_dir(tmp.path())
        .assert()
        .success();

    let files = list_files(&tmp.path().join("out"));
    for name in ["AccountQuery", "InfoQuery", "NestedQuery", "PetBits"] {
        assert!(
            files.iter().any(|f| f.contains(name)),
            "{} missing in {:?}",
            name,
            files
        );
    }
}

#[test]
fn unknown_bazel_mode_fails() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "nope"))
        .current_dir(tmp.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("Unknown --bazel-mode: nope"));
}

// ---------------------------------------------------------------------------
// symlinked inputs (sandboxed actions present inputs as symlinks)
// ---------------------------------------------------------------------------

#[cfg(unix)]
#[test]
fn symlinked_inputs_are_discovered() {
    use std::os::unix::fs::symlink;

    let real = TempDir::new().unwrap();
    write_fixture(real.path());
    let sandbox = TempDir::new().unwrap();
    // file symlinks for every declared input, like a Bazel sandbox
    for path in std::iter::once("Schema/schema.graphqls").chain(OPERATION_FILES.iter().copied()) {
        let dest = sandbox.path().join(path);
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        symlink(real.path().join(path), dest).unwrap();
    }
    let config = config_json(no_mocks());

    cli_bin()
        .args(generate_args(&config, "out", "operations"))
        .args([
            "--bazel-generate-for",
            "Features/Account/AccountQuery.graphql",
        ])
        .current_dir(sandbox.path())
        .assert()
        .success();
    let files = list_files(&sandbox.path().join("out"));
    assert!(
        files
            .iter()
            .any(|f| f.ends_with("AccountQuery.graphql.swift")),
        "{:?}",
        files
    );

    // a glob over a symlinked directory also works
    let linked = TempDir::new().unwrap();
    symlink(real.path().join("Schema"), linked.path().join("Schema")).unwrap();
    symlink(real.path().join("Features"), linked.path().join("Features")).unwrap();
    symlink(real.path().join("Shared"), linked.path().join("Shared")).unwrap();
    let glob_config = serde_json::json!({
        "schemaNamespace": "PetsAPI",
        "input": {"schemaSearchPaths": ["Schema/schema.graphqls"], "operationSearchPaths": ["**/*.graphql"]},
        "output": {"schemaTypes": {"path": ".", "moduleType": {"other": {}}}, "operations": {"absolute": {"path": "."}}, "testMocks": {"none": {}}}
    })
    .to_string();
    cli_bin()
        .args(generate_args(&glob_config, "out", "schema_types"))
        .current_dir(linked.path())
        .assert()
        .success();
    assert!(linked.path().join("out/Objects/Dog.graphql.swift").exists());
}

// ---------------------------------------------------------------------------
// validation errors never panic
// ---------------------------------------------------------------------------

fn write_invalid_fixture(root: &Path, operation: &str) -> String {
    fs::create_dir_all(root.join("Schema")).unwrap();
    fs::write(root.join("Schema/schema.graphqls"), SCHEMA).unwrap();
    fs::write(root.join("Bad.graphql"), operation).unwrap();
    serde_json::json!({
        "schemaNamespace": "PetsAPI",
        "input": {"schemaSearchPaths": ["Schema/schema.graphqls"], "operationSearchPaths": ["Bad.graphql"]},
        "output": {"schemaTypes": {"path": "Out", "moduleType": {"other": {}}}, "operations": {"inSchemaModule": {}}, "testMocks": {"none": {}}}
    })
    .to_string()
}

#[test]
fn invalid_operations_are_validation_errors_not_panics() {
    let cases: &[(&str, &str)] = &[
        (
            "query Q { pets { ...PetDetails } }",
            "Bad.graphql:1:error:Unknown fragment \"PetDetails\".",
        ),
        (
            "query Q { pets { nope } }",
            "Cannot query field \"nope\" on type \"Pet\".",
        ),
        (
            "query Q($id: Nope!) { pets { id } }",
            "Unknown type \"Nope\".",
        ),
        (
            "query Q { pets @nope { id } }",
            "Unknown directive \"@nope\".",
        ),
        ("query Q { pets }", "must have a selection of subfields"),
        (
            "{ pets { id } }",
            "Apollo does not support anonymous operations",
        ),
        (
            "fragment A on Dog { ...B } fragment B on Dog { ...A } query Q { pets { ...A } }",
            "Cannot spread fragment \"A\" within itself",
        ),
        (
            "query Q { pets { ... on Dog @defer { bark } } }",
            "without a 'label' argument",
        ),
        ("query Q { pets { id ", "Syntax Error:"),
    ];
    for (operation, expected) in cases {
        let tmp = TempDir::new().unwrap();
        let config = write_invalid_fixture(tmp.path(), operation);
        let assert = cli_bin()
            .args(["generate", "--string", &config])
            .current_dir(tmp.path())
            .assert()
            .code(1);
        let stderr = String::from_utf8_lossy(&assert.get_output().stderr).to_string();
        assert!(
            stderr.contains(expected),
            "operation {:?}: expected {:?} in:\n{}",
            operation,
            expected,
            stderr
        );
        assert!(
            !stderr.contains("panicked"),
            "operation {:?} panicked:\n{}",
            operation,
            stderr
        );
        assert!(
            stderr.contains("Error: An error occured during validation of the GraphQL schema or operations! Check ["),
            "{}",
            stderr
        );
        assert!(
            stderr.contains("[ERROR - ApolloCodegenLib:ApolloCodegen.swift:185] - "),
            "{}",
            stderr
        );
    }
}

#[test]
fn invalid_schema_is_an_error_not_a_panic() {
    let tmp = TempDir::new().unwrap();
    let config = write_invalid_fixture(tmp.path(), "query Q { x }");
    fs::write(
        tmp.path().join("Schema/schema.graphqls"),
        "type Query { x: Nope }",
    )
    .unwrap();
    let assert = cli_bin()
        .args(["generate", "--string", &config])
        .current_dir(tmp.path())
        .assert()
        .code(1);
    let stderr = String::from_utf8_lossy(&assert.get_output().stderr).to_string();
    assert!(
        stderr.contains("GraphQLSchemaValidationError-Unknown type \"Nope\"."),
        "{}",
        stderr
    );
    assert!(!stderr.contains("panicked"), "{}", stderr);
}

#[test]
fn version_flag_prints_the_apollo_version() {
    cli_bin().arg("--version").assert().success().stdout(
        predicate::str::is_match(format!(
            r"^apollo-ios-cli {}\n$",
            regex::escape(codegen_cli::constants::CLI_VERSION)
        ))
        .unwrap(),
    );
}

// ---------------------------------------------------------------------------
// persistent worker protocol
// ---------------------------------------------------------------------------

fn put_varint(buf: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            buf.push(byte);
            return;
        }
        buf.push(byte | 0x80);
    }
}

fn put_bytes(buf: &mut Vec<u8>, field: u32, bytes: &[u8]) {
    put_varint(buf, u64::from(field << 3 | 2));
    put_varint(buf, bytes.len() as u64);
    buf.extend_from_slice(bytes);
}

/// Encodes a length-delimited `blaze.worker.WorkRequest`.
fn encode_request(request_id: i32, arguments: &[String], inputs: &[(&str, &[u8])]) -> Vec<u8> {
    let mut body = Vec::new();
    for arg in arguments {
        put_bytes(&mut body, 1, arg.as_bytes());
    }
    for (path, digest) in inputs {
        let mut input = Vec::new();
        put_bytes(&mut input, 1, path.as_bytes());
        put_bytes(&mut input, 2, digest);
        put_bytes(&mut body, 2, &input);
    }
    if request_id != 0 {
        put_varint(&mut body, u64::from(3u32 << 3));
        put_varint(&mut body, request_id as u64);
    }
    let mut framed = Vec::new();
    put_varint(&mut framed, body.len() as u64);
    framed.extend_from_slice(&body);
    framed
}

#[derive(Debug, Default, PartialEq)]
struct Response {
    exit_code: i32,
    output: String,
    request_id: i32,
    was_cancelled: bool,
}

fn read_varint(reader: &mut impl Read) -> Option<u64> {
    let mut value = 0u64;
    let mut shift = 0;
    loop {
        let mut byte = [0u8; 1];
        reader.read_exact(&mut byte).ok()?;
        value |= u64::from(byte[0] & 0x7f) << shift;
        if byte[0] & 0x80 == 0 {
            return Some(value);
        }
        shift += 7;
    }
}

/// Reads one length-delimited `blaze.worker.WorkResponse`.
fn read_response(reader: &mut impl Read) -> Option<Response> {
    let len = read_varint(reader)? as usize;
    let mut body = vec![0u8; len];
    reader.read_exact(&mut body).ok()?;
    let mut cursor = std::io::Cursor::new(body);
    let mut response = Response::default();
    while let Some(tag) = read_varint(&mut cursor) {
        match tag {
            0x08 => response.exit_code = read_varint(&mut cursor)? as i32,
            0x12 => {
                let len = read_varint(&mut cursor)? as usize;
                let mut bytes = vec![0u8; len];
                cursor.read_exact(&mut bytes).ok()?;
                response.output = String::from_utf8_lossy(&bytes).to_string();
            }
            0x18 => response.request_id = read_varint(&mut cursor)? as i32,
            0x20 => response.was_cancelled = read_varint(&mut cursor)? != 0,
            _ => return None,
        }
    }
    Some(response)
}

struct Worker {
    child: Child,
}

impl Worker {
    fn spawn(cwd: &Path) -> Self {
        let child = StdCommand::new(cli_path())
            .arg("--persistent_worker")
            .current_dir(cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn worker");
        Worker { child }
    }

    fn send(&mut self, request_id: i32, arguments: &[String], inputs: &[(&str, &[u8])]) {
        let stdin = self.child.stdin.as_mut().unwrap();
        stdin
            .write_all(&encode_request(request_id, arguments, inputs))
            .unwrap();
        stdin.flush().unwrap();
    }

    fn receive(&mut self) -> Response {
        read_response(self.child.stdout.as_mut().unwrap()).expect("a WorkResponse")
    }

    fn finish(mut self) -> (i32, String) {
        drop(self.child.stdin.take());
        let output = self.child.wait_with_output().unwrap();
        (
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr).to_string(),
        )
    }
}

fn worker_args(config: &str, out: &str, extra: &[&str]) -> Vec<String> {
    let mut args: Vec<String> = generate_args(config, out, "operations")
        .into_iter()
        .map(String::from)
        .collect();
    args.extend(extra.iter().map(|s| s.to_string()));
    args
}

fn inputs() -> Vec<(&'static str, &'static [u8])> {
    let mut v: Vec<(&str, &[u8])> = vec![("Schema/schema.graphqls", &[1, 2, 3])];
    for (i, path) in OPERATION_FILES.iter().enumerate() {
        v.push((path, Box::leak(vec![10 + i as u8].into_boxed_slice())));
    }
    v
}

#[test]
fn worker_singleplex_round_trip_survives_invalid_input() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());
    let inputs = inputs();
    let mut worker = Worker::spawn(tmp.path());

    // 1. schema types
    worker.send(
        0,
        &[
            "generate",
            "--string",
            &config,
            "--bazel-output-dir",
            "schema-out",
        ]
        .map(String::from),
        &inputs,
    );
    let response = worker.receive();
    assert_eq!(response.exit_code, 0, "{}", response.output);
    assert_eq!(response.request_id, 0);
    assert!(tmp
        .path()
        .join("schema-out/Objects/Dog.graphql.swift")
        .exists());

    // 2. operations for one package (compilation served from the cache)
    worker.send(
        0,
        &worker_args(
            &config,
            "account-out",
            &[
                "--bazel-generate-for",
                "Features/Account/AccountQuery.graphql",
            ],
        ),
        &inputs,
    );
    let response = worker.receive();
    assert_eq!(response.exit_code, 0, "{}", response.output);
    let files = list_files(&tmp.path().join("account-out"));
    assert!(
        files
            .iter()
            .any(|f| f.ends_with("AccountQuery.graphql.swift")),
        "{:?}",
        files
    );
    assert!(
        !files.iter().any(|f| f.contains("InfoQuery")),
        "{:?}",
        files
    );

    // 3. an invalid operation: error response, worker keeps running
    fs::write(
        tmp.path().join("Features/AccountInfo/InfoQuery.graphql"),
        "query InfoQuery { me { ...Nope } }",
    )
    .unwrap();
    let mut changed = inputs.clone();
    changed[3] = ("Features/AccountInfo/InfoQuery.graphql", &[99]);
    worker.send(
        0,
        &worker_args(
            &config,
            "bad-out",
            &["--bazel-framework-path", "Features/AccountInfo"],
        ),
        &changed,
    );
    let response = worker.receive();
    assert_eq!(response.exit_code, 1);
    assert!(
        response.output.contains("Unknown fragment") && response.output.contains("Nope"),
        "{}",
        response.output
    );
    assert!(
        !response.output.contains("Internal error"),
        "{}",
        response.output
    );

    // 4. fixed again: back to success
    fs::write(
        tmp.path().join("Features/AccountInfo/InfoQuery.graphql"),
        "query InfoQuery { me { id } }",
    )
    .unwrap();
    changed[3] = ("Features/AccountInfo/InfoQuery.graphql", &[100]);
    worker.send(
        0,
        &worker_args(
            &config,
            "info-out",
            &["--bazel-framework-path", "Features/AccountInfo"],
        ),
        &changed,
    );
    let response = worker.receive();
    assert_eq!(response.exit_code, 0, "{}", response.output);
    assert!(list_files(&tmp.path().join("info-out"))
        .iter()
        .any(|f| f.contains("InfoQuery")));

    let (code, stderr) = worker.finish();
    assert_eq!(code, 0, "{}", stderr);
    assert!(!stderr.contains("panicked"), "{}", stderr);
    // the schema was parsed once for the first request and once after the inputs changed
    assert_eq!(stderr.matches("Schema cache miss").count(), 1, "{}", stderr);
}

#[test]
fn worker_multiplex_handles_concurrent_requests_by_id() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(no_mocks());
    let inputs = inputs();
    // an invalid config (unknown fragment) for one of the requests
    fs::create_dir_all(tmp.path().join("Broken")).unwrap();
    fs::write(
        tmp.path().join("Broken/Broken.graphql"),
        "query Broken { me { ...Nope } }",
    )
    .unwrap();
    let broken_config = serde_json::json!({
        "schemaNamespace": "PetsAPI",
        "input": {"schemaSearchPaths": ["Schema/schema.graphqls"], "operationSearchPaths": ["Broken/Broken.graphql"]},
        "output": {"schemaTypes": {"path": ".", "moduleType": {"other": {}}}, "operations": {"absolute": {"path": "."}}, "testMocks": {"none": {}}}
    })
    .to_string();
    let broken_inputs: Vec<(&str, &[u8])> = vec![
        ("Schema/schema.graphqls", &[1, 2, 3]),
        ("Broken/Broken.graphql", &[7]),
    ];

    let mut worker = Worker::spawn(tmp.path());
    // all requests are sent before any response is read
    worker.send(
        11,
        &worker_args(
            &config,
            "out-11",
            &[
                "--bazel-generate-for",
                "Features/Account/AccountQuery.graphql",
            ],
        ),
        &inputs,
    );
    worker.send(
        12,
        &worker_args(&broken_config, "out-12", &[]),
        &broken_inputs,
    );
    worker.send(
        13,
        &worker_args(
            &config,
            "out-13",
            &[
                "--bazel-generate-for",
                "Features/AccountInfo/InfoQuery.graphql",
            ],
        ),
        &inputs,
    );
    worker.send(
        14,
        &[
            "generate",
            "--string",
            &config,
            "--bazel-output-dir",
            "out-14",
        ]
        .map(String::from),
        &inputs,
    );

    let mut responses: Vec<Response> = (0..4).map(|_| worker.receive()).collect();
    responses.sort_by_key(|r| r.request_id);
    assert_eq!(
        responses.iter().map(|r| r.request_id).collect::<Vec<_>>(),
        vec![11, 12, 13, 14]
    );
    assert_eq!(responses[0].exit_code, 0, "{}", responses[0].output);
    assert_eq!(responses[1].exit_code, 1);
    assert!(
        responses[1].output.contains("Unknown fragment") && responses[1].output.contains("Nope"),
        "{}",
        responses[1].output
    );
    assert_eq!(responses[2].exit_code, 0, "{}", responses[2].output);
    assert_eq!(responses[3].exit_code, 0, "{}", responses[3].output);
    assert!(list_files(&tmp.path().join("out-11"))
        .iter()
        .any(|f| f.ends_with("AccountQuery.graphql.swift")));
    assert!(list_files(&tmp.path().join("out-13"))
        .iter()
        .any(|f| f.ends_with("InfoQuery.graphql.swift")));
    assert!(tmp.path().join("out-14/Objects/Dog.graphql.swift").exists());

    // still alive afterwards
    worker.send(
        15,
        &worker_args(
            &config,
            "out-15",
            &["--bazel-generate-for", "Shared/PetBits.graphql"],
        ),
        &inputs,
    );
    let response = worker.receive();
    assert_eq!(response.request_id, 15);
    assert_eq!(response.exit_code, 0, "{}", response.output);

    let (code, stderr) = worker.finish();
    assert_eq!(code, 0, "{}", stderr);
    assert!(!stderr.contains("panicked"), "{}", stderr);
    // one schema, shared by every request (same schema digests)
    assert_eq!(stderr.matches("Schema cache miss").count(), 1, "{}", stderr);
}

#[test]
fn worker_rejects_non_generate_commands_without_dying() {
    let tmp = TempDir::new().unwrap();
    let mut worker = Worker::spawn(tmp.path());
    worker.send(
        1,
        &["init", "--module-type", "other"].map(String::from),
        &[],
    );
    let response = worker.receive();
    assert_eq!(response.request_id, 1);
    assert_eq!(response.exit_code, 1);
    assert!(response
        .output
        .contains("Worker only supports the 'generate' command"));
    let (code, _) = worker.finish();
    assert_eq!(code, 0);
}

// ---------------------------------------------------------------------------
// test_mocks mode: scoped test mocks (fork extension)
// ---------------------------------------------------------------------------

fn absolute_mocks() -> serde_json::Value {
    serde_json::json!({"absolute": {"path": "/elsewhere/Mocks"}})
}

fn mock_files(dir: &Path) -> Vec<String> {
    list_files(dir)
        .into_iter()
        .filter(|f| f.starts_with("TestMocks/"))
        .map(|f| f["TestMocks/".len()..].to_string())
        .collect()
}

#[test]
fn test_mocks_mode_writes_only_mocks_scoped_to_the_selected_operations() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(absolute_mocks());

    // Account: pets -> Pet -> Dog, Cat (interface expansion) + Query.
    cli_bin()
        .args(generate_args(&config, "account", "test_mocks"))
        .args([
            "--bazel-generate-for",
            "Features/Account/AccountQuery.graphql",
            "--bazel-mocks-scope",
            "referenced",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    let files = list_files(&tmp.path().join("account"));
    assert_eq!(
        files,
        [
            "TestMocks/Cat+Mock.graphql.swift",
            "TestMocks/Dog+Mock.graphql.swift",
            "TestMocks/MockObject+Interfaces.graphql.swift",
            "TestMocks/Query+Mock.graphql.swift",
        ]
    );

    // AccountInfo: me -> User + Query. Prefix selection works as well.
    cli_bin()
        .args(generate_args(&config, "info", "test_mocks"))
        .args([
            "--bazel-framework-path",
            "Features/AccountInfo",
            "--bazel-mocks-scope",
            "referenced",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("info")),
        [
            "MockObject+Interfaces.graphql.swift",
            "Query+Mock.graphql.swift",
            "User+Mock.graphql.swift"
        ]
    );

    // Without a selection, "referenced" covers every operation (same as "all").
    cli_bin()
        .args(generate_args(&config, "all", "test_mocks"))
        .args(["--bazel-mocks-scope", "referenced"])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("all")),
        [
            "Cat+Mock.graphql.swift",
            "Dog+Mock.graphql.swift",
            "MockObject+Interfaces.graphql.swift",
            "Query+Mock.graphql.swift",
            "User+Mock.graphql.swift",
        ]
    );
}

#[test]
fn test_mocks_partition_unions_to_the_unscoped_output() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(absolute_mocks());

    // Reference: unscoped mocks as schema_types mode writes them today.
    cli_bin()
        .args(generate_args(&config, "all", "schema_types"))
        .current_dir(tmp.path())
        .assert()
        .success();
    let all_dir = tmp.path().join("all/TestMocks");

    // Base: everything but the feature-exclusive types, with the typealias files.
    cli_bin()
        .args(generate_args(&config, "base", "test_mocks"))
        .args([
            "--bazel-mocks-exclude",
            "Dog",
            "--bazel-mocks-exclude",
            "Cat",
            "--bazel-mocks-exclude",
            "User",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("base")),
        [
            "MockObject+Interfaces.graphql.swift",
            "Query+Mock.graphql.swift"
        ]
    );

    // Feature A: Account's referenced types minus the base's, importing the base.
    cli_bin()
        .args(generate_args(&config, "a", "test_mocks"))
        .args([
            "--bazel-generate-for",
            "Features/Account/AccountQuery.graphql",
            "--bazel-mocks-scope",
            "referenced",
            "--bazel-mocks-exclude",
            "Query",
            "--bazel-mocks-base-module",
            "PetsBaseMocks",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("a")),
        ["Cat+Mock.graphql.swift", "Dog+Mock.graphql.swift"]
    );

    // Feature B: explicit type list (as a rule with a declared ownership would pass).
    cli_bin()
        .args(generate_args(&config, "b", "test_mocks"))
        .args([
            "--bazel-mocks-scope",
            "referenced",
            "--bazel-generate-for",
            "Features/AccountInfo/InfoQuery.graphql",
            "--bazel-mocks-exclude",
            "Query",
            "--bazel-mocks-base-module",
            "PetsBaseMocks",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("b")),
        ["User+Mock.graphql.swift"]
    );

    // Union == all, file for file; feature files only add the base-module import.
    let mut union: Vec<(String, String)> = Vec::new();
    for (dir, strip_import) in [("base", false), ("a", true), ("b", true)] {
        let mocks = tmp.path().join(dir).join("TestMocks");
        for file in mock_files(&tmp.path().join(dir)) {
            let mut content = fs::read_to_string(mocks.join(&file)).unwrap();
            if strip_import {
                assert!(
                    content.contains("import PetsAPI\nimport PetsBaseMocks\n"),
                    "{file}: {content}"
                );
                content = content.replace("import PetsBaseMocks\n", "");
            } else {
                assert!(!content.contains("PetsBaseMocks"), "{file}");
            }
            union.push((file, content));
        }
    }
    union.sort();
    let names: Vec<&str> = union.iter().map(|(f, _)| f.as_str()).collect();
    assert_eq!(
        names.len(),
        union
            .iter()
            .map(|(f, _)| f)
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        "no type generated twice: {names:?}"
    );
    let all_files = list_files(&all_dir);
    assert_eq!(
        names,
        all_files.iter().map(String::as_str).collect::<Vec<_>>()
    );
    for (file, content) in &union {
        assert_eq!(
            content,
            &fs::read_to_string(all_dir.join(file)).unwrap(),
            "{file} differs from the unscoped output"
        );
    }
}

#[test]
fn test_mocks_typealias_files_follow_base_module_and_flag() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let config = config_json(absolute_mocks());

    // With a base module the typealias files are the base's: not generated...
    cli_bin()
        .args(generate_args(&config, "feature", "test_mocks"))
        .args([
            "--bazel-mocks-for",
            "Dog",
            "--bazel-mocks-scope",
            "referenced",
            "--bazel-generate-for",
            "nothing.graphql",
            "--bazel-mocks-base-module",
            "Base",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("feature")),
        ["Dog+Mock.graphql.swift"]
    );

    // ...unless asked for explicitly, and never when switched off.
    cli_bin()
        .args(generate_args(&config, "with", "test_mocks"))
        .args([
            "--bazel-mocks-for",
            "Dog",
            "--bazel-mocks-scope",
            "referenced",
            "--bazel-generate-for",
            "nothing.graphql",
            "--bazel-mocks-base-module",
            "Base",
            "--bazel-mocks-typealiases",
            "true",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("with")),
        [
            "Dog+Mock.graphql.swift",
            "MockObject+Interfaces.graphql.swift"
        ]
    );

    cli_bin()
        .args(generate_args(&config, "without", "test_mocks"))
        .args(["--bazel-mocks-typealiases", "false"])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert!(!mock_files(&tmp.path().join("without"))
        .iter()
        .any(|f| f.starts_with("MockObject+")));

    // The config keys work the same way (scope + base module from the config).
    let scoped = serde_json::json!({"absolute": {"path": "Mocks", "scope": "referencedByOperations", "baseModule": "Base", "includeTypes": ["User"]}});
    cli_bin()
        .args(generate_args(&config_json(scoped), "cfg", "test_mocks"))
        .args([
            "--bazel-generate-for",
            "Features/Account/AccountQuery.graphql",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("cfg")),
        [
            "Cat+Mock.graphql.swift",
            "Dog+Mock.graphql.swift",
            "Query+Mock.graphql.swift",
            "User+Mock.graphql.swift"
        ]
    );
    let user =
        fs::read_to_string(tmp.path().join("cfg/TestMocks/User+Mock.graphql.swift")).unwrap();
    assert!(
        user.contains("import ApolloTestSupport\n@testable import PetsAPI\nimport Base\n"),
        "{user}"
    );

    // schema_types mode honours the scoping as well (mocks next to the schema types).
    cli_bin()
        .args(generate_args(&config, "st", "schema_types"))
        .args([
            "--bazel-mocks-exclude",
            "Query",
            "--bazel-mocks-exclude",
            "User",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    assert_eq!(
        mock_files(&tmp.path().join("st")),
        [
            "Cat+Mock.graphql.swift",
            "Dog+Mock.graphql.swift",
            "MockObject+Interfaces.graphql.swift"
        ]
    );
    assert!(tmp.path().join("st/Objects/Query.graphql.swift").is_file());
}

#[test]
fn test_mocks_mode_errors_are_clear() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());

    cli_bin()
        .args(generate_args(&config_json(no_mocks()), "out", "test_mocks"))
        .current_dir(tmp.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("'output.testMocks'"));

    cli_bin()
        .args(generate_args(
            &config_json(absolute_mocks()),
            "out",
            "test_mocks",
        ))
        .args(["--bazel-mocks-for", "Ghost"])
        .current_dir(tmp.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("'Ghost'"));

    cli_bin()
        .args(generate_args(
            &config_json(absolute_mocks()),
            "out",
            "test_mocks",
        ))
        .args(["--bazel-mocks-scope", "some"])
        .current_dir(tmp.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("Unknown --bazel-mocks-scope"));
}

// ---------------------------------------------------------------------------
// Mock fields in Bazel mode (AnimalKingdom fixture)
//
// A mock's `MockFields` are collected from the IR of every compiled operation.
// The Bazel modes that render no operations (`schema_types`, `test_mocks`) must
// build that IR anyway, so their mock files are byte-identical to plain `generate`.
// ---------------------------------------------------------------------------

/// Copies the repo's AnimalKingdom fixture (`Sources/AnimalKingdomAPI/animalkingdom-graphql`,
/// inputs only) into `root/graphql` and writes `root/config.json`: schema module `Schema`
/// (`other`), operations in the schema module, public mocks under `Mocks`.
fn write_animal_kingdom(root: &Path) -> String {
    let mut src = workspace_root();
    src.pop(); // apollo-ios-codegen
    src.pop(); // repo root
    let src = src.join("Sources/AnimalKingdomAPI/animalkingdom-graphql");
    assert!(
        src.is_dir(),
        "AnimalKingdom fixture not found at {}",
        src.display()
    );
    let dst = root.join("graphql");
    fs::create_dir_all(&dst).unwrap();
    let mut copied = 0;
    for entry in fs::read_dir(&src).unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".graphql") || name.ends_with(".graphqls") {
            fs::copy(entry.path(), dst.join(&name)).unwrap();
            copied += 1;
        }
    }
    assert!(
        copied >= 10,
        "only {copied} fixture files copied from {}",
        src.display()
    );
    let config = serde_json::json!({
        "schemaNamespace": "AnimalKingdomAPI",
        "input": {
            "schemaSearchPaths": ["graphql/AnimalSchema.graphqls"],
            "operationSearchPaths": ["graphql/**/*.graphql"]
        },
        "output": {
            "schemaTypes": {"path": "Schema", "moduleType": {"other": {}}},
            "operations": {"inSchemaModule": {}},
            "testMocks": {"absolute": {"path": "Mocks", "accessModifier": "public"}}
        }
    })
    .to_string();
    fs::write(root.join("config.json"), &config).unwrap();
    config
}

/// Every `.swift` file of `dir` by name.
fn swift_files(dir: &Path) -> std::collections::BTreeMap<String, String> {
    let mut files = std::collections::BTreeMap::new();
    for entry in fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .flatten()
    {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".swift") {
            files.insert(name, fs::read_to_string(entry.path()).unwrap());
        }
    }
    files
}

/// Plain `generate` in `root`: the reference mocks (`root/Mocks`).
fn plain_mocks(root: &Path) -> std::collections::BTreeMap<String, String> {
    cli_bin()
        .args(["generate", "--path", "config.json"])
        .current_dir(root)
        .assert()
        .success();
    let mocks = swift_files(&root.join("Mocks"));
    let dog = &mocks["Dog+Mock.graphql.swift"];
    assert_eq!(dog.matches("@Field<").count(), 12, "{dog}");
    assert!(
        dog.contains("public extension Mock where O == Dog {\n  convenience init("),
        "{dog}"
    );
    assert!(
        dog.contains("@Field<Human>(\"owner\") public var owner"),
        "{dog}"
    );
    mocks
}

/// Asserts every mock file under `out/TestMocks` is byte-identical to the plain one
/// (after dropping an optional `import <base>` line) and, with `all`, that the set of
/// files is the plain set. Returns the file names.
fn assert_mocks_match_plain(
    out: &Path,
    plain: &std::collections::BTreeMap<String, String>,
    all: bool,
    base_import: Option<&str>,
) -> Vec<String> {
    let bazel = swift_files(&out.join("TestMocks"));
    assert!(!bazel.is_empty(), "no mocks under {}", out.display());
    for (name, content) in &bazel {
        let content = match base_import {
            Some(module) => content.replace(&format!("import {module}\n"), ""),
            None => content.clone(),
        };
        let expected = plain
            .get(name)
            .unwrap_or_else(|| panic!("{}: {name} is not a plain mock", out.display()));
        assert_eq!(
            &content,
            expected,
            "{}/TestMocks/{name} differs from plain generate",
            out.display()
        );
    }
    if all {
        assert_eq!(
            bazel.keys().collect::<Vec<_>>(),
            plain.keys().collect::<Vec<_>>(),
            "{}",
            out.display()
        );
    }
    bazel.into_keys().collect()
}

#[test]
fn bazel_mode_mocks_carry_their_fields_and_equal_plain_generate() {
    let tmp = TempDir::new().unwrap();
    let config = write_animal_kingdom(tmp.path());
    let plain = plain_mocks(tmp.path());
    let schema_files_before = list_files(&tmp.path().join("Schema"));
    assert!(
        schema_files_before
            .iter()
            .any(|f| f.ends_with("Dog.graphql.swift")),
        "{schema_files_before:?}"
    );

    // (out dir, mode, extra flags, every mock expected)
    let cases: &[(&str, &str, &[&str], bool)] = &[
        ("tm", "test_mocks", &[], true),
        ("st", "schema_types", &[], true),
        (
            "tm-for",
            "test_mocks",
            &["--bazel-generate-for", "graphql/DogQuery.graphql"],
            true,
        ),
        (
            "tm-prefix",
            "test_mocks",
            &["--bazel-framework-path", "graphql"],
            true,
        ),
        (
            "st-for",
            "schema_types",
            &[
                "--bazel-generate-for",
                "graphql/DogQuery.graphql",
                "--bazel-keep-schema-configuration",
            ],
            true,
        ),
        (
            "tm-ref",
            "test_mocks",
            &[
                "--bazel-mocks-scope",
                "referenced",
                "--bazel-generate-for",
                "graphql/PetAdoptionMutation.graphql",
            ],
            false,
        ),
        (
            "tm-ref-prefix",
            "test_mocks",
            &[
                "--bazel-mocks-scope",
                "referenced",
                "--bazel-framework-path",
                "graphql",
            ],
            true,
        ),
    ];
    for (out, mode, extra, all) in cases {
        cli_bin()
            .args(generate_args(&config, out, mode))
            .args(*extra)
            .current_dir(tmp.path())
            .assert()
            .success();
        let files = assert_mocks_match_plain(&tmp.path().join(out), &plain, *all, None);
        assert!(
            files.contains(&"Dog+Mock.graphql.swift".to_string()),
            "{out}: {files:?}"
        );
    }
    // the referenced scope of the mutation alone is a strict subset (no Query)
    let referenced = swift_files(&tmp.path().join("tm-ref/TestMocks"));
    assert!(
        referenced.contains_key("Mutation+Mock.graphql.swift")
            && !referenced.contains_key("Query+Mock.graphql.swift"),
        "{:?}",
        referenced.keys()
    );
    assert!(referenced.len() < plain.len());

    // a feature module importing a base: identical but for the import line
    cli_bin()
        .args(generate_args(&config, "tm-base", "test_mocks"))
        .args([
            "--bazel-mocks-base-module",
            "AnimalBaseMocks",
            "--bazel-mocks-exclude",
            "Query",
            "--bazel-mocks-exclude",
            "Mutation",
        ])
        .current_dir(tmp.path())
        .assert()
        .success();
    let files = assert_mocks_match_plain(
        &tmp.path().join("tm-base"),
        &plain,
        false,
        Some("AnimalBaseMocks"),
    );
    assert!(
        !files.iter().any(|f| f.starts_with("MockObject"))
            && !files.contains(&"Query+Mock.graphql.swift".to_string()),
        "{files:?}"
    );
    assert!(
        fs::read_to_string(tmp.path().join("tm-base/TestMocks/Dog+Mock.graphql.swift"))
            .unwrap()
            .contains("import AnimalBaseMocks\n")
    );

    // Bazel mode writes only into its tree artifact: the plain output next to it is untouched
    // (pruning used to walk the configured paths and delete every generated file there).
    assert_eq!(swift_files(&tmp.path().join("Mocks")), plain);
    assert_eq!(list_files(&tmp.path().join("Schema")), schema_files_before);
}

#[test]
fn worker_bazel_mode_mocks_equal_plain_generate() {
    let tmp = TempDir::new().unwrap();
    let config = write_animal_kingdom(tmp.path());
    let plain = plain_mocks(tmp.path());

    let mut graphql: Vec<String> = fs::read_dir(tmp.path().join("graphql"))
        .unwrap()
        .flatten()
        .map(|e| format!("graphql/{}", e.file_name().to_string_lossy()))
        .collect();
    graphql.sort();
    let digests: Vec<Vec<u8>> = (0..graphql.len()).map(|i| vec![i as u8 + 1]).collect();
    let inputs: Vec<(&str, &[u8])> = graphql
        .iter()
        .zip(&digests)
        .map(|(p, d)| (p.as_str(), d.as_slice()))
        .collect();
    let args = |out: &str, mode: &str, extra: &[&str]| -> Vec<String> {
        let mut v: Vec<String> = generate_args(&config, out, mode)
            .into_iter()
            .map(String::from)
            .collect();
        v.extend(extra.iter().map(|s| s.to_string()));
        v
    };

    let mut worker = Worker::spawn(tmp.path());
    // 1. an operations request first: the later mock requests are served from the
    //    compilation cache with a fresh IR, which is where the fields were missing
    worker.send(
        1,
        &args(
            "ops",
            "operations",
            &["--bazel-generate-for", "graphql/DogQuery.graphql"],
        ),
        &inputs,
    );
    let response = worker.receive();
    assert_eq!(response.exit_code, 0, "{}", response.output);
    assert!(list_files(&tmp.path().join("ops"))
        .iter()
        .any(|f| f.ends_with("DogQuery.graphql.swift")));

    let cases: &[(i32, &str, &str, &[&str], bool)] = &[
        (2, "w-tm", "test_mocks", &[], true),
        (3, "w-st", "schema_types", &[], true),
        (
            4,
            "w-tm-ref",
            "test_mocks",
            &[
                "--bazel-mocks-scope",
                "referenced",
                "--bazel-generate-for",
                "graphql/PetAdoptionMutation.graphql",
            ],
            false,
        ),
        (
            5,
            "w-tm-for",
            "test_mocks",
            &["--bazel-generate-for", "graphql/DogQuery.graphql"],
            true,
        ),
        (
            6,
            "w-st-prefix",
            "schema_types",
            &["--bazel-framework-path", "graphql"],
            true,
        ),
    ];
    for (id, out, mode, extra, _) in cases {
        worker.send(*id, &args(out, mode, extra), &inputs);
    }
    let mut responses: Vec<Response> = cases.iter().map(|_| worker.receive()).collect();
    responses.sort_by_key(|r| r.request_id);
    for (response, (id, out, _, _, all)) in responses.iter().zip(cases) {
        assert_eq!(response.request_id, *id);
        assert_eq!(response.exit_code, 0, "{out}: {}", response.output);
        let files = assert_mocks_match_plain(&tmp.path().join(out), &plain, *all, None);
        assert!(
            files.contains(&"Dog+Mock.graphql.swift".to_string()),
            "{out}: {files:?}"
        );
    }

    let (code, stderr) = worker.finish();
    assert_eq!(code, 0, "{}", stderr);
    assert!(!stderr.contains("panicked"), "{}", stderr);
    assert_eq!(
        stderr.matches("Compilation cache miss").count(),
        1,
        "{}",
        stderr
    );
    assert_eq!(swift_files(&tmp.path().join("Mocks")), plain);
}
