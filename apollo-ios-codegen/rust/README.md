# Rust port of `apollo-ios-cli`

This directory contains a Rust implementation of the Apollo iOS code generation CLI. It
produces the same files, with the same bytes, as the Swift + graphql-js implementation in
`../Sources`, and adds output modes and a persistent worker for build systems such as Bazel.
Without the `--bazel-*` flags it behaves exactly like the Swift CLI.

The port uses [apollo-rs](https://github.com/apollographql/apollo-rs) (`apollo-compiler`) in
place of graphql-js running in JavaScriptCore, and reproduces graphql-js behaviour where the
generated output depends on it (referenced-type order, `__typename` handling, string
escaping, operation source printing, validation messages).

## Layout

| Crate | Mirrors (Swift) | Responsibility |
|---|---|---|
| `graphql-compiler` | `GraphQLCompiler` + `apollo-codegen-frontend` (TS) | Parses and validates with apollo-compiler, then converts to the Swift-equivalent model (`GraphQLSchema`, `GraphQLType`, `GraphQLValue`, `CompilationResult`). No apollo-compiler type crosses this crate's boundary. |
| `ir` | `IR` | `IRBuilder`, definitions, entities, `EntitySelectionTree`, direct and merged selections, scope descriptors, inclusion conditions, field collector. |
| `template-string` + `template-string-macros` | `TemplateString` | Runtime builder plus the `template_string!` proc macro with Swift's interpolation forms (`if:`, `ifLet:`, `forEachIn:`, `list:`, `comment:`, `documentation:`, `section:`). |
| `apollo-codegen-lib` | `ApolloCodegenLib` | Configuration, file discovery, templates, file generators, capitalization and inflection, test mock scope. Also the `ir-compare` debugging binary. |
| `codegen-cli` | `CodegenCLI` | `generate`, `init`, `fetch-schema`, `generate-operation-manifest`, and the Bazel flags. |
| `apollo-ios-cli` | the executable | Entry point, persistent worker loop, worker protocol I/O (`proto/worker_protocol.proto`), benchmarks. |
| `utilities` | `Utilities` | Small helpers. |

The version constant (`CODEGEN_VERSION` in
`apollo-codegen-lib/src/templates/swift_package_manager_module_template.rs`) must match
`Sources/ApolloCodegenLib/Constants.swift`; `--version` prints it.

## Building and testing

```sh
cd apollo-ios-codegen/rust
cargo build --release -p apollo-ios-cli      # binary at target/release/apollo-ios-cli
cargo test --workspace                       # unit + integration tests
cargo fmt --all --check && cargo clippy --workspace --all-targets
cargo test --release -p apollo-ios-cli -- --ignored bench_   # timing benchmarks (ignored by default)
```

A stable Rust toolchain is sufficient; the worker protocol types are generated at build time
from `proto/worker_protocol.proto` with `protox` (no `protoc` needed).

## Parity check

The compatibility contract is byte-for-byte equality with the Swift CLI on identical inputs.
`scripts/parity-smoke.sh` runs both CLIs on the repository's AnimalKingdom fixture and diffs
the generated trees:

```sh
(cd apollo-ios-codegen && swift build -c release --product apollo-ios-cli)
(cd apollo-ios-codegen/rust && cargo build --release -p apollo-ios-cli)
apollo-ios-codegen/rust/scripts/parity-smoke.sh \
  apollo-ios-codegen/.build/release/apollo-ios-cli \
  apollo-ios-codegen/rust/target/release/apollo-ios-cli
```

The same comparison is run in CI (`.github/workflows/rust-codegen.yml`). The full harness
used during development additionally covers the other SwiftScripts targets, the
`Tests/TestCodeGenConfigurations` configs, an options matrix, a synthetic schema exercising
every template feature, `init`, operation manifests, invalid inputs (exit status, no panics)
and test mocks compiled against `ApolloTestSupport`.

## Bazel mode

All flags are additive to `generate`; without `--bazel-output-dir` the CLI behaves like
upstream.

- `--bazel-output-dir <dir>`: write a tree artifact instead of the configured output paths
  (the config's output section only selects the module layout). Pruning is off in this mode.
- `--bazel-mode schema_types | operations | test_mocks`: schema types (plus mocks under
  `TestMocks/` when configured), operations and fragments only, or mocks only.
- `--bazel-generate-for <file>` (repeatable): generate exactly the definitions in those files;
  `--bazel-framework-path <prefix>` is the older prefix form. The schema module still sees every
  operation, so referenced types are complete.
- `--bazel-keep-schema-configuration`: keep `SchemaConfiguration.swift` and `CustomScalars/`
  in the artifact (by default a rule provides these user-editable files itself).
- `--bazel-strip-import <module>`: drop `import <module>` lines (e.g. when operations are
  compiled into the schema module).
- `--bazel-optimize-schema-metadata`: dictionary lookup in `SchemaMetadata.objectType(forTypename:)`.
- Test mocks: `--bazel-mocks-scope all|referenced`, `--bazel-mocks-for <Type>`,
  `--bazel-mocks-exclude <Type>`, `--bazel-mocks-base-module <Module>`,
  `--bazel-mocks-typealiases true|false`. The same settings are available as the config keys
  `scope`, `includeTypes`, `excludeTypes`, `baseModule`, `includeTypealiases` inside
  `output.testMocks.absolute|swiftPackage`. A partition is a base module (shared types plus the
  `MockObject+Interfaces` / `MockObject+Unions` typealias files) and per-feature modules that
  import it; the union of a partition equals the unscoped output file for file.

## Persistent worker

`apollo-ios-cli --persistent_worker` implements the Bazel worker protocol over stdin/stdout
(length-delimited `WorkRequest` / `WorkResponse`), singleplex and multiplex. The parsed schema
is shared across requests (keyed on schema paths and input digests) and compilation results are
cached per config and input digests, so one worker parses a schema once for every operations
target that uses it. Validation and I/O errors come back as a `WorkResponse` with
`exit_code = 1`; a panic inside a request is caught and reported the same way. All diagnostic
output goes to stderr. `WorkRequest.sandbox_dir` is not implemented (Bazel falls back to
sandboxed singleplex workers with `--worker_sandboxing`).
