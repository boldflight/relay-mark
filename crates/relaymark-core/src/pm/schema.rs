//! The canonical editor schema as prosemirror-model's `Schema`: node and mark
//! types with their specs, and content expressions compiled to the same
//! automaton (edge order included, since it decides filler and wrapper nodes).

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
    /// `defaultAttrs`; `None` when an attribute is required.
    default_attrs: Option<Map>,
    pub is_inline: bool,
    pub is_text: bool,
    /// `whitespace == "pre"` (a `code` node).
    pub pre: bool,
    pub atom: bool,
    pub isolating: bool,
    pub defining: bool,
    /// `spec.selectable !== false`.
    pub selectable: bool,
    pub table_role: Option<String>,
    pub linebreak_replacement: bool,
    /// `None` admits every mark.
    mark_set: Option<Vec<MarkId>>,
    pub content: MatchId,
}

pub struct MarkType {
    pub name: String,
    attrs: Vec<(String, Option<Value>)>,
    excluded: Vec<MarkId>,
    /// `spec.inclusive === false`.
    pub not_inclusive: bool,
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
                not_inclusive: mark["inclusive"] == Value::Bool(false),
            })
            .collect();
        let mut nodes: Vec<NodeType> = node_values
            .iter()
            .map(|node| {
                let name = node["name"].as_str().unwrap_or_default().to_owned();
                let attrs = attr_specs(node.get("attrs"));
                let default_attrs = attrs.iter().map(|(name, default)| default.clone().map(|d| (name.clone(), d))).collect::<Option<Map>>();
                NodeType {
                    is_text: name == "text",
                    is_inline: node["inline"].as_bool().unwrap_or(false) || name == "text",
                    pre: node["code"].as_bool().unwrap_or(false),
                    atom: node["atom"].as_bool().unwrap_or(false),
                    isolating: node["isolating"].as_bool().unwrap_or(false),
                    defining: node["defining"].as_bool().unwrap_or(false),
                    selectable: node["selectable"] != Value::Bool(false),
                    table_role: node["tableRole"].as_str().map(str::to_owned),
                    linebreak_replacement: node["linebreakReplacement"].as_bool().unwrap_or(false),
                    groups: node["group"].as_str().unwrap_or("").split_whitespace().map(str::to_owned).collect(),
                    attrs,
                    default_attrs,
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

    pub fn is_atom(&self, ty: TypeId) -> bool {
        self.is_leaf(ty) || self.nodes[ty].atom
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
        self.nodes[ty].default_attrs.is_none()
    }

    pub fn default_attrs(&self, ty: TypeId) -> Option<&Map> {
        self.nodes[ty].default_attrs.as_ref()
    }

    pub fn has_attr(&self, ty: TypeId, name: &str) -> bool {
        self.nodes[ty].attrs.iter().any(|(key, _)| key == name)
    }

    pub fn mark_has_attr(&self, ty: MarkId, name: &str) -> bool {
        self.marks[ty].attrs.iter().any(|(key, _)| key == name)
    }

    pub fn allows_mark(&self, ty: TypeId, mark: MarkId) -> bool {
        self.nodes[ty].mark_set.as_ref().is_none_or(|set| set.contains(&mark))
    }

    pub fn mark_set_is_all(&self, ty: TypeId) -> bool {
        self.nodes[ty].mark_set.is_none()
    }

    pub fn excludes(&self, mark: MarkId, other: MarkId) -> bool {
        self.marks[mark].excluded.contains(&other)
    }

    /// `NodeType.computeAttrs`: every declared attribute in declaration order.
    pub fn node_attrs(&self, ty: TypeId, given: Option<&Map>) -> Result<Map> {
        if given.is_none()
            && let Some(defaults) = &self.nodes[ty].default_attrs
        {
            return Ok(defaults.clone());
        }
        compute_attrs(&self.nodes[ty].attrs, given, &self.nodes[ty].name)
    }

    /// `MarkType.create` attributes.
    pub fn mark_attrs(&self, ty: MarkId, given: Option<&Map>) -> Result<Map> {
        compute_attrs(&self.marks[ty].attrs, given, &self.marks[ty].name)
    }

    /// `NodeType.compatibleContent`.
    pub fn compatible_content(&self, ty: TypeId, other: TypeId) -> bool {
        ty == other || self.compatible(self.nodes[ty].content, self.nodes[other].content)
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

    pub fn match_types(&self, state: MatchId, types: impl IntoIterator<Item = TypeId>) -> Option<MatchId> {
        types.into_iter().try_fold(state, |current, ty| self.match_type(current, ty))
    }

    pub fn match_inline_content(&self, state: MatchId) -> bool {
        self.edges(state).first().is_some_and(|(ty, _)| self.nodes[*ty].is_inline)
    }

    /// Whether a node of this type can be generated to fill content.
    pub fn generatable(&self, ty: TypeId) -> bool {
        !(self.nodes[ty].is_text || self.has_required_attrs(ty))
    }

    pub fn default_type(&self, state: MatchId) -> Option<TypeId> {
        self.edges(state).iter().map(|(ty, _)| *ty).find(|&ty| self.generatable(ty))
    }

    pub fn compatible(&self, a: MatchId, b: MatchId) -> bool {
        self.edges(a).iter().any(|(x, _)| self.edges(b).iter().any(|(y, _)| x == y))
    }

    /// `ContentMatch.fillBefore`: the node types to create in front of
    /// `after` (as its child types) for it to match, empty when it already
    /// does.
    pub fn fill_before(&self, state: MatchId, after: &[TypeId], to_end: bool) -> Option<Vec<TypeId>> {
        let mut seen = vec![state];
        let mut types = Vec::new();
        self.fill_search(state, &mut types, after, to_end, &mut seen).then_some(types)
    }

    fn fill_search(&self, state: MatchId, types: &mut Vec<TypeId>, after: &[TypeId], to_end: bool, seen: &mut Vec<MatchId>) -> bool {
        if let Some(finished) = self.match_types(state, after.iter().copied())
            && (!to_end || self.valid_end(finished))
        {
            return true;
        }
        for &(ty, next) in self.edges(state) {
            if self.generatable(ty) && !seen.contains(&next) {
                seen.push(next);
                types.push(ty);
                if self.fill_search(next, types, after, to_end, seen) {
                    return true;
                }
                types.pop();
            }
        }
        false
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
}

fn compute_attrs(specs: &[(String, Option<Value>)], given: Option<&Map>, name: &str) -> Result<Map> {
    let mut out = Map::with_capacity(specs.len());
    for (key, default) in specs {
        match given.and_then(|g| g.get(key)).or(default.as_ref()) {
            Some(value) => {
                out.insert(key.clone(), value.clone());
            }
            None => bail!("No value supplied for attribute {key}"),
        }
    }
    let _ = name;
    Ok(out)
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
