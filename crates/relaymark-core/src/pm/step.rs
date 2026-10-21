//! prosemirror-transform 1.12's position maps and steps.

use std::rc::Rc;

use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};

use super::model::{Fragment, Mark, Node, Slice, replace};
use super::schema::schema;

const DEL_BEFORE: u8 = 1;
const DEL_AFTER: u8 = 2;
const DEL_ACROSS: u8 = 4;
const DEL_SIDE: u8 = 8;

#[derive(Debug, Clone, Copy)]
pub struct MapResult {
    pub pos: usize,
    del_info: u8,
    recover: Option<(usize, usize)>,
}

impl MapResult {
    pub fn deleted(&self) -> bool {
        self.del_info & DEL_SIDE > 0
    }
    pub fn deleted_before(&self) -> bool {
        self.del_info & (DEL_BEFORE | DEL_ACROSS) > 0
    }
    pub fn deleted_after(&self) -> bool {
        self.del_info & (DEL_AFTER | DEL_ACROSS) > 0
    }
    pub fn deleted_across(&self) -> bool {
        self.del_info & DEL_ACROSS > 0
    }
}

/// `StepMap`: (start, old size, new size) triples.
#[derive(Debug, Clone, Default)]
pub struct StepMap {
    pub ranges: Vec<usize>,
    pub inverted: bool,
}

impl StepMap {
    pub fn new(ranges: Vec<usize>) -> StepMap {
        StepMap { ranges, inverted: false }
    }

    pub fn empty() -> StepMap {
        StepMap::default()
    }

    fn recover(&self, (index, offset): (usize, usize)) -> usize {
        let mut diff: isize = 0;
        if !self.inverted {
            for i in 0..index {
                diff += self.ranges[i * 3 + 2] as isize - self.ranges[i * 3 + 1] as isize;
            }
        }
        (self.ranges[index * 3] as isize + diff + offset as isize) as usize
    }

    pub fn map(&self, pos: usize, assoc: i8) -> usize {
        self.map_inner(pos, assoc).pos
    }

    pub fn map_result(&self, pos: usize, assoc: i8) -> MapResult {
        self.map_inner(pos, assoc)
    }

    fn map_inner(&self, pos: usize, assoc: i8) -> MapResult {
        let mut diff: isize = 0;
        let (old_index, new_index) = if self.inverted { (2, 1) } else { (1, 2) };
        let mut i = 0;
        while i < self.ranges.len() {
            let start = self.ranges[i] as isize - if self.inverted { diff } else { 0 };
            if start > pos as isize {
                break;
            }
            let old_size = self.ranges[i + old_index] as isize;
            let new_size = self.ranges[i + new_index] as isize;
            let end = start + old_size;
            let p = pos as isize;
            if p <= end {
                let side = if old_size == 0 {
                    assoc
                } else if p == start {
                    -1
                } else if p == end {
                    1
                } else {
                    assoc
                };
                let result = start + diff + if side < 0 { 0 } else { new_size };
                let recover = if p == (if assoc < 0 { start } else { end }) { None } else { Some((i / 3, (p - start) as usize)) };
                let mut del = 0;
                if old_size > 0 {
                    del |= if p == start {
                        DEL_AFTER
                    } else if p == end {
                        DEL_BEFORE
                    } else {
                        DEL_ACROSS
                    };
                    if if assoc < 0 { p != start } else { p != end } {
                        del |= DEL_SIDE;
                    }
                }
                return MapResult { pos: result as usize, del_info: del, recover };
            }
            diff += new_size - old_size;
            i += 3;
        }
        MapResult { pos: (pos as isize + diff) as usize, del_info: 0, recover: None }
    }

