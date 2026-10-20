//! Command-line driver for manual checks and benchmarks.
//!
//!     cargo run --release --example relaymark -- <job> [namespace] < input
//!
//! Jobs: `parse` (source to document JSON), `serialize`, `markdown`, `html`,
//! `snapshot`, `prosemirror` (each from document JSON), and `compile`
//! (composition source to `{document, manifest, diagnostics}`).

use std::io::Read;

fn main() {
    let mut args = std::env::args().skip(1);
    let job = args.next().unwrap_or_default();
    let namespace = args.next();
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).expect("stdin");
    let document = || serde_json::from_str::<relaymark_core::Value>(&input).expect("document JSON");
    let output = match job.as_str() {
        "parse" => relaymark_core::parse_document(&input, namespace.as_deref()).map(|v| relaymark_core::to_json(&v)),
        "serialize" => relaymark_core::serialize_document(&document()),
        "markdown" => relaymark_core::project_markdown(&document()),
        "html" => relaymark_core::render_html(&document()),
        "snapshot" => relaymark_core::document_to_snapshot(&document()).map(|v| relaymark_core::to_json(&v)),
        "prosemirror" => relaymark_core::document_to_prosemirror(&document()).map(|v| relaymark_core::to_json(&v)),
        "compile" => Ok(relaymark_core::to_json(&relaymark_core::compile(&input))),
        _ => {
            eprintln!("usage: relaymark <parse|serialize|markdown|html|snapshot|prosemirror|compile> [namespace] < input");
            std::process::exit(2);
        }
    };
    match output {
        Ok(text) => println!("{text}"),
        Err(error) => {
            eprintln!("refused: {error}");
            std::process::exit(1);
        }
    }
}
