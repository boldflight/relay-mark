//! prosemirror-model 1.25's document model over the canonical schema: marks,
//! immutable nodes with shared structure, fragments, slices, resolved
//! positions and `replace`. Positions count UTF-16 code units in text, as in
//! JavaScript.

use std::rc::Rc;

use serde_json::Value;

use crate::error::{Error, Result, bail};
use crate::json::{self, Map};

use super::schema::{MarkId, MatchId, Schema, TypeId, schema};

#[derive(Debug, Clone)]
pub struct Mark {
    pub ty: MarkId,
    pub attrs: Rc<Map>,
}

impl PartialEq for Mark {
    fn eq(&self, other: &Self) -> bool {
        self.ty == other.ty && (Rc::ptr_eq(&self.attrs, &other.attrs) || compare_attrs(&self.attrs, &other.attrs))
    }
}

/// `compareDeep` of two attribute objects: order-insensitive.
pub fn compare_attrs(a: &Map, b: &Map) -> bool {
    a.len() == b.len() && a.iter().all(|(key, value)| b.get(key).is_some_and(|other| json::deep_equal(value, other)))
}

impl Mark {
    pub fn new(ty: MarkId, attrs: Option<&Map>) -> Result<Self> {
        Ok(Mark { ty, attrs: Rc::new(schema().mark_attrs(ty, attrs)?) })
    }

    pub fn add_to_set(&self, set: &[Mark]) -> Vec<Mark> {
        let schema = schema();
        let mut copy: Option<Vec<Mark>> = None;
        let mut placed = false;
        for (index, other) in set.iter().enumerate() {
            if self == other {
                return set.to_vec();
            }
            if schema.excludes(self.ty, other.ty) {
                copy.get_or_insert_with(|| set[..index].to_vec());
            } else if schema.excludes(other.ty, self.ty) {
                return set.to_vec();
            } else {
                if !placed && other.ty > self.ty {
                    copy.get_or_insert_with(|| set[..index].to_vec()).push(self.clone());
                    placed = true;
                }
                if let Some(copy) = copy.as_mut() {
                    copy.push(other.clone());
                }
            }
        }
        let mut copy = copy.unwrap_or_else(|| set.to_vec());
        if !placed {
            copy.push(self.clone());
        }
        copy
    }

    pub fn remove_from_set(&self, set: &[Mark]) -> Vec<Mark> {
        match set.iter().position(|mark| mark == self) {
            Some(index) => set[..index].iter().chain(&set[index + 1..]).cloned().collect(),
            None => set.to_vec(),
        }
    }

    pub fn is_in_set(&self, set: &[Mark]) -> bool {
        set.iter().any(|mark| mark == self)
    }

    pub fn to_json(&self) -> Value {
        let mut object = Map::with_capacity(2);
        object.insert("type".into(), Value::String(schema().marks[self.ty].name.clone()));
        if !self.attrs.is_empty() {
            object.insert("attrs".into(), Value::Object((*self.attrs).clone()));
        }
        Value::Object(object)
    }

    pub fn from_json(json: &Value) -> Result<Self> {
        if !json::truthy(Some(json)) {
            bail!("Invalid input for Mark.fromJSON");
        }
        let name = json.get("type").and_then(Value::as_str).unwrap_or_default();
        let Some(ty) = schema().mark_type(name) else { bail!("There is no mark type {name} in this schema") };
        Mark::new(ty, json.get("attrs").and_then(Value::as_object))
    }
}

pub fn same_mark_set(a: &[Mark], b: &[Mark]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x == y)
}

/// `Mark.setFrom`: sorted by rank.
pub fn mark_set_from(mut marks: Vec<Mark>) -> Vec<Mark> {
    marks.sort_by_key(|mark| mark.ty);
    marks
}

/// A `nodesBetween` callback: (node, position, parent, index), returning
/// whether to descend into the node.
pub type Visit<'a> = dyn FnMut(&Node, usize, Option<&Node>, usize) -> bool + 'a;

/// UTF-16 length of text.
pub fn utf16_len(text: &str) -> usize {
    text.chars().map(char::len_utf16).sum()
}

/// Text as JavaScript holds it: UTF-16 code units, which positions count and
/// cuts may split. Most text is also valid Unicode, kept alongside.
#[derive(Clone)]
struct Text {
    units: Rc<[u16]>,
    string: Option<Rc<str>>,
}

impl Text {
    fn from_units(units: Vec<u16>) -> Text {
        let string = String::from_utf16(&units).ok().map(Rc::from);
        Text { units: units.into(), string }
    }

    fn from_str(text: &str) -> Text {
        Text { units: text.encode_utf16().collect::<Vec<_>>().into(), string: Some(text.into()) }
    }
}

struct NodeData {
    ty: TypeId,
    attrs: Rc<Map>,
    content: Fragment,
    marks: Rc<[Mark]>,
    text: Option<Text>,
    size: usize,
}

/// An immutable node; cloning shares it.
#[derive(Clone)]
pub struct Node(Rc<NodeData>);

impl std::fmt::Debug for Node {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", json::stringify(&self.to_json()))
    }
}

impl Node {
    pub fn new(ty: TypeId, attrs: Rc<Map>, content: Fragment, marks: Vec<Mark>) -> Self {
        let size = if schema().is_leaf(ty) { 1 } else { content.size + 2 };
        Node(Rc::new(NodeData { ty, attrs, content, marks: marks.into(), text: None, size }))
    }

    pub fn text_node(text: &str, marks: Vec<Mark>) -> Result<Self> {
        if text.is_empty() {
            bail!("Empty text nodes are not allowed");
        }
        let text = Text::from_str(text);
        Ok(Node(Rc::new(NodeData {
            ty: schema().text,
            attrs: Rc::new(Map::new()),
            content: Fragment::empty(),
            marks: mark_set_from(marks).into(),
            size: text.units.len(),
            text: Some(text),
        })))
    }