    /// `forEach(oldStart, oldEnd, newStart, newEnd)`.
    pub fn for_each(&self, f: &mut dyn FnMut(usize, usize, usize, usize)) {
        let (old_index, new_index) = if self.inverted { (2, 1) } else { (1, 2) };
        let mut diff: isize = 0;
        let mut i = 0;
        while i < self.ranges.len() {
            let start = self.ranges[i] as isize;
            let old_start = start - if self.inverted { diff } else { 0 };
            let new_start = start + if self.inverted { 0 } else { diff };
            let old_size = self.ranges[i + old_index] as isize;
            let new_size = self.ranges[i + new_index] as isize;
            f(old_start as usize, (old_start + old_size) as usize, new_start as usize, (new_start + new_size) as usize);
            diff += new_size - old_size;
            i += 3;
        }
    }

    pub fn invert(&self) -> StepMap {
        StepMap { ranges: self.ranges.clone(), inverted: !self.inverted }
    }
}

/// `Mapping`, with mirrors.
#[derive(Debug, Clone, Default)]
pub struct Mapping {
    pub maps: Vec<StepMap>,
    mirror: Vec<usize>,
    pub from: usize,
    pub to: usize,
}

impl Mapping {
    pub fn new() -> Mapping {
        Mapping::default()
    }

    pub fn slice(&self, from: usize, to: usize) -> Mapping {
        Mapping { maps: self.maps.clone(), mirror: self.mirror.clone(), from, to }
    }

    pub fn append_map(&mut self, map: StepMap, mirrors: Option<usize>) {
        self.maps.push(map);
        self.to = self.maps.len();
        if let Some(m) = mirrors {
            let n = self.maps.len() - 1;
            self.set_mirror(n, m);
        }
    }

    pub fn append_mapping(&mut self, mapping: &Mapping) {
        let start_size = self.maps.len();
        for (i, map) in mapping.maps.iter().enumerate() {
            let mirr = mapping.get_mirror(i);
            self.append_map(map.clone(), mirr.filter(|&m| m < i).map(|m| start_size + m));
        }
    }

    pub fn get_mirror(&self, n: usize) -> Option<usize> {
        let mut i = 0;
        while i < self.mirror.len() {
            if self.mirror[i] == n {
                return Some(self.mirror[if i % 2 == 1 { i - 1 } else { i + 1 }]);
            }
            i += 1;
        }
        None
    }

    pub fn set_mirror(&mut self, n: usize, m: usize) {
        self.mirror.push(n);
        self.mirror.push(m);
    }

    pub fn map(&self, pos: usize, assoc: i8) -> usize {
        if !self.mirror.is_empty() {
            return self.map_inner(pos, assoc).pos;
        }
        let mut pos = pos;
        for i in self.from..self.to {
            pos = self.maps[i].map(pos, assoc);
        }
        pos
    }

    pub fn map_result(&self, pos: usize, assoc: i8) -> MapResult {
        self.map_inner(pos, assoc)
    }

    fn map_inner(&self, pos: usize, assoc: i8) -> MapResult {
        let mut del_info = 0;
        let mut pos = pos;
        let mut i = self.from;
        while i < self.to {
            let map = &self.maps[i];
            let result = map.map_result(pos, assoc);
            if let Some(recover) = result.recover
                && let Some(corr) = self.get_mirror(i)
                && corr > i
                && corr < self.to
            {
                i = corr;
                pos = self.maps[corr].recover(recover);
                i += 1;
                continue;
            }
            del_info |= result.del_info;
            pos = result.pos;
            i += 1;
        }
        MapResult { pos, del_info, recover: None }
    }
}

/// Something positions map through: a step map or a mapping.
pub trait Mappable {
    fn map_pos(&self, pos: usize, assoc: i8) -> usize;
    fn map_res(&self, pos: usize, assoc: i8) -> MapResult;
}

impl Mappable for StepMap {
    fn map_pos(&self, pos: usize, assoc: i8) -> usize {
        self.map(pos, assoc)
    }
    fn map_res(&self, pos: usize, assoc: i8) -> MapResult {
        self.map_result(pos, assoc)
    }
}

