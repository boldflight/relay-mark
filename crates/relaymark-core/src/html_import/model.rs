// Ported from prosemirror-model 1.25.12.
// ProseMirror is Copyright (C) 2015-2017 by Marijn Haverbeke and others, used under the MIT License; see THIRD_PARTY_NOTICES.md.
//! The parts of the maintained ProseMirror model (prosemirror-model 1.25)
//! that DOM parsing uses, over the canonical editor schema: node and mark
//! types, content expressions compiled to the same automaton (edge order
//! included, since it decides filler and wrapper nodes), nodes, fragments and
//! slices.

use std::collections::HashMap;
use std::sync::OnceLock;

use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::Map;
use crate::schema::EDITOR_SCHEMA_JSON;

pub type TypeId = usize;
pub type MarkId = usize;
/// A content match state (`ContentMatch`).
pub type MatchId = usize;

/// `ContentMatch.empty`: the match of every leaf type.
pub const EMPTY_MATCH: MatchId = 0;

pub struct NodeType {
    pub name: String,
    pub groups: Vec<String>,
    attrs: Vec<(String, Option<Value>)>,
    pub is_inline: bool,
    pub is_text: bool,
    /// `whitespace == "pre"` (a `code` node).
    pub pre: bool,
    pub isolating: bool,
    pub linebreak_replacement: bool,
    /// `None` admits every mark.
    mark_set: Option<Vec<MarkId>>,
    pub content: MatchId,
}

pub struct MarkType {
    pub name: String,
    attrs: Vec<(String, Option<Value>)>,
    excluded: Vec<MarkId>,
}

struct MatchState {
    valid_end: bool,
    next: Vec<(TypeId, MatchId)>,
}

pub struct Schema {
    pub nodes: Vec<NodeType>,
    pub marks: Vec<MarkType>,
    matches: Vec<MatchState>,
    node_index: HashMap<String, TypeId>,
    mark_index: HashMap<String, MarkId>,
    pub top: TypeId,
    pub text: TypeId,
}

pub fn schema() -> &'static Schema {
    static SCHEMA: OnceLock<Schema> = OnceLock::new();
    SCHEMA.get_or_init(|| Schema::load(EDITOR_SCHEMA_JSON))
}

fn attr_specs(value: Option<&Value>) -> Vec<(String, Option<Value>)> {
    value.and_then(Value::as_object).map(|attrs| attrs.iter().map(|(name, spec)| (name.clone(), spec.get("default").cloned())).collect()).unwrap_or_default()
}

impl Schema {
    fn load(text: &str) -> Self {
        let source: Value = serde_json::from_str(text).expect("packaged editor schema is JSON");
        let node_values = source["nodes"].as_array().expect("schema nodes");
        let mark_values = source["marks"].as_array().expect("schema marks");
        let mark_index: HashMap<String, MarkId> =
            mark_values.iter().enumerate().map(|(i, mark)| (mark["name"].as_str().expect("mark name").to_owned(), i)).collect();
        let marks = mark_values
            .iter()
            .map(|mark| MarkType {
                name: mark["name"].as_str().unwrap_or_default().to_owned(),
                attrs: attr_specs(mark.get("attrs")),
                excluded: mark["excludes"].as_array().into_iter().flatten().filter_map(|name| mark_index.get(name.as_str()?).copied()).collect(),
            })
            .collect();
        let mut nodes: Vec<NodeType> = node_values
            .iter()
            .map(|node| {
                let name = node["name"].as_str().unwrap_or_default().to_owned();
                NodeType {
                    is_text: name == "text",
                    is_inline: node["inline"].as_bool().unwrap_or(false) || name == "text",
                    pre: node["code"].as_bool().unwrap_or(false),
                    isolating: node["isolating"].as_bool().unwrap_or(false),
                    linebreak_replacement: node["linebreakReplacement"].as_bool().unwrap_or(false),
                    groups: node["group"].as_str().unwrap_or("").split_whitespace().map(str::to_owned).collect(),
                    attrs: attr_specs(node.get("attrs")),
                    mark_set: node["markSet"].as_array().map(|names| names.iter().filter_map(|n| mark_index.get(n.as_str()?).copied()).collect()),
                    content: EMPTY_MATCH,
                    name,
                }
            })
            .collect();
        let node_index: HashMap<String, TypeId> = nodes.iter().enumerate().map(|(i, node)| (node.name.clone(), i)).collect();
        let mut matches = vec![MatchState { valid_end: true, next: Vec::new() }];
        for (index, node) in node_values.iter().enumerate() {
            if let Some(expression) = node["content"].as_str().filter(|e| !e.is_empty()) {
                nodes[index].content = compile(expression, &nodes, &node_index, &mut matches);
            }
        }
        let top = node_index[source["top"].as_str().unwrap_or("doc")];
        let text = node_index["text"];
        Self { nodes, marks, matches, node_index, mark_index, top, text }
    }

