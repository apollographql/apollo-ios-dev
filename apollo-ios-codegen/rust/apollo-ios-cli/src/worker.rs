//! Bazel persistent worker mode (singleplex and multiplex).
//!
//! Implements the Bazel worker protocol: reads `WorkRequest`s from stdin, runs
//! the codegen pipeline and writes `WorkResponse`s to stdout. Requests with
//! `request_id == 0` (singleplex) are processed inline, in order. Requests with a
//! non-zero id (multiplex, `supports-multiplex-workers`) are processed
//! concurrently on their own threads and answered with the same `request_id`,
//! in whatever order they finish; stdout writes are serialized.
//!
//! The parsed schema is shared across every request of the process through an
//! `Arc<CompiledSchema>` cache keyed on the schema files (paths + Bazel digests),
//! so a multiplex worker parses each schema once. The compilation result is
//! cached per config digest (the raw config text) + schema digests + operation
//! digests, so two targets with different configs never serve each other's
//! compilation. Concurrent requests for the same compilation wait for one
//! compile, and test mock requests also share the operations' collected fields.
//!
//! Nothing a request does can take the worker down: validation and I/O errors
//! are returned as a `WorkResponse` with `exit_code = 1`, and a panic inside a
//! request is caught and reported the same way.
//!
//! All non-protocol output goes to stderr.

use std::collections::{BTreeMap, VecDeque};

use indexmap::{IndexMap, IndexSet};
use std::io::{self, BufReader};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use clap::Parser;
use sha2::{Digest as _, Sha256};

use apollo_codegen_lib::codegen::{
    ApolloCodegen, CompilationResult, CompileResult, CompiledSchema,
};
use apollo_codegen_lib::codegen_logger::CodegenLogger;
use apollo_codegen_lib::templates::ConfigurationContext;

use codegen_cli::commands::generate::Generate;
use codegen_cli::input_options;

use crate::worker_io::{read_work_request, write_work_response};
use crate::worker_proto::{Input, WorkRequest, WorkResponse};
use crate::{Cli, Commands};

/// Bazel input path -> digest, sorted for stable comparison.
type DigestMap = BTreeMap<String, Vec<u8>>;

/// Stack size for request threads: template rendering and IR building recurse
/// deeply, and spawned threads default to 512 KiB on macOS.
const REQUEST_THREAD_STACK_SIZE: usize = 64 * 1024 * 1024;

/// Compilations seen by one request so far, oldest first. Under rules_apollo most
/// are operations targets whose config (their own `operationSearchPaths`) no other
/// request shares.
const MAX_PROBATION_COMPILATIONS: usize = 8;

/// Compilations that served more than one request (test mocks and the schema
/// types share the whole app's compilation). Probation entries never evict these,
/// so hundreds of one-off operations requests cannot push them out.
const MAX_PROTECTED_COMPILATIONS: usize = 4;

/// Cached parsed schema (the expensive part, ~5s on large schemas).
///
/// Keyed on the schema files themselves (their sorted paths) rather than the
/// whole config: under rules_apollo every operations target has a different
/// config (its own `operationSearchPaths`) but the same schema, and the point of
/// the cache is to parse that schema once. The digests invalidate the entry when
/// the schema changes.
struct CachedSchema {
    schema_digests: DigestMap,
    compiled_schema: Arc<CompiledSchema>,
}

/// One compilation, shared by every request with the same config digest, schema
/// digests and operation digests.
///
/// Hit only when all three match: `compile_graphql`/`validate_against_schema` read
/// the config (schema namespace, experimental features), so a different config
/// must recompile even for identical operation files.
pub struct CompilationSlot {
    schema_digests: DigestMap,
    operation_digests: DigestMap,
    /// Set by the first request. Concurrent requests for the same slot wait for
    /// it instead of compiling the same operations again.
    result: OnceLock<Result<Arc<CompilationResult>, String>>,
    /// The compilation's IR with the fields of every operation collected, shared
    /// by test mock requests. Collecting walks every operation of the app, and
    /// the result is the same for every request of this slot.
    mock_ir: OnceLock<Arc<CompileResult>>,
}

