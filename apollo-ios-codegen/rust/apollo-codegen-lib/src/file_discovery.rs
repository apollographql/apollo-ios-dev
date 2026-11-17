//! GraphQL file discovery via glob-based search path matching.
//!
//! Discovers `.graphql` and `.graphqls` files by walking directories and matching
//! against glob patterns, while excluding build artifact directories.
//!
//! Mirrors Swift's `ApolloCodegen.match(searchPaths:relativeTo:)` method from
//! `Sources/ApolloCodegenLib/ApolloCodegen.swift`.

use std::path::{Path, PathBuf};

use globset::GlobBuilder;
use indexmap::IndexSet;
use walkdir::WalkDir;

/// Directories excluded from file discovery.
///
/// Matches Swift's `ApolloCodegen.match()` excludedDirectories exactly:
/// `.build` (Swift PM), `.swiftpm`, `.Pods` (CocoaPods).
const EXCLUDED_DIRECTORIES: &[&str] = &[".build", ".swiftpm", ".Pods"];

/// Matches files against glob search paths, excluding certain directories.
/// Returns an ordered set of absolute file paths.
///
/// Mirrors Swift's `ApolloCodegen.match(searchPaths:relativeTo:)`.
///
/// # Arguments
/// * `search_paths` - Glob patterns to match against (e.g. `["**/*.graphql"]`)
/// * `relative_to` - Optional root directory for resolving relative patterns
///
/// # Returns
/// An `IndexSet<String>` of matched file paths (preserving insertion order).
pub fn match_search_paths(
    search_paths: &[String],
    relative_to: Option<&Path>,
) -> Result<IndexSet<String>, std::io::Error> {
    let mut results = IndexSet::new();

    for pattern in search_paths {
        // Resolve pattern relative to root URL
        let full_pattern = if let Some(root) = relative_to {
            if Path::new(pattern).is_absolute() {
                pattern.clone()
            } else {
                root.join(pattern).to_string_lossy().to_string()
            }
        } else {
            pattern.clone()
        };

        // A literal path (no glob characters) is checked directly, like glob(3) does: it
        // matches when the path names a file, following symlinks (Bazel sandboxes and
        // `ctx.actions.symlink` present inputs as file symlinks). No directory walk.
        if !has_glob_characters(&full_pattern) {
            let literal = Path::new(&full_pattern);
            if literal.is_file() {
                results.insert(make_absolute(literal));
            }
            continue;
        }

        // Extract the base directory from the pattern (everything before first wildcard)
        let base_dir = extract_base_dir(&full_pattern);

        // Build the glob matcher
        let glob = GlobBuilder::new(&full_pattern)
            .literal_separator(false)
            .build()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?
            .compile_matcher();

        // Walk the base directory
        let base = Path::new(&base_dir);
        if !base.exists() {
            continue;
        }
        // Walking `.` yields `./x` entries, which a bare relative pattern such as
        // `schema.graphqls` or `*.graphql` (no `./` prefix) would never match, although
        // Swift's glob(3) matches it against the plain relative path.
        let strip_dot_slash = base_dir == ".";

        // Swift's `Glob` expands `**` into the root directory followed by every
        // subdirectory (FileManager enumerator order) and runs glob(3) with
        // GLOB_NOSORT on each, so matches come grouped per directory, in raw
        // directory (readdir) order. WalkDir yields entries in readdir order with
        // depth-first descent, so group its matches by parent directory, keeping
        // directories in order of first appearance (root first).
        let mut dir_order: Vec<std::path::PathBuf> = Vec::new();
        let mut by_dir: indexmap::IndexMap<std::path::PathBuf, Vec<String>> =
            indexmap::IndexMap::new();
        // Links are followed so that symlinked files and directories (how Bazel sandboxes
        // and `ctx.actions.symlink` present inputs) are discovered like regular ones.
        for entry in WalkDir::new(base)
            .follow_links(true)
            .into_iter()
            .filter_entry(|e| !is_excluded_directory(e))
            .filter_map(|e| e.ok())
        {
            let path = entry.path();
            if entry.file_type().is_dir() {
                if !by_dir.contains_key(path) {
                    dir_order.push(path.to_path_buf());
                    by_dir.insert(path.to_path_buf(), Vec::new());
                }
                continue;
            }
            if path.is_file() {
                let path_str = path.to_string_lossy();
                if glob.is_match(candidate_path(&path_str, strip_dot_slash)) {
                    let parent = path.parent().map(|p| p.to_path_buf()).unwrap_or_default();
                    if !by_dir.contains_key(&parent) {
                        dir_order.push(parent.clone());
                        by_dir.insert(parent.clone(), Vec::new());
                    }
                    // Use canonical absolute path for consistent matching
                    by_dir.get_mut(&parent).unwrap().push(make_absolute(path));
                }
            }
        }
        for dir in dir_order {
            if let Some(files) = by_dir.swap_remove(&dir) {
                for m in files {
                    results.insert(m);
                }
            }
        }
    }

    Ok(results)
}

