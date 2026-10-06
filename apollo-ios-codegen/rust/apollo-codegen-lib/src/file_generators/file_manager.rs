//! Thread-safe file manager for Apollo code generation.
//!
//! Provides filesystem operations (create, rename, delete) with tracking of written files.
//!
//! Mirrors Swift's `ApolloFileManager` from `FileManager+Apollo.swift`.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

// MARK: - FileManagerError

/// Errors that can occur during file management operations.
///
/// Mirrors Swift's `FileManagerPathError` enum.
#[derive(Debug)]
pub enum FileManagerError {
    /// The path exists but is not a file.
    NotAFile(PathBuf),
    /// The path exists but is not a directory.
    NotADirectory(PathBuf),
    /// Cannot create a file at the given path.
    CannotCreateFile(PathBuf),
    /// An I/O error occurred.
    Io(std::io::Error),
}

impl From<std::io::Error> for FileManagerError {
    fn from(e: std::io::Error) -> Self {
        FileManagerError::Io(e)
    }
}

impl std::fmt::Display for FileManagerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FileManagerError::NotAFile(path) => {
                write!(f, "{} is not a file!", path.display())
            }
            FileManagerError::NotADirectory(path) => {
                write!(f, "{} is not a directory!", path.display())
            }
            FileManagerError::CannotCreateFile(path) => {
                write!(f, "Cannot create file at {}", path.display())
            }
            FileManagerError::Io(e) => write!(f, "I/O error: {}", e),
        }
    }
}

impl std::error::Error for FileManagerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            FileManagerError::Io(e) => Some(e),
            _ => None,
        }
    }
}

// MARK: - ApolloFileManager

/// Thread-safe file manager that tracks written files.
///
/// Uses `Arc<Mutex<BTreeSet<PathBuf>>>` for thread-safe file tracking (per D-65/FNDN-05).
///
/// Mirrors Swift's `ApolloFileManager` class from `FileManager+Apollo.swift`.
pub struct ApolloFileManager {
    written_files: Arc<Mutex<BTreeSet<PathBuf>>>,
}

impl ApolloFileManager {
    /// Creates a new `ApolloFileManager` with an empty set of written files.
    pub fn new() -> Self {
        Self {
            written_files: Arc::new(Mutex::new(BTreeSet::new())),
        }
    }

    /// Creates a file at the specified path, writing the given data.
    ///
    /// Creates parent directories as needed. If `overwrite` is `false` and the file
    /// already exists, the write is skipped without error.
    ///
    /// Mirrors Swift's `ApolloFileManager.createFile(atPath:data:overwrite:)`.
    pub fn create_file(
        &self,
        path: &Path,
        data: &[u8],
        overwrite: bool,
    ) -> Result<(), std::io::Error> {
        // Create parent directories
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        // Skip if !overwrite and file exists
        if !overwrite && path.exists() {
            return Ok(());
        }
        std::fs::write(path, data)?;
        self.written_files
            .lock()
            .unwrap()
            .insert(path.to_path_buf());
        Ok(())
    }

    /// Renames a file from one path to another.
    ///
    /// If the old path does not exist, the operation is a no-op.
    ///
    /// Mirrors Swift's `ApolloFileManager.renameFile(atPath:toPath:)`.
    pub fn rename_file(&self, old_path: &Path, new_path: &Path) -> Result<(), std::io::Error> {
        if !old_path.exists() {
            return Ok(());
        }
        std::fs::rename(old_path, new_path)?;
        self.written_files
            .lock()
            .unwrap()
            .insert(new_path.to_path_buf());
        Ok(())
    }

    /// Deletes a file at the specified path.
    ///
    /// If the path does not exist or is a directory, the operation is a no-op.
    ///
    /// Mirrors Swift's `ApolloFileManager.deleteFile(atPath:)`.
    pub fn delete_file(&self, path: &Path) -> Result<(), std::io::Error> {
        if path.is_dir() {
            return Ok(());
        }
        match std::fs::remove_file(path) {
            Ok(()) => Ok(()),
            // Ignore NotFound — file may have been deleted by another process
            // (e.g. parallel Bazel workers sharing the same execroot).
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e),
        }
    }

    /// Creates the directory (including all intermediate directories) if it does not exist.
    ///
    /// Mirrors Swift's `ApolloFileManager.createDirectoryIfNeeded(atPath:)`.
    pub fn create_directory_if_needed(&self, path: &Path) -> Result<(), std::io::Error> {
        if !path.exists() {
            std::fs::create_dir_all(path)?;
        }
        Ok(())
    }

    /// Returns a snapshot of all file paths that have been written by this file manager.
    pub fn written_files(&self) -> BTreeSet<PathBuf> {
        self.written_files.lock().unwrap().clone()
    }
}

