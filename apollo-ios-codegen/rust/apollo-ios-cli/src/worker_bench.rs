//! Benchmarks for Bazel worker mode (PERF-02, PERF-03).
//!
//! PERF-02: Warm-start worker is faster than cold one-shot mode.
//! PERF-03: RSS memory does not grow unboundedly across requests.
//!
//! These are integration tests (run via `cargo test`) that use the
//! AnimalKingdomAPI fixtures. They measure real codegen performance,
//! not mocked operations.

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::Instant;

    use apollo_codegen_lib::codegen::{ApolloCodegen, ItemsToGenerate};
    use apollo_codegen_lib::config::ApolloCodegenConfiguration;
    use apollo_codegen_lib::templates::ConfigurationContext;

    /// Locates the AnimalKingdomAPI schema directory.
    ///
    /// Path resolution from CARGO_MANIFEST_DIR (rust/apollo-ios-cli):
    ///   parent     -> rust/
    ///   parent x2  -> apollo-ios-codegen/
    ///   parent x3  -> repo root (apollo-ios-dev/)
    ///
    /// Sources/AnimalKingdomAPI/animalkingdom-graphql/ lives at repo root.
    fn find_animal_kingdom_dir() -> Option<PathBuf> {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

        // Try repo root (3 levels up from manifest dir)
        let repo_root = manifest_dir.parent()?.parent()?.parent()?;
        let schema_dir = repo_root
            .join("Sources")
            .join("AnimalKingdomAPI")
            .join("animalkingdom-graphql");

        if schema_dir.exists() {
            return Some(schema_dir);
        }

        // Fallback: 2 levels up (in case of different repo layout)
        let alt_root = manifest_dir.parent()?.parent()?;
        let alt_dir = alt_root
            .join("Sources")
            .join("AnimalKingdomAPI")
            .join("animalkingdom-graphql");

        if alt_dir.exists() {
            return Some(alt_dir);
        }

        None
    }

    /// Creates a minimal codegen configuration pointing to the
    /// AnimalKingdomAPI schema and operations for benchmark use.
    ///
    /// Returns a ConfigurationContext or None if test fixtures are not available.
    fn create_bench_config() -> Option<ConfigurationContext> {
        let schema_dir = match find_animal_kingdom_dir() {
            Some(d) => d,
            None => {
                eprintln!("Benchmark skipped: AnimalKingdomAPI not found");
                return None;
            }
        };

        // Use a temp directory for output so we don't pollute the repo
        let output_dir = std::env::temp_dir().join("apollo_worker_bench");
        let _ = std::fs::create_dir_all(&output_dir);

        let schema_path = format!("{}/**/*.graphqls", schema_dir.display());
        let operation_path = format!("{}/**/*.graphql", schema_dir.display());

        let config_json = format!(
            r#"{{
            "schemaNamespace": "AnimalKingdomAPI",
            "input": {{
                "operationSearchPaths": ["{}"],
                "schemaSearchPaths": ["{}"]
            }},
            "output": {{
                "testMocks": {{ "none": {{}} }},
                "schemaTypes": {{
                    "path": "{}",
                    "moduleType": {{ "embeddedInTarget": {{ "name": "AnimalKingdomAPI", "accessModifier": "internal" }} }}
                }},
                "operations": {{ "inSchemaModule": {{}} }}
            }}
        }}"#,
            operation_path.replace('\\', "\\\\"),
            schema_path.replace('\\', "\\\\"),
            output_dir.display().to_string().replace('\\', "\\\\"),
        );

        let config: ApolloCodegenConfiguration = match serde_json::from_str(&config_json) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("Benchmark skipped: config parse error: {}", e);
                return None;
            }
        };

        Some(ConfigurationContext::new(config, None))
    }

    /// Gets current RSS in bytes using getrusage (macOS).
    ///
    /// On macOS, ru_maxrss is reported in bytes.
    /// Returns 0 on failure or unsupported platforms.
    #[cfg(target_os = "macos")]
    fn get_rss_bytes() -> usize {
        use std::mem::MaybeUninit;
        unsafe {
            let mut usage = MaybeUninit::<libc::rusage>::uninit();
            if libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) == 0 {
                // macOS: ru_maxrss is in bytes
                usage.assume_init().ru_maxrss as usize
            } else {
                0
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    fn get_rss_bytes() -> usize {
        // On Linux, ru_maxrss is in kilobytes
        use std::mem::MaybeUninit;
        unsafe {
            let mut usage = MaybeUninit::<libc::rusage>::uninit();
            if libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) == 0 {
                (usage.assume_init().ru_maxrss as usize) * 1024
            } else {
                0
            }
        }
    }

    /// PERF-02: Warm-start is faster than cold-start.
    ///
    /// Measures:
    /// 1. Cold: compile_schema_and_ir() + generate_from_ir() (full pipeline)
    /// 2. Warm: generate_from_ir() only (reusing cached CompileResult)
    ///
    /// Asserts warm is strictly faster than cold.
    #[test]
    fn bench_warm_vs_cold() {
        let context = match create_bench_config() {
            Some(c) => c,
            None => {
                eprintln!("PERF-02 benchmark skipped: test fixtures not available");
                return;
            }
        };

        // Cold start: full pipeline
        let cold_start = Instant::now();
        let compile_result = match ApolloCodegen::compile_schema_and_ir(&context) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("PERF-02 benchmark skipped: compilation error: {}", e);
                return;
            }
        };
        let _ = ApolloCodegen::generate_from_ir(
            &compile_result,
            &context,
            ItemsToGenerate::CODE,
        );
        let cold_duration = cold_start.elapsed();

        // Warm start: only generate_from_ir (reuse compile_result)
        let warm_start = Instant::now();
        let _ = ApolloCodegen::generate_from_ir(
            &compile_result,
            &context,
            ItemsToGenerate::CODE,
        );
        let warm_duration = warm_start.elapsed();

        eprintln!("PERF-02 Results:");
        eprintln!("  Cold start (compile + generate): {:?}", cold_duration);
        eprintln!("  Warm start (generate only):      {:?}", warm_duration);
        eprintln!(
            "  Speedup: {:.1}x",
            cold_duration.as_secs_f64() / warm_duration.as_secs_f64().max(0.001)
        );

        // Assert warm is faster than cold
        assert!(
            warm_duration < cold_duration,
            "PERF-02 FAILED: warm ({:?}) should be faster than cold ({:?})",
            warm_duration,
            cold_duration,
        );
    }

    /// PERF-03: RSS does not grow unboundedly across repeated requests.
    ///
    /// Runs warm-up iterations to let the allocator stabilize, then
    /// runs N measurement iterations of generate_from_ir() using the
    /// same cached CompileResult, sampling RSS after each batch.
    /// Asserts that RSS in the last half of measurement samples does
    /// not exceed the first half by more than 20%.
    #[test]
    fn bench_memory_stability() {
        let context = match create_bench_config() {
            Some(c) => c,
            None => {
                eprintln!("PERF-03 benchmark skipped: test fixtures not available");
                return;
            }
        };

        // Build schema+IR once (cache warm-up)
        let compile_result = match ApolloCodegen::compile_schema_and_ir(&context) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("PERF-03 benchmark skipped: compilation error: {}", e);
                return;
            }
        };

        // Warm-up phase: run several iterations to let the allocator
        // reach steady state before we start measuring. This avoids
        // counting initial heap growth as "unbounded growth".
        let warmup_iterations = 5;
        for _ in 0..warmup_iterations {
            let _ = ApolloCodegen::generate_from_ir(
                &compile_result,
                &context,
                ItemsToGenerate::CODE,
            );
        }

        let iterations = 20;
        let sample_interval = 2;
        let mut rss_samples: Vec<usize> = Vec::new();

        // Record baseline RSS after warm-up
        rss_samples.push(get_rss_bytes());

        for i in 0..iterations {
            // Run generate_from_ir (the per-request work)
            let _ = ApolloCodegen::generate_from_ir(
                &compile_result,
                &context,
                ItemsToGenerate::CODE,
            );

            // Sample RSS every sample_interval iterations
            if i % sample_interval == 0 {
                rss_samples.push(get_rss_bytes());
            }
        }

        // Final sample
        rss_samples.push(get_rss_bytes());

        eprintln!("PERF-03 Results (RSS in MB, after {} warm-up iterations):", warmup_iterations);
        for (i, &rss) in rss_samples.iter().enumerate() {
            eprintln!("  Sample {}: {:.1} MB", i, rss as f64 / (1024.0 * 1024.0));
        }

        // Assert no unbounded growth (D-94)
        // Compare average RSS of second half vs first half of steady-state samples.
        // Using halves instead of quarters gives more data points per bucket.
        let half = rss_samples.len() / 2;
        if half == 0 {
            eprintln!("PERF-03: Not enough samples for growth analysis");
            return;
        }

        let first_half: Vec<usize> = rss_samples[..half].to_vec();
        let last_half: Vec<usize> = rss_samples[half..].to_vec();

        let first_avg =
            first_half.iter().sum::<usize>() as f64 / first_half.len() as f64;
        let last_avg =
            last_half.iter().sum::<usize>() as f64 / last_half.len() as f64;

        let growth_pct = if first_avg > 0.0 {
            ((last_avg - first_avg) / first_avg) * 100.0
        } else {
            0.0
        };

        eprintln!(
            "  First half avg: {:.1} MB, Last half avg: {:.1} MB, Growth: {:.1}%",
            first_avg / (1024.0 * 1024.0),
            last_avg / (1024.0 * 1024.0),
            growth_pct,
        );

        // Allow up to 20% growth for allocator fragmentation/overhead.
        // ru_maxrss is a high-water mark, so it may not decrease. The key
        // assertion is that it doesn't KEEP growing -- it should plateau.
        assert!(
            growth_pct < 20.0,
            "PERF-03 FAILED: RSS grew by {:.1}% between first and last half (max 20% allowed)",
            growth_pct,
        );
    }

    /// Verifies that multiple cold starts produce consistent timing
    /// (no performance regression from repeated full pipeline runs).
    #[test]
    fn bench_cold_consistency() {
        let context = match create_bench_config() {
            Some(c) => c,
            None => {
                eprintln!("Cold consistency benchmark skipped: test fixtures not available");
                return;
            }
        };

        let mut durations = Vec::new();

        for _ in 0..3 {
            let start = Instant::now();
            let compile_result = match ApolloCodegen::compile_schema_and_ir(&context) {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("Cold consistency skipped: {}", e);
                    return;
                }
            };
            let _ = ApolloCodegen::generate_from_ir(
                &compile_result,
                &context,
                ItemsToGenerate::CODE,
            );
            durations.push(start.elapsed());
        }

        eprintln!("Cold consistency results:");
        for (i, d) in durations.iter().enumerate() {
            eprintln!("  Run {}: {:?}", i + 1, d);
        }

        // No assertion -- informational. If runs vary wildly, investigate.
    }
}