    pub fn node_type(&self, name: &str) -> Option<TypeId> {
        self.node_index.get(name).copied()
    }

    pub fn mark_type(&self, name: &str) -> Option<MarkId> {
        self.mark_index.get(name).copied()
    }

    pub fn is_leaf(&self, ty: TypeId) -> bool {
        self.nodes[ty].content == EMPTY_MATCH
    }

    pub fn is_block(&self, ty: TypeId) -> bool {
        !self.nodes[ty].is_inline
    }

    pub fn inline_content(&self, ty: TypeId) -> bool {
        self.match_inline_content(self.nodes[ty].content)
    }

    pub fn is_textblock(&self, ty: TypeId) -> bool {
        self.is_block(ty) && self.inline_content(ty)
    }

    pub fn has_required_attrs(&self, ty: TypeId) -> bool {
        self.nodes[ty].attrs.iter().any(|(_, default)| default.is_none())
    }

    pub fn allows_mark(&self, ty: TypeId, mark: MarkId) -> bool {
        self.nodes[ty].mark_set.as_ref().is_none_or(|set| set.contains(&mark))
    }

    /// `NodeType.computeAttrs`: every declared attribute in declaration order.
    pub fn node_attrs(&self, ty: TypeId, given: Option<&Map>) -> Result<Map> {
        compute_attrs(&self.nodes[ty].attrs, given, &self.nodes[ty].name)
    }

    pub fn mark(&self, ty: MarkId, given: Option<&Map>) -> Result<Mark> {
        Ok(Mark { ty, attrs: compute_attrs(&self.marks[ty].attrs, given, &self.marks[ty].name)? })
    }

    // ContentMatch

    pub fn valid_end(&self, state: MatchId) -> bool {
        self.matches[state].valid_end
    }

    pub fn edges(&self, state: MatchId) -> &[(TypeId, MatchId)] {
        &self.matches[state].next
    }

    pub fn match_type(&self, state: MatchId, ty: TypeId) -> Option<MatchId> {
        self.edges(state).iter().find(|(edge, _)| *edge == ty).map(|(_, next)| *next)
    }

    pub fn match_fragment(&self, state: MatchId, nodes: &[Node]) -> Option<MatchId> {
        nodes.iter().try_fold(state, |current, node| self.match_type(current, node.ty))
    }

    fn match_inline_content(&self, state: MatchId) -> bool {
        self.edges(state).first().is_some_and(|(ty, _)| self.nodes[*ty].is_inline)
    }

    fn generatable(&self, ty: TypeId) -> bool {
        !(self.nodes[ty].is_text || self.has_required_attrs(ty))
    }

    /// `ContentMatch.fillBefore`.
    pub fn fill_before(&self, state: MatchId, after: &[Node], to_end: bool, start: usize) -> Option<Vec<Node>> {
        let mut seen = vec![state];
        self.fill_search(state, &mut Vec::new(), after, to_end, start, &mut seen)
    }

    fn fill_search(&self, state: MatchId, types: &mut Vec<TypeId>, after: &[Node], to_end: bool, start: usize, seen: &mut Vec<MatchId>) -> Option<Vec<Node>> {
        let finished = self.match_fragment(state, after.get(start..).unwrap_or_default());
        if let Some(finished) = finished
            && (!to_end || self.valid_end(finished))
        {
            return Some(types.iter().map(|&ty| self.create_and_fill(ty).expect("filler node")).collect());
        }
        for &(ty, next) in self.edges(state) {
            if self.generatable(ty) && !seen.contains(&next) {
                seen.push(next);
                types.push(ty);
                if let Some(found) = self.fill_search(next, types, after, to_end, start, seen) {
                    return Some(found);
                }
                types.pop();
            }
        }
        None
    }

