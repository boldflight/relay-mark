//! The RelayMark conformance fixtures in `spec/relaymark/`, run against this
//! crate: the conformance suite (as `relaymark conformance` runs it) and every
//! collaboration fixture whose contract is a document conversion.
//!
//! Each collaboration fixture file is classified below, so a new fixture
//! fails this test until someone decides what the engine must do with it.

use relaymark_core as rm;
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

fn spec() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/relaymark")
}

fn read(path: &Path) -> Value {
    serde_json::from_str(&std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))).expect("fixture JSON")
}

fn fixture(name: &str) -> Value {
    read(&spec().join("collaboration/fixtures").join(name))
}

/// `stableStringify`: keys in code point order, so equality ignores key order
/// exactly as the reference runtime's `equalCanonicalJSON` does.
fn canonical(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let sorted: BTreeMap<&String, &Value> = map.iter().collect();
            let entries: Vec<String> = sorted.into_iter().map(|(k, v)| format!("{}:{}", Value::String(k.clone()), canonical(v))).collect();
            format!("{{{}}}", entries.join(","))
        }
        Value::Array(items) => format!("[{}]", items.iter().map(canonical).collect::<Vec<_>>().join(",")),
        other => rm::to_json(other),
    }
}

#[track_caller]
fn same(actual: &Value, expected: &Value, what: &str) {
    assert_eq!(canonical(actual), canonical(expected), "{what}");
}

#[track_caller]
fn valid(document: &Value, what: &str) {
    assert_eq!(rm::validate(document, &json!({})), Vec::<Value>::new(), "{what}: diagnostics");
    assert_eq!(rm::validate_schema(document, "relaymark-document.schema.json"), Vec::<Value>::new(), "{what}: JSON Schema");
}

#[test]
fn conformance_suite() {
    let suite_path = spec().join("conformance/suite.json");
    let suite = read(&suite_path);
    let dir = suite_path.parent().expect("suite directory").to_path_buf();
    let file = |key: &str, f: &Value| f.get(key).and_then(Value::as_str).map(|p| dir.join(p));
    let mut failures = Vec::new();
    let fixtures = suite["fixtures"].as_array().expect("fixtures");
    for f in fixtures {
        let id = f["id"].as_str().unwrap_or_default();
        let context = f.get("validation_context").cloned().unwrap_or(json!({}));
        let actual = if let Some(path) = file("input_composition", f) {
            let layers = read(&path);
            let composition = rm::compose_layers(&layers["layers"]);
            json!({"composition": composition, "diagnostics": composition["diagnostics"], "layerComposition": layers})
        } else if let Some(manifest) = file("input_manifest", f) {
            let document = std::fs::read(file("input_ast", f).expect("input_ast")).expect("input AST bytes");
            let manifest = std::fs::read(manifest).expect("input manifest bytes");
            rm::validate_transported_agent_answer_pair(&document, &manifest, &context).unwrap_or_else(|e| panic!("{id}: {e}"))
        } else if let Some(path) = file("input_ast", f) {
            let document = read(&path);
            let diagnostics = rm::validate(&document, &context);
            let manifest = rm::project_manifest(&document, &diagnostics);
            json!({"document": document, "diagnostics": diagnostics, "manifest": manifest})
        } else {
            rm::compile(&std::fs::read_to_string(file("source", f).expect("source")).expect("source text"))
        };
        let mut errors = Vec::new();
        for (key, field) in
            [("expected_composition", "composition"), ("expected_ast", "document"), ("expected_manifest", "manifest"), ("expected_diagnostics", "diagnostics")]
        {
            if let Some(path) = file(key, f)
                && canonical(&actual[field]) != canonical(&read(&path))
            {
                errors.push(format!("{field} differs from {key}"));
            }
        }
        for schema in f["schemas"].as_array().into_iter().flatten().filter_map(Value::as_str) {
            let name = Path::new(schema).file_name().and_then(|n| n.to_str()).unwrap_or_default();
            let target = match read(&dir.join(schema))["properties"]["type"]["const"].as_str() {
                Some("relaymark.document") => "document",
                Some("relaymark.manifest") => "manifest",
                Some("relaymark.layer_composition") => "layerComposition",
                other => panic!("{id}: unexpected schema target {other:?}"),
            };
            let issues = rm::validate_schema(&actual[target], name);
            if !issues.is_empty() {
                errors.push(format!("{target} fails {name}: {issues:?}"));
            }
        }
        if !errors.is_empty() {
            failures.push(format!("{id}: {}", errors.join("; ")));
        }
    }
    assert!(failures.is_empty(), "{} of {} suite fixtures failed:\n{}", failures.len(), fixtures.len(), failures.join("\n"));
    assert_eq!(fixtures.len(), 17, "suite size changed; update the report");
}