    /// `NodeType.create`.
    pub fn create(ty: TypeId, attrs: Option<&Map>, content: Fragment, marks: Vec<Mark>) -> Result<Self> {
        let schema = schema();
        if schema.nodes[ty].is_text {
            bail!("NodeType.create can't construct text nodes");
        }
        Ok(Node::new(ty, Rc::new(schema.node_attrs(ty, attrs)?), content, mark_set_from(marks)))
    }

    /// `NodeType.createChecked`.
    pub fn create_checked(ty: TypeId, attrs: Option<&Map>, content: Fragment, marks: Vec<Mark>) -> Result<Self> {
        if !valid_content(ty, &content) {
            bail!("Invalid content for node {}", schema().nodes[ty].name);
        }
        Node::create(ty, attrs, content, marks)
    }

    /// `NodeType.createAndFill`.
    pub fn create_and_fill(ty: TypeId, attrs: Option<&Map>, content: Fragment, marks: Vec<Mark>) -> Result<Option<Self>> {
        let schema = schema();
        let attrs = schema.node_attrs(ty, attrs)?;
        let start = schema.nodes[ty].content;
        let mut content = content;
        if content.size > 0 {
            let Some(before) = fill_before(start, &content, false, 0)? else { return Ok(None) };
            content = before.append(&content);
        }
        let matched = match_fragment(start, &content, 0, content.child_count());
        let Some(after) = matched.map(|m| fill_before(m, &Fragment::empty(), true, 0)).transpose()?.flatten() else { return Ok(None) };
        Ok(Some(Node::new(ty, Rc::new(attrs), content.append(&after), mark_set_from(marks))))
    }