    /// `ContentMatch.findWrapping`.
    pub fn find_wrapping(&self, state: MatchId, target: TypeId) -> Option<Vec<TypeId>> {
        struct Active {
            state: MatchId,
            ty: Option<TypeId>,
            via: Option<usize>,
        }
        let mut seen: Vec<TypeId> = Vec::new();
        let mut active = vec![Active { state, ty: None, via: None }];
        let mut cursor = 0;
        while cursor < active.len() {
            let current = cursor;
            cursor += 1;
            let state = active[current].state;
            if self.match_type(state, target).is_some() {
                let mut result = Vec::new();
                let mut at = Some(current);
                while let Some(index) = at {
                    let Some(ty) = active[index].ty else { break };
                    result.push(ty);
                    at = active[index].via;
                }
                result.reverse();
                return Some(result);
            }
            for &(ty, next) in self.edges(state) {
                if !self.is_leaf(ty) && !self.has_required_attrs(ty) && !seen.contains(&ty) && (active[current].ty.is_none() || self.valid_end(next)) {
                    active.push(Active { state: self.nodes[ty].content, ty: Some(ty), via: Some(current) });
                    seen.push(ty);
                }
            }
        }
        None
    }

    /// `NodeType.create` (content unchecked).
    pub fn create(&self, ty: TypeId, attrs: Option<&Map>, content: Vec<Node>, marks: Vec<Mark>) -> Result<Node> {
        Ok(Node { ty, attrs: self.node_attrs(ty, attrs)?, content, marks, text: None })
    }

    /// `NodeType.createAndFill()` with default attributes and no content.
    pub fn create_and_fill(&self, ty: TypeId) -> Option<Node> {
        let content = self.fill_before(self.nodes[ty].content, &[], true, 0)?;
        self.create(ty, None, content, Vec::new()).ok()
    }

    pub fn text_node(&self, text: &str, marks: Vec<Mark>) -> Node {
        Node { ty: self.text, attrs: Map::new(), content: Vec::new(), marks, text: Some(text.to_owned()) }
    }

    /// `Mark.addToSet`.
    pub fn add_mark(&self, mark: &Mark, set: &[Mark]) -> Vec<Mark> {
        let excludes = |a: &Mark, b: &Mark| self.marks[a.ty].excluded.contains(&b.ty);
        let mut copy: Option<Vec<Mark>> = None;
        let mut placed = false;
        for (index, other) in set.iter().enumerate() {
            if mark == other {
                return set.to_vec();
            }
            if excludes(mark, other) {
                copy.get_or_insert_with(|| set[..index].to_vec());
            } else if excludes(other, mark) {
                return set.to_vec();
            } else {
                if !placed && other.ty > mark.ty {
                    copy.get_or_insert_with(|| set[..index].to_vec()).push(mark.clone());
                    placed = true;
                }
                if let Some(copy) = copy.as_mut() {
                    copy.push(other.clone());
                }
            }
        }
        let mut copy = copy.unwrap_or_else(|| set.to_vec());
        if !placed {
            copy.push(mark.clone());
        }
        copy
    }

    /// `markMayApply`: whether the mark occurs anywhere a node of `ty` may.
    pub fn mark_may_apply(&self, mark: MarkId, ty: TypeId) -> bool {
        (0..self.nodes.len()).any(|parent| {
            if !self.allows_mark(parent, mark) {
                return false;
            }
            let mut seen = Vec::new();
            self.reaches(self.nodes[parent].content, ty, &mut seen)
        })
    }

    fn reaches(&self, state: MatchId, ty: TypeId, seen: &mut Vec<MatchId>) -> bool {
        seen.push(state);
        for &(edge, next) in self.edges(state) {
            if edge == ty {
                return true;
            }
            if !seen.contains(&next) && self.reaches(next, ty, seen) {
                return true;
            }
        }
        false
    }

    /// `Node.check`: content expressions, allowed marks and mark sets.
    pub fn check(&self, node: &Node) -> Result<()> {
        let name = &self.nodes[node.ty].name;
        let valid = self.match_fragment(self.nodes[node.ty].content, &node.content).is_some_and(|end| self.valid_end(end));
        if !valid || node.content.iter().any(|child| child.marks.iter().any(|mark| !self.allows_mark(node.ty, mark.ty))) {
            bail!("Invalid content for node {name}");
        }
        let mut set: Vec<Mark> = Vec::new();
        for mark in &node.marks {
            set = self.add_mark(mark, &set);
        }
        if set != node.marks {
            bail!("Invalid collection of marks for node {name}");
        }
        node.content.iter().try_for_each(|child| self.check(child))
    }