impl Default for ApolloFileManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_file_tracks_written() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.swift");

        let fm = ApolloFileManager::new();
        fm.create_file(&file_path, b"hello", true).unwrap();

        let written = fm.written_files();
        assert!(written.contains(&file_path));
        assert_eq!(written.len(), 1);

        // Verify file content
        let content = std::fs::read_to_string(&file_path).unwrap();
        assert_eq!(content, "hello");
    }

    #[test]
    fn test_create_file_overwrite_false_skips_existing() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.swift");

        // Create initial file
        std::fs::write(&file_path, "original").unwrap();

        let fm = ApolloFileManager::new();
        fm.create_file(&file_path, b"new content", false).unwrap();

        // Content should still be original
        let content = std::fs::read_to_string(&file_path).unwrap();
        assert_eq!(content, "original");

        // File should NOT be in written_files since it was skipped
        assert!(fm.written_files().is_empty());
    }

    #[test]
    fn test_create_file_overwrite_true_replaces_existing() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.swift");

        // Create initial file
        std::fs::write(&file_path, "original").unwrap();

        let fm = ApolloFileManager::new();
        fm.create_file(&file_path, b"new content", true).unwrap();

        // Content should be updated
        let content = std::fs::read_to_string(&file_path).unwrap();
        assert_eq!(content, "new content");

        assert!(fm.written_files().contains(&file_path));
    }

    #[test]
    fn test_create_file_creates_parent_directories() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("nested/deep/test.swift");

        let fm = ApolloFileManager::new();
        fm.create_file(&file_path, b"content", true).unwrap();

        assert!(file_path.exists());
        assert!(fm.written_files().contains(&file_path));
    }

    #[test]
    fn test_written_files_returns_btree_set() {
        let dir = tempfile::tempdir().unwrap();
        let path_a = dir.path().join("a.swift");
        let path_b = dir.path().join("b.swift");
        let path_c = dir.path().join("c.swift");

        let fm = ApolloFileManager::new();
        fm.create_file(&path_c, b"c", true).unwrap();
        fm.create_file(&path_a, b"a", true).unwrap();
        fm.create_file(&path_b, b"b", true).unwrap();

        let written = fm.written_files();
        assert_eq!(written.len(), 3);

        // BTreeSet should be sorted
        let paths: Vec<_> = written.into_iter().collect();
        assert_eq!(paths[0], path_a);
        assert_eq!(paths[1], path_b);
        assert_eq!(paths[2], path_c);
    }

    #[test]
    fn test_delete_file_removes_existing() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.swift");
        std::fs::write(&file_path, "content").unwrap();

        let fm = ApolloFileManager::new();
        fm.delete_file(&file_path).unwrap();

        assert!(!file_path.exists());
    }

    #[test]
    fn test_delete_file_noop_if_not_exists() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("nonexistent.swift");

        let fm = ApolloFileManager::new();
        // Should not error
        fm.delete_file(&file_path).unwrap();
    }

    #[test]
    fn test_delete_file_noop_for_directory() {
        let dir = tempfile::tempdir().unwrap();
        let subdir = dir.path().join("subdir");
        std::fs::create_dir(&subdir).unwrap();

        let fm = ApolloFileManager::new();
        // Should not delete or error for directories
        fm.delete_file(&subdir).unwrap();
        assert!(subdir.exists());
    }

    #[test]
    fn test_rename_file_tracks_new_path() {
        let dir = tempfile::tempdir().unwrap();
        let old_path = dir.path().join("old.swift");
        let new_path = dir.path().join("new.swift");
        std::fs::write(&old_path, "content").unwrap();

        let fm = ApolloFileManager::new();
        fm.rename_file(&old_path, &new_path).unwrap();

        assert!(!old_path.exists());
        assert!(new_path.exists());
        assert!(fm.written_files().contains(&new_path));
        assert!(!fm.written_files().contains(&old_path));
    }

    #[test]
    fn test_rename_file_noop_if_old_not_exists() {
        let dir = tempfile::tempdir().unwrap();
        let old_path = dir.path().join("nonexistent.swift");
        let new_path = dir.path().join("new.swift");

        let fm = ApolloFileManager::new();
        fm.rename_file(&old_path, &new_path).unwrap();

        assert!(!new_path.exists());
        assert!(fm.written_files().is_empty());
    }

    #[test]
    fn test_create_directory_if_needed() {
        let dir = tempfile::tempdir().unwrap();
        let new_dir = dir.path().join("new/nested/dir");

        let fm = ApolloFileManager::new();
        fm.create_directory_if_needed(&new_dir).unwrap();

        assert!(new_dir.exists());
        assert!(new_dir.is_dir());
    }

    #[test]
    fn test_create_directory_if_needed_already_exists() {
        let dir = tempfile::tempdir().unwrap();

        let fm = ApolloFileManager::new();
        // Should not error when directory already exists
        fm.create_directory_if_needed(dir.path()).unwrap();
        assert!(dir.path().exists());
    }

    #[test]
    fn test_default_creates_empty_manager() {
        let fm = ApolloFileManager::default();
        assert!(fm.written_files().is_empty());
    }
}