    pub fn ty(&self) -> TypeId {
        self.0.ty
    }
    pub fn attrs(&self) -> &Rc<Map> {
        &self.0.attrs
    }
    pub fn attr(&self, name: &str) -> &Value {
        self.0.attrs.get(name).unwrap_or(&Value::Null)
    }
    pub fn content(&self) -> &Fragment {
        &self.0.content
    }
    pub fn marks(&self) -> &[Mark] {
        &self.0.marks
    }
    /// Text as UTF-16 code units.
    pub fn text_units(&self) -> Option<&[u16]> {
        self.0.text.as_ref().map(|t| &*t.units)
    }
    /// The text, when it is valid Unicode (a cut can split a surrogate pair).
    pub fn text(&self) -> Option<&str> {
        self.0.text.as_ref().and_then(|t| t.string.as_deref())
    }
    /// The text with any split surrogate replaced, for display only.
    pub fn text_lossy(&self) -> Option<String> {
        self.0.text.as_ref().map(|t| t.string.as_deref().map_or_else(|| String::from_utf16_lossy(&t.units), str::to_owned))
    }
    pub fn node_size(&self) -> usize {
        self.0.size
    }
    pub fn type_name(&self) -> &'static str {
        &schema().nodes[self.0.ty].name
    }
    pub fn is_text(&self) -> bool {
        self.0.text.is_some()
    }
    pub fn text_valid(&self) -> bool {
        self.0.text.as_ref().is_none_or(|t| t.string.is_some())
    }
    pub fn is_leaf(&self) -> bool {
        schema().is_leaf(self.0.ty)
    }
    pub fn is_atom(&self) -> bool {
        schema().is_atom(self.0.ty)
    }
    pub fn is_inline(&self) -> bool {
        schema().nodes[self.0.ty].is_inline
    }
    pub fn is_block(&self) -> bool {
        !self.is_inline()
    }
    pub fn is_textblock(&self) -> bool {
        schema().is_textblock(self.0.ty)
    }
    pub fn inline_content(&self) -> bool {
        schema().inline_content(self.0.ty)
    }
    pub fn child_count(&self) -> usize {
        self.0.content.child_count()
    }
    pub fn child(&self, index: usize) -> &Node {
        self.0.content.child(index)
    }
    pub fn maybe_child(&self, index: usize) -> Option<&Node> {
        self.0.content.maybe_child(index)
    }
    pub fn first_child(&self) -> Option<&Node> {
        self.0.content.first_child()
    }
    pub fn last_child(&self) -> Option<&Node> {
        self.0.content.last_child()
    }
    pub fn ptr_eq(&self, other: &Node) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }

    pub fn same_markup(&self, other: &Node) -> bool {
        self.has_markup(other.ty(), Some(other.attrs()), other.marks())
    }

    pub fn has_markup(&self, ty: TypeId, attrs: Option<&Map>, marks: &[Mark]) -> bool {
        let empty = Map::new();
        let expected = attrs.or(schema().default_attrs(ty)).unwrap_or(&empty);
        self.ty() == ty && compare_attrs(self.attrs(), expected) && same_mark_set(self.marks(), marks)
    }

    pub fn eq(&self, other: &Node) -> bool {
        if self.ptr_eq(other) {
            return true;
        }
        match self.text_units() {
            Some(a) => self.same_markup(other) && Some(a) == other.text_units(),
            None => self.same_markup(other) && self.content().eq(other.content()),
        }
    }

    pub fn copy(&self, content: Fragment) -> Node {
        if content.ptr_eq(self.content()) {
            return self.clone();
        }
        let size = if self.is_leaf() { 1 } else { content.size + 2 };
        Node(Rc::new(NodeData { ty: self.0.ty, attrs: self.0.attrs.clone(), size, content, marks: self.0.marks.clone(), text: None }))
    }

    pub fn mark(&self, marks: Vec<Mark>) -> Node {
        Node(Rc::new(NodeData {
            ty: self.0.ty,
            attrs: self.0.attrs.clone(),
            content: self.0.content.clone(),
            marks: marks.into(),
            text: self.0.text.clone(),
            size: self.0.size,
        }))
    }

    pub fn with_units(&self, units: Vec<u16>) -> Node {
        if self.text_units() == Some(&units[..]) {
            return self.clone();
        }
        Node(Rc::new(NodeData {
            ty: self.0.ty,
            attrs: self.0.attrs.clone(),
            content: Fragment::empty(),
            marks: self.0.marks.clone(),
            size: units.len(),
            text: Some(Text::from_units(units)),
        }))
    }

    /// This text node with `other`'s text appended.
    pub fn joined(&self, other: &Node) -> Node {
        let mut units = self.text_units().unwrap_or_default().to_vec();
        units.extend_from_slice(other.text_units().unwrap_or_default());
        self.with_units(units)
    }

    /// `Node.cut` / `TextNode.cut`.
    pub fn cut(&self, from: usize, to: Option<usize>) -> Result<Node> {
        if let Some(units) = self.text_units() {
            let to = to.unwrap_or(self.0.size).min(units.len());
            if from == 0 && to == self.0.size {
                return Ok(self.clone());
            }
            return Ok(self.with_units(units[from.min(to)..to].to_vec()));
        }
        let to = to.unwrap_or(self.content().size);
        if from == 0 && to == self.content().size {
            return Ok(self.clone());
        }
        Ok(self.copy(self.content().cut(from, Some(to))?))
    }

    pub fn slice(&self, from: usize, to: usize, include_parents: bool) -> Result<Slice> {
        if from == to {
            return Ok(Slice::empty());
        }
        let rf = self.resolve(from)?;
        let rt = self.resolve(to)?;
        let depth = if include_parents { 0 } else { rf.shared_depth(to) };
        let start = rf.start(depth);
        let node = rf.node(depth);
        let content = node.content().cut(rf.pos - start, Some(rt.pos - start))?;
        Ok(Slice::new(content, rf.depth - depth, rt.depth - depth))
    }

    pub fn replace(&self, from: usize, to: usize, slice: &Slice) -> Result<Node> {
        replace(&self.resolve(from)?, &self.resolve(to)?, slice)
    }

    pub fn node_at(&self, pos: usize) -> Option<Node> {
        let mut node = self.clone();
        let mut pos = pos;
        loop {
            let (index, offset) = node.content().find_index(pos).ok()?;
            let child = node.maybe_child(index)?.clone();
            if offset == pos || child.is_text() {
                return Some(child);
            }
            pos -= offset + 1;
            node = child;
        }
    }

    /// `childAfter`: (node, index, offset).
    pub fn child_after(&self, pos: usize) -> Result<(Option<Node>, usize, usize)> {
        let (index, offset) = self.content().find_index(pos)?;
        Ok((self.maybe_child(index).cloned(), index, offset))
    }

    pub fn child_before(&self, pos: usize) -> Result<(Option<Node>, usize, usize)> {
        if pos == 0 {
            return Ok((None, 0, 0));
        }
        let (index, offset) = self.content().find_index(pos)?;
        if offset < pos {
            return Ok((Some(self.child(index).clone()), index, offset));
        }
        let node = self.child(index - 1).clone();
        let size = node.node_size();
        Ok((Some(node), index - 1, offset - size))
    }

    pub fn resolve(&self, pos: usize) -> Result<ResolvedPos> {
        ResolvedPos::resolve(self, pos)
    }

    /// Calls `f(node, pos, parent, index)` for every node overlapping
    /// `from..to`; returning false skips a node's children.
    pub fn nodes_between(&self, from: usize, to: usize, f: &mut Visit<'_>, start: usize) {
        self.content().nodes_between(from, to, f, start, Some(self));
    }

    pub fn descendants(&self, f: &mut Visit<'_>) {
        self.nodes_between(0, self.content().size, f, 0);
    }

    pub fn text_content(&self) -> String {
        match self.text_lossy() {
            Some(text) => text,
            None => self.content().text_between(0, self.content().size, ""),
        }
    }

    pub fn range_has_mark(&self, from: usize, to: usize, mark: &dyn Fn(&Mark) -> bool) -> bool {
        let mut found = false;
        if to > from {
            self.nodes_between(
                from,
                to,
                &mut |node, _, _, _| {
                    if node.marks().iter().any(mark) {
                        found = true;
                    }
                    !found
                },
                0,
            );
        }
        found
    }

    pub fn content_match_at(&self, index: usize) -> Result<MatchId> {
        match match_fragment(schema().nodes[self.ty()].content, self.content(), 0, index) {
            Some(matched) => Ok(matched),
            None => bail!("Called contentMatchAt on a node with invalid content"),
        }
    }

    pub fn can_replace(&self, from: usize, to: usize, replacement: &Fragment, start: usize, end: usize) -> Result<bool> {
        let schema = schema();
        let one = match_fragment(self.content_match_at(from)?, replacement, start, end);
        let two = one.and_then(|one| match_fragment(one, self.content(), to, self.child_count()));
        if !two.is_some_and(|two| schema.valid_end(two)) {
            return Ok(false);
        }
        Ok((start..end).all(|i| allows_marks(self.ty(), replacement.child(i).marks())))
    }

    pub fn can_replace_with(&self, from: usize, to: usize, ty: TypeId, marks: Option<&[Mark]>) -> Result<bool> {
        if marks.is_some_and(|marks| !allows_marks(self.ty(), marks)) {
            return Ok(false);
        }
        let schema = schema();
        let start = schema.match_type(self.content_match_at(from)?, ty);
        let end = start.and_then(|start| match_fragment(start, self.content(), to, self.child_count()));
        Ok(end.is_some_and(|end| schema.valid_end(end)))
    }

    pub fn can_append(&self, other: &Node) -> Result<bool> {
        if other.content().size > 0 {
            self.can_replace(self.child_count(), self.child_count(), other.content(), 0, other.child_count())
        } else {
            Ok(schema().compatible_content(self.ty(), other.ty()))
        }
    }

    /// `Node.check`.
    pub fn check(&self) -> Result<()> {
        let schema = schema();
        let name = &schema.nodes[self.ty()].name;
        if !self.text_valid() {
            bail!("A text node splits a Unicode surrogate pair");
        }
        if !valid_content(self.ty(), self.content()) {
            bail!("Invalid content for node {name}");
        }
        for key in self.attrs().keys() {
            if !schema.has_attr(self.ty(), key) {
                bail!("Unsupported attribute {key} for node of type {name}");
            }
        }
        let mut copy: Vec<Mark> = Vec::new();
        for mark in self.marks() {
            for key in mark.attrs.keys() {
                if !schema.mark_has_attr(mark.ty, key) {
                    bail!("Unsupported attribute {key} for mark of type {}", schema.marks[mark.ty].name);
                }
            }
            copy = mark.add_to_set(&copy);
        }
        if !same_mark_set(&copy, self.marks()) {
            bail!("Invalid collection of marks for node {name}");
        }
        self.content().iter().try_for_each(Node::check)
    }

    pub fn to_json(&self) -> Value {
        let mut object = Map::with_capacity(4);
        object.insert("type".into(), Value::String(self.type_name().to_owned()));
        if !self.attrs().is_empty() {
            object.insert("attrs".into(), Value::Object((**self.attrs()).clone()));
        }
        if self.content().size > 0 {
            object.insert("content".into(), self.content().to_json());
        }
        if !self.marks().is_empty() {
            object.insert("marks".into(), Value::Array(self.marks().iter().map(Mark::to_json).collect()));
        }
        if let Some(text) = self.text_lossy() {
            object.insert("text".into(), Value::String(text));
        }
        Value::Object(object)
    }

    /// `Node.fromJSON` (`schema.nodeFromJSON`).
    pub fn from_json(json: &Value) -> Result<Node> {
        if !json::truthy(Some(json)) {
            bail!("Invalid input for Node.fromJSON");
        }
        let marks = match json.get("marks") {
            Some(value) if json::truthy(Some(value)) => {
                let Some(items) = value.as_array() else { bail!("Invalid mark data for Node.fromJSON") };
                items.iter().map(Mark::from_json).collect::<Result<Vec<_>>>()?
            }
            _ => Vec::new(),
        };
        let name = json.get("type").and_then(Value::as_str).unwrap_or_default();
        if name == "text" {
            let Some(text) = json.get("text").and_then(Value::as_str) else { bail!("Invalid text node in JSON") };
            return Node::text_node(text, marks);
        }
        let content = Fragment::from_json(json.get("content"))?;
        let Some(ty) = schema().node_type(name) else { bail!("Unknown node type: {name}") };
        let attrs = match json.get("attrs") {
            Some(Value::Object(map)) => Some(map),
            Some(value) if json::truthy(Some(value)) => None,
            _ => None,
        };
        Node::create(ty, attrs, content, marks)
    }
}