/// Checks if a walkdir entry is an excluded directory.
fn is_excluded_directory(entry: &walkdir::DirEntry) -> bool {
    if !entry.file_type().is_dir() {
        return false;
    }
    if let Some(name) = entry.file_name().to_str() {
        EXCLUDED_DIRECTORIES.contains(&name)
    } else {
        false
    }
}

/// Makes a path absolute without resolving symlinks.
///
/// Uses the current working directory for relative paths, matching Swift's
/// behavior of not resolving symlinks (which would cause `/tmp` -> `/private/tmp`
/// mismatches on macOS).
/// The string a walked entry is matched against: entries under a `.` base come back as
/// `./x` and must still match a bare relative pattern.
fn candidate_path(path: &str, strip_dot_slash: bool) -> &str {
    if strip_dot_slash {
        path.strip_prefix("./").unwrap_or(path)
    } else {
        path
    }
}

fn make_absolute(path: &Path) -> String {
    if path.is_absolute() {
        path.to_string_lossy().to_string()
    } else {
        let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        cwd.join(path).to_string_lossy().to_string()
    }
}

/// Whether the pattern contains glob metacharacters (`*`, `?` or `[`).
fn has_glob_characters(pattern: &str) -> bool {
    pattern.contains(['*', '?', '['])
}