impl Mappable for Mapping {
    fn map_pos(&self, pos: usize, assoc: i8) -> usize {
        self.map(pos, assoc)
    }
    fn map_res(&self, pos: usize, assoc: i8) -> MapResult {
        self.map_result(pos, assoc)
    }
}

/// A step's attribute value; `None` is JavaScript's `undefined`.
pub type AttrValue = Option<Value>;

#[derive(Debug, Clone)]
pub enum Step {
    Replace { from: usize, to: usize, slice: Slice, structure: bool },
    ReplaceAround { from: usize, to: usize, gap_from: usize, gap_to: usize, slice: Slice, insert: usize, structure: bool },
    AddMark { from: usize, to: usize, mark: Mark },
    RemoveMark { from: usize, to: usize, mark: Mark },
    AddNodeMark { pos: usize, mark: Mark },
    RemoveNodeMark { pos: usize, mark: Mark },
    Attr { pos: usize, attr: String, value: AttrValue },
    DocAttr { attr: String, value: AttrValue },
}

/// `StepResult`: the new document, or the failure message.
pub type StepResult = std::result::Result<Node, String>;

fn from_replace(doc: &Node, from: usize, to: usize, slice: &Slice) -> Result<StepResult> {
    // Out-of-range positions throw; an impossible replacement fails.
    let rf = doc.resolve(from)?;
    let rt = doc.resolve(to)?;
    Ok(replace(&rf, &rt, slice).map_err(|e| e.message().to_owned()))
}

fn content_between(doc: &Node, from: usize, to: usize) -> Result<bool> {
    let rf = doc.resolve(from)?;
    let mut dist = to as isize - from as isize;
    let mut depth = rf.depth;
    while dist > 0 && depth > 0 && rf.index_after(depth) == rf.node(depth).child_count() {
        depth -= 1;
        dist -= 1;
    }
    if dist > 0 {
        let mut next = rf.node(depth).maybe_child(rf.index_after(depth)).cloned();
        while dist > 0 {
            match next {
                Some(node) if !node.is_leaf() => next = node.first_child().cloned(),
                _ => return Ok(true),
            }
            dist -= 1;
        }
    }
    Ok(false)
}

/// `mapFragment` of mark steps.
fn map_fragment(fragment: &Fragment, f: &dyn Fn(&Node, &Node) -> Node, parent: &Node) -> Fragment {
    let mapped = fragment
        .iter()
        .map(|child| {
            let mut child = child.clone();
            if child.content().size > 0 {
                child = child.copy(map_fragment(child.content(), f, &child));
            }
            if child.is_inline() {
                child = f(&child, parent);
            }
            child
        })
        .collect();
    Fragment::from_array(mapped)
}

fn update_attrs(node: &Node, attr: &str, value: &AttrValue) -> Map {
    let mut attrs = (**node.attrs()).clone();
    match value {
        Some(value) => {
            attrs.insert(attr.to_owned(), value.clone());
        }
        // `undefined` takes the attribute's default again.
        None => {
            attrs.shift_remove(attr);
        }
    }
    attrs
}

