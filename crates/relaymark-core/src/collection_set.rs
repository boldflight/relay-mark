//! The smart-list evaluator: which held `entity.card` records a Composer set
//! shows and in what order, so web and Apple list the same members the same
//! way. The authority is relay-elixir `test/fixtures/collection_set_v1.json`,
//! vendored as spec/relaymark/collection-set-v1.json; the web's
//! `assets/js/sync/collection_set.js` is the reference implementation.
//!
//! It evaluates only the cards it is given plus the shell type catalog. It
//! never invents members, never queries, and never authorizes: query-listed
//! collections and body-text search stay server-projected.
//!
//! Input: `{records, shell_entity_types, list, entity_id, account, params,
//! page, page_size}`, where `records` are the held `entity.card`,
//! `collection.member` and `workspace.shell` projection records. Output:
//! `{status, ids, total, page, page_count}`; `status` is `partial` (no ids, no
//! counts) only when a collection list names a collection that is not held.

use std::cmp::Ordering;
use std::sync::LazyLock;

use icu_collator::options::CollatorOptions;
use icu_collator::{Collator, CollatorBorrowed};
use regex::Regex;
use serde_json::{Map, Value, json};
use unicode_normalization::UnicodeNormalization;

use crate::error::{Result, bail};
use crate::json::{is_js_space, js_trim};

const ENTITY_CARD: &str = "entity.card";
const COLLECTION_MEMBER: &str = "collection.member";
const WORKSPACE_SHELL: &str = "workspace.shell";

/// JSON null and a missing field are both JavaScript's `??` absence.
fn field<'v>(value: &'v Value, key: &str) -> Option<&'v Value> {
    value.get(key).filter(|v| !v.is_null())
}

fn str_field<'v>(value: &'v Value, key: &str) -> Option<&'v str> {
    field(value, key).and_then(Value::as_str)
}

/// JavaScript truthiness of an optional field.
fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => false,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Number(n)) => n.as_f64().is_some_and(|n| n != 0.0),
        Some(_) => true,
    }
}

/// JavaScript string comparison orders by UTF-16 code unit.
fn cmp16(a: &str, b: &str) -> Ordering {
    a.encode_utf16().cmp(b.encode_utf16())
}

fn by_id(a: &Value, b: &Value) -> Ordering {
    cmp16(str_field(a, "entity_id").unwrap_or(""), str_field(b, "entity_id").unwrap_or(""))
}

fn trashed(card: &Value) -> bool {
    card.get("card").and_then(|c| c.get("trashed?")) == Some(&Value::Bool(true))
}

// ── Time ────────────────────────────────────────────────────────────────

/// `[seconds, microseconds]` of an ISO 8601 timestamp, so precision
/// differences do not reorder. Anything unparseable is `[0, fraction]`.
fn instant(value: Option<&Value>) -> (i64, u32) {
    static SHAPE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(.*?)(?:\.(\d{1,6}))?(Z|[+-]\d{2}:?\d{2})?$").expect("instant pattern"));
    static BODY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$").expect("timestamp pattern"));
    let text = value.and_then(Value::as_str).unwrap_or("");
    let Some(shape) = SHAPE.captures(text) else { return (0, 0) };
    let micros: u32 = shape.get(2).map_or("", |m| m.as_str()).chars().chain(std::iter::repeat('0')).take(6).collect::<String>().parse().unwrap_or(0);
    let Some(body) = BODY.captures(shape.get(1).map_or("", |m| m.as_str())) else { return (0, micros) };
    let number = |i: usize| body.get(i).map_or(0, |m| m.as_str().parse::<i64>().unwrap_or(0));
    let (year, month, day) = (number(1), number(2), number(3));
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return (0, micros);
    }
    // Days since the epoch (civil-from-days inverse).
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    let mut seconds = days * 86_400 + number(4) * 3600 + number(5) * 60 + number(6);
    if let Some(zone) = shape.get(3).map(|m| m.as_str()).filter(|z| *z != "Z") {
        let digits: String = zone[1..].chars().filter(char::is_ascii_digit).collect();
        let offset = digits[..2].parse::<i64>().unwrap_or(0) * 3600 + digits[2..].parse::<i64>().unwrap_or(0) * 60;
        seconds -= if zone.starts_with('-') { -offset } else { offset };
    }
    (seconds, micros)
}

fn cmp_instant(a: (i64, u32), b: (i64, u32)) -> Ordering {
    a.cmp(&b)
}

