//! A small mutable DOM built by html5ever: just what HTML import reads (element
//! names, ordered attributes, text, siblings) and the two edits it makes
//! (moving a nested list into its item, rewriting an attribute).

use std::borrow::Cow;
use std::cell::{Ref, RefCell};

use html5ever::interface::{ElementFlags, NodeOrText, QuirksMode, TreeSink};
use html5ever::tendril::{StrTendril, TendrilSink};
use html5ever::{Attribute, QualName, ns, parse_document};

/// A node in a [`Dom`].
pub type Id = usize;

#[derive(Debug, Clone, PartialEq)]
pub enum Kind {
    Document,
    Element,
    Text(String),
    /// Comments, processing instructions and doctypes: present, never content.
    Other,
}

#[derive(Debug, Clone)]
struct NodeData {
    kind: Kind,
    name: QualName,
    attrs: Vec<(String, String)>,
    parent: Option<Id>,
    children: Vec<Id>,
}

/// A parsed HTML document.
#[derive(Debug, Clone)]
pub struct Dom {
    nodes: Vec<NodeData>,
}

impl Dom {
    /// Parses a whole HTML document as a browser would.
    pub fn parse(html: &str) -> Self {
        let sink = Sink { nodes: RefCell::new(vec![blank(Kind::Document)]) };
        parse_document(sink, Default::default()).one(StrTendril::from(html))
    }

    pub fn document(&self) -> Id {
        0
    }

    pub fn kind(&self, id: Id) -> &Kind {
        &self.nodes[id].kind
    }

    pub fn is_element(&self, id: Id) -> bool {
        self.nodes[id].kind == Kind::Element
    }

    /// The lower-case local name of an element; empty for other nodes.
    pub fn name(&self, id: Id) -> &str {
        if self.is_element(id) { &self.nodes[id].name.local } else { "" }
    }

    /// Whether this is an element in the HTML namespace.
    pub fn is_html(&self, id: Id) -> bool {
        self.is_element(id) && self.nodes[id].name.ns == ns!(html)
    }

    pub fn attrs(&self, id: Id) -> &[(String, String)] {
        &self.nodes[id].attrs
    }

    pub fn attr(&self, id: Id, name: &str) -> Option<&str> {
        self.nodes[id].attrs.iter().find(|(key, _)| key == name).map(|(_, value)| value.as_str())
    }

    pub fn has_attr(&self, id: Id, name: &str) -> bool {
        self.attr(id, name).is_some()
    }

    pub fn set_attr(&mut self, id: Id, name: &str, value: &str) {
        let attrs = &mut self.nodes[id].attrs;
        match attrs.iter_mut().find(|(key, _)| key == name) {
            Some((_, existing)) => *existing = value.to_owned(),
            None => attrs.push((name.to_owned(), value.to_owned())),
        }
    }

    pub fn remove_attr(&mut self, id: Id, name: &str) {
        self.nodes[id].attrs.retain(|(key, _)| key != name);
    }

    pub fn children(&self, id: Id) -> &[Id] {
        &self.nodes[id].children
    }

    /// Element children only, as `Element.children`.
    pub fn element_children(&self, id: Id) -> Vec<Id> {
        self.children(id).iter().copied().filter(|&child| self.is_element(child)).collect()
    }

    pub fn parent(&self, id: Id) -> Option<Id> {
        self.nodes[id].parent
    }

    pub fn previous_sibling(&self, id: Id) -> Option<Id> {
        let siblings = self.children(self.parent(id)?);
        let index = siblings.iter().position(|&sibling| sibling == id)?;
        index.checked_sub(1).map(|before| siblings[before])
    }

    pub fn text(&self, id: Id) -> Option<&str> {
        match &self.nodes[id].kind {
            Kind::Text(text) => Some(text),
            _ => None,
        }
    }

    /// `Node.textContent` of an element or text node.
    pub fn text_content(&self, id: Id) -> String {
        let mut out = String::new();
        self.collect_text(id, &mut out);
        out
    }

    fn collect_text(&self, id: Id, out: &mut String) {
        match &self.nodes[id].kind {
            Kind::Text(text) => out.push_str(text),
            Kind::Element | Kind::Document => self.children(id).iter().for_each(|&child| self.collect_text(child, out)),
            Kind::Other => {}
        }
    }

    /// The first descendant element (document order) with this local name.
    pub fn find_descendant(&self, id: Id, name: &str) -> Option<Id> {
        self.descendants(id).into_iter().find(|&node| self.name(node) == name)
    }

    /// Every descendant element in document order.
    pub fn descendants(&self, id: Id) -> Vec<Id> {
        let mut out = Vec::new();
        let mut stack: Vec<Id> = self.children(id).iter().rev().copied().collect();
        while let Some(node) = stack.pop() {
            if self.is_element(node) {
                out.push(node);
                stack.extend(self.children(node).iter().rev());
            }
        }
        out
    }

    /// Moves `child` to the end of `parent`'s children.
    pub fn append_child(&mut self, parent: Id, child: Id) {
        self.detach(child);
        self.nodes[child].parent = Some(parent);
        self.nodes[parent].children.push(child);
    }

    fn detach(&mut self, id: Id) {
        if let Some(parent) = self.nodes[id].parent.take() {
            self.nodes[parent].children.retain(|&child| child != id);
        }
    }

