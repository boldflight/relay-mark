//! The megazord: the one Rust library the RelayMark Swift package links on
//! Apple platforms, as in Mozilla application-services' `megazords/ios-rust`.
//!
//! Every Rust staticlib carries its own copy of the Rust standard library, so
//! an app that links two of them gets two runtimes and duplicate symbols such
//! as `rust_eh_personality`. Each uniffi binding stays its own library crate
//! and is re-exported here, and only this crate is built as a staticlib. It
//! has no logic of its own. A new Rust library joins as its own crate with a
//! dependency and a line below; see docs/engineering/apple-rust-library.md.

pub use relaymark_ffi;
pub use yniffi;