/// The date `EntitySet.sort/3` orders newest/oldest by: an arrival (only the
/// Inbox's candidates carry one), a deletion (Trash), else creation.
fn item_date(card: &Value, inbox: bool) -> (i64, u32) {
    let arrival = if inbox { card.get("inbox").and_then(|i| field(i, "arrival_at")) } else { None };
    instant(arrival.or_else(|| field(card, "deleted_at")).or_else(|| field(card, "inserted_at")))
}

// ── Strings ─────────────────────────────────────────────────────────────

fn name_of(card: &Value) -> &str {
    str_field(card, "name").unwrap_or("")
}

/// `EntitySet.sort/3`'s name order: downcased name, then entity id.
fn by_name(a: &Value, b: &Value) -> Ordering {
    cmp16(&name_of(a).to_lowercase(), &name_of(b).to_lowercase()).then_with(|| by_id(a, b))
}

/// `Intl.Collator('und')`: the CLDR root collation with default options (no
/// numeric ordering), shared with the web so the Inbox and Collections tie-break
/// names order the same everywhere. The CLDR version tracks icu_collator's
/// bundled data; a browser's ICU can differ slightly for rare characters.
fn collate(a: &str, b: &str) -> Ordering {
    static COLLATOR: LazyLock<CollatorBorrowed<'static>> =
        LazyLock::new(|| Collator::try_new(Default::default(), CollatorOptions::default()).expect("root collator"));
    COLLATOR.compare(a, b)
}

/// `Relay.Core.Tags.normalize_tag_input/1`: the one tag-name rule.
fn normalize_tag_name(value: &str) -> String {
    static SEPARATOR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[^\p{L}\p{M}\p{Nd}\p{Nl}]+").expect("separator pattern"));
    static EDGES: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[-\p{M}]+|-+$").expect("edge pattern"));
    let folded: String = value.nfkc().collect();
    let lowered: String = js_trim(&folded).trim_start_matches('#').chars().flat_map(char::to_lowercase).collect();
    EDGES.replace_all(&SEPARATOR.replace_all(&lowered, "-"), "").into_owned()
}

/// A param that is an array, or a comma-separated string, of values.
fn values(value: Option<&Value>) -> Vec<String> {
    let text = |v: &Value| v.as_str().map_or_else(|| v.to_string(), str::to_owned);
    match value {
        Some(Value::Array(items)) => items.iter().map(text).collect(),
        Some(Value::String(s)) => s.split(',').filter(|part| !part.is_empty()).map(str::to_owned).collect(),
        _ => Vec::new(),
    }
}

// ── The filter (`composerRecordFilter`) ─────────────────────────────────

struct Filter<'p> {
    kind: &'p str,
    account: &'p Value,
    source: Option<&'p str>,
    types: Vec<String>,
    tags: Vec<String>,
    show_completed: bool,
    text: String,
}

impl<'p> Filter<'p> {
    fn new(kind: &'p str, params: &'p Value, account: &'p Value, enabled: Option<&[String]>) -> Self {
        let types = match enabled {
            Some(enabled) => values(params.get("type_slugs")).into_iter().map(|v| js_trim(&v).to_lowercase()).filter(|v| enabled.contains(v)).collect(),
            None => Vec::new(),
        };
        Filter {
            kind,
            account,
            source: str_field(params, "content_source"),
            types,
            tags: values(params.get("tag_names")).iter().map(|t| normalize_tag_name(t)).filter(|t| !t.is_empty()).collect(),
            show_completed: matches!(str_field(params, "completed"), Some("show" | "true" | "1")),
            text: js_trim(str_field(params, "text").unwrap_or("")).to_lowercase(),
        }
    }