    /// `Node.toJSON`.
    pub fn to_json(&self, node: &Node) -> Value {
        let mut object = Map::with_capacity(4);
        object.insert("type".into(), Value::String(self.nodes[node.ty].name.clone()));
        if !node.attrs.is_empty() {
            object.insert("attrs".into(), Value::Object(node.attrs.clone()));
        }
        if !node.content.is_empty() {
            object.insert("content".into(), self.fragment_json(&node.content));
        }
        if !node.marks.is_empty() {
            let marks = node
                .marks
                .iter()
                .map(|mark| {
                    let mut json = Map::with_capacity(2);
                    json.insert("type".into(), Value::String(self.marks[mark.ty].name.clone()));
                    if !mark.attrs.is_empty() {
                        json.insert("attrs".into(), Value::Object(mark.attrs.clone()));
                    }
                    Value::Object(json)
                })
                .collect();
            object.insert("marks".into(), Value::Array(marks));
        }
        if let Some(text) = &node.text {
            object.insert("text".into(), Value::String(text.clone()));
        }
        Value::Object(object)
    }

    pub fn fragment_json(&self, nodes: &[Node]) -> Value {
        Value::Array(nodes.iter().map(|node| self.to_json(node)).collect())
    }
}

fn compute_attrs(specs: &[(String, Option<Value>)], given: Option<&Map>, name: &str) -> Result<Map> {
    let mut out = Map::with_capacity(specs.len());
    for (key, default) in specs {
        match given.and_then(|g| g.get(key)).or(default.as_ref()) {
            Some(value) => {
                out.insert(key.clone(), value.clone());
            }
            None => bail!("No value supplied for attribute {key} on {name}"),
        }
    }
    Ok(out)
}

#[derive(Debug, Clone, PartialEq)]
pub struct Mark {
    pub ty: MarkId,
    pub attrs: Map,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    pub ty: TypeId,
    pub attrs: Map,
    pub content: Vec<Node>,
    pub marks: Vec<Mark>,
    pub text: Option<String>,
}

impl Node {
    pub fn is_text(&self) -> bool {
        self.text.is_some()
    }

    /// Whether this text node joins `other` (same marks).
    fn same_text_markup(&self, other: &Node) -> bool {
        self.is_text() && other.is_text() && self.marks == other.marks
    }
}

/// `Fragment.fromArray`: adjacent text nodes with the same marks join.
pub fn fragment(nodes: Vec<Node>) -> Vec<Node> {
    let mut out: Vec<Node> = Vec::with_capacity(nodes.len());
    for node in nodes {
        push_joined(&mut out, node);
    }
    out
}

/// `Fragment.append`.
pub fn append(mut fragment: Vec<Node>, other: Vec<Node>) -> Vec<Node> {
    let mut other = other.into_iter();
    if let Some(first) = other.next() {
        push_joined(&mut fragment, first);
        fragment.extend(other);
    }
    fragment
}

fn push_joined(out: &mut Vec<Node>, node: Node) {
    if let Some(last) = out.last_mut()
        && last.same_text_markup(&node)
    {
        last.text.as_mut().expect("text").push_str(node.text.as_deref().expect("text"));
        return;
    }
    out.push(node);
}

/// `Slice.maxOpen`.
pub fn max_open(schema: &Schema, content: &[Node], open_isolating: bool) -> (usize, usize) {
    let depth = |first: bool| {
        let mut depth = 0;
        let mut current = if first { content.first() } else { content.last() };
        while let Some(node) = current {
            if schema.is_leaf(node.ty) || (!open_isolating && schema.nodes[node.ty].isolating) {
                break;
            }
            depth += 1;
            current = if first { node.content.first() } else { node.content.last() };
        }
        depth
    };
    (depth(true), depth(false))
}

// Content expressions, compiled exactly as prosemirror-model's content.ts.

enum Expr {
    Choice(Vec<Expr>),
    Seq(Vec<Expr>),
    Plus(Box<Expr>),
    Star(Box<Expr>),
    Opt(Box<Expr>),
    Range(usize, Option<usize>, Box<Expr>),
    Name(TypeId),
}