impl Step {
    /// `Step.apply`: `Ok(Err(message))` is a failed step.
    pub fn apply(&self, doc: &Node) -> Result<StepResult> {
        match self {
            Step::Replace { from, to, slice, structure } => {
                if *structure && content_between(doc, *from, *to)? {
                    return Ok(Err("Structure replace would overwrite content".into()));
                }
                from_replace(doc, *from, *to, slice)
            }
            Step::ReplaceAround { from, to, gap_from, gap_to, slice, insert, structure } => {
                if *structure && (content_between(doc, *from, *gap_from)? || content_between(doc, *gap_to, *to)?) {
                    return Ok(Err("Structure gap-replace would overwrite content".into()));
                }
                let gap = doc.slice(*gap_from, *gap_to, false)?;
                if gap.open_start > 0 || gap.open_end > 0 {
                    return Ok(Err("Gap is not a flat range".into()));
                }
                let Some(inserted) = slice.insert_at(*insert, &gap.content)? else { return Ok(Err("Content does not fit in gap".into())) };
                from_replace(doc, *from, *to, &inserted)
            }
            Step::AddMark { from, to, mark } => {
                let old = doc.slice(*from, *to, false)?;
                let rf = doc.resolve(*from)?;
                let parent = rf.node(rf.shared_depth(*to)).clone();
                let s = schema();
                let content = map_fragment(
                    &old.content,
                    &|node, parent| {
                        if !node.is_atom() || !s.allows_mark(parent.ty(), mark.ty) {
                            return node.clone();
                        }
                        node.mark(mark.add_to_set(node.marks()))
                    },
                    &parent,
                );
                from_replace(doc, *from, *to, &Slice::new(content, old.open_start, old.open_end))
            }
            Step::RemoveMark { from, to, mark } => {
                let old = doc.slice(*from, *to, false)?;
                let content = map_fragment(&old.content, &|node, _| node.mark(mark.remove_from_set(node.marks())), doc);
                from_replace(doc, *from, *to, &Slice::new(content, old.open_start, old.open_end))
            }
            Step::AddNodeMark { pos, mark } | Step::RemoveNodeMark { pos, mark } => {
                let Some(node) = doc.node_at(*pos) else { return Ok(Err("No node at mark step's position".into())) };
                let marks = if matches!(self, Step::AddNodeMark { .. }) { mark.add_to_set(node.marks()) } else { mark.remove_from_set(node.marks()) };
                let updated = Node::create(node.ty(), Some(node.attrs()), Fragment::empty(), marks)?;
                from_replace(doc, *pos, pos + 1, &Slice::new(Fragment::from_node(updated), 0, if node.is_leaf() { 0 } else { 1 }))
            }
            Step::Attr { pos, attr, value } => {
                let Some(node) = doc.node_at(*pos) else { return Ok(Err("No node at attribute step's position".into())) };
                let attrs = update_attrs(&node, attr, value);
                let updated = Node::create(node.ty(), Some(&attrs), Fragment::empty(), node.marks().to_vec())?;
                from_replace(doc, *pos, pos + 1, &Slice::new(Fragment::from_node(updated), 0, if node.is_leaf() { 0 } else { 1 }))
            }
            Step::DocAttr { attr, value } => {
                let attrs = update_attrs(doc, attr, value);
                Ok(Ok(Node::create(doc.ty(), Some(&attrs), doc.content().clone(), doc.marks().to_vec())?))
            }
        }
    }

    pub fn get_map(&self) -> StepMap {
        match self {
            Step::Replace { from, to, slice, .. } => StepMap::new(vec![*from, to - from, slice.size().max(0) as usize]),
            Step::ReplaceAround { from, to, gap_from, gap_to, slice, insert, .. } => {
                StepMap::new(vec![*from, gap_from - from, *insert, *gap_to, to - gap_to, (slice.size() - *insert as isize).max(0) as usize])
            }
            _ => StepMap::empty(),
        }
    }