    fn keeps(&self, card: &Value) -> bool {
        // `EntitySetQuery.matches_content_source?/3`: others includes an unknown creator.
        let mine = card.get("created_by") == Some(self.account);
        match self.source {
            Some("mine") if !mine => return false,
            Some("others") if mine => return false,
            _ => {}
        }
        let card_trashed = card.get("card").and_then(|c| c.get("trashed?"));
        if if self.kind == "trash" { card_trashed == Some(&Value::Bool(false)) } else { trashed(card) } {
            return false;
        }
        if !self.show_completed && card.get("task").and_then(|t| str_field(t, "status")).is_some_and(|s| s == "done" || s == "cancelled") {
            return false;
        }
        if !self.types.is_empty() && !str_field(card, "entity_type").is_some_and(|t| self.types.iter().any(|v| v == t)) {
            return false;
        }
        let tags = card.get("card").and_then(|c| field(c, "tags")).or_else(|| card.get("row").and_then(|r| field(r, "tags")));
        let names: Vec<String> = tags
            .and_then(Value::as_array)
            .map(|tags| tags.iter().map(|tag| normalize_tag_name(tag.get("name").and_then(Value::as_str).or_else(|| tag.as_str()).unwrap_or(""))).collect())
            .unwrap_or_default();
        if !self.tags.iter().all(|tag| names.contains(tag)) {
            return false;
        }
        if !self.text.is_empty() {
            let name = str_field(card, "name").or_else(|| card.get("row").and_then(|r| str_field(r, "name"))).unwrap_or("");
            if !name.to_lowercase().contains(&self.text) {
                return false;
            }
        }
        true
    }
}

// ── Sorting (`sortSet`) ─────────────────────────────────────────────────

fn sort_set(items: &mut Vec<&Value>, sort: &str, dir: &str, inbox: bool) {
    match sort {
        "name" => {
            items.sort_by(|a, b| by_name(a, b));
            if dir == "desc" {
                items.reverse();
            }
        }
        "newest" | "oldest" => {
            items.sort_by(|a, b| cmp_instant(item_date(a, inbox), item_date(b, inbox)).then_with(|| by_id(a, b)));
            if sort == "newest" {
                items.reverse();
            }
        }
        _ if dir == "asc" => items.reverse(),
        _ => {}
    }
}

// ── Source orders (`CARD_LISTS`) ────────────────────────────────────────

fn newest_first(a: Option<&Value>, b: Option<&Value>) -> Ordering {
    cmp_instant(instant(b), instant(a))
}

/// JavaScript `<` over the values a rank key or pin id holds.
fn cmp_value(a: Option<&Value>, b: Option<&Value>) -> Ordering {
    match (a, b) {
        (Some(Value::Number(x)), Some(Value::Number(y))) => x.as_f64().partial_cmp(&y.as_f64()).unwrap_or(Ordering::Equal),
        (Some(Value::String(x)), Some(Value::String(y))) => cmp16(x, y),
        _ => Ordering::Equal,
    }
}

fn compare_keys(a: &[Value], b: &[Value]) -> Ordering {
    for index in 0..a.len().max(b.len()) {
        match (a.get(index), b.get(index)) {
            (Some(x), Some(y)) if x == y => {}
            (None, _) => return Ordering::Less,
            (_, None) => return Ordering::Greater,
            (x, y) => return cmp_value(x, y),
        }
    }
    Ordering::Equal
}

fn rank_key(card: &Value) -> &[Value] {
    card.get("inbox").and_then(|i| field(i, "key")).and_then(Value::as_array).map_or(&[], Vec::as_slice)
}

/// The members of a list and their source order.
fn card_list<'c>(list: &str, cards: &'c Map<String, Value>) -> Result<Vec<&'c Value>> {
    let held = |card: &&Value| truthy(card.get("row")) && !trashed(card);
    let mut rows: Vec<&Value> = match list {
        "inbox" => cards.values().filter(|c| held(c) && c.get("workspace_member") == Some(&Value::Bool(true)) && truthy(c.get("inbox"))).collect(),
        "pinned" => cards.values().filter(|c| held(c) && truthy(c.get("pin"))).collect(),
        "recent" => cards.values().filter(|c| held(c) && truthy(c.get("recent_opened_at"))).collect(),
        "shared" => cards.values().filter(|c| held(c) && c.get("shared") == Some(&Value::Bool(true))).collect(),
        "trash" => cards.values().filter(|c| truthy(c.get("row")) && trashed(c)).collect(),
        other => bail!("Unknown collection set list {other}"),
    };
    match list {
        // The ranker's projected order: by `key`, then name, then id.
        "inbox" => rows.sort_by(|a, b| compare_keys(rank_key(a), rank_key(b)).then_with(|| collate(name_of(a), name_of(b))).then_with(|| by_id(a, b))),
        // `Pins.pinned_entities_query`: newest pin first, then pin id descending.
        "pinned" => rows.sort_by(|a, b| {
            let (pa, pb) = (a.get("pin"), b.get("pin"));
            newest_first(pa.and_then(|p| field(p, "at")), pb.and_then(|p| field(p, "at")))
                .then_with(|| cmp_value(pb.and_then(|p| p.get("id")), pa.and_then(|p| p.get("id"))))
                .then_with(|| by_id(a, b))
        }),
        // `PaperActivities.authorized_recent_query/2`: newest open first, then id descending.
        "recent" => rows.sort_by(|a, b| newest_first(field(a, "recent_opened_at"), field(b, "recent_opened_at")).then_with(|| by_id(b, a))),
        // The server's `shared` source: entity id order.
        "shared" => rows.sort_by(|a, b| by_id(a, b)),
        // The server's `trash` source: newest deletion first, then id.
        _ => rows.sort_by(|a, b| newest_first(field(a, "deleted_at"), field(b, "deleted_at")).then_with(|| by_id(a, b))),
    }
    Ok(rows)
}

