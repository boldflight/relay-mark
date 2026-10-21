//! prosemirror-model's `DOMParser` (from_dom.ts, 1.25): DOM to nodes by parse
//! rules, with the same context, wrapping, whitespace and mark handling. Only
//! the options HTML import uses are kept (no positions, context or top node).

use crate::error::{Result, bail};
use crate::json::{Map, is_js_space};

use super::dom::{Dom, Id, Kind};
use super::model::{Mark, MarkId, MatchId, Node, Schema, TypeId, append, fragment};

/// What a `getAttrs` decided.
pub enum Attrs {
    /// `false`: the rule does not match.
    Skip,
    /// `null`: default attributes.
    Default,
    Given(Map),
}

pub type TagAttrs = Box<dyn Fn(&Dom, Id) -> Result<Attrs> + Send + Sync>;
pub type Matcher = Box<dyn Fn(&Dom, Id) -> bool + Send + Sync>;
pub type Pick = Box<dyn Fn(&Dom, Id) -> Id + Send + Sync>;
pub type StyleAttrs = Box<dyn Fn(&str) -> Attrs + Send + Sync>;

pub enum Target {
    Node(TypeId),
    Mark(MarkId),
}

pub enum ContentElement {
    Itself,
    /// The first descendant with this local name (`querySelector(tag)`).
    Descendant(&'static str),
    Pick(Pick),
}

pub struct TagRule {
    /// The selector's element name, for the list normalization test.
    pub tag: &'static str,
    pub matches: Matcher,
    pub target: Target,
    pub attrs: Option<TagAttrs>,
    pub content: ContentElement,
    pub preserve_whitespace: Option<Whitespace>,
    pub priority: i32,
    pub consuming: bool,
}

pub struct StyleRule {
    /// `property` or `property=value`.
    pub style: &'static str,
    pub target: Option<MarkId>,
    /// `clearMark` for marks of this type.
    pub clear: Option<MarkId>,
    pub attrs: Option<StyleAttrs>,
    pub priority: i32,
    pub consuming: bool,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Whitespace {
    Collapse,
    Preserve,
    Full,
}

pub struct Parser {
    pub schema: &'static Schema,
    tags: Vec<TagRule>,
    styles: Vec<StyleRule>,
    matched_styles: Vec<&'static str>,
    normalize_lists: bool,
}

const BLOCK_TAGS: &[&str] = &[
    "address",
    "article",
    "aside",
    "blockquote",
    "body",
    "canvas",
    "dd",
    "div",
    "dl",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "hgroup",
    "hr",
    "li",
    "noscript",
    "ol",
    "output",
    "p",
    "pre",
    "section",
    "table",
    "tfoot",
    "ul",
];
const IGNORE_TAGS: &[&str] = &["head", "noscript", "object", "script", "style", "title"];

const PRESERVE_WS: u8 = 1;
const PRESERVE_WS_FULL: u8 = 2;
const OPEN_LEFT: u8 = 4;

fn ws_options(schema: &Schema, ty: Option<TypeId>, preserve: Option<Whitespace>, base: u8) -> u8 {
    match preserve {
        Some(Whitespace::Full) => PRESERVE_WS | PRESERVE_WS_FULL,
        Some(Whitespace::Preserve) => PRESERVE_WS,
        Some(Whitespace::Collapse) => 0,
        None if ty.is_some_and(|ty| schema.nodes[ty].pre) => PRESERVE_WS | PRESERVE_WS_FULL,
        None => base & !OPEN_LEFT,
    }
}

fn is_html_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\r' | '\n' | '\u{c}')
}

impl Parser {
    /// `DOMParser.fromSchema`: mark rules then node rules, stable by priority.
    pub fn new(schema: &'static Schema, mark_tags: Vec<TagRule>, node_tags: Vec<TagRule>, styles: Vec<StyleRule>) -> Self {
        let mut tags: Vec<TagRule> = Vec::new();
        for rule in mark_tags.into_iter().chain(node_tags) {
            let index = tags.iter().position(|existing| existing.priority < rule.priority).unwrap_or(tags.len());
            tags.insert(index, rule);
        }
        let mut sorted: Vec<StyleRule> = Vec::new();
        for rule in styles {
            let index = sorted.iter().position(|existing| existing.priority < rule.priority).unwrap_or(sorted.len());
            sorted.insert(index, rule);
        }
        let mut matched_styles = Vec::new();
        for rule in &sorted {
            let property = rule.style.split('=').next().unwrap_or_default();
            if !matched_styles.contains(&property) {
                matched_styles.push(property);
            }
        }
        // Lists are normalized when no list type may directly contain itself.
        let normalize_lists = !tags.iter().any(|rule| match rule.target {
            Target::Node(ty) => matches!(rule.tag, "ul" | "ol") && schema.match_type(schema.nodes[ty].content, ty).is_some(),
            Target::Mark(_) => false,
        });
        Self { schema, tags, styles: sorted, matched_styles, normalize_lists }
    }

