//! The parts of ProseMirror the editing commands run on, ported from the
//! maintained JavaScript packages the web editor uses: prosemirror-model,
//! -transform, -state, -commands, -schema-list and -tables. Each behaves as
//! its package does, so web and native produce identical documents.

pub mod model;
pub mod schema;
pub mod step;
pub mod transform;