struct Member<'c> {
    membership: &'c Value,
    card: &'c Value,
}

fn position(member: &Member) -> Option<i64> {
    member.membership.get("position").and_then(Value::as_f64).filter(|p| p.fract() == 0.0).map(|p| p as i64)
}

/// A collection's source order, which the server leaves to the database, is
/// locally the order members were added.
fn by_added(a: &Member, b: &Member) -> Ordering {
    let added = |m: &Member| instant(m.membership.get("added_at"));
    cmp_instant(added(a), added(b)).then_with(|| by_name(a.card, b.card))
}

/// A course lists its lessons and an album its assets by position there. The
/// server lists a course's other members before its lessons, and an album's
/// after its assets; members without a position keep the added order.
fn source_order(kind: &str, a: &Member, b: &Member) -> Ordering {
    match (position(a), position(b)) {
        (Some(x), Some(y)) => x.cmp(&y).then_with(|| by_added(a, b)),
        (Some(_), None) => {
            if kind == "course" {
                Ordering::Greater
            } else {
                Ordering::Less
            }
        }
        (None, Some(_)) => {
            if kind == "course" {
                Ordering::Less
            } else {
                Ordering::Greater
            }
        }
        (None, None) => by_added(a, b),
    }
}

// ── Evaluation ──────────────────────────────────────────────────────────

pub fn evaluate(input: &Value) -> Result<Value> {
    let Some(records) = input.get("records").and_then(Value::as_array) else { bail!("Missing collection set records") };
    let mut cards = Map::new();
    let mut memberships: Vec<(&str, &Value)> = Vec::new();
    let mut enabled: Vec<String> = Vec::new();
    let mut types: Vec<&Value> = Vec::new();
    for record in records {
        let (Some(projection), Some(key), Some(payload)) = (str_field(record, "projection"), str_field(record, "key"), record.get("payload")) else {
            bail!("Invalid collection set record");
        };
        match projection {
            ENTITY_CARD => {
                cards.insert(key.to_owned(), payload.clone());
            }
            COLLECTION_MEMBER => memberships.push((key, payload)),
            WORKSPACE_SHELL if str_field(payload, "kind") == Some("entity_type") => {
                enabled.extend(str_field(payload, "slug").map(str::to_owned));
                types.push(payload);
            }
            _ => {}
        }
    }
    let list = str_field(input, "list").unwrap_or("");
    let params = input.get("params").filter(|p| p.is_object()).cloned().unwrap_or_else(|| json!({}));
    let account = input.get("account").cloned().unwrap_or(Value::Null);
    // Leased rows already passed authoritative type membership. A missing
    // or partial shell catalog cannot establish an alternative local filter.
    let catalog = (str_field(input, "shell_entity_types") == Some("complete")).then_some(enabled.as_slice());
    let filter = Filter::new(if list == "collection" { "collection" } else { list }, &params, &account, catalog);
    let sort = str_field(&params, "sort").unwrap_or("suggested");
    let dir = str_field(&params, "dir").unwrap_or("desc");

    let kept: Vec<&Value> = if list == "collection" {
        let Some(collection_id) = str_field(input, "entity_id") else { bail!("Missing collection id") };
        let collection = cards.get(collection_id);
        // Only a workspace member's collection that lists memberships, not a query's results.
        if !collection.is_some_and(|c| c.get("workspace_member") == Some(&Value::Bool(true)) && c.get("collection_listed_by_query") != Some(&Value::Bool(true)))
        {
            return Ok(
                json!({"status": "partial", "ids": [], "total": null, "page": input.get("page").and_then(Value::as_i64).unwrap_or(1), "page_count": null}),
            );
        }
        let kind = collection.and_then(|c| str_field(c, "collection_kind")).unwrap_or("");
        // A membership shows only while its card is present, as the server serves it.
        let mut members: Vec<Member> = memberships
            .iter()
            .filter(|(_, m)| str_field(m, "collection_id") == Some(collection_id))
            .filter_map(|(_, membership)| Some(Member { membership, card: str_field(membership, "entity_id").and_then(|id| cards.get(id))? }))
            .filter(|m| truthy(m.card.get("row")) && filter.keeps(m.card))
            .collect();
        members.sort_by(|a, b| source_order(kind, a, b));
        let mut ordered: Vec<&Value> = members.iter().map(|m| m.card).collect();
        sort_set(&mut ordered, sort, dir, false);
        ordered
    } else {
        let mut ordered: Vec<&Value> = card_list(list, &cards)?.into_iter().filter(|c| filter.keeps(c)).collect();
        sort_set(&mut ordered, sort, dir, list == "inbox");
        ordered
    };

    // A page size below 1 (or not a number) clamps to 1.
    let page_size = input.get("page_size").and_then(Value::as_f64).map_or(24.0, f64::floor).max(1.0) as usize;
    let page_count = kept.len().div_ceil(page_size).max(1);
    let page = (input.get("page").and_then(Value::as_i64).unwrap_or(1).max(1) as usize).min(page_count);
    let shown: Vec<&Value> = kept.iter().skip((page - 1) * page_size).take(page_size).copied().collect();
    let ids: Vec<&str> = shown.iter().filter_map(|c| str_field(c, "entity_id")).collect();
    let mut answer = json!({"status": "complete", "ids": ids, "total": kept.len(), "page": page, "page_count": page_count});
    match str_field(input, "grouping") {
        None => {}
        Some(grouping @ ("type" | "status")) => answer["groups"] = group_metadata(grouping, &shown, &types),
        Some(other) => bail!("Unknown grouping {other}"),
    }
    Ok(answer)
}