/// Collaboration fixtures that are not document conversions: Yjs protocol
/// behavior (convergence, relative positions, retained branches, undo) and
/// the editor's content-edit command planning. The Yjs update bytes inside
/// the conversion fixtures are likewise Yjs's contract, not this engine's.
const NOT_ENGINE: &[(&str, &str)] = &[
    ("convergence-v1.json", "Yjs binary convergence"),
    ("inline-v1.json", "Yjs inline convergence"),
    ("relative-ranges-v1.json", "Yjs relative positions"),
    ("retained-marked-text-branches.json", "Yjs retained branches"),
    ("content-edit-identical-human-replacement.json", "editor content-edit planning"),
];

/// PM fixtures whose contract is `normalized` <-> `expected_ast`.
const PROSEMIRROR: &[&str] = &[
    "agent-suggestion-v3-draft.json",
    "entity-reference-v3-draft.json",
    "inline-marks-v3-draft.json",
    "inline-offered-marks-v3-draft.json",
    "markdown-blocks-v3-draft.json",
    "paper-controls-v3-draft.json",
    "task-list-v3-draft.json",
    "task-list-flat-v3-draft.json",
    "canonical-form.json",
];

#[test]
fn collaboration_fixtures() {
    let dir = spec().join("collaboration/fixtures");
    let mut names: Vec<String> = std::fs::read_dir(&dir).expect("fixtures").filter_map(|e| e.ok()?.file_name().into_string().ok()).collect();
    names.sort();
    let mut checked = Vec::new();
    for name in &names {
        if NOT_ENGINE.iter().any(|(n, _)| n == name) {
            continue;
        }
        check_collaboration_fixture(name);
        checked.push(name.clone());
    }
    eprintln!("checked {} of {} collaboration fixtures; not engine contracts: {:?}", checked.len(), names.len(), NOT_ENGINE);
}

fn round_trip(pm: &Value, ast: &Value, name: &str) {
    same(&rm::prosemirror_to_document(pm).unwrap_or_else(|e| panic!("{name}: {e}")), ast, &format!("{name}: ProseMirror to document"));
    same(&rm::document_to_prosemirror(ast).unwrap_or_else(|e| panic!("{name}: {e}")), pm, &format!("{name}: document to ProseMirror"));
    let snapshot = rm::document_to_snapshot(ast).unwrap_or_else(|e| panic!("{name}: {e}"));
    same(&rm::snapshot_to_document(&snapshot).unwrap_or_else(|e| panic!("{name}: {e}")), ast, &format!("{name}: snapshot round trip"));
}

