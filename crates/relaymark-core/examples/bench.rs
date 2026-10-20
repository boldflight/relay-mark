//! Times one engine job, for comparison with `tools/bench.mjs` (JavaScript)
//! and `tools/bench.exs` (Elixir) on the same inputs.
//!
//!     cargo run --release --example bench -- <job> <input> <iterations>
//!
//! Jobs and their input files: `parse` (Markdown), `load` (stored source),
//! `serialize`, `markdown`, `html`, `to_snapshot`, `to_prosemirror`
//! (document JSON), `from_snapshot` (snapshot JSON), `from_prosemirror`
//! (ProseMirror JSON). `iterations` 0 only reads the input, for a memory
//! baseline. Prints one JSON line with the first and median times in ms.

use relaymark_core as rm;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [job, input, iterations] = args.as_slice() else {
        eprintln!("usage: bench <job> <input> <iterations>");
        std::process::exit(2);
    };
    let iterations: usize = iterations.parse().expect("iterations");
    let text = std::fs::read_to_string(input).expect("input");
    let json = || serde_json::from_str::<rm::Value>(&text).expect("input JSON");
    let value = if matches!(job.as_str(), "parse" | "load") { rm::Value::Null } else { json() };
    let run = || match job.as_str() {
        "parse" => drop(std::hint::black_box(rm::parse_document(&text, Some("bench")).expect("parse"))),
        "load" => drop(std::hint::black_box(rm::parse_document(&text, None).expect("load"))),
        "serialize" => drop(std::hint::black_box(rm::serialize_document(&value).expect("serialize"))),
        "markdown" => drop(std::hint::black_box(rm::project_markdown(&value).expect("markdown"))),
        "html" => drop(std::hint::black_box(rm::render_html(&value).expect("html"))),
        "to_snapshot" => drop(std::hint::black_box(rm::document_to_snapshot(&value).expect("snapshot"))),
        "from_snapshot" => drop(std::hint::black_box(rm::snapshot_to_document(&value).expect("snapshot"))),
        "to_prosemirror" => drop(std::hint::black_box(rm::document_to_prosemirror(&value).expect("prosemirror"))),
        "from_prosemirror" => drop(std::hint::black_box(rm::prosemirror_to_document(&value).expect("prosemirror"))),
        other => panic!("unknown job {other}"),
    };
    let mut times = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let start = Instant::now();
        run();
        times.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    let first = times.first().copied().unwrap_or(0.0);
    times.sort_by(f64::total_cmp);
    let median = times.get(times.len() / 2).copied().unwrap_or(0.0);
    println!("{{\"engine\":\"rust\",\"job\":\"{job}\",\"iterations\":{iterations},\"first_ms\":{first:.3},\"median_ms\":{median:.3}}}");
}