    /// `DOMParser.parse` with `preserveWhitespace`.
    pub fn parse(&self, dom: &mut Dom, root: Id, preserve: Option<Whitespace>) -> Result<Node> {
        let mut context = Context::new(self, preserve, false);
        context.add_all(dom, root, &[])?;
        match context.finish()? {
            Finished::Node(node) => Ok(node),
            Finished::Fragment(_) => unreachable!("a closed parse has a top node"),
        }
    }

    /// `DOMParser.parseSlice` content (before `Slice.maxOpen`).
    pub fn parse_slice(&self, dom: &mut Dom, root: Id, preserve: Option<Whitespace>) -> Result<Vec<Node>> {
        let mut context = Context::new(self, preserve, true);
        context.add_all(dom, root, &[])?;
        match context.finish()? {
            Finished::Fragment(nodes) => Ok(nodes),
            Finished::Node(_) => unreachable!("an open parse has no top node"),
        }
    }

    fn match_tag(&self, dom: &Dom, id: Id, after: Option<usize>) -> Result<Option<(usize, Option<Map>)>> {
        for index in after.map_or(0, |i| i + 1)..self.tags.len() {
            let rule = &self.tags[index];
            if !(rule.matches)(dom, id) {
                continue;
            }
            let attrs = match &rule.attrs {
                Some(get) => match get(dom, id)? {
                    Attrs::Skip => continue,
                    Attrs::Default => None,
                    Attrs::Given(attrs) => Some(attrs),
                },
                None => None,
            };
            return Ok(Some((index, attrs)));
        }
        Ok(None)
    }

    fn match_style(&self, property: &str, value: &str, after: Option<usize>) -> Option<(usize, Option<Map>)> {
        for index in after.map_or(0, |i| i + 1)..self.styles.len() {
            let rule = &self.styles[index];
            let style = rule.style;
            if !style.starts_with(property)
                || (style.len() > property.len() && (style.as_bytes()[property.len()] != b'=' || &style[property.len() + 1..] != value))
            {
                continue;
            }
            let attrs = match &rule.attrs {
                Some(get) => match get(value) {
                    Attrs::Skip => continue,
                    Attrs::Default => None,
                    Attrs::Given(attrs) => Some(attrs),
                },
                None => None,
            };
            return Some((index, attrs));
        }
        None
    }
}

struct NodeContext {
    serial: usize,
    ty: Option<TypeId>,
    attrs: Option<Map>,
    marks: Vec<Mark>,
    solid: bool,
    matched: Option<MatchId>,
    options: u8,
    content: Vec<Node>,
}

enum Finished {
    Node(Node),
    Fragment(Vec<Node>),
}

impl NodeContext {
    fn find_wrapping(&mut self, schema: &Schema, node: &Node) -> Option<Vec<TypeId>> {
        if self.matched.is_none() {
            let Some(ty) = self.ty else { return Some(Vec::new()) };
            let start = schema.nodes[ty].content;
            match schema.fill_before(start, std::slice::from_ref(node), false, 0) {
                Some(fill) => self.matched = schema.match_fragment(start, &fill),
                None => {
                    let wrap = schema.find_wrapping(start, node.ty)?;
                    self.matched = Some(start);
                    return Some(wrap);
                }
            }
        }
        schema.find_wrapping(self.matched.expect("match"), node.ty)
    }

    fn finish(mut self, schema: &Schema, open_end: bool) -> Result<Finished> {
        if self.options & PRESERVE_WS == 0
            && let Some(last) = self.content.last_mut()
            && let Some(text) = &mut last.text
        {
            let trimmed = text.trim_end_matches(is_html_space).len();
            if trimmed == 0 {
                self.content.pop();
            } else {
                text.truncate(trimmed);
            }
        }
        let mut content = fragment(self.content);
        if !open_end && let Some(matched) = self.matched {
            let Some(fill) = schema.fill_before(matched, &[], true, 0) else { bail!("Cannot read properties of null (reading 'size')") };
            content = append(content, fill);
        }
        Ok(match self.ty {
            Some(ty) => Finished::Node(schema.create(ty, self.attrs.as_ref(), content, self.marks)?),
            None => Finished::Fragment(content),
        })
    }