// ── Groups v1 (`localGroupMetadata`) ────────────────────────────────────
//
// Type groups are labelled by the workspace's type name; status groups follow
// `STATUS_ORDER` and include every status target of the page's types, so a
// board column may be empty. Descriptors are `[key, label]` in rank order
// (priority, then the label's UTF-8 bytes, then the key's), and each entity
// maps to its group key. Labels are English: the web humanizes slugs and
// statuses the same way, and a localized label would come from the shell type
// name, which the host supplies.

/// Which entity types accept each status target, in the order targets are added.
const STATUS_ACCEPTS: [(&str, &[&str]); 11] = [
    ("backlog", &["task"]),
    ("todo", &["task"]),
    ("in_progress", &["task"]),
    ("done", &["task"]),
    ("active", &["project"]),
    ("paused", &["project"]),
    ("completed", &["project"]),
    ("archived", &["project"]),
    ("confirmed", &["event"]),
    ("tentative", &["event"]),
    ("cancelled", &["task", "event"]),
];

/// Status label to rank priority; any other label ranks 1000.
const STATUS_ORDER: [(&str, u32); 32] = [
    ("No Status", 0),
    ("Open", 5),
    ("Active", 10),
    ("Backlog", 15),
    ("Todo", 20),
    ("To Do", 20),
    ("Planned", 25),
    ("Scheduled", 25),
    ("Tentative", 25),
    ("Confirmed", 25),
    ("In Progress", 30),
    ("Processing", 30),
    ("Matching", 30),
    ("Paused", 40),
    ("Waiting", 40),
    ("Blocked", 45),
    ("Needs Review", 50),
    ("Review", 50),
    ("In Review", 50),
    ("Done", 60),
    ("Completed", 60),
    ("Resolved", 60),
    ("Approved", 60),
    ("Sent", 60),
    ("Delivered", 60),
    ("Cancelled", 70),
    ("Canceled", 70),
    ("Rejected", 70),
    ("Declined", 70),
    ("Dismissed", 70),
    ("Failed", 70),
    ("Archived", 80),
];

