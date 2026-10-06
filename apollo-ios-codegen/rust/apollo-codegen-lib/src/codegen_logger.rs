//! Logging infrastructure for Apollo codegen.
//!
//! Mirrors Swift's `CodegenLogger` from `Sources/ApolloCodegenLib/CodegenLogger.swift`.
//! Uses `eprintln!` (stderr) per Rust CLI convention and Bazel worker protocol (WRKR-04).

use std::sync::atomic::{AtomicU8, Ordering};

/// Log severity level matching Swift's `CodegenLogger.LogLevel` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum LogLevel {
    Error = 0,
    Warning = 1,
    Debug = 2,
}

impl LogLevel {
    /// Returns the display name for this log level.
    ///
    /// Matches Swift's `LogLevel.name` computed property.
    pub fn name(&self) -> &'static str {
        match self {
            LogLevel::Error => "ERROR",
            LogLevel::Warning => "WARNING",
            LogLevel::Debug => "DEBUG",
        }
    }
}

/// Global log level, defaulting to Warning (1).
///
/// Matches Swift's `CodegenLogger.level` default of `.debug`, but Rust CLI convention
/// defaults to warning -- verbose flag raises to debug.
static LOG_LEVEL: AtomicU8 = AtomicU8::new(1);

/// Helper to get logs printing to stderr so they can be read from the command line.
///
/// Mirrors Swift's `CodegenLogger` struct.
pub struct CodegenLogger;

impl CodegenLogger {
    /// Sets the log level based on the verbose flag.
    ///
    /// When verbose is true, sets level to Debug; otherwise Warning.
    pub fn set_level(verbose: bool) {
        let level = if verbose { LogLevel::Debug } else { LogLevel::Warning };
        LOG_LEVEL.store(level as u8, Ordering::Relaxed);
    }

    /// Sets the log level directly.
    pub fn set_log_level(level: LogLevel) {
        LOG_LEVEL.store(level as u8, Ordering::Relaxed);
    }

    /// Logs the given string if its level is at or below the current global level.
    ///
    /// Format matches Swift exactly: `[LEVEL - ApolloCodegenLib:file:line] - message`
    ///
    /// - `message`: The string to log out
    /// - `level`: The log level at which to print this specific log
    /// - `file`: The file where this function was called
    /// - `line`: The line where this function was called
    pub fn log(message: &str, level: LogLevel, file: &str, line: u32) {
        if (level as u8) <= LOG_LEVEL.load(Ordering::Relaxed) {
            let file_name = file.rsplit('/').next().unwrap_or(file);
            eprintln!(
                "[{} - ApolloCodegenLib:{}:{}] - {}",
                level.name(),
                file_name,
                line,
                message
            );
        }
    }
}

/// Convenience macro that auto-fills file and line for `CodegenLogger::log`.
#[macro_export]
macro_rules! codegen_log {
    ($message:expr, $level:expr) => {
        $crate::codegen_logger::CodegenLogger::log($message, $level, file!(), line!())
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Global lock to serialize tests that mutate shared `LOG_LEVEL` state.
    /// This prevents flaky failures when tests run in parallel.
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_log_level_default_is_warning() {
        let _guard = TEST_LOCK.lock().unwrap();
        // LOG_LEVEL initializer is Warning (1)
        LOG_LEVEL.store(LogLevel::Warning as u8, Ordering::Relaxed);
        assert_eq!(LOG_LEVEL.load(Ordering::Relaxed), LogLevel::Warning as u8);
    }

    #[test]
    fn test_set_level_verbose_true() {
        let _guard = TEST_LOCK.lock().unwrap();
        CodegenLogger::set_level(true);
        assert_eq!(LOG_LEVEL.load(Ordering::Relaxed), LogLevel::Debug as u8);
        // Reset
        LOG_LEVEL.store(LogLevel::Warning as u8, Ordering::Relaxed);
    }

    #[test]
    fn test_set_level_verbose_false() {
        let _guard = TEST_LOCK.lock().unwrap();
        CodegenLogger::set_level(false);
        assert_eq!(LOG_LEVEL.load(Ordering::Relaxed), LogLevel::Warning as u8);
        // Reset
        LOG_LEVEL.store(LogLevel::Warning as u8, Ordering::Relaxed);
    }

    #[test]
    fn test_log_level_name() {
        assert_eq!(LogLevel::Error.name(), "ERROR");
        assert_eq!(LogLevel::Warning.name(), "WARNING");
        assert_eq!(LogLevel::Debug.name(), "DEBUG");
    }

    #[test]
    fn test_log_level_ordering() {
        assert_eq!(LogLevel::Error as u8, 0);
        assert_eq!(LogLevel::Warning as u8, 1);
        assert_eq!(LogLevel::Debug as u8, 2);
    }

    #[test]
    fn test_set_log_level_direct() {
        let _guard = TEST_LOCK.lock().unwrap();
        CodegenLogger::set_log_level(LogLevel::Error);
        assert_eq!(LOG_LEVEL.load(Ordering::Relaxed), 0);
        // Reset
        LOG_LEVEL.store(LogLevel::Warning as u8, Ordering::Relaxed);
    }
}