    fn inline_context(&self, schema: &Schema, dom: &Dom, id: Id) -> bool {
        if let Some(ty) = self.ty {
            return schema.inline_content(ty);
        }
        if let Some(first) = self.content.first() {
            return schema.nodes[first.ty].is_inline;
        }
        dom.parent(id).is_some_and(|parent| !BLOCK_TAGS.contains(&dom.name(parent)))
    }
}

struct Context<'p> {
    parser: &'p Parser,
    schema: &'static Schema,
    open: usize,
    needs_block: bool,
    nodes: Vec<NodeContext>,
    local_preserve_ws: bool,
    is_open: bool,
    serials: usize,
}

impl<'p> Context<'p> {
    fn new(parser: &'p Parser, preserve: Option<Whitespace>, is_open: bool) -> Self {
        let schema = parser.schema;
        let options = ws_options(schema, None, preserve, 0) | if is_open { OPEN_LEFT } else { 0 };
        let top = if is_open {
            NodeContext { serial: 0, ty: None, attrs: None, marks: Vec::new(), solid: true, matched: None, options, content: Vec::new() }
        } else {
            let matched = Some(schema.nodes[schema.top].content);
            NodeContext { serial: 0, ty: Some(schema.top), attrs: None, marks: Vec::new(), solid: true, matched, options, content: Vec::new() }
        };
        Self { parser, schema, open: 0, needs_block: false, nodes: vec![top], local_preserve_ws: false, is_open, serials: 1 }
    }

    fn top(&mut self) -> &mut NodeContext {
        &mut self.nodes[self.open]
    }

    fn add_dom(&mut self, dom: &mut Dom, id: Id, marks: &[Mark]) -> Result<()> {
        match dom.kind(id) {
            Kind::Text(_) => self.add_text_node(dom, id, marks),
            Kind::Element => self.add_element(dom, id, marks, None),
            _ => Ok(()),
        }
    }

    fn add_text_node(&mut self, dom: &Dom, id: Id, marks: &[Mark]) -> Result<()> {
        let mut value = dom.text(id).unwrap_or_default().to_owned();
        let schema = self.schema;
        let top_options = self.nodes[self.open].options;
        let preserve = if top_options & PRESERVE_WS_FULL != 0 {
            Whitespace::Full
        } else if self.local_preserve_ws || top_options & PRESERVE_WS != 0 {
            Whitespace::Preserve
        } else {
            Whitespace::Collapse
        };
        if preserve == Whitespace::Full || self.nodes[self.open].inline_context(schema, dom, id) || value.chars().any(|c| !is_html_space(c)) {
            match preserve {
                Whitespace::Collapse => {
                    value = collapse_html_space(&value);
                    if value.starts_with(is_html_space) && self.open == self.nodes.len() - 1 {
                        let top = &self.nodes[self.open];
                        let before = top.content.last();
                        let dom_before_br = dom.previous_sibling(id).is_some_and(|sibling| dom.name(sibling) == "br");
                        if before.is_none() || dom_before_br || before.and_then(|n| n.text.as_deref()).is_some_and(|t| t.ends_with(is_html_space)) {
                            value.remove(0);
                        }
                    }
                }
                Whitespace::Full => value = value.replace("\r\n", "\n").replace('\r', "\n"),
                Whitespace::Preserve => {
                    let replacement = (0..schema.nodes.len()).find(|&ty| schema.nodes[ty].linebreak_replacement);
                    let wrapped = match replacement {
                        Some(ty) if value.contains(['\r', '\n']) => {
                            let probe = schema.create(ty, None, Vec::new(), Vec::new())?;
                            self.nodes[self.open].find_wrapping(schema, &probe).is_some().then_some(ty)
                        }
                        _ => None,
                    };
                    if let Some(ty) = wrapped {
                        let normalized = value.replace("\r\n", "\n").replace('\r', "\n");
                        for (index, line) in normalized.split('\n').enumerate() {
                            if index > 0 {
                                let line_break = schema.create(ty, None, Vec::new(), Vec::new())?;
                                self.insert_node(line_break, marks, true)?;
                            }
                            if !line.is_empty() {
                                self.insert_node(schema.text_node(line, Vec::new()), marks, !line.chars().any(|c| !is_js_space(c)))?;
                            }
                        }
                        value.clear();
                    } else {
                        value = value.replace("\r\n", " ").replace(['\r', '\n'], " ");
                    }
                }
            }
            if !value.is_empty() {
                let cautious = !value.chars().any(|c| !is_js_space(c));
                self.insert_node(schema.text_node(&value, Vec::new()), marks, cautious)?;
            }
        }
        Ok(())
    }