    pub fn map(&self, mapping: &dyn Mappable) -> Option<Step> {
        match self {
            Step::Replace { from, to, slice, structure } => {
                let t = mapping.map_res(*to, -1);
                let f = mapping.map_res(*from, 1);
                if f.deleted_across() && t.deleted_across() {
                    return None;
                }
                Some(Step::Replace { from: f.pos, to: f.pos.max(t.pos), slice: slice.clone(), structure: *structure })
            }
            Step::ReplaceAround { from, to, gap_from, gap_to, slice, insert, structure } => {
                let f = mapping.map_res(*from, 1);
                let t = mapping.map_res(*to, -1);
                let gf = if from == gap_from { f.pos } else { mapping.map_pos(*gap_from, -1) };
                let gt = if to == gap_to { t.pos } else { mapping.map_pos(*gap_to, 1) };
                if (f.deleted_across() && t.deleted_across()) || gf < f.pos || gt > t.pos {
                    return None;
                }
                Some(Step::ReplaceAround { from: f.pos, to: t.pos, gap_from: gf, gap_to: gt, slice: slice.clone(), insert: *insert, structure: *structure })
            }
            Step::AddMark { from, to, mark } | Step::RemoveMark { from, to, mark } => {
                let f = mapping.map_res(*from, 1);
                let t = mapping.map_res(*to, -1);
                if (f.deleted() && t.deleted()) || f.pos >= t.pos {
                    return None;
                }
                Some(if matches!(self, Step::AddMark { .. }) {
                    Step::AddMark { from: f.pos, to: t.pos, mark: mark.clone() }
                } else {
                    Step::RemoveMark { from: f.pos, to: t.pos, mark: mark.clone() }
                })
            }
            Step::AddNodeMark { pos, mark } | Step::RemoveNodeMark { pos, mark } => {
                let p = mapping.map_res(*pos, 1);
                if p.deleted_after() {
                    return None;
                }
                Some(if matches!(self, Step::AddNodeMark { .. }) {
                    Step::AddNodeMark { pos: p.pos, mark: mark.clone() }
                } else {
                    Step::RemoveNodeMark { pos: p.pos, mark: mark.clone() }
                })
            }
            Step::Attr { pos, attr, value } => {
                let p = mapping.map_res(*pos, 1);
                if p.deleted_after() {
                    return None;
                }
                Some(Step::Attr { pos: p.pos, attr: attr.clone(), value: value.clone() })
            }
            Step::DocAttr { .. } => Some(self.clone()),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut json = Map::new();
        let num = |n: &usize| Value::from(*n);
        match self {
            Step::Replace { from, to, slice, structure } => {
                json.insert("stepType".into(), "replace".into());
                json.insert("from".into(), num(from));
                json.insert("to".into(), num(to));
                if slice.size() != 0 {
                    json.insert("slice".into(), slice.to_json());
                }
                if *structure {
                    json.insert("structure".into(), true.into());
                }
            }
            Step::ReplaceAround { from, to, gap_from, gap_to, slice, insert, structure } => {
                json.insert("stepType".into(), "replaceAround".into());
                json.insert("from".into(), num(from));
                json.insert("to".into(), num(to));
                json.insert("gapFrom".into(), num(gap_from));
                json.insert("gapTo".into(), num(gap_to));
                json.insert("insert".into(), num(insert));
                if slice.size() != 0 {
                    json.insert("slice".into(), slice.to_json());
                }
                if *structure {
                    json.insert("structure".into(), true.into());
                }
            }
            Step::AddMark { from, to, mark } | Step::RemoveMark { from, to, mark } => {
                json.insert("stepType".into(), (if matches!(self, Step::AddMark { .. }) { "addMark" } else { "removeMark" }).into());
                json.insert("mark".into(), mark.to_json());
                json.insert("from".into(), num(from));
                json.insert("to".into(), num(to));
            }
            Step::AddNodeMark { pos, mark } | Step::RemoveNodeMark { pos, mark } => {
                json.insert("stepType".into(), (if matches!(self, Step::AddNodeMark { .. }) { "addNodeMark" } else { "removeNodeMark" }).into());
                json.insert("pos".into(), num(pos));
                json.insert("mark".into(), mark.to_json());
            }
            Step::Attr { pos, attr, value } => {
                json.insert("stepType".into(), "attr".into());
                json.insert("pos".into(), num(pos));
                json.insert("attr".into(), attr.clone().into());
                if let Some(value) = value {
                    json.insert("value".into(), value.clone());
                }
            }
            Step::DocAttr { attr, value } => {
                json.insert("stepType".into(), "docAttr".into());
                json.insert("attr".into(), attr.clone().into());
                if let Some(value) = value {
                    json.insert("value".into(), value.clone());
                }
            }
        }
        Value::Object(json)
    }

    pub fn from_json(json: &Value) -> Result<Step> {
        let Some(kind) = json.get("stepType").filter(|v| json::truthy(Some(v))) else { bail!("Invalid input for Step.fromJSON") };
        let position = |key: &str, what: &str| -> Result<usize> {
            match json.get(key) {
                Some(Value::Number(n)) => match n.as_u64() {
                    Some(n) => Ok(n as usize),
                    // A negative or fractional position names no place in a document.
                    None => bail!("Position {n} out of range"),
                },
                _ => bail!("Invalid input for {what}.fromJSON"),
            }
        };
        let structure = json::truthy(json.get("structure"));
        Ok(match kind.as_str() {
            Some("replace") => Step::Replace {
                from: position("from", "ReplaceStep")?,
                to: position("to", "ReplaceStep")?,
                slice: Slice::from_json(json.get("slice"))?,
                structure,
            },
            Some("replaceAround") => Step::ReplaceAround {
                from: position("from", "ReplaceAroundStep")?,
                to: position("to", "ReplaceAroundStep")?,
                gap_from: position("gapFrom", "ReplaceAroundStep")?,
                gap_to: position("gapTo", "ReplaceAroundStep")?,
                insert: position("insert", "ReplaceAroundStep")?,
                slice: Slice::from_json(json.get("slice"))?,
                structure,
            },
            Some("addMark") => Step::AddMark {
                from: position("from", "AddMarkStep")?,
                to: position("to", "AddMarkStep")?,
                mark: Mark::from_json(json.get("mark").unwrap_or(&Value::Null))?,
            },
            Some("removeMark") => Step::RemoveMark {
                from: position("from", "RemoveMarkStep")?,
                to: position("to", "RemoveMarkStep")?,
                mark: Mark::from_json(json.get("mark").unwrap_or(&Value::Null))?,
            },
            Some("addNodeMark") => {
                Step::AddNodeMark { pos: position("pos", "AddNodeMarkStep")?, mark: Mark::from_json(json.get("mark").unwrap_or(&Value::Null))? }
            }
            Some("removeNodeMark") => {
                Step::RemoveNodeMark { pos: position("pos", "RemoveNodeMarkStep")?, mark: Mark::from_json(json.get("mark").unwrap_or(&Value::Null))? }
            }
            Some("attr") => {
                let pos = position("pos", "AttrStep")?;
                let Some(attr) = json.get("attr").and_then(Value::as_str) else { bail!("Invalid input for AttrStep.fromJSON") };
                Step::Attr { pos, attr: attr.to_owned(), value: json.get("value").cloned() }
            }
            Some("docAttr") => {
                let Some(attr) = json.get("attr").and_then(Value::as_str) else { bail!("Invalid input for DocAttrStep.fromJSON") };
                Step::DocAttr { attr: attr.to_owned(), value: json.get("value").cloned() }
            }
            _ => bail!("No step type {} defined", json::stringify(kind)),
        })
    }

    pub fn slice(&self) -> Option<&Slice> {
        match self {
            Step::Replace { slice, .. } | Step::ReplaceAround { slice, .. } => Some(slice),
            _ => None,
        }
    }
}

/// `Transform`: a document and the steps applied to it.
#[derive(Clone)]
pub struct Transform {
    pub doc: Node,
    pub steps: Vec<Step>,
    pub docs: Vec<Node>,
    pub mapping: Mapping,
}

impl Transform {
    pub fn new(doc: Node) -> Transform {
        Transform { doc, steps: Vec::new(), docs: Vec::new(), mapping: Mapping::new() }
    }