/// `NodeType.validContent`.
pub fn valid_content(ty: TypeId, content: &Fragment) -> bool {
    let schema = schema();
    let Some(end) = match_fragment(schema.nodes[ty].content, content, 0, content.child_count()) else { return false };
    schema.valid_end(end) && content.iter().all(|child| allows_marks(ty, child.marks()))
}

pub fn allows_marks(ty: TypeId, marks: &[Mark]) -> bool {
    let schema = schema();
    marks.iter().all(|mark| schema.allows_mark(ty, mark.ty))
}

/// `NodeType.allowedMarks`.
pub fn allowed_marks(ty: TypeId, marks: &[Mark]) -> Vec<Mark> {
    let schema = schema();
    marks.iter().filter(|mark| schema.allows_mark(ty, mark.ty)).cloned().collect()
}

/// `ContentMatch.matchFragment(frag, start, end)`.
pub fn match_fragment(state: MatchId, fragment: &Fragment, start: usize, end: usize) -> Option<MatchId> {
    let schema = schema();
    let end = end.min(fragment.child_count());
    schema.match_types(state, (start.min(end)..end).map(|i| fragment.child(i).ty()))
}

/// `ContentMatch.fillBefore(after, toEnd, startIndex)`.
pub fn fill_before(state: MatchId, after: &Fragment, to_end: bool, start: usize) -> Result<Option<Fragment>> {
    let types: Vec<TypeId> = after.iter().skip(start).map(Node::ty).collect();
    let Some(fill) = schema().fill_before(state, &types, to_end) else { return Ok(None) };
    let nodes = fill
        .into_iter()
        .map(|ty| Node::create_and_fill(ty, None, Fragment::empty(), Vec::new()).map(|n| n.expect("generatable")))
        .collect::<Result<Vec<_>>>()?;
    Ok(Some(Fragment::from_array(nodes)))
}

#[derive(Clone)]
pub struct Fragment {
    nodes: Rc<Vec<Node>>,
    pub size: usize,
}

impl std::fmt::Debug for Fragment {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_list().entries(self.nodes.iter()).finish()
    }
}

impl Fragment {
    /// `Fragment.empty`, shared so identity checks hold as in JavaScript.
    pub fn empty() -> Fragment {
        thread_local! {
            static EMPTY: Rc<Vec<Node>> = Rc::new(Vec::new());
        }
        Fragment { nodes: EMPTY.with(Rc::clone), size: 0 }
    }

    fn with(nodes: Vec<Node>) -> Fragment {
        let size = nodes.iter().map(Node::node_size).sum();
        Fragment { nodes: Rc::new(nodes), size }
    }

    pub fn from_node(node: Node) -> Fragment {
        Fragment::with(vec![node])
    }

    /// `Fragment.fromArray`: adjacent text with the same marks joins.
    pub fn from_array(nodes: Vec<Node>) -> Fragment {
        let mut out: Vec<Node> = Vec::with_capacity(nodes.len());
        for node in nodes {
            if let Some(last) = out.last_mut()
                && node.is_text()
                && last.same_markup(&node)
            {
                *last = last.joined(&node);
                continue;
            }
            out.push(node);
        }
        Fragment::with(out)
    }

    pub fn from_json(value: Option<&Value>) -> Result<Fragment> {
        match value {
            None => Ok(Fragment::empty()),
            Some(value) if !json::truthy(Some(value)) => Ok(Fragment::empty()),
            Some(Value::Array(items)) => Ok(Fragment::from_array(items.iter().map(Node::from_json).collect::<Result<Vec<_>>>()?)),
            Some(_) => bail!("Invalid input for Fragment.fromJSON"),
        }
    }