    fn add_element(&mut self, dom: &mut Dom, id: Id, marks: &[Mark], match_after: Option<usize>) -> Result<()> {
        let outer_ws = self.local_preserve_ws;
        let mut top = self.nodes[self.open].serial;
        let name = dom.name(id).to_owned();
        if name == "pre" || style_value(dom, id, "white-space").is_some_and(|value| value.contains("pre")) {
            self.local_preserve_ws = true;
        }
        if (name == "ul" || name == "ol") && self.parser.normalize_lists {
            normalize_list(dom, id);
        }
        let rule = self.parser.match_tag(dom, id, match_after)?;
        match rule {
            None if IGNORE_TAGS.contains(&name.as_str()) => self.ignore_fallback(dom, id, marks)?,
            None => {
                let mut sync = false;
                let old_needs_block = self.needs_block;
                let mut leaf = false;
                if BLOCK_TAGS.contains(&name.as_str()) {
                    let current = &self.nodes[self.open];
                    if current.content.first().is_some_and(|first| self.schema.nodes[first.ty].is_inline) && self.open > 0 {
                        self.open -= 1;
                        top = self.nodes[self.open].serial;
                    }
                    sync = true;
                    if self.nodes[self.open].ty.is_none() {
                        self.needs_block = true;
                    }
                } else if dom.children(id).is_empty() {
                    self.leaf_fallback(dom, id, marks)?;
                    leaf = true;
                }
                if !leaf {
                    let inner = self.read_styles(dom, id, marks)?;
                    self.add_all(dom, id, &inner)?;
                    if sync {
                        self.sync(top);
                    }
                    self.needs_block = old_needs_block;
                }
            }
            Some((index, attrs)) => {
                let inner = self.read_styles(dom, id, marks)?;
                let continue_after = (!self.parser.tags[index].consuming).then_some(index);
                self.add_element_by_rule(dom, id, index, attrs, &inner, continue_after)?;
            }
        }
        self.local_preserve_ws = outer_ws;
        Ok(())
    }

    fn leaf_fallback(&mut self, dom: &mut Dom, id: Id, marks: &[Mark]) -> Result<()> {
        if dom.name(id) == "br" && self.nodes[self.open].ty.is_some_and(|ty| self.schema.inline_content(ty)) {
            let newline = dom.create_text("\n");
            self.add_text_node(dom, newline, marks)?;
        }
        Ok(())
    }

    fn ignore_fallback(&mut self, dom: &Dom, id: Id, marks: &[Mark]) -> Result<()> {
        if dom.name(id) == "br" && !self.nodes[self.open].ty.is_some_and(|ty| self.schema.inline_content(ty)) {
            self.find_place(&self.schema.text_node("-", Vec::new()), marks, true)?;
        }
        Ok(())
    }

    fn read_styles(&mut self, dom: &Dom, id: Id, marks: &[Mark]) -> Result<Vec<Mark>> {
        let mut marks = marks.to_vec();
        let declarations = styles(dom, id);
        if declarations.is_empty() {
            return Ok(marks);
        }
        for &property in &self.parser.matched_styles {
            let Some(value) = declarations.iter().rev().find(|(name, _)| name == property).map(|(_, value)| value.as_str()) else { continue };
            if value.is_empty() {
                continue;
            }
            let mut after = None;
            while let Some((index, attrs)) = self.parser.match_style(property, value, after) {
                let rule = &self.parser.styles[index];
                if let Some(cleared) = rule.clear {
                    marks.retain(|mark| mark.ty != cleared);
                } else if let Some(mark) = rule.target {
                    marks.push(self.schema.mark(mark, attrs.as_ref())?);
                }
                if rule.consuming {
                    break;
                }
                after = Some(index);
            }
        }
        Ok(marks)
    }

