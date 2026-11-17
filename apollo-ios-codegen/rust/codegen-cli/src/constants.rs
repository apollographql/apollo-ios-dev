//! CLI constants matching Swift's `Constants` enum.
//!
//! Mirrors `Sources/CodegenCLI/Constants.swift`.

/// CLI version string matching Swift's `Constants.CLIVersion`.
///
/// Every parity branch is a drop-in replacement for one Apollo iOS release, so the CLI
/// version is the same constant that the generated `Package.swift` pins the SDK to
/// (`CODEGEN_VERSION`); `--version` therefore identifies the release a binary was built for.
pub const CLI_VERSION: &str =
    apollo_codegen_lib::templates::swift_package_manager_module_template::CODEGEN_VERSION;

/// Default config file path matching Swift's `Constants.defaultFilePath`.
pub const DEFAULT_FILE_PATH: &str = "./apollo-codegen-config.json";