    pub fn before(&self) -> &Node {
        self.docs.first().unwrap_or(&self.doc)
    }

    /// `step`: throws on a failed step.
    pub fn step(&mut self, step: Step) -> Result<()> {
        if let Err(failed) = self.maybe_step(step)? {
            bail!("{failed}");
        }
        Ok(())
    }

    pub fn maybe_step(&mut self, step: Step) -> Result<std::result::Result<(), String>> {
        match step.apply(&self.doc)? {
            Ok(doc) => {
                self.add_step(step, doc);
                Ok(Ok(()))
            }
            Err(failed) => Ok(Err(failed)),
        }
    }

    pub fn doc_changed(&self) -> bool {
        !self.steps.is_empty()
    }

    pub fn add_step(&mut self, step: Step, doc: Node) {
        self.docs.push(std::mem::replace(&mut self.doc, doc));
        self.mapping.append_map(step.get_map(), None);
        self.steps.push(step);
    }

    pub fn set_node_attribute(&mut self, pos: usize, attr: &str, value: Value) -> Result<()> {
        self.step(Step::Attr { pos, attr: attr.to_owned(), value: Some(value) })
    }

    /// `addMark`.
    pub fn add_mark(&mut self, from: usize, to: usize, mark: &Mark) -> Result<()> {
        let s = schema();
        let mut removed: Vec<(usize, usize, Mark)> = Vec::new();
        let mut added: Vec<(usize, usize)> = Vec::new();
        self.doc.nodes_between(
            from,
            to,
            &mut |node, pos, parent, _| {
                if !node.is_inline() {
                    return true;
                }
                let marks = node.marks();
                if !mark.is_in_set(marks) && parent.is_some_and(|p| s.allows_mark(p.ty(), mark.ty)) {
                    let start = pos.max(from);
                    let end = (pos + node.node_size()).min(to);
                    let new_set = mark.add_to_set(marks);
                    for m in marks {
                        if !m.is_in_set(&new_set) {
                            match removed.last_mut() {
                                Some(last) if last.1 == start && last.2 == *m => last.1 = end,
                                _ => removed.push((start, end, m.clone())),
                            }
                        }
                    }
                    match added.last_mut() {
                        Some(last) if last.1 == start => last.1 = end,
                        _ => added.push((start, end)),
                    }
                }
                true
            },
            0,
        );
        for (from, to, m) in removed {
            self.step(Step::RemoveMark { from, to, mark: m })?;
        }
        for (from, to) in added {
            self.step(Step::AddMark { from, to, mark: mark.clone() })?;
        }
        Ok(())
    }