/// Extracts the base directory from a glob pattern.
///
/// Returns everything before the first wildcard character (`*`, `?`, or `[`).
/// If no wildcard is found, returns the pattern's parent directory.
fn extract_base_dir(pattern: &str) -> String {
    // Find first glob special character
    let first_special = pattern.find(['*', '?', '[']);
    let prefix = match first_special {
        Some(pos) => &pattern[..pos],
        None => pattern,
    };
    // Get the parent directory of the prefix
    match prefix.rfind('/') {
        Some(pos) => prefix[..=pos].to_string(),
        None => ".".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_base_dir_simple_glob() {
        assert_eq!(extract_base_dir("**/*.graphql"), ".");
    }

    #[test]
    fn test_extract_base_dir_with_prefix() {
        assert_eq!(extract_base_dir("src/**/*.graphql"), "src/");
    }

    #[test]
    fn test_extract_base_dir_absolute_prefix() {
        assert_eq!(
            extract_base_dir("/root/project/**/*.graphql"),
            "/root/project/"
        );
    }

    #[test]
    fn test_extract_base_dir_no_glob() {
        assert_eq!(extract_base_dir("src/schema.graphql"), "src/");
    }

    #[test]
    fn test_extract_base_dir_question_mark() {
        assert_eq!(extract_base_dir("src/?.graphql"), "src/");
    }

    #[test]
    fn test_extract_base_dir_bracket() {
        assert_eq!(extract_base_dir("src/[ab].graphql"), "src/");
    }

    #[test]
    fn test_excluded_directory_detection_build() {
        // Test the EXCLUDED_DIRECTORIES list
        assert!(EXCLUDED_DIRECTORIES.contains(&".build"));
        assert!(EXCLUDED_DIRECTORIES.contains(&".swiftpm"));
        assert!(EXCLUDED_DIRECTORIES.contains(&".Pods"));
        assert!(!EXCLUDED_DIRECTORIES.contains(&"src"));
        assert!(!EXCLUDED_DIRECTORIES.contains(&"node_modules"));
    }

    #[test]
    fn test_candidate_path_strips_dot_slash_only_for_dot_base() {
        assert_eq!(candidate_path("./schema.graphqls", true), "schema.graphqls");
        assert_eq!(candidate_path("./a/b.graphql", true), "a/b.graphql");
        assert_eq!(candidate_path("schema.graphqls", true), "schema.graphqls");
        assert_eq!(
            candidate_path("./schema.graphqls", false),
            "./schema.graphqls"
        );
        assert_eq!(candidate_path("sub/x.graphql", false), "sub/x.graphql");
    }

    /// Bare relative patterns (`schema.graphqls`, `*.graphql`) resolve against the current
    /// directory, like Swift's glob(3) does. The test changes the process cwd, so it is
    /// serialized with a lock in case other cwd-changing tests are added.
    #[test]
    fn test_match_search_paths_bare_relative_pattern_matches_in_cwd() {
        use std::sync::Mutex;
        use tempfile::tempdir;
        static CWD_LOCK: Mutex<()> = Mutex::new(());
        let _guard = CWD_LOCK.lock().unwrap_or_else(|e| e.into_inner());

        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join("schema.graphqls"), "type Query { a: Int }").unwrap();
        std::fs::create_dir_all(dir.path().join("sub")).unwrap();
        std::fs::write(dir.path().join("sub/Q.graphql"), "query Q { a }").unwrap();
        std::fs::write(dir.path().join("R.graphql"), "query R { a }").unwrap();

        let previous = std::env::current_dir().unwrap();
        std::env::set_current_dir(dir.path()).unwrap();
        let schema = match_search_paths(&["schema.graphqls".to_string()], None);
        let ops = match_search_paths(&["*.graphql".to_string(), "**/*.graphql".to_string()], None);
        std::env::set_current_dir(previous).unwrap();

        let schema = schema.unwrap();
        assert_eq!(schema.len(), 1, "{:?}", schema);
        assert!(schema.iter().next().unwrap().ends_with("/schema.graphqls"));
        let ops = ops.unwrap();
        assert_eq!(ops.len(), 2, "{:?}", ops);
        assert!(ops.iter().any(|p| p.ends_with("/R.graphql")));
        assert!(ops.iter().any(|p| p.ends_with("/sub/Q.graphql")));
    }

    #[test]
    fn test_match_search_paths_empty_returns_empty() {
        let result = match_search_paths(&[], None).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn test_match_search_paths_nonexistent_dir_returns_empty() {
        let result =
            match_search_paths(&["/nonexistent/path/**/*.graphql".to_string()], None).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn test_match_search_paths_discovers_files() {
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let schema_file = dir.path().join("schema.graphql");
        let op_file = dir.path().join("operations").join("query.graphql");
        std::fs::create_dir_all(op_file.parent().unwrap()).unwrap();
        std::fs::write(&schema_file, "type Query { id: ID }").unwrap();
        std::fs::write(&op_file, "query Test { id }").unwrap();

        let pattern = format!("{}/**/*.graphql", dir.path().display());
        let result = match_search_paths(&[pattern], None).unwrap();
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_match_search_paths_excludes_build_dir() {
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let normal_file = dir.path().join("schema.graphql");
        let build_file = dir.path().join(".build").join("generated.graphql");
        let swiftpm_file = dir.path().join(".swiftpm").join("generated.graphql");
        let pods_file = dir.path().join(".Pods").join("generated.graphql");

        std::fs::write(&normal_file, "type Query { id: ID }").unwrap();
        std::fs::create_dir_all(build_file.parent().unwrap()).unwrap();
        std::fs::write(&build_file, "excluded").unwrap();
        std::fs::create_dir_all(swiftpm_file.parent().unwrap()).unwrap();
        std::fs::write(&swiftpm_file, "excluded").unwrap();
        std::fs::create_dir_all(pods_file.parent().unwrap()).unwrap();
        std::fs::write(&pods_file, "excluded").unwrap();

        let pattern = format!("{}/**/*.graphql", dir.path().display());
        let result = match_search_paths(&[pattern], None).unwrap();
        assert_eq!(
            result.len(),
            1,
            "Should find only schema.graphql, not files in excluded dirs"
        );
    }

    #[test]
    fn test_match_search_paths_relative_to_root() {
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let schema_file = dir.path().join("src").join("schema.graphql");
        std::fs::create_dir_all(schema_file.parent().unwrap()).unwrap();
        std::fs::write(&schema_file, "type Query { id: ID }").unwrap();

        let result =
            match_search_paths(&["src/**/*.graphql".to_string()], Some(dir.path())).unwrap();
        assert_eq!(result.len(), 1);
    }
    /// Bazel sandboxes and `ctx.actions.symlink` present inputs as symlinks: a literal
    /// search path that is a file symlink, a symlinked file inside a walked directory and a
    /// symlinked directory must all be discovered.
    #[cfg(unix)]
    #[test]
    fn test_match_search_paths_follows_symlinks() {
        use std::os::unix::fs::symlink;
        use tempfile::tempdir;

        let real = tempdir().unwrap();
        std::fs::write(real.path().join("schema.graphqls"), "type Query { a: Int }").unwrap();
        std::fs::create_dir_all(real.path().join("ops")).unwrap();
        std::fs::write(real.path().join("ops/Q.graphql"), "query Q { a }").unwrap();

        let staged = tempdir().unwrap();
        // literal path -> file symlink
        symlink(
            real.path().join("schema.graphqls"),
            staged.path().join("schema.graphqls"),
        )
        .unwrap();
        // file symlink inside a walked directory
        std::fs::create_dir_all(staged.path().join("linked-files")).unwrap();
        symlink(
            real.path().join("ops/Q.graphql"),
            staged.path().join("linked-files/Q.graphql"),
        )
        .unwrap();
        // directory symlink
        symlink(real.path().join("ops"), staged.path().join("linked-dir")).unwrap();

        let schema = match_search_paths(
            &[staged
                .path()
                .join("schema.graphqls")
                .to_string_lossy()
                .to_string()],
            None,
        )
        .unwrap();
        assert_eq!(schema.len(), 1, "{:?}", schema);
        assert!(schema.iter().next().unwrap().ends_with("/schema.graphqls"));

        let ops = match_search_paths(&[format!("{}/**/*.graphql", staged.path().display())], None)
            .unwrap();
        assert_eq!(ops.len(), 2, "{:?}", ops);
        assert!(
            ops.iter().any(|p| p.ends_with("/linked-files/Q.graphql")),
            "{:?}",
            ops
        );
        assert!(
            ops.iter().any(|p| p.ends_with("/linked-dir/Q.graphql")),
            "{:?}",
            ops
        );
    }

    #[test]
    fn test_literal_search_path_is_checked_directly() {
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join("schema.graphqls"), "type Query { a: Int }").unwrap();
        std::fs::create_dir_all(dir.path().join("sub")).unwrap();
        std::fs::write(
            dir.path().join("sub/other.graphqls"),
            "type Query { b: Int }",
        )
        .unwrap();

        // Exact file: found without walking the directory (the sibling is not matched).
        let found = match_search_paths(
            &[dir
                .path()
                .join("schema.graphqls")
                .to_string_lossy()
                .to_string()],
            None,
        )
        .unwrap();
        assert_eq!(found.len(), 1, "{:?}", found);
        assert!(found.iter().next().unwrap().ends_with("/schema.graphqls"));

        // Missing file: no match, no error.
        let missing = match_search_paths(
            &[dir
                .path()
                .join("missing.graphqls")
                .to_string_lossy()
                .to_string()],
            None,
        )
        .unwrap();
        assert!(missing.is_empty());

        // A directory is not a file match.
        let directory = match_search_paths(
            &[dir.path().join("sub").to_string_lossy().to_string()],
            None,
        )
        .unwrap();
        assert!(directory.is_empty());

        // Relative literal resolved against `relative_to`.
        let relative =
            match_search_paths(&["schema.graphqls".to_string()], Some(dir.path())).unwrap();
        assert_eq!(relative.len(), 1, "{:?}", relative);
    }
}