/// Caches shared by every request of the worker process.
#[derive(Default)]
pub struct WorkerCache {
    /// sorted schema paths -> parsed schema
    schemas: IndexMap<Vec<String>, CachedSchema>,
    /// config digest -> compilation
    compilations: IndexMap<String, Arc<CompilationSlot>>,
    /// config digests of compilations used by one request, oldest first
    probation: VecDeque<String>,
    /// config digests of compilations used by several requests, least recently
    /// used first
    protected: VecDeque<String>,
}

impl WorkerCache {
    fn schema(&self, schema_digests: &DigestMap) -> Option<Arc<CompiledSchema>> {
        let key: Vec<String> = schema_digests.keys().cloned().collect();
        self.schemas
            .get(&key)
            .filter(|cached| cached.schema_digests == *schema_digests)
            .map(|cached| Arc::clone(&cached.compiled_schema))
    }

    fn insert_schema(&mut self, schema_digests: DigestMap, compiled: Arc<CompiledSchema>) {
        let key: Vec<String> = schema_digests.keys().cloned().collect();
        self.schemas.insert(
            key,
            CachedSchema {
                schema_digests,
                compiled_schema: compiled,
            },
        );
    }

    /// Returns the slot for this config, schema and operations, creating an empty
    /// one on a miss. A hit moves the slot to the protected list.
    fn compilation_slot(
        &mut self,
        config_digest: &str,
        schema_digests: &DigestMap,
        operation_digests: &DigestMap,
    ) -> Arc<CompilationSlot> {
        if let Some(slot) = self.compilations.get(config_digest) {
            if slot.schema_digests == *schema_digests
                && slot.operation_digests == *operation_digests
            {
                let slot = Arc::clone(slot);
                self.probation.retain(|d| d != config_digest);
                self.protected.retain(|d| d != config_digest);
                self.protected.push_back(config_digest.to_string());
                while self.protected.len() > MAX_PROTECTED_COMPILATIONS {
                    if let Some(oldest) = self.protected.pop_front() {
                        self.compilations.swap_remove(&oldest);
                    }
                }
                return slot;
            }
        }

        // Miss, or the schema or operations changed: start over in probation.
        self.forget(config_digest);
        while self.probation.len() >= MAX_PROBATION_COMPILATIONS {
            if let Some(oldest) = self.probation.pop_front() {
                self.compilations.swap_remove(&oldest);
            }
        }
        let slot = Arc::new(CompilationSlot {
            schema_digests: schema_digests.clone(),
            operation_digests: operation_digests.clone(),
            result: OnceLock::new(),
            mock_ir: OnceLock::new(),
        });
        self.probation.push_back(config_digest.to_string());
        self.compilations
            .insert(config_digest.to_string(), Arc::clone(&slot));
        slot
    }

    /// Drops the compilation of `config_digest`, if any.
    fn forget(&mut self, config_digest: &str) {
        if self.compilations.swap_remove(config_digest).is_some() {
            self.probation.retain(|d| d != config_digest);
            self.protected.retain(|d| d != config_digest);
        }
    }

    /// Drops `slot` if it is still the cached one (a failed compilation is not
    /// kept: the next request retries it).
    fn forget_slot(&mut self, config_digest: &str, slot: &Arc<CompilationSlot>) {
        if self
            .compilations
            .get(config_digest)
            .is_some_and(|cached| Arc::ptr_eq(cached, slot))
        {
            self.forget(config_digest);
        }
    }
}