    fn add_element_by_rule(&mut self, dom: &mut Dom, id: Id, index: usize, attrs: Option<Map>, marks: &[Mark], continue_after: Option<usize>) -> Result<()> {
        let schema = self.schema;
        let rule = &self.parser.tags[index];
        let mut marks = marks.to_vec();
        let mut sync = false;
        let mut leaf_node = false;
        match rule.target {
            Target::Node(ty) => {
                if !schema.is_leaf(ty) {
                    if let Some(inner) = self.enter(ty, attrs, &marks, rule.preserve_whitespace)? {
                        sync = true;
                        marks = inner;
                    }
                } else {
                    leaf_node = true;
                    let node = schema.create(ty, attrs.as_ref(), Vec::new(), Vec::new())?;
                    if !self.insert_node(node, &marks, dom.name(id) == "br")? {
                        self.leaf_fallback(dom, id, &marks)?;
                    }
                }
            }
            Target::Mark(ty) => {
                let mark = schema.mark(ty, attrs.as_ref())?;
                marks.push(mark);
            }
        }
        let start_in = self.nodes[self.open].serial;
        if leaf_node {
            // A leaf's DOM content is not parsed.
        } else if let Some(after) = continue_after {
            self.add_element(dom, id, &marks, Some(after))?;
        } else {
            let content = match &rule.content {
                ContentElement::Itself => Some(id),
                ContentElement::Descendant(tag) => dom.find_descendant(id, tag),
                ContentElement::Pick(pick) => Some(pick(dom, id)),
            };
            let Some(content) = content else { bail!("Cannot read properties of null (reading 'firstChild')") };
            self.add_all(dom, content, &marks)?;
        }
        if sync && self.sync(start_in) {
            self.open -= 1;
        }
        Ok(())
    }

    fn add_all(&mut self, dom: &mut Dom, parent: Id, marks: &[Mark]) -> Result<()> {
        // Children may move (list normalization) while they are read, so walk
        // by sibling from the live list, as the DOM's `nextSibling` does.
        let mut index = 0;
        while let Some(&child) = dom.children(parent).get(index) {
            self.add_dom(dom, child, marks)?;
            index = if dom.children(parent).get(index) == Some(&child) {
                index + 1
            } else {
                dom.children(parent).iter().position(|&c| c == child).map_or(index, |at| at + 1)
            };
        }
        Ok(())
    }

    fn find_place(&mut self, node: &Node, marks: &[Mark], cautious: bool) -> Result<Option<Vec<Mark>>> {
        let schema = self.schema;
        let mut route: Option<Vec<TypeId>> = None;
        let mut sync = 0;
        let mut penalty = 0;
        for depth in (0..=self.open).rev() {
            let found = self.nodes[depth].find_wrapping(schema, node);
            if let Some(found) = found
                && route.as_ref().is_none_or(|route| route.len() > found.len() + penalty)
            {
                let direct = found.is_empty();
                route = Some(found);
                sync = self.nodes[depth].serial;
                if direct {
                    break;
                }
            }
            if self.nodes[depth].solid {
                if cautious {
                    break;
                }
                penalty += 2;
            }
        }
        let Some(route) = route else { return Ok(None) };
        self.sync(sync);
        let mut marks = marks.to_vec();
        for ty in route {
            marks = self.enter_inner(ty, None, &marks, false, None)?;
        }
        Ok(Some(marks))
    }

    fn insert_node(&mut self, node: Node, marks: &[Mark], cautious: bool) -> Result<bool> {
        let schema = self.schema;
        let mut marks = marks.to_vec();
        if schema.nodes[node.ty].is_inline
            && self.needs_block
            && self.nodes[self.open].ty.is_none()
            && let Some(block) = (0..schema.nodes.len()).find(|&ty| schema.is_textblock(ty) && !schema.has_required_attrs(ty))
        {
            marks = self.enter_inner(block, None, &marks, false, None)?;
        }
        let Some(inner) = self.find_place(&node, &marks, cautious)? else { return Ok(false) };
        self.close_extra(false)?;
        let top = self.top();
        if let Some(matched) = top.matched {
            top.matched = schema.match_type(matched, node.ty);
        }
        let top_ty = top.ty;
        let mut node_marks: Vec<Mark> = Vec::new();
        for mark in inner.iter().chain(node.marks.iter()) {
            let allowed = match top_ty {
                Some(ty) => schema.allows_mark(ty, mark.ty),
                None => schema.mark_may_apply(mark.ty, node.ty),
            };
            if allowed {
                node_marks = schema.add_mark(mark, &node_marks);
            }
        }
        let mut node = node;
        node.marks = node_marks;
        self.top().content.push(node);
        Ok(true)
    }

