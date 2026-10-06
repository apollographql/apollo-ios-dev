//! Root CLI binary for Apollo iOS code generation.
//!
//! Mirrors Swift's `Sources/apollo-ios-cli/Apollo_iOS_CLI.swift`.
//! Registers 4 subcommands: init, generate, fetch-schema, generate-operation-manifest.
//! Exit codes: 0 = success, 1 = any error (D-77).
//!
//! When invoked with `--persistent_worker`, enters Bazel worker mode (D-87).

mod worker;
mod worker_io;
mod worker_proto;

#[cfg(test)]
mod worker_bench;

use clap::{Parser, Subcommand};

use codegen_cli::commands::{
    fetch_schema::FetchSchema, generate::Generate,
    generate_operation_manifest::GenerateOperationManifest, initialize::Initialize,
};
use codegen_cli::constants;

/// A command line utility for Apollo iOS code generation.
#[derive(Parser)]
#[command(name = "apollo-ios-cli")]
#[command(about = "A command line utility for Apollo iOS code generation.")]
#[command(version = constants::CLI_VERSION)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Initialize a new configuration with defaults.
    #[command(name = "init")]
    Init(Initialize),
    /// Generate Swift source code based on a code generation configuration.
    Generate(Generate),
    /// Download a GraphQL schema from the Apollo Registry or GraphQL introspection.
    #[command(name = "fetch-schema")]
    FetchSchema(FetchSchema),
    /// Generate Persisted Queries operation manifest based on a code generation configuration.
    #[command(name = "generate-operation-manifest")]
    GenerateOperationManifest(GenerateOperationManifest),
}

/// Expand Bazel-style `@<file>` flagfile arguments. Bazel writes a single
/// params file per action when `args.use_param_file("@%s", ...)` is set on a
/// rule. In persistent-worker mode Bazel reads that file itself and ships the
/// args via a `WorkRequest` proto (so `@<file>` never reaches argv). In plain
/// spawn mode (RBE / non-worker local execution), Bazel passes `@<file>`
/// literally on argv and expects the binary to expand it.
///
/// Each line in the params file becomes one argv entry, in order.
fn expand_response_files(args: Vec<String>) -> Vec<String> {
    args.into_iter()
        .flat_map(|arg| match arg.strip_prefix('@') {
            Some(path) => match std::fs::read_to_string(path) {
                Ok(contents) => contents
                    .lines()
                    .map(|line| line.to_string())
                    .collect::<Vec<_>>(),
                Err(_) => vec![arg],
            },
            None => vec![arg],
        })
        .collect()
}

fn main() {
    // D-87: Check for --persistent_worker before clap parsing.
    // Bazel passes this flag when spawning persistent workers.
    // Must be checked in raw args because Bazel may also pass
    // arguments that clap doesn't understand.
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--persistent_worker") {
        worker::run_worker_loop();
        return; // run_worker_loop calls process::exit, but belt-and-suspenders
    }

    // Expand `@<file>` response-file arguments for non-worker spawns (RBE).
    // Worker mode handled above; this is a no-op when no @-args are present.
    let expanded = expand_response_files(args);

    // Normal CLI mode
    let cli = Cli::parse_from(expanded);

    let result = match cli.command {
        Commands::Init(mut cmd) => cmd.run(),
        Commands::Generate(cmd) => cmd.run(),
        Commands::FetchSchema(cmd) => cmd.run(),
        Commands::GenerateOperationManifest(cmd) => cmd.run(),
    };

    // D-77: Exit codes match Swift -- 0 = success, 1 = any error
    match result {
        Ok(()) => std::process::exit(0),
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    }
}
