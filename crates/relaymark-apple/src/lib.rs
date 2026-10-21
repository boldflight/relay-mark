//! The one Rust library the RelayMark Swift package links on Apple platforms.
//!
//! Every Rust staticlib carries its own copy of the Rust standard library, so
//! an app that links two of them gets two runtimes and duplicate symbols such
//! as `rust_eh_personality`. Each uniffi binding the Swift package needs is a
//! plain library crate re-exported here instead, and this crate alone is built
//! as a staticlib. A new Rust binding joins by adding a dependency and a line
//! below; see docs/engineering/apple-rust-library.md.

pub use relaymark_ffi;
pub use yniffi;