    fn enter(&mut self, ty: TypeId, attrs: Option<Map>, marks: &[Mark], preserve: Option<Whitespace>) -> Result<Option<Vec<Mark>>> {
        let probe = self.schema.create(ty, attrs.as_ref(), Vec::new(), Vec::new())?;
        match self.find_place(&probe, marks, false)? {
            Some(_) => Ok(Some(self.enter_inner(ty, attrs, marks, true, preserve)?)),
            None => Ok(None),
        }
    }

    fn enter_inner(&mut self, ty: TypeId, attrs: Option<Map>, marks: &[Mark], solid: bool, preserve: Option<Whitespace>) -> Result<Vec<Mark>> {
        self.close_extra(false)?;
        let schema = self.schema;
        let top = &mut self.nodes[self.open];
        top.matched = top.matched.and_then(|matched| schema.match_type(matched, ty));
        let mut options = ws_options(schema, Some(ty), preserve, top.options);
        if top.options & OPEN_LEFT != 0 && top.content.is_empty() {
            options |= OPEN_LEFT;
        }
        let top_ty = top.ty;
        let mut apply: Vec<Mark> = Vec::new();
        let mut rest = Vec::new();
        for mark in marks {
            let allowed = match top_ty {
                Some(parent) => schema.allows_mark(parent, mark.ty),
                None => schema.mark_may_apply(mark.ty, ty),
            };
            if allowed {
                apply = schema.add_mark(mark, &apply);
            } else {
                rest.push(mark.clone());
            }
        }
        let matched = if options & OPEN_LEFT != 0 { None } else { Some(schema.nodes[ty].content) };
        let serial = self.serials;
        self.serials += 1;
        self.nodes.push(NodeContext { serial, ty: Some(ty), attrs, marks: apply, solid, matched, options, content: Vec::new() });
        self.open += 1;
        Ok(rest)
    }

    fn close_extra(&mut self, open_end: bool) -> Result<()> {
        while self.nodes.len() - 1 > self.open {
            let finished = self.nodes.pop().expect("node").finish(self.schema, open_end)?;
            let Finished::Node(node) = finished else { unreachable!("inner contexts have a type") };
            self.nodes.last_mut().expect("parent").content.push(node);
        }
        Ok(())
    }

    fn finish(mut self) -> Result<Finished> {
        self.open = 0;
        self.close_extra(self.is_open)?;
        let top = self.nodes.pop().expect("top");
        top.finish(self.schema, self.is_open)
    }

    fn sync(&mut self, to: usize) -> bool {
        for index in (0..=self.open).rev() {
            if self.nodes[index].serial == to {
                self.open = index;
                return true;
            } else if self.local_preserve_ws {
                self.nodes[index].options |= PRESERVE_WS;
            }
        }
        false
    }
}

/// `value.replace(/[ \t\r\n\u000c]+/g, " ")`.
fn collapse_html_space(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut in_space = false;
    for character in value.chars() {
        if is_html_space(character) {
            if !in_space {
                out.push(' ');
            }
            in_space = true;
        } else {
            out.push(character);
            in_space = false;
        }
    }
    out
}

/// The element's inline `style` declarations, lower-cased property names.
pub fn styles(dom: &Dom, id: Id) -> Vec<(String, String)> {
    let Some(style) = dom.attr(id, "style") else { return Vec::new() };
    style
        .split(';')
        .filter_map(|declaration| {
            let (name, value) = declaration.split_once(':')?;
            let name = name.trim().to_ascii_lowercase();
            (!name.is_empty()).then(|| (name, value.trim().to_owned()))
        })
        .collect()
}

/// `element.style.getPropertyValue(property)`.
pub fn style_value(dom: &Dom, id: Id, property: &str) -> Option<String> {
    styles(dom, id).into_iter().rev().find(|(name, _)| name == property).map(|(_, value)| value)
}

/// Moves a list nested directly in a list into the item before it.
fn normalize_list(dom: &mut Dom, list: Id) {
    let mut previous_item: Option<Id> = None;
    let mut index = 0;
    while let Some(&child) = dom.children(list).get(index) {
        let name = if dom.is_element(child) { Some(dom.name(child).to_owned()) } else { None };
        match name.as_deref() {
            Some("ol" | "ul") if previous_item.is_some() => {
                let item = previous_item.expect("item");
                dom.append_child(item, child);
                // `child = prevItem`: continue after the item, which is now at `index - 1`.
                continue;
            }
            Some("li") => previous_item = Some(child),
            Some(_) => previous_item = None,
            None => {}
        }
        index += 1;
    }
}