/// `humanize`: underscores to spaces, each whitespace-separated word capitalized.
/// An empty word (leading or trailing whitespace) reads "undefined", as in the web.
fn humanize(value: &str) -> String {
    let text = value.replace('_', " ");
    let mut words: Vec<&str> = vec![];
    let mut word_start = 0;
    let mut chars = text.char_indices().peekable();
    while let Some((index, c)) = chars.next() {
        if is_js_space(c) {
            words.push(&text[word_start..index]);
            word_start = index + c.len_utf8();
            while let Some(&(next, d)) = chars.peek().filter(|(_, d)| is_js_space(*d)) {
                word_start = next + d.len_utf8();
                chars.next();
            }
        }
    }
    words.push(&text[word_start..]);
    words
        .iter()
        .map(|word| match word.chars().next() {
            None => "undefined".to_owned(),
            Some(first) => first.to_uppercase().chain(word[first.len_utf8()..].to_lowercase().chars()).collect(),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

struct Group {
    key: String,
    label: String,
    rank: Vec<u32>,
}

fn rank(priority: u32, label: &str, key: &str) -> Vec<u32> {
    std::iter::once(priority).chain(label.bytes().map(u32::from)).chain(std::iter::once(0)).chain(key.bytes().map(u32::from)).collect()
}

fn status_of(card: &Value) -> &str {
    ["task", "project", "event"].iter().find_map(|kind| card.get(kind).and_then(|v| str_field(v, "status")).filter(|s| !s.is_empty())).unwrap_or("")
}

fn group_metadata(grouping: &str, cards: &[&Value], types: &[&Value]) -> Value {
    let type_group = |slug: &str| {
        let shell = types.iter().find(|t| str_field(t, "slug") == Some(slug));
        let label = shell.and_then(|t| str_field(t, "name")).map_or_else(|| humanize(&slug.replace('-', " ")), str::to_owned);
        let key = format!("type:{}", shell.and_then(|t| str_field(t, "entity_type_id")).unwrap_or(slug));
        Group { rank: rank(0, &label, &key), key, label }
    };
    let status_group = |value: &str| {
        let label = if value.is_empty() { "No Status".to_owned() } else { humanize(value) };
        let priority = STATUS_ORDER.iter().find(|(name, _)| *name == label).map_or(1000, |(_, priority)| *priority);
        let key = format!("status:{value}");
        Group { rank: rank(priority, &label, &key), key, label }
    };
    let slugs: Vec<&str> = cards.iter().map(|c| str_field(c, "entity_type").unwrap_or("")).collect();
    let describe = |card: &Value| if grouping == "type" { type_group(str_field(card, "entity_type").unwrap_or("")) } else { status_group(status_of(card)) };
    // A later record's descriptor replaces an earlier one with the same key.
    fn add(groups: &mut Vec<Group>, group: Group) {
        match groups.iter_mut().find(|g| g.key == group.key) {
            Some(held) => *held = group,
            None => groups.push(group),
        }
    }
    let mut groups: Vec<Group> = Vec::new();
    for card in cards {
        add(&mut groups, describe(card));
    }
    if grouping == "status" {
        for (value, accepts) in STATUS_ACCEPTS {
            if accepts.iter().any(|accepted| slugs.contains(accepted)) && !groups.iter().any(|g| g.key == format!("status:{value}")) {
                add(&mut groups, status_group(value));
            }
        }
    }
    groups.sort_by(|a, b| a.rank.cmp(&b.rank));
    let keys: Map<String, Value> = cards.iter().filter_map(|c| Some((str_field(c, "entity_id")?.to_owned(), Value::String(describe(c).key)))).collect();
    json!({"grouping": grouping, "descriptors": groups.iter().map(|g| json!([g.key, g.label])).collect::<Vec<_>>(), "entity_group_keys": keys})
}

#[cfg(test)]
mod tests {
    use super::collate;
    use std::cmp::Ordering::{Greater, Less};

    /// Orders of the CLDR root collation (UTS #35 "Root Collation", built on UTS #10's
    /// default weights, non-ignorable punctuation, no numeric ordering), which the web
    /// gets from `Intl.Collator('und')`. Keep: a plain code-point compare puts "A" before "a"
    /// and "é" after "f", and the Inbox tie-break would list differently from the web.
    #[test]
    fn names_order_as_the_root_collation_does() {
        // Accents are a secondary difference: "e" < "é", yet both sort before "f" (UTS #10 section 1.2).
        assert_eq!(collate("e", "é"), Less);
        assert_eq!(collate("é", "f"), Less);
        // Case is a tertiary difference and the root orders lowercase first.
        assert_eq!(collate("a", "A"), Less);
        assert_eq!(collate("A", "b"), Less);
        // No numeric ordering: "item 10" sorts before "item 2" character by character.
        assert_eq!(collate("item 10", "item 2"), Less);
        // Space is not ignored, so it sorts before any letter.
        assert_eq!(collate("a b", "ab"), Less);
        assert_eq!(collate("b", "a"), Greater);
    }
}