/// Runs the persistent worker loop.
///
/// Called from main() when --persistent_worker is detected.
/// Exits on stdin EOF or SIGINT/SIGTERM.
pub fn run_worker_loop() {
    // Redirect panics to stderr so they never corrupt stdout
    std::panic::set_hook(Box::new(|info| {
        eprintln!("Worker panic: {}", info);
    }));

    // Set up signal handler for graceful shutdown
    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_signal = shutdown.clone();
    if let Err(e) = ctrlc::set_handler(move || {
        eprintln!("Worker received shutdown signal, exiting...");
        shutdown_signal.store(true, Ordering::SeqCst);
    }) {
        eprintln!("Worker could not install signal handler: {}", e);
    }

    let stdin = io::stdin().lock();
    let mut reader = BufReader::new(stdin);

    // Long-lived caches shared by every request.
    let cache: Arc<Mutex<WorkerCache>> = Arc::new(Mutex::new(WorkerCache::default()));
    let mut in_flight: Vec<std::thread::JoinHandle<()>> = Vec::new();

    eprintln!("Apollo iOS codegen worker started (singleplex + multiplex)");

    loop {
        if shutdown.load(Ordering::SeqCst) {
            eprintln!("Worker shutting down due to signal");
            break;
        }

        // Read next request; None = EOF = graceful shutdown
        let request = match read_work_request(&mut reader) {
            Ok(Some(req)) => req,
            Ok(None) => {
                eprintln!("Worker received EOF, shutting down");
                break;
            }
            Err(e) => {
                eprintln!("Error reading WorkRequest: {}", e);
                break;
            }
        };

        // Cancellation: requests cannot be aborted midway; Bazel accepts the
        // regular response of a request it asked to cancel, so nothing to do.
        if request.cancel {
            eprintln!(
                "Cancel request for {} ignored; the request completes normally",
                request.request_id
            );
            continue;
        }

        in_flight.retain(|handle| !handle.is_finished());

        if request.request_id == 0 {
            // Singleplex: process inline, in order.
            let response = process_request(&request, &cache);
            if let Err(e) = write_response(&response) {
                eprintln!("Error writing WorkResponse: {}", e);
                break;
            }
        } else {
            // Multiplex: process concurrently, answer with the request's id.
            let cache = Arc::clone(&cache);
            let spawned = std::thread::Builder::new()
                .name(format!("request-{}", request.request_id))
                .stack_size(REQUEST_THREAD_STACK_SIZE)
                .spawn(move || {
                    let response = process_request(&request, &cache);
                    if let Err(e) = write_response(&response) {
                        eprintln!("Error writing WorkResponse: {}", e);
                    }
                });
            match spawned {
                Ok(handle) => in_flight.push(handle),
                Err(e) => eprintln!("Could not spawn request thread: {}", e),
            }
        }
    }

    for handle in in_flight {
        let _ = handle.join();
    }

    // Graceful shutdown -- drop caches explicitly
    drop(cache);
    eprintln!("Worker shutdown complete");
    std::process::exit(0);
}

/// Writes one response; `Stdout::lock()` serializes concurrent writers so only
/// whole protocol messages reach stdout.
fn write_response(response: &WorkResponse) -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    write_work_response(&mut stdout, response)
}

/// Handles one request, never panicking: a panic inside the pipeline becomes
/// an `exit_code = 1` response and the worker keeps running.
pub fn process_request(request: &WorkRequest, cache: &Mutex<WorkerCache>) -> WorkResponse {
    match catch_unwind(AssertUnwindSafe(|| handle_request(request, cache))) {
        Ok(response) => response,
        Err(payload) => {
            let message = payload
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_else(|| "unknown panic".to_string());
            failure(request, format!("Internal error: {}", message))
        }
    }
}

fn failure(request: &WorkRequest, output: String) -> WorkResponse {
    WorkResponse {
        exit_code: 1,
        output,
        request_id: request.request_id,
        was_cancelled: false,
    }
}