    /// Adds a detached text node (for PM's synthetic `<br>` newline).
    pub fn create_text(&mut self, text: &str) -> Id {
        self.nodes.push(blank(Kind::Text(text.to_owned())));
        self.nodes.len() - 1
    }
}

fn blank(kind: Kind) -> NodeData {
    NodeData { kind, name: QualName::new(None, ns!(), "".into()), attrs: Vec::new(), parent: None, children: Vec::new() }
}

struct Sink {
    nodes: RefCell<Vec<NodeData>>,
}

impl Sink {
    fn push(&self, data: NodeData) -> Id {
        let mut nodes = self.nodes.borrow_mut();
        nodes.push(data);
        nodes.len() - 1
    }

    fn detach(&self, id: Id) {
        let mut nodes = self.nodes.borrow_mut();
        if let Some(parent) = nodes[id].parent.take() {
            nodes[parent].children.retain(|&child| child != id);
        }
    }

    /// Inserts at `index` of `parent`, merging text into an adjacent text node.
    fn insert(&self, parent: Id, index: usize, child: NodeOrText<Id>) {
        match child {
            NodeOrText::AppendText(text) => {
                let mut nodes = self.nodes.borrow_mut();
                if let Some(&before) = index.checked_sub(1).and_then(|i| nodes[parent].children.get(i))
                    && let Kind::Text(existing) = &mut nodes[before].kind
                {
                    existing.push_str(&text);
                    return;
                }
                drop(nodes);
                let id = self.push(blank(Kind::Text(text.to_string())));
                let mut nodes = self.nodes.borrow_mut();
                nodes[id].parent = Some(parent);
                nodes[parent].children.insert(index, id);
            }
            NodeOrText::AppendNode(id) => {
                self.detach(id);
                let mut nodes = self.nodes.borrow_mut();
                let index = index.min(nodes[parent].children.len());
                nodes[id].parent = Some(parent);
                nodes[parent].children.insert(index, id);
            }
        }
    }
}

impl TreeSink for Sink {
    type Handle = Id;
    type Output = Dom;
    type ElemName<'a> = Ref<'a, QualName>;

    fn finish(self) -> Dom {
        Dom { nodes: self.nodes.into_inner() }
    }

    fn parse_error(&self, _message: Cow<'static, str>) {}

    fn get_document(&self) -> Id {
        0
    }

    fn elem_name<'a>(&'a self, target: &'a Id) -> Ref<'a, QualName> {
        Ref::map(self.nodes.borrow(), |nodes| &nodes[*target].name)
    }

    fn create_element(&self, name: QualName, attrs: Vec<Attribute>, _flags: ElementFlags) -> Id {
        let attrs = attrs.into_iter().map(|attribute| (attribute.name.local.to_string(), attribute.value.to_string())).collect();
        self.push(NodeData { kind: Kind::Element, name, attrs, parent: None, children: Vec::new() })
    }

    fn create_comment(&self, _text: StrTendril) -> Id {
        self.push(blank(Kind::Other))
    }

    fn create_pi(&self, _target: StrTendril, _data: StrTendril) -> Id {
        self.push(blank(Kind::Other))
    }

    fn append(&self, parent: &Id, child: NodeOrText<Id>) {
        let index = self.nodes.borrow()[*parent].children.len();
        self.insert(*parent, index, child);
    }

    fn append_based_on_parent_node(&self, element: &Id, prev_element: &Id, child: NodeOrText<Id>) {
        if self.nodes.borrow()[*element].parent.is_some() {
            self.append_before_sibling(element, child);
        } else {
            self.append(prev_element, child);
        }
    }

    fn append_doctype_to_document(&self, _name: StrTendril, _public_id: StrTendril, _system_id: StrTendril) {
        let id = self.push(blank(Kind::Other));
        self.append(&0, NodeOrText::AppendNode(id));
    }

    fn get_template_contents(&self, target: &Id) -> Id {
        *target
    }

    fn same_node(&self, x: &Id, y: &Id) -> bool {
        x == y
    }

    fn set_quirks_mode(&self, _mode: QuirksMode) {}

    fn append_before_sibling(&self, sibling: &Id, new_node: NodeOrText<Id>) {
        let (parent, index) = {
            let nodes = self.nodes.borrow();
            let parent = nodes[*sibling].parent.expect("sibling has a parent");
            (parent, nodes[parent].children.iter().position(|child| child == sibling).expect("sibling is a child"))
        };
        self.insert(parent, index, new_node);
    }

    fn add_attrs_if_missing(&self, target: &Id, attrs: Vec<Attribute>) {
        let mut nodes = self.nodes.borrow_mut();
        let existing = &mut nodes[*target].attrs;
        for attribute in attrs {
            let name = attribute.name.local.to_string();
            if !existing.iter().any(|(key, _)| *key == name) {
                existing.push((name, attribute.value.to_string()));
            }
        }
    }

    fn remove_from_parent(&self, target: &Id) {
        self.detach(*target);
    }

    fn reparent_children(&self, node: &Id, new_parent: &Id) {
        let children = std::mem::take(&mut self.nodes.borrow_mut()[*node].children);
        let mut nodes = self.nodes.borrow_mut();
        for child in &children {
            nodes[*child].parent = Some(*new_parent);
        }
        nodes[*new_parent].children.extend(children);
    }
}
