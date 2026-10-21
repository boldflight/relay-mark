//! Peak heap of each conversion on one large input, counted by a global
//! allocator (`peak +N MB` above what was live before the call).
//!
//!     cargo run --release --example memory -- md < paper.md
//!     cargo run --release --example memory -- html < paper.html
//!     cargo run --release --example memory -- snap < document.json
use std::alloc::{GlobalAlloc, Layout, System};
use std::io::Read;
use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};
struct Counting;
static NOW: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        let n = NOW.fetch_add(l.size(), Relaxed) + l.size();
        PEAK.fetch_max(n, Relaxed);
        unsafe { System.alloc(l) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        NOW.fetch_sub(l.size(), Relaxed);
        unsafe { System.dealloc(p, l) }
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        if n > l.size() {
            let c = NOW.fetch_add(n - l.size(), Relaxed) + n - l.size();
            PEAK.fetch_max(c, Relaxed);
        } else {
            NOW.fetch_sub(l.size() - n, Relaxed);
        }
        unsafe { System.realloc(p, l, n) }
    }
}
#[global_allocator]
static A: Counting = Counting;
fn mark(label: &str, base: usize) {
    eprintln!("{label}: peak +{} MB (live {} MB)", (PEAK.load(Relaxed) - base) / 1_000_000, NOW.load(Relaxed) / 1_000_000);
}
fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();
    let job = std::env::args().nth(1).unwrap();
    let reset = || {
        PEAK.store(NOW.load(Relaxed), Relaxed);
        NOW.load(Relaxed)
    };
    if job == "md" {
        let b = reset();
        let doc = relaymark_core::parse_document(&input, Some("ns")).unwrap();
        mark("parse_document", b);
        let b = reset();
        let json = relaymark_core::to_json(&doc);
        mark("to_json(doc)", b);
        eprintln!("doc json {} MB", json.len() / 1_000_000);
        let b = reset();
        let snap = relaymark_core::document_to_snapshot(&doc).unwrap();
        mark("document_to_snapshot", b);
        let b = reset();
        let _ = relaymark_core::snapshot_to_document(&snap).unwrap();
        mark("snapshot_to_document", b);
        let b = reset();
        let _ = relaymark_core::document_to_prosemirror(&doc).unwrap();
        mark("document_to_prosemirror", b);
        let b = reset();
        let _: relaymark_core::Value = serde_json::from_str(&json).unwrap();
        mark("serde parse doc json", b);
        return;
    }
    if job == "html" {
        let b = reset();
        let out = relaymark_core::import::html(Some(&input), "ns").unwrap();
        mark("import::html", b);
        let b = reset();
        let s = relaymark_core::to_json(&out);
        mark("to_json", b);
        eprintln!("{}", s.len());
    } else {
        let doc: relaymark_core::Value = serde_json::from_str(&input).unwrap();
        let b = reset();
        let snap = relaymark_core::document_to_snapshot(&doc).unwrap();
        mark("document_to_snapshot", b);
        let b = reset();
        let out = relaymark_core::import::snapshot(&snap, "ns").unwrap();
        mark("import::snapshot", b);
        let b = reset();
        let d = relaymark_core::snapshot_to_document(&snap).unwrap();
        mark("snapshot_to_document", b);
        let b = reset();
        let p = relaymark_core::document_to_prosemirror(&doc).unwrap();
        mark("document_to_prosemirror", b);
        let b = reset();
        let _ = relaymark_core::prosemirror_to_document(&p).unwrap();
        mark("prosemirror_to_document", b);
        let b = reset();
        let _ = relaymark_core::serialize_document(&doc).unwrap();
        mark("serialize", b);
        let b = reset();
        let _ = relaymark_core::parse_document(&relaymark_core::serialize_document(&doc).unwrap(), Some("ns")).unwrap();
        mark("serialize+parse", b);
        drop((out, d));
    }
}