/// Handles a single WorkRequest.
///
/// 1. Parse WorkRequest.arguments through clap
/// 2. Look the schema up in the shared cache (parsed once per schema)
/// 3. Look the compilation up (config digest + schema + operation digests)
/// 4. Generate into the tree artifact or the configured paths
/// 5. Return WorkResponse with exit_code and output and the request's id
///
/// All request-local state lives in this function's scope and drops when it
/// returns. Only the shared caches persist.
fn handle_request(request: &WorkRequest, cache: &Mutex<WorkerCache>) -> WorkResponse {
    let t_total = std::time::Instant::now();

    // Parse arguments through clap; prepend argv[0].
    let mut args = vec!["apollo-ios-cli".to_string()];
    args.extend(request.arguments.iter().cloned());

    let cli = match Cli::try_parse_from(&args) {
        Ok(cli) => cli,
        Err(e) => return failure(request, format!("Failed to parse arguments: {}", e)),
    };

    // Only the generate command is supported in worker mode
    let generate_cmd: Generate = match cli.command {
        Commands::Generate(cmd) => cmd,
        _ => {
            return failure(
                request,
                "Worker only supports the 'generate' command".to_string(),
            )
        }
    };

    CodegenLogger::set_level(generate_cmd.inputs.verbose);

    let t0 = std::time::Instant::now();

    // Load configuration (errors are returned in the WorkResponse)
    let config_text = match config_text(&generate_cmd) {
        Ok(text) => text,
        Err(e) => return failure(request, format!("Failed to load configuration: {}", e)),
    };
    let config_digest = sha256_hex(config_text.as_bytes());
    let mut configuration = match generate_cmd.inputs.get_codegen_configuration() {
        Ok(config) => config,
        Err(e) => return failure(request, format!("Failed to load configuration: {}", e)),
    };

    if let Err(e) = generate_cmd.apply_bazel_mock_overrides(&mut configuration) {
        return failure(request, e.to_string());
    }

    let root_url = input_options::root_output_url(&generate_cmd.inputs);

    // Disable pruning in worker mode: several workers share the execroot
    // and Bazel manages the outputs through tree artifacts; pruning in one worker
    // would delete files another one is writing.
    configuration.options.prune_generated_files = false;

    let items_to_generate = Generate::items_to_generate(&configuration);
    let mut config = ConfigurationContext::new(configuration, root_url);

    // Direct-write: generation writes into the Bazel tree artifact directory.
    if let Some(ref output_dir) = generate_cmd.bazel_output_dir {
        let output_root = std::path::PathBuf::from(output_dir);
        if let Err(e) = std::fs::create_dir_all(&output_root) {
            return failure(
                request,
                format!("Failed to create output dir {}: {}", output_dir, e),
            );
        }
        config.set_output_root(Some(output_root));
    }

    let config_ms = t0.elapsed().as_secs_f64() * 1000.0;

    // Step 1: cache lookup (cheap BTreeMap comparisons) before any file discovery.
    let t1 = std::time::Instant::now();
    let schema_digests = extract_schema_digests(&request.inputs, &config);
    let operation_digests = extract_operation_digests(&request.inputs);
    let slot = lock(cache).compilation_slot(&config_digest, &schema_digests, &operation_digests);

    // Step 2: compile, unless another request did or is doing it. Files are
    // discovered only when something has to be parsed or compiled (globbing the
    // source tree costs ~400-900ms on large trees).
    let mut discover_ms = 0.0;
    let compiled = slot.result.get_or_init(|| {
        let t_discover = std::time::Instant::now();
        let (schema_matches, operation_matches) =
            ApolloCodegen::discover_files(&config).map_err(|e| e.to_string())?;
        discover_ms = t_discover.elapsed().as_secs_f64() * 1000.0;

        let cached_schema = lock(cache).schema(&schema_digests);
        let compiled_schema = match cached_schema {
            Some(schema) => schema,
            None => {
                // Parse under the cache lock: concurrent multiplex requests for
                // the same schema wait for this parse instead of repeating it.
                let mut cache = lock(cache);
                match cache.schema(&schema_digests) {
                    Some(schema) => schema,
                    None => {
                        eprintln!("Schema cache miss -- parsing schema");
                        let compiled = Arc::new(
                            ApolloCodegen::parse_schema_files(&schema_matches)
                                .map_err(|e| e.to_string())?,
                        );
                        cache.insert_schema(schema_digests.clone(), Arc::clone(&compiled));
                        compiled
                    }
                }
            }
        };

        eprintln!("Compilation cache miss -- compiling operations");
        ApolloCodegen::compile_operations_with_schema(&compiled_schema, &operation_matches, &config)
            .map(|result| Arc::clone(&result.compilation_result))
            .map_err(|e| e.to_string())
    });
    let compilation_result = match compiled {
        Ok(result) => Arc::clone(result),
        Err(message) => {
            lock(cache).forget_slot(&config_digest, &slot);
            return failure(request, message.clone());
        }
    };
    let schema_ms = t1.elapsed().as_secs_f64() * 1000.0;

    // Step 3: IR builder over the (shared) compilation result. Test mocks share
    // one with the fields of every operation collected; everything else gets a
    // fresh one.
    let t3 = std::time::Instant::now();
    let shares_mock_ir = generate_cmd.bazel_mode == "test_mocks" && config.output_root().is_some();
    let compile_result = if shares_mock_ir {
        Arc::clone(slot.mock_ir.get_or_init(|| {
            let compile_result =
                ApolloCodegen::compile_result_from_cached(Arc::clone(&compilation_result));
            ApolloCodegen::collect_mock_fields(&compile_result, &config);
            Arc::new(compile_result)
        }))
    } else {
        Arc::new(ApolloCodegen::compile_result_from_cached(
            compilation_result,
        ))
    };
    let compile_ms = t3.elapsed().as_secs_f64() * 1000.0;

    // Step 4: generate
    let t4 = std::time::Instant::now();
    let generate_result = if config.output_root().is_some() {
        generate_cmd
            .generate_bazel_with(&compile_result, &config, items_to_generate, shares_mock_ir)
            .map_err(|e| e.to_string())
    } else {
        ApolloCodegen::generate_from_ir(&compile_result, &config, items_to_generate)
            .map_err(|e| e.to_string())
    };
    let generate_ms = t4.elapsed().as_secs_f64() * 1000.0;

    match generate_result {
        Ok(()) => {
            let total_ms = t_total.elapsed().as_secs_f64() * 1000.0;
            let target_label = generate_cmd
                .bazel_generate_for
                .first()
                .map(String::as_str)
                .or(generate_cmd.bazel_framework_path.as_deref())
                .unwrap_or(&generate_cmd.bazel_mode);
            eprintln!(
                "[perf] #{} {} {} | total={:.1}ms config={:.1}ms discover={:.1}ms schema+compile={:.1}ms ir={:.1}ms generate={:.1}ms",
                request.request_id, generate_cmd.bazel_mode, target_label, total_ms, config_ms, discover_ms, schema_ms, compile_ms, generate_ms
            );
            WorkResponse {
                exit_code: 0,
                output: String::new(),
                request_id: request.request_id,
                was_cancelled: false,
            }
        }
        Err(message) => failure(request, message),
    }
}