    /// `removeMark` of one mark, or of every mark of a type (`ty`).
    pub fn remove_mark(&mut self, from: usize, to: usize, mark: Option<&Mark>, ty: Option<usize>) -> Result<()> {
        struct Matched {
            style: Mark,
            from: usize,
            to: usize,
            step: usize,
        }
        let mut matched: Vec<Matched> = Vec::new();
        let mut step = 0;
        self.doc.nodes_between(
            from,
            to,
            &mut |node, pos, _, _| {
                if !node.is_inline() {
                    return true;
                }
                step += 1;
                let to_remove: Vec<Mark> = if let Some(ty) = ty {
                    node.marks().iter().filter(|m| m.ty == ty).cloned().collect()
                } else if let Some(mark) = mark {
                    if mark.is_in_set(node.marks()) { vec![mark.clone()] } else { Vec::new() }
                } else {
                    node.marks().to_vec()
                };
                if !to_remove.is_empty() {
                    let end = (pos + node.node_size()).min(to);
                    for style in to_remove {
                        let found = matched.iter().rposition(|m| m.step + 1 == step && m.style == style);
                        match found {
                            Some(i) => {
                                matched[i].to = end;
                                matched[i].step = step;
                            }
                            None => matched.push(Matched { style, from: pos.max(from), to: end, step }),
                        }
                    }
                }
                true
            },
            0,
        );
        for m in matched {
            self.step(Step::RemoveMark { from: m.from, to: m.to, mark: m.style })?;
        }
        Ok(())
    }
}

impl Mark {
    pub fn ptr_attrs(&self) -> &Rc<Map> {
        &self.attrs
    }
}