    pub fn to_json(&self) -> Value {
        if self.nodes.is_empty() { Value::Null } else { Value::Array(self.nodes.iter().map(Node::to_json).collect()) }
    }

    pub fn ptr_eq(&self, other: &Fragment) -> bool {
        Rc::ptr_eq(&self.nodes, &other.nodes)
    }

    pub fn iter(&self) -> std::slice::Iter<'_, Node> {
        self.nodes.iter()
    }

    pub fn nodes(&self) -> &[Node] {
        &self.nodes
    }

    pub fn child_count(&self) -> usize {
        self.nodes.len()
    }

    pub fn child(&self, index: usize) -> &Node {
        &self.nodes[index]
    }

    pub fn maybe_child(&self, index: usize) -> Option<&Node> {
        self.nodes.get(index)
    }

    pub fn first_child(&self) -> Option<&Node> {
        self.nodes.first()
    }

    pub fn last_child(&self) -> Option<&Node> {
        self.nodes.last()
    }

    pub fn eq(&self, other: &Fragment) -> bool {
        self.nodes.len() == other.nodes.len() && self.nodes.iter().zip(other.nodes.iter()).all(|(a, b)| a.eq(b))
    }

    pub fn nodes_between(&self, from: usize, to: usize, f: &mut Visit<'_>, node_start: usize, parent: Option<&Node>) {
        let mut pos = 0;
        for (i, child) in self.nodes.iter().enumerate() {
            if pos >= to {
                break;
            }
            let end = pos + child.node_size();
            if end > from && f(child, node_start + pos, parent, i) && child.content().size > 0 {
                let start = pos + 1;
                child.content().nodes_between(
                    from.saturating_sub(start),
                    child.content().size.min(to.saturating_sub(start)),
                    f,
                    node_start + start,
                    Some(child),
                );
            }
            pos = end;
        }
    }

    pub fn descendants(&self, f: &mut Visit<'_>) {
        self.nodes_between(0, self.size, f, 0, None);
    }

    pub fn text_between(&self, from: usize, to: usize, block_separator: &str) -> String {
        let mut text = String::new();
        let mut first = true;
        self.nodes_between(
            from,
            to,
            &mut |node, pos, _, _| {
                let node_text = match node.text_units() {
                    Some(units) => String::from_utf16_lossy(&units[(from.max(pos) - pos).min(units.len())..(to - pos).min(units.len())]),
                    None => String::new(),
                };
                if node.is_block() && node.is_textblock() && !block_separator.is_empty() {
                    if first {
                        first = false;
                    } else {
                        text.push_str(block_separator);
                    }
                }
                text.push_str(&node_text);
                true
            },
            0,
            None,
        );
        text
    }

    pub fn append(&self, other: &Fragment) -> Fragment {
        if other.size == 0 {
            return self.clone();
        }
        if self.size == 0 {
            return other.clone();
        }
        let mut content = (*self.nodes).clone();
        let last = content.last().expect("last").clone();
        let first = other.first_child().expect("first");
        let mut start = 0;
        if last.is_text() && last.same_markup(first) {
            let len = content.len();
            content[len - 1] = last.joined(first);
            start = 1;
        }
        content.extend(other.nodes[start..].iter().cloned());
        Fragment { nodes: Rc::new(content), size: self.size + other.size }
    }

    pub fn cut(&self, from: usize, to: Option<usize>) -> Result<Fragment> {
        let to = to.unwrap_or(self.size);
        if from == 0 && to == self.size {
            return Ok(self.clone());
        }
        let mut result = Vec::new();
        let mut size = 0;
        if to > from {
            let mut pos = 0;
            for child in self.nodes.iter() {
                if pos >= to {
                    break;
                }
                let end = pos + child.node_size();
                if end > from {
                    let mut child = child.clone();
                    if pos < from || end > to {
                        child = if let Some(units) = child.text_units() {
                            let len = units.len();
                            child.cut(from.saturating_sub(pos), Some(len.min(to - pos)))?
                        } else {
                            child.cut(from.saturating_sub(pos + 1), Some(child.content().size.min(to.saturating_sub(pos + 1))))?
                        };
                    }
                    size += child.node_size();
                    result.push(child);
                }
                pos = end;
            }
        }
        Ok(Fragment { nodes: Rc::new(result), size })
    }

    pub fn cut_by_index(&self, from: usize, to: usize) -> Fragment {
        if from == to {
            return Fragment::empty();
        }
        if from == 0 && to == self.nodes.len() {
            return self.clone();
        }
        Fragment::with(self.nodes[from..to].to_vec())
    }

    pub fn replace_child(&self, index: usize, node: Node) -> Fragment {
        let current = &self.nodes[index];
        if current.ptr_eq(&node) {
            return self.clone();
        }
        let size = self.size + node.node_size() - current.node_size();
        let mut copy = (*self.nodes).clone();
        copy[index] = node;
        Fragment { nodes: Rc::new(copy), size }
    }

    pub fn add_to_start(&self, node: Node) -> Fragment {
        let size = self.size + node.node_size();
        let mut copy = Vec::with_capacity(self.nodes.len() + 1);
        copy.push(node);
        copy.extend(self.nodes.iter().cloned());
        Fragment { nodes: Rc::new(copy), size }
    }

    pub fn add_to_end(&self, node: Node) -> Fragment {
        let size = self.size + node.node_size();
        let mut copy = (*self.nodes).clone();
        copy.push(node);
        Fragment { nodes: Rc::new(copy), size }
    }

    /// `findIndex`: (index, offset).
    pub fn find_index(&self, pos: usize) -> Result<(usize, usize)> {
        if pos == 0 {
            return Ok((0, pos));
        }
        if pos == self.size {
            return Ok((self.nodes.len(), pos));
        }
        if pos > self.size {
            bail!("Position {pos} outside of fragment");
        }
        let mut cur = 0;
        for (i, child) in self.nodes.iter().enumerate() {
            let end = cur + child.node_size();
            if end >= pos {
                if end == pos {
                    return Ok((i + 1, end));
                }
                return Ok((i, cur));
            }
            cur = end;
        }
        unreachable!("position inside the fragment")
    }
}