/// Locks the cache, recovering from a poisoned lock (a panicking request must not
/// take the cache down with it).
fn lock(cache: &Mutex<WorkerCache>) -> std::sync::MutexGuard<'_, WorkerCache> {
    cache
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The raw configuration text (`--string` or the `--path` file), hashed as the
/// config digest.
fn config_text(generate_cmd: &Generate) -> Result<String, String> {
    match &generate_cmd.inputs.string {
        Some(json) => Ok(json.clone()),
        None => std::fs::read_to_string(&generate_cmd.inputs.path)
            .map_err(|e| format!("{}: {}", generate_cmd.inputs.path, e)),
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Extracts digests for schema files from the WorkRequest inputs.
///
/// Uses the config's schemaSearchPaths to identify which input files are
/// schema files (typically just one `schema.graphqls`). Returns a sorted
/// map of schema file path -> digest for cache key comparison.
fn extract_schema_digests(inputs: &[Input], config: &ConfigurationContext) -> DigestMap {
    let schema_paths: IndexSet<&str> = config
        .config
        .input
        .schema_search_paths
        .iter()
        .map(|s| s.as_str())
        .collect();

    let mut digests = BTreeMap::new();
    for input in inputs {
        // Match by exact path or by suffix (Bazel paths may be relative to execroot)
        if schema_paths.contains(input.path.as_str())
            || schema_paths.iter().any(|sp| input.path.ends_with(sp))
            || input.path.ends_with(".graphqls")
        {
            digests.insert(input.path.clone(), input.digest.clone());
        }
    }
    digests
}

/// Extracts digests for operation files (.graphql, not .graphqls) from WorkRequest inputs.
fn extract_operation_digests(inputs: &[Input]) -> DigestMap {
    let mut digests = BTreeMap::new();
    for input in inputs {
        if input.path.ends_with(".graphql") && !input.path.ends_with(".graphqls") {
            digests.insert(input.path.clone(), input.digest.clone());
        }
    }
    digests
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::worker_proto::Input;

    const CONFIG: &str = r#"{"schemaNamespace":"MySchema","input":{"operationSearchPaths":["**/*.graphql"],"schemaSearchPaths":["Schema/schema.graphqls"]},"output":{"testMocks":{"none":{}},"schemaTypes":{"moduleType":{"other":{}},"path":"out"},"operations":{"inSchemaModule":{}}}}"#;

    fn request(request_id: i32, arguments: &[&str]) -> WorkRequest {
        WorkRequest {
            arguments: arguments.iter().map(|s| s.to_string()).collect(),
            inputs: vec![],
            request_id,
            cancel: false,
            verbosity: 0,
            sandbox_dir: String::new(),
        }
    }

    fn digests(entries: &[(&str, u8)]) -> DigestMap {
        entries
            .iter()
            .map(|(path, byte)| (path.to_string(), vec![*byte]))
            .collect()
    }

    #[test]
    fn test_extract_schema_digests_matches_graphqls() {
        let inputs = vec![
            Input {
                path: "Schema/schema.graphqls".to_string(),
                digest: vec![1, 2, 3],
            },
            Input {
                path: "Features/X/Query.graphql".to_string(),
                digest: vec![4, 5],
            },
        ];
        let cfg: apollo_codegen_lib::config::ApolloCodegenConfiguration =
            serde_json::from_str(CONFIG).unwrap();
        let ctx = ConfigurationContext::new(cfg, None);

        let digests = extract_schema_digests(&inputs, &ctx);
        assert_eq!(digests.len(), 1);
        assert_eq!(digests["Schema/schema.graphqls"], vec![1, 2, 3]);
    }

    #[test]
    fn test_extract_operation_digests() {
        let inputs = vec![
            Input {
                path: "Schema/schema.graphqls".to_string(),
                digest: vec![1, 2, 3],
            },
            Input {
                path: "Features/Account/Query.graphql".to_string(),
                digest: vec![4, 5],
            },
            Input {
                path: "Shared/Fragments/Shared.graphql".to_string(),
                digest: vec![6, 7],
            },
            Input {
                path: "some/other.txt".to_string(),
                digest: vec![8],
            },
        ];
        let digests = extract_operation_digests(&inputs);
        assert_eq!(digests.len(), 2);
        assert!(digests.contains_key("Features/Account/Query.graphql"));
        assert!(digests.contains_key("Shared/Fragments/Shared.graphql"));
        assert!(!digests.contains_key("Schema/schema.graphqls"));
    }

    #[test]
    fn test_unsupported_command_is_an_error_response() {
        let cache = Mutex::new(WorkerCache::default());
        let response = process_request(&request(0, &["init", "--module-type", "other"]), &cache);
        assert_eq!(response.exit_code, 1);
        assert!(
            response
                .output
                .contains("Worker only supports the 'generate' command"),
            "{}",
            response.output
        );
        assert_eq!(response.request_id, 0);
    }

    #[test]
    fn test_invalid_args_is_an_error_response() {
        let cache = Mutex::new(WorkerCache::default());
        let response = process_request(&request(3, &["--not-a-real-flag"]), &cache);
        assert_eq!(response.exit_code, 1);
        assert!(response.output.contains("Failed to parse arguments"));
        assert_eq!(
            response.request_id, 3,
            "multiplex responses echo the request id"
        );
    }

    #[test]
    fn test_missing_config_is_an_error_response_with_request_id() {
        let cache = Mutex::new(WorkerCache::default());
        let response = process_request(
            &request(
                7,
                &[
                    "generate",
                    "--path",
                    "/nonexistent/apollo-codegen-config.json",
                ],
            ),
            &cache,
        );
        assert_eq!(response.exit_code, 1);
        assert!(
            response.output.contains("Failed to load configuration"),
            "{}",
            response.output
        );
        assert_eq!(response.request_id, 7);
    }

    #[test]
    fn test_schema_cache_is_keyed_on_paths_and_digests() {
        let mut cache = WorkerCache::default();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("schema.graphqls");
        std::fs::write(&path, "type Query { a: Int }").unwrap();
        let mut set = indexmap::IndexSet::new();
        set.insert(path.to_string_lossy().to_string());
        let compiled = Arc::new(ApolloCodegen::parse_schema_files(&set).unwrap());

        let v1 = digests(&[("Schema/schema.graphqls", 1)]);
        assert!(cache.schema(&v1).is_none());
        cache.insert_schema(v1.clone(), Arc::clone(&compiled));
        assert!(Arc::ptr_eq(&cache.schema(&v1).unwrap(), &compiled));
        // same path, new content: miss (and the entry is replaced on insert)
        let v2 = digests(&[("Schema/schema.graphqls", 2)]);
        assert!(cache.schema(&v2).is_none());
        // different schema files: independent entry
        let other = digests(&[("Other/schema.graphqls", 1)]);
        assert!(cache.schema(&other).is_none());
        cache.insert_schema(other.clone(), Arc::clone(&compiled));
        assert!(cache.schema(&other).is_some());
        assert!(cache.schema(&v1).is_some());
    }

    #[test]
    fn test_compilation_cache_is_keyed_on_config_schema_and_operations() {
        let mut cache = WorkerCache::default();
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("schema.graphqls"), "type Query { a: Int }").unwrap();
        std::fs::write(dir.path().join("Q.graphql"), "query Q { a }").unwrap();
        let config_json = format!(
            r#"{{"schemaNamespace":"Inv","input":{{"schemaSearchPaths":["{d}/schema.graphqls"],"operationSearchPaths":["{d}/*.graphql"]}},"output":{{"schemaTypes":{{"path":"Out","moduleType":{{"other":{{}}}}}},"operations":{{"inSchemaModule":{{}}}},"testMocks":{{"none":{{}}}}}}}}"#,
            d = dir.path().display()
        );
        let configuration: apollo_codegen_lib::config::ApolloCodegenConfiguration =
            serde_json::from_str(&config_json).unwrap();
        let config = ConfigurationContext::new(configuration, None);
        let result = Arc::clone(
            &ApolloCodegen::compile_schema_and_ir(&config)
                .unwrap()
                .compilation_result,
        );
        let schema = digests(&[("schema.graphqls", 1)]);
        let ops = digests(&[("A.graphql", 1), ("B.graphql", 2)]);
        let filled = |cache: &mut WorkerCache, key: &str| {
            let slot = cache.compilation_slot(key, &schema, &ops);
            slot.result.get_or_init(|| Ok(Arc::clone(&result)));
            slot
        };
        let slot = filled(&mut cache, "cfg-a");

        let hit = cache.compilation_slot("cfg-a", &schema, &ops);
        assert!(Arc::ptr_eq(&hit, &slot));
        assert!(hit.result.get().is_some());
        // a different config never serves the cached compilation
        assert!(cache
            .compilation_slot("cfg-b", &schema, &ops)
            .result
            .get()
            .is_none());
        // changed schema or operations miss
        assert!(cache
            .compilation_slot("cfg-c", &schema, &ops)
            .result
            .get()
            .is_none());
        let changed = cache.compilation_slot("cfg-a", &digests(&[("schema.graphqls", 9)]), &ops);
        assert!(!Arc::ptr_eq(&changed, &slot));
        assert!(changed.result.get().is_none());
        let changed = cache.compilation_slot("cfg-a", &schema, &digests(&[("A.graphql", 1)]));
        assert!(changed.result.get().is_none());
    }

    #[test]
    fn test_one_off_compilations_do_not_evict_shared_ones() {
        let mut cache = WorkerCache::default();
        let schema = digests(&[("schema.graphqls", 1)]);
        let ops = digests(&[("A.graphql", 1)]);

        // "app" serves two requests (e.g. two mocks targets): protected.
        let app = cache.compilation_slot("app", &schema, &ops);
        assert!(Arc::ptr_eq(
            &cache.compilation_slot("app", &schema, &ops),
            &app
        ));

        // Many operations targets, each seen once.
        for i in 0..(MAX_PROBATION_COMPILATIONS * 4) {
            cache.compilation_slot(&format!("ops-{}", i), &schema, &ops);
        }
        assert!(Arc::ptr_eq(
            &cache.compilation_slot("app", &schema, &ops),
            &app
        ));
        assert_eq!(cache.probation.len(), MAX_PROBATION_COMPILATIONS);
        // the oldest one-off entries are gone
        let first = cache.compilation_slot("ops-0", &schema, &ops);
        assert!(first.result.get().is_none());

        // protected entries are bounded too, least recently used first
        for i in 0..MAX_PROTECTED_COMPILATIONS {
            let key = format!("shared-{}", i);
            cache.compilation_slot(&key, &schema, &ops);
            cache.compilation_slot(&key, &schema, &ops);
        }
        assert_eq!(cache.protected.len(), MAX_PROTECTED_COMPILATIONS);
        assert!(!cache.protected.contains(&"app".to_string()));
        assert_eq!(
            cache.compilations.len(),
            cache.probation.len() + cache.protected.len()
        );
    }

    #[test]
    fn test_failed_compilations_are_not_kept() {
        let mut cache = WorkerCache::default();
        let schema = digests(&[("schema.graphqls", 1)]);
        let ops = digests(&[("A.graphql", 1)]);
        let slot = cache.compilation_slot("cfg", &schema, &ops);
        slot.result.get_or_init(|| Err("boom".to_string()));
        cache.forget_slot("cfg", &slot);
        assert!(cache
            .compilation_slot("cfg", &schema, &ops)
            .result
            .get()
            .is_none());
    }

    #[test]
    fn test_concurrent_misses_compile_once() {
        let cache = Arc::new(Mutex::new(WorkerCache::default()));
        let schema = digests(&[("schema.graphqls", 1)]);
        let ops = digests(&[("A.graphql", 1)]);
        let compiles = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let threads: Vec<_> = (0..8)
            .map(|_| {
                let (cache, schema, ops, compiles) = (
                    Arc::clone(&cache),
                    schema.clone(),
                    ops.clone(),
                    Arc::clone(&compiles),
                );
                std::thread::spawn(move || {
                    let slot = lock(&cache).compilation_slot("cfg", &schema, &ops);
                    slot.result
                        .get_or_init(|| {
                            compiles.fetch_add(1, Ordering::SeqCst);
                            std::thread::sleep(std::time::Duration::from_millis(50));
                            Err("compiled".to_string())
                        })
                        .clone()
                })
            })
            .collect();
        for thread in threads {
            assert_eq!(thread.join().unwrap().err(), Some("compiled".to_string()));
        }
        assert_eq!(compiles.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn test_sha256_hex_is_stable() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_ne!(sha256_hex(b"{}"), sha256_hex(b"{ }"));
    }
}
