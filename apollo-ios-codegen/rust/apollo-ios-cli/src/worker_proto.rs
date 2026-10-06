//! Generated protobuf types for the Bazel worker protocol.
//!
//! Types are generated at build time by prost-build from
//! `rust/proto/worker_protocol.proto` (D-85, D-86).

pub mod blaze_worker {
    include!(concat!(env!("OUT_DIR"), "/blaze.worker.rs"));
}

pub use blaze_worker::{Input, WorkRequest, WorkResponse};