#[derive(Clone, Debug)]
pub struct Slice {
    pub content: Fragment,
    pub open_start: usize,
    pub open_end: usize,
}

impl Slice {
    pub fn new(content: Fragment, open_start: usize, open_end: usize) -> Slice {
        Slice { content, open_start, open_end }
    }

    pub fn empty() -> Slice {
        Slice::new(Fragment::empty(), 0, 0)
    }

    pub fn size(&self) -> isize {
        self.content.size as isize - self.open_start as isize - self.open_end as isize
    }

    pub fn eq(&self, other: &Slice) -> bool {
        self.content.eq(&other.content) && self.open_start == other.open_start && self.open_end == other.open_end
    }

    pub fn insert_at(&self, pos: usize, fragment: &Fragment) -> Result<Option<Slice>> {
        let content = insert_into(&self.content, pos + self.open_start, fragment, self.open_start as isize + 1, self.open_end as isize + 1, None)?;
        Ok(content.map(|content| Slice::new(content, self.open_start, self.open_end)))
    }

    pub fn remove_between(&self, from: usize, to: usize) -> Result<Slice> {
        Ok(Slice::new(remove_range(&self.content, from + self.open_start, to + self.open_start)?, self.open_start, self.open_end))
    }

    pub fn to_json(&self) -> Value {
        if self.content.size == 0 {
            return Value::Null;
        }
        let mut object = Map::new();
        object.insert("content".into(), self.content.to_json());
        if self.open_start > 0 {
            object.insert("openStart".into(), self.open_start.into());
        }
        if self.open_end > 0 {
            object.insert("openEnd".into(), self.open_end.into());
        }
        Value::Object(object)
    }

    pub fn from_json(json: Option<&Value>) -> Result<Slice> {
        let Some(json) = json.filter(|j| json::truthy(Some(j))) else { return Ok(Slice::empty()) };
        let depth = |key: &str| -> Result<usize> {
            match json.get(key) {
                None | Some(Value::Null) => Ok(0),
                Some(value) if !json::truthy(Some(value)) => Ok(0),
                Some(Value::Number(n)) => match n.as_u64() {
                    Some(n) => Ok(n as usize),
                    None => bail!("Invalid input for Slice.fromJSON"),
                },
                Some(_) => bail!("Invalid input for Slice.fromJSON"),
            }
        };
        Ok(Slice::new(Fragment::from_json(json.get("content"))?, depth("openStart")?, depth("openEnd")?))
    }

    /// `Slice.maxOpen`.
    pub fn max_open(fragment: Fragment, open_isolating: bool) -> Slice {
        let schema = schema();
        let depth = |first: bool| {
            let mut depth = 0;
            let mut current = if first { fragment.first_child() } else { fragment.last_child() };
            while let Some(node) = current {
                if node.is_leaf() || (!open_isolating && schema.nodes[node.ty()].isolating) {
                    break;
                }
                depth += 1;
                current = if first { node.first_child() } else { node.last_child() };
            }
            depth
        };
        let (start, end) = (depth(true), depth(false));
        Slice::new(fragment, start, end)
    }
}

fn remove_range(content: &Fragment, from: usize, to: usize) -> Result<Fragment> {
    let (index, offset) = content.find_index(from)?;
    let child = content.maybe_child(index).cloned();
    let (index_to, offset_to) = content.find_index(to)?;
    if offset == from || child.as_ref().is_some_and(Node::is_text) {
        if offset_to != to && !content.child(index_to).is_text() {
            bail!("Removing non-flat range");
        }
        return Ok(content.cut(0, Some(from))?.append(&content.cut(to, None)?));
    }
    if index != index_to {
        bail!("Removing non-flat range");
    }
    let child = child.expect("child");
    Ok(content.replace_child(index, child.copy(remove_range(child.content(), from - offset - 1, to - offset - 1)?)))
}

fn insert_into(content: &Fragment, dist: usize, insert: &Fragment, open_start: isize, open_end: isize, parent: Option<&Node>) -> Result<Option<Fragment>> {
    let (index, offset) = content.find_index(dist)?;
    let child = content.maybe_child(index).cloned();
    if offset == dist || child.as_ref().is_some_and(Node::is_text) {
        if let Some(parent) = parent
            && open_start <= 0
            && open_end <= 0
            && !parent.can_replace(index, index, insert, 0, insert.child_count())?
        {
            return Ok(None);
        }
        return Ok(Some(content.cut(0, Some(dist))?.append(insert).append(&content.cut(dist, None)?)));
    }
    let child = child.expect("child");
    let inner = insert_into(
        child.content(),
        dist - offset - 1,
        insert,
        if index == 0 { open_start - 1 } else { 0 },
        if index + 1 == content.child_count() { open_end - 1 } else { 0 },
        Some(&child),
    )?;
    Ok(inner.map(|inner| content.replace_child(index, child.copy(inner))))
}

#[derive(Clone)]
pub struct ResolvedPos {
    pub pos: usize,
    /// (node, index, offset) per depth.
    path: Vec<(Node, usize, usize)>,
    pub parent_offset: usize,
    pub depth: usize,
}

impl std::fmt::Debug for ResolvedPos {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ResolvedPos({})", self.pos)
    }
}

impl ResolvedPos {
    pub fn resolve(doc: &Node, pos: usize) -> Result<ResolvedPos> {
        if pos > doc.content().size {
            return Err(Error::new(format!("Position {pos} out of range")));
        }
        let mut path = Vec::new();
        let mut start = 0;
        let mut parent_offset = pos;
        let mut node = doc.clone();
        loop {
            let (index, offset) = node.content().find_index(parent_offset)?;
            let rem = parent_offset - offset;
            path.push((node.clone(), index, start + offset));
            if rem == 0 {
                break;
            }
            let child = node.child(index).clone();
            if child.is_text() {
                break;
            }
            parent_offset = rem - 1;
            start += offset + 1;
            node = child;
        }
        let depth = path.len() - 1;
        Ok(ResolvedPos { pos, path, parent_offset, depth })
    }