fn check_collaboration_fixture(name: &str) {
    let f = fixture(name);
    let ok = |r: rm::Result<Value>| r.unwrap_or_else(|e| panic!("{name}: {e}"));
    let text = |r: rm::Result<String>| r.unwrap_or_else(|e| panic!("{name}: {e}"));
    if PROSEMIRROR.contains(&name) {
        round_trip(&f["normalized"], &f["expected_ast"], name);
        valid(&f["expected_ast"], name);
        if let Some(authored) = f["authored_source"].as_str() {
            let serialized = text(rm::serialize_source(&f["expected_ast"]));
            assert!(serialized == authored || serialized == format!("Before\n\n{authored}\n\nAfter\n"), "{name}: authored source");
            let compiled = rm::compile(authored);
            same(&compiled["diagnostics"], &json!([]), &format!("{name}: compile diagnostics"));
            let reserialized = text(rm::serialize_source(&compiled["document"]));
            assert!(reserialized == authored || reserialized == format!("{authored}\n"), "{name}: compiled source");
        }
        return;
    }
    match name {
        "ai-authored-mark.json" => {
            round_trip(&f["prosemirror"], &f["ast"], name);
            assert_eq!(text(rm::render_html(&f["ast"])), f["html"].as_str().unwrap_or_default(), "{name}: HTML");
            assert_eq!(text(rm::project_markdown(&f["ast"])), f["markdown"].as_str().unwrap_or_default(), "{name}: Markdown");
        }
        "inline-atoms-v3-draft.json" => {
            let ast = ok(rm::prosemirror_to_document(&f["normalized"]));
            same(&ast, &f["expected_ast"], name);
            valid(&ast, name);
            // Hydration attributes are accepted on input and never written back.
            let back = ok(rm::document_to_prosemirror(&ast));
            same(&ok(rm::prosemirror_to_document(&back)), &ast, name);
            assert_eq!(text(rm::serialize_source(&ast)), f["relaymark_source"].as_str().unwrap_or_default(), "{name}: source");
            let compiled = rm::compile(f["relaymark_source"].as_str().unwrap_or_default());
            let contents = |d: &Value| Value::Array(d["blocks"].as_array().into_iter().flatten().map(|b| b["content"].clone()).collect());
            same(&contents(&compiled["document"]), &contents(&ast), name);
        }
        "rich-callout-v3-draft.json" | "rich-image-v3-draft.json" => {
            let ast = ok(rm::prosemirror_to_document(&f["normalized"]));
            valid(&ast, name);
            same(&ok(rm::document_to_prosemirror(&ast)), &f["normalized"], name);
            same(&ok(rm::snapshot_to_document(&ok(rm::document_to_snapshot(&ast)))), &ast, name);
        }
        "rich-video-v3-draft.json" => {
            // The normalized shape carries hydration fields refused today; the
            // raw shape is the durable one.
            assert!(rm::prosemirror_to_document(&f["normalized"]).is_err(), "{name}: hydrated video refused");
            round_trip(&f["raw"], &f["expected_ast"], name);
            valid(&f["expected_ast"], name);
            assert!(rm::snapshot_to_document(&f["xml"]).is_err(), "{name}: historical XML needs import");
            same(&ok(rm::import::snapshot(&f["xml"], "retained-video"))["document"], &f["expected_ast"], name);
        }
        "table-concurrent-v3-draft.json" => {
            assert!(rm::prosemirror_to_document(&f["raw"]).is_err(), "{name}: raw table lacks schema defaults");
            let ast = ok(rm::prosemirror_to_document(&f["normalized"]));
            valid(&ast, name);
            same(&ok(rm::document_to_prosemirror(&ast)), &f["inverse"], name);
        }
        "table-mixed-v3-draft.json" => {
            let ast = ok(rm::prosemirror_to_document(&f["normalized"]));
            valid(&ast, name);
            same(&ok(rm::prosemirror_to_document(&ok(rm::document_to_prosemirror(&ast)))), &ast, name);
        }
        "canonical-source.json" | "canonical-historical-source.json" | "canonical-inline-media.json" => {
            let ast = ok(rm::parse_document(f["source"].as_str().unwrap_or_default(), f["namespace"].as_str()));
            same(&ast, &f["expected_ast"], name);
            same(&ok(rm::parse_document(&text(rm::serialize_document(&ast)), None)), &ast, name);
            same(&ok(rm::snapshot_to_document(&ok(rm::document_to_snapshot(&ast)))), &ast, name);
        }
        "canonical-source-compatibility.json" => {
            let imported = ok(rm::import::source(f["source"].as_str().unwrap_or_default(), f["namespace"].as_str().unwrap_or_default()));
            same(&imported["document"], &f["expected_ast"], name);
        }
        "canonical-empty-callout-source.json" => {
            let namespace = f["namespace"].as_str().unwrap_or_default();
            for case in f["cases"].as_array().into_iter().flatten() {
                let imported = ok(rm::import::source(case["source"].as_str().unwrap_or_default(), namespace));
                same(&imported["document"], &case["expected_ast"], name);
                same(&ok(rm::parse_document(&text(rm::serialize_document(&imported["document"])), None)), &imported["document"], name);
            }
        }
        "canonical-directives.json" => {
            let pm = ok(rm::document_to_prosemirror(&f));
            same(&ok(rm::prosemirror_to_document(&pm)), &f, name);
            same(&ok(rm::parse_document(&text(rm::serialize_document(&f)), None)), &f, name);
            same(&ok(rm::snapshot_to_document(&ok(rm::document_to_snapshot(&f)))), &f, name);
            assert!(text(rm::render_html(&f)).contains("<strong>Résumé 世界</strong>"), "{name}: HTML");
            assert!(text(rm::project_markdown(&f)).contains("| Subject | Value |"), "{name}: Markdown");
        }
        "canonical-table-widths.json" => {
            let ast = &f["document"];
            same(&ok(rm::snapshot_to_document(&ok(rm::document_to_snapshot(ast)))), ast, name);
            let html = text(rm::render_html(ast));
            for colgroup in f["expected_colgroups"].as_array().into_iter().flatten().filter_map(Value::as_str) {
                assert!(html.contains(colgroup), "{name}: colgroup {colgroup}");
            }
        }
        "canonical-heading-destinations.json" => {
            let mut ast = ok(rm::parse_document(f["source"].as_str().unwrap_or_default(), Some("static-null-heading")));
            let index = f["explicit_heading_index"].as_u64().unwrap_or_default() as usize;
            ast["blocks"][index]["props"]["headingId"] = f["explicit_heading_id"].clone();
            let html = text(rm::render_html(&ast));
            let ids: Vec<Value> = html
                .match_indices("<h")
                .filter_map(|(at, _)| html[at..].split_once('>').map(|(open, _)| open.to_owned()))
                .filter_map(|open| open.split_once(" id=\"").and_then(|(_, rest)| rest.split_once('"')).map(|(id, _)| json!(id)))
                .collect();
            same(&Value::Array(ids), &f["heading_destinations"], name);
            assert!(html.contains("&quot;headingId&quot;:null"), "{name}: authored null retained");
        }
        "canonical-editor-schema.json" => {
            // The production editor's independently exported schema names the
            // same identified nodes as the canonical schema compiled in.
            let identified = |schema: &Value| {
                let mut names: Vec<String> = schema["nodes"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|n| n["attrs"].get("relaymarkId").is_some())
                    .filter_map(|n| n["name"].as_str().map(str::to_owned))
                    .collect();
                names.sort();
                names
            };
            assert_eq!(identified(&f), identified(rm::editor_schema()), "{name}");
        }
        "block-identity-v3-draft.json" => {
            let pattern = regex::Regex::new(r"^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$").expect("pattern");
            for id in f["expected_preorder_ids"].as_array().into_iter().flatten().filter_map(Value::as_str) {
                assert!(pattern.is_match(id), "{name}: {id}");
            }
        }
        "historical-form-publication.json" | "form-publication-import-expected.json" => {
            let publication = fixture("historical-form-publication.json");
            let imported = ok(rm::import::form_publication(&publication, "publication-proof", None));
            same(&imported, &fixture("form-publication-import-expected.json"), name);
        }
        "form-publication-retained-source.json" => {
            let publication = fixture("historical-form-publication.json");
            let imported = ok(rm::import::form_publication(&publication, "publication-proof", f["source"].as_str()));
            same(&imported, &f["expected"], name);
        }
        "rich-table-ast.pending.json" => {
            assert_eq!(f["enabled"], json!(false), "{name}: pending fixture enabled; give it a contract here");
        }
        other => panic!("unclassified collaboration fixture {other}: add its engine contract to tests/conformance.rs"),
    }
}