struct Tokens<'a> {
    tokens: Vec<String>,
    pos: usize,
    nodes: &'a [NodeType],
    index: &'a HashMap<String, TypeId>,
}

impl Tokens<'_> {
    fn next(&self) -> Option<&str> {
        self.tokens.get(self.pos).map(String::as_str)
    }

    fn eat(&mut self, token: &str) -> bool {
        let matched = self.next() == Some(token);
        if matched {
            self.pos += 1;
        }
        matched
    }
}

/// `string.split(/\s*(?=\b|\W|$)/)` without leading or trailing empties.
fn tokenize(expression: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    for character in expression.chars() {
        let word = character.is_alphanumeric() || character == '_';
        if character.is_whitespace() {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
        } else if word && current.chars().last().is_some_and(|c| c.is_alphanumeric() || c == '_') {
            current.push(character);
        } else {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            current.push(character);
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

fn parse_expr(stream: &mut Tokens) -> Expr {
    let mut exprs = vec![parse_seq(stream)];
    while stream.eat("|") {
        exprs.push(parse_seq(stream));
    }
    if exprs.len() == 1 { exprs.pop().expect("one") } else { Expr::Choice(exprs) }
}

fn parse_seq(stream: &mut Tokens) -> Expr {
    let mut exprs = vec![parse_subscript(stream)];
    while stream.next().is_some_and(|next| next != ")" && next != "|") {
        exprs.push(parse_subscript(stream));
    }
    if exprs.len() == 1 { exprs.pop().expect("one") } else { Expr::Seq(exprs) }
}

fn parse_subscript(stream: &mut Tokens) -> Expr {
    let mut expr = parse_atom(stream);
    loop {
        if stream.eat("+") {
            expr = Expr::Plus(Box::new(expr));
        } else if stream.eat("*") {
            expr = Expr::Star(Box::new(expr));
        } else if stream.eat("?") {
            expr = Expr::Opt(Box::new(expr));
        } else if stream.eat("{") {
            let number = |stream: &mut Tokens| {
                let value = stream.next().and_then(|n| n.parse().ok()).expect("content expression number");
                stream.pos += 1;
                value
            };
            let min = number(stream);
            let mut max = Some(min);
            if stream.eat(",") {
                max = if stream.next() != Some("}") { Some(number(stream)) } else { None };
            }
            assert!(stream.eat("}"), "Unclosed braced range");
            expr = Expr::Range(min, max, Box::new(expr));
        } else {
            return expr;
        }
    }
}

fn parse_atom(stream: &mut Tokens) -> Expr {
    if stream.eat("(") {
        let expr = parse_expr(stream);
        assert!(stream.eat(")"), "Missing closing paren");
        return expr;
    }
    let name = stream.next().expect("content expression name").to_owned();
    let types: Vec<TypeId> = match stream.index.get(&name) {
        Some(&ty) => vec![ty],
        None => (0..stream.nodes.len()).filter(|&i| stream.nodes[i].groups.contains(&name)).collect(),
    };
    assert!(!types.is_empty(), "No node type or group '{name}' found");
    stream.pos += 1;
    let mut exprs: Vec<Expr> = types.into_iter().map(Expr::Name).collect();
    if exprs.len() == 1 { exprs.pop().expect("one") } else { Expr::Choice(exprs) }
}

struct Edge {
    term: Option<TypeId>,
    to: Option<usize>,
}

struct Nfa {
    states: Vec<Vec<Edge>>,
}

/// A dangling edge: (state, edge index).
type Out = Vec<(usize, usize)>;

impl Nfa {
    fn node(&mut self) -> usize {
        self.states.push(Vec::new());
        self.states.len() - 1
    }

    fn edge(&mut self, from: usize, to: Option<usize>, term: Option<TypeId>) -> (usize, usize) {
        self.states[from].push(Edge { term, to });
        (from, self.states[from].len() - 1)
    }

    fn connect(&mut self, edges: &Out, to: usize) {
        for &(state, index) in edges {
            self.states[state][index].to = Some(to);
        }
    }

    fn compile(&mut self, expr: &Expr, from: usize) -> Out {
        match expr {
            Expr::Choice(exprs) => exprs.iter().flat_map(|expr| self.compile(expr, from)).collect(),
            Expr::Seq(exprs) => {
                let mut from = from;
                for (i, expr) in exprs.iter().enumerate() {
                    let next = self.compile(expr, from);
                    if i == exprs.len() - 1 {
                        return next;
                    }
                    from = self.node();
                    self.connect(&next, from);
                }
                unreachable!("a sequence has members")
            }
            Expr::Star(expr) => {
                let looped = self.node();
                self.edge(from, Some(looped), None);
                let inner = self.compile(expr, looped);
                self.connect(&inner, looped);
                vec![self.edge(looped, None, None)]
            }
            Expr::Plus(expr) => {
                let looped = self.node();
                let first = self.compile(expr, from);
                self.connect(&first, looped);
                let inner = self.compile(expr, looped);
                self.connect(&inner, looped);
                vec![self.edge(looped, None, None)]
            }
            Expr::Opt(expr) => {
                let mut out = vec![self.edge(from, None, None)];
                out.extend(self.compile(expr, from));
                out
            }
            Expr::Range(min, max, expr) => {
                let mut current = from;
                for _ in 0..*min {
                    let next = self.node();
                    let inner = self.compile(expr, current);
                    self.connect(&inner, next);
                    current = next;
                }
                match max {
                    None => {
                        let inner = self.compile(expr, current);
                        self.connect(&inner, current);
                    }
                    Some(max) => {
                        for _ in *min..*max {
                            let next = self.node();
                            self.edge(current, Some(next), None);
                            let inner = self.compile(expr, current);
                            self.connect(&inner, next);
                            current = next;
                        }
                    }
                }
                vec![self.edge(current, None, None)]
            }
            Expr::Name(ty) => vec![self.edge(from, None, Some(*ty))],
        }
    }

    /// `nullFrom`: states reachable by null edges, sorted descending.
    fn null_from(&self, node: usize) -> Vec<usize> {
        let mut result = Vec::new();
        self.scan(node, &mut result);
        result.sort_by(|a, b| b.cmp(a));
        result
    }

    fn scan(&self, node: usize, result: &mut Vec<usize>) {
        let edges = &self.states[node];
        if edges.len() == 1 && edges[0].term.is_none() {
            return self.scan(edges[0].to.expect("connected"), result);
        }
        result.push(node);
        for edge in edges {
            let to = edge.to.expect("connected");
            if edge.term.is_none() && !result.contains(&to) {
                self.scan(to, result);
            }
        }
    }
}

fn compile(expression: &str, nodes: &[NodeType], index: &HashMap<String, TypeId>, matches: &mut Vec<MatchState>) -> MatchId {
    let mut stream = Tokens { tokens: tokenize(expression), pos: 0, nodes, index };
    if stream.next().is_none() {
        return EMPTY_MATCH;
    }
    let expr = parse_expr(&mut stream);
    assert!(stream.next().is_none(), "Unexpected trailing text in content expression '{expression}'");
    let mut nfa = Nfa { states: vec![Vec::new()] };
    let out = nfa.compile(&expr, 0);
    let end = nfa.node();
    nfa.connect(&out, end);
    let mut labeled: HashMap<Vec<usize>, MatchId> = HashMap::new();
    let start = nfa.null_from(0);
    explore(&nfa, start, &mut labeled, matches)
}

fn explore(nfa: &Nfa, states: Vec<usize>, labeled: &mut HashMap<Vec<usize>, MatchId>, matches: &mut Vec<MatchState>) -> MatchId {
    let mut out: Vec<(TypeId, Vec<usize>)> = Vec::new();
    for &node in &states {
        for edge in &nfa.states[node] {
            let Some(term) = edge.term else { continue };
            let position = out.iter().position(|(ty, _)| *ty == term);
            let mut set_index = position;
            for reached in nfa.null_from(edge.to.expect("connected")) {
                let index = *set_index.get_or_insert_with(|| {
                    out.push((term, Vec::new()));
                    out.len() - 1
                });
                if !out[index].1.contains(&reached) {
                    out[index].1.push(reached);
                }
            }
        }
    }
    let id = matches.len();
    matches.push(MatchState { valid_end: states.contains(&(nfa.states.len() - 1)), next: Vec::new() });
    labeled.insert(states, id);
    for (term, mut targets) in out {
        targets.sort_by(|a, b| b.cmp(a));
        let next = match labeled.get(&targets) {
            Some(&existing) => existing,
            None => explore(nfa, targets, labeled, matches),
        };
        matches[id].next.push((term, next));
    }
    id
}