    fn resolve_depth(&self, depth: isize) -> usize {
        if depth < 0 { (self.depth as isize + depth) as usize } else { depth as usize }
    }

    pub fn node(&self, depth: usize) -> &Node {
        &self.path[depth].0
    }
    /// `node(-n)`.
    pub fn node_rel(&self, depth: isize) -> &Node {
        &self.path[self.resolve_depth(depth)].0
    }
    pub fn parent(&self) -> &Node {
        &self.path[self.depth].0
    }
    pub fn doc(&self) -> &Node {
        &self.path[0].0
    }
    pub fn index(&self, depth: usize) -> usize {
        self.path[depth].1
    }
    pub fn index_here(&self) -> usize {
        self.path[self.depth].1
    }
    pub fn index_after(&self, depth: usize) -> usize {
        self.index(depth) + if depth == self.depth && self.text_offset() == 0 { 0 } else { 1 }
    }
    pub fn start(&self, depth: usize) -> usize {
        if depth == 0 { 0 } else { self.path[depth - 1].2 + 1 }
    }
    pub fn end(&self, depth: usize) -> usize {
        self.start(depth) + self.node(depth).content().size
    }
    pub fn before(&self, depth: usize) -> Result<usize> {
        if depth == 0 {
            bail!("There is no position before the top-level node");
        }
        Ok(if depth == self.depth + 1 { self.pos } else { self.path[depth - 1].2 })
    }
    pub fn after(&self, depth: usize) -> Result<usize> {
        if depth == 0 {
            bail!("There is no position after the top-level node");
        }
        Ok(if depth == self.depth + 1 { self.pos } else { self.path[depth - 1].2 + self.path[depth].0.node_size() })
    }
    pub fn text_offset(&self) -> usize {
        self.pos - self.path[self.depth].2
    }
    pub fn node_after(&self) -> Option<Node> {
        let parent = self.parent();
        let index = self.index_here();
        if index == parent.child_count() {
            return None;
        }
        let d_off = self.text_offset();
        let child = parent.child(index);
        if d_off > 0 { child.cut(d_off, None).ok() } else { Some(child.clone()) }
    }
    pub fn node_before(&self) -> Option<Node> {
        let index = self.index_here();
        let d_off = self.text_offset();
        if d_off > 0 {
            return self.parent().child(index).cut(0, Some(d_off)).ok();
        }
        if index == 0 { None } else { Some(self.parent().child(index - 1).clone()) }
    }
    pub fn pos_at_index(&self, index: usize, depth: usize) -> usize {
        let node = self.node(depth);
        let mut pos = if depth == 0 { 0 } else { self.path[depth - 1].2 + 1 };
        for i in 0..index {
            pos += node.child(i).node_size();
        }
        pos
    }

    /// `ResolvedPos.marks()`.
    pub fn marks(&self) -> Vec<Mark> {
        let schema = schema();
        let parent = self.parent();
        let index = self.index_here();
        if parent.content().size == 0 {
            return Vec::new();
        }
        if self.text_offset() > 0 {
            return parent.child(index).marks().to_vec();
        }
        let mut main = index.checked_sub(1).and_then(|i| parent.maybe_child(i));
        let mut other = parent.maybe_child(index);
        if main.is_none() {
            std::mem::swap(&mut main, &mut other);
        }
        let mut marks = main.expect("a child").marks().to_vec();
        let mut i = 0;
        while i < marks.len() {
            if schema.marks[marks[i].ty].not_inclusive && other.is_none_or(|o| !marks[i].is_in_set(o.marks())) {
                marks = marks[i].remove_from_set(&marks);
            } else {
                i += 1;
            }
        }
        marks
    }

    pub fn marks_across(&self, end: &ResolvedPos) -> Option<Vec<Mark>> {
        let schema = schema();
        let after = self.parent().maybe_child(self.index_here())?;
        if !after.is_inline() {
            return None;
        }
        let next = end.parent().maybe_child(end.index_here());
        let mut marks = after.marks().to_vec();
        let mut i = 0;
        while i < marks.len() {
            if schema.marks[marks[i].ty].not_inclusive && next.is_none_or(|n| !marks[i].is_in_set(n.marks())) {
                marks = marks[i].remove_from_set(&marks);
            } else {
                i += 1;
            }
        }
        Some(marks)
    }

    pub fn shared_depth(&self, pos: usize) -> usize {
        for depth in (1..=self.depth).rev() {
            if self.start(depth) <= pos && self.end(depth) >= pos {
                return depth;
            }
        }
        0
    }

    pub fn block_range(&self, other: &ResolvedPos, pred: Option<&dyn Fn(&Node) -> bool>) -> Option<NodeRange> {
        if other.pos < self.pos {
            return other.block_range(self, pred);
        }
        let first = self.depth as isize - if self.parent().inline_content() || self.pos == other.pos { 1 } else { 0 };
        let mut d = first;
        while d >= 0 {
            let depth = d as usize;
            if other.pos <= self.end(depth) && pred.is_none_or(|p| p(self.node(depth))) {
                return Some(NodeRange { from: self.clone(), to: other.clone(), depth });
            }
            d -= 1;
        }
        None
    }

    pub fn same_parent(&self, other: &ResolvedPos) -> bool {
        self.pos - self.parent_offset == other.pos - other.parent_offset
    }

    pub fn max<'a>(&'a self, other: &'a ResolvedPos) -> &'a ResolvedPos {
        if other.pos > self.pos { other } else { self }
    }

    pub fn min<'a>(&'a self, other: &'a ResolvedPos) -> &'a ResolvedPos {
        if other.pos < self.pos { other } else { self }
    }
}

#[derive(Clone, Debug)]
pub struct NodeRange {
    pub from: ResolvedPos,
    pub to: ResolvedPos,
    pub depth: usize,
}

impl NodeRange {
    pub fn start(&self) -> usize {
        self.from.before(self.depth + 1).expect("range depth")
    }
    pub fn end(&self) -> usize {
        self.to.after(self.depth + 1).expect("range depth")
    }
    pub fn parent(&self) -> &Node {
        self.from.node(self.depth)
    }
    pub fn start_index(&self) -> usize {
        self.from.index(self.depth)
    }
    pub fn end_index(&self) -> usize {
        self.to.index_after(self.depth)
    }
}

// replace.ts

pub fn replace(from: &ResolvedPos, to: &ResolvedPos, slice: &Slice) -> Result<Node> {
    if slice.open_start > from.depth {
        bail!("Inserted content deeper than insertion position");
    }
    if from.depth as isize - slice.open_start as isize != to.depth as isize - slice.open_end as isize {
        bail!("Inconsistent open depths");
    }
    replace_outer(from, to, slice, 0)
}

fn replace_outer(from: &ResolvedPos, to: &ResolvedPos, slice: &Slice, depth: usize) -> Result<Node> {
    let index = from.index(depth);
    let node = from.node(depth);
    if index == to.index(depth) && depth < from.depth - slice.open_start {
        let inner = replace_outer(from, to, slice, depth + 1)?;
        Ok(node.copy(node.content().replace_child(index, inner)))
    } else if slice.content.size == 0 {
        close(node, replace_two_way(from, to, depth)?)
    } else if slice.open_start == 0 && slice.open_end == 0 && from.depth == depth && to.depth == depth {
        let parent = from.parent();
        let content = parent.content();
        close(parent, content.cut(0, Some(from.parent_offset))?.append(&slice.content).append(&content.cut(to.parent_offset, None)?))
    } else {
        let (start, end) = prepare_slice_for_replace(slice, from)?;
        close(node, replace_three_way(from, &start, &end, to, depth)?)
    }
}

fn check_join(main: &Node, sub: &Node) -> Result<()> {
    if !schema().compatible_content(sub.ty(), main.ty()) {
        bail!("Cannot join {} onto {}", sub.type_name(), main.type_name());
    }
    Ok(())
}

fn joinable(before: &ResolvedPos, after: &ResolvedPos, depth: usize) -> Result<Node> {
    let node = before.node(depth).clone();
    check_join(&node, after.node(depth))?;
    Ok(node)
}

fn add_node(child: Node, target: &mut Vec<Node>) {
    if let Some(last) = target.last_mut()
        && child.is_text()
        && child.same_markup(last)
    {
        *last = last.joined(&child);
        return;
    }
    target.push(child);
}

fn add_range(start: Option<&ResolvedPos>, end: Option<&ResolvedPos>, depth: usize, target: &mut Vec<Node>) {
    let node = end.or(start).expect("a position").node(depth);
    let mut start_index = 0;
    let end_index = end.map_or(node.child_count(), |e| e.index(depth));
    if let Some(start) = start {
        start_index = start.index(depth);
        if start.depth > depth {
            start_index += 1;
        } else if start.text_offset() > 0 {
            add_node(start.node_after().expect("node after"), target);
            start_index += 1;
        }
    }
    for i in start_index..end_index {
        add_node(node.child(i).clone(), target);
    }
    if let Some(end) = end
        && end.depth == depth
        && end.text_offset() > 0
    {
        add_node(end.node_before().expect("node before"), target);
    }
}

fn close(node: &Node, content: Fragment) -> Result<Node> {
    if !valid_content(node.ty(), &content) {
        bail!("Invalid content for node {}", node.type_name());
    }
    Ok(node.copy(content))
}

fn replace_three_way(from: &ResolvedPos, start: &ResolvedPos, end: &ResolvedPos, to: &ResolvedPos, depth: usize) -> Result<Fragment> {
    let open_start = if from.depth > depth { Some(joinable(from, start, depth + 1)?) } else { None };
    let open_end = if to.depth > depth { Some(joinable(end, to, depth + 1)?) } else { None };
    let mut content = Vec::new();
    add_range(None, Some(from), depth, &mut content);
    match (&open_start, &open_end) {
        (Some(os), Some(oe)) if start.index(depth) == end.index(depth) => {
            check_join(os, oe)?;
            add_node(close(os, replace_three_way(from, start, end, to, depth + 1)?)?, &mut content);
        }
        _ => {
            if let Some(os) = &open_start {
                add_node(close(os, replace_two_way(from, start, depth + 1)?)?, &mut content);
            }
            add_range(Some(start), Some(end), depth, &mut content);
            if let Some(oe) = &open_end {
                add_node(close(oe, replace_two_way(end, to, depth + 1)?)?, &mut content);
            }
        }
    }
    add_range(Some(to), None, depth, &mut content);
    Ok(Fragment::with(content))
}

fn replace_two_way(from: &ResolvedPos, to: &ResolvedPos, depth: usize) -> Result<Fragment> {
    let mut content = Vec::new();
    add_range(None, Some(from), depth, &mut content);
    if from.depth > depth {
        let ty = joinable(from, to, depth + 1)?;
        add_node(close(&ty, replace_two_way(from, to, depth + 1)?)?, &mut content);
    }
    add_range(Some(to), None, depth, &mut content);
    Ok(Fragment::with(content))
}

fn prepare_slice_for_replace(slice: &Slice, along: &ResolvedPos) -> Result<(ResolvedPos, ResolvedPos)> {
    let extra = along.depth - slice.open_start;
    let parent = along.node(extra);
    let mut node = parent.copy(slice.content.clone());
    for i in (0..extra).rev() {
        node = along.node(i).copy(Fragment::from_node(node));
    }
    let start = node.resolve(slice.open_start + extra)?;
    let end = node.resolve(node.content().size - slice.open_end - extra)?;
    Ok((start, end))
}

impl Schema {
    /// `schema.text`.
    pub fn text(&self, text: &str, marks: Vec<Mark>) -> Result<Node> {
        Node::text_node(text, marks)
    }
}
