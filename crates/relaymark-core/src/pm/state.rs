// Ported from prosemirror-state 1.4.4 and prosemirror-tables 1.8.5.
// ProseMirror is Copyright (C) 2015-2017 by Marijn Haverbeke and others, used under the MIT License; see THIRD_PARTY_NOTICES.md.
//! prosemirror-state 1.4's selections and transactions, with
//! prosemirror-tables' `CellSelection`.

use serde_json::{Value, json};

use crate::error::{Result, bail};

use super::model::{Fragment, Mark, Node, ResolvedPos, Slice, same_mark_set};
use super::schema::schema;
use super::step::{Mappable, Step, Transform};
use super::tables::{TableMap, in_same_table, points_at_cell};

#[derive(Clone, Debug)]
pub struct SelRange {
    pub from: ResolvedPos,
    pub to: ResolvedPos,
}

#[derive(Clone, Debug)]
pub enum Selection {
    Text { anchor: ResolvedPos, head: ResolvedPos },
    Node { anchor: ResolvedPos, head: ResolvedPos, node: Node },
    All { anchor: ResolvedPos, head: ResolvedPos },
    Cell { anchor_cell: ResolvedPos, head_cell: ResolvedPos, ranges: Vec<SelRange> },
}

fn range_of(anchor: &ResolvedPos, head: &ResolvedPos) -> SelRange {
    SelRange { from: anchor.min(head).clone(), to: anchor.max(head).clone() }
}

impl Selection {
    pub fn text(anchor: ResolvedPos, head: ResolvedPos) -> Selection {
        Selection::Text { anchor, head }
    }

    pub fn text_create(doc: &Node, anchor: usize, head: usize) -> Result<Selection> {
        let a = doc.resolve(anchor)?;
        let h = if head == anchor { a.clone() } else { doc.resolve(head)? };
        Ok(Selection::Text { anchor: a, head: h })
    }

    pub fn node(pos: ResolvedPos) -> Result<Selection> {
        let Some(node) = pos.node_after() else { bail!("Cannot read properties of null (reading 'nodeSize')") };
        let end = pos.doc().resolve(pos.pos + node.node_size())?;
        Ok(Selection::Node { anchor: pos, head: end, node })
    }

    pub fn all(doc: &Node) -> Result<Selection> {
        Ok(Selection::All { anchor: doc.resolve(0)?, head: doc.resolve(doc.content().size)? })
    }

    /// `new CellSelection($anchorCell, $headCell)`.
    pub fn cell(anchor_cell: ResolvedPos, head_cell: ResolvedPos) -> Result<Selection> {
        let table = anchor_cell.node_rel(-1).clone();
        let map = TableMap::get(&table)?;
        let table_start = anchor_cell.start(anchor_cell.depth - 1);
        let anchor_rel = anchor_cell.pos - table_start;
        // A head cell in an earlier table lies before this one: ProseMirror's
        // TableMap reports its negative offset as a missing cell, after the
        // anchor's own lookup.
        let Some(head_rel) = head_cell.pos.checked_sub(table_start) else {
            map.find_cell(anchor_rel)?;
            bail!("No cell with offset -{} found", table_start - head_cell.pos)
        };
        let rect = map.rect_between(anchor_rel, head_rel)?;
        let doc = anchor_cell.doc().clone();
        let mut cells: Vec<usize> = map.cells_in_rect(&rect).into_iter().filter(|&p| p != head_rel).collect();
        cells.insert(0, head_rel);
        let mut ranges = Vec::new();
        for pos in cells {
            let Some(cell) = table.node_at(pos) else { bail!("No cell with offset {pos} found") };
            let from = table_start + pos + 1;
            ranges.push(SelRange { from: doc.resolve(from)?, to: doc.resolve(from + cell.content().size)? });
        }
        Ok(Selection::Cell { anchor_cell, head_cell, ranges })
    }

    pub fn ranges(&self) -> Vec<SelRange> {
        match self {
            Selection::Text { anchor, head } | Selection::Node { anchor, head, .. } | Selection::All { anchor, head } => vec![range_of(anchor, head)],
            Selection::Cell { ranges, .. } => ranges.clone(),
        }
    }

    pub fn anchor_r(&self) -> &ResolvedPos {
        match self {
            Selection::Text { anchor, .. } | Selection::Node { anchor, .. } | Selection::All { anchor, .. } => anchor,
            Selection::Cell { ranges, .. } => &ranges[0].from,
        }
    }

    pub fn head_r(&self) -> &ResolvedPos {
        match self {
            Selection::Text { head, .. } | Selection::Node { head, .. } | Selection::All { head, .. } => head,
            Selection::Cell { ranges, .. } => &ranges[0].to,
        }
    }

    pub fn sel_from(&self) -> ResolvedPos {
        match self {
            Selection::Cell { ranges, .. } => ranges[0].from.clone(),
            _ => self.anchor_r().min(self.head_r()).clone(),
        }
    }

    pub fn sel_to(&self) -> ResolvedPos {
        match self {
            Selection::Cell { ranges, .. } => ranges[0].to.clone(),
            _ => self.anchor_r().max(self.head_r()).clone(),
        }
    }

    pub fn from(&self) -> usize {
        self.sel_from().pos
    }

    pub fn to(&self) -> usize {
        self.sel_to().pos
    }

    pub fn head(&self) -> usize {
        self.head_r().pos
    }

    pub fn anchor(&self) -> usize {
        self.anchor_r().pos
    }

    pub fn empty(&self) -> bool {
        self.ranges().iter().all(|r| r.from.pos == r.to.pos)
    }

    /// `TextSelection.$cursor`.
    pub fn cursor(&self) -> Option<&ResolvedPos> {
        match self {
            Selection::Text { anchor, head } if anchor.pos == head.pos => Some(head),
            _ => None,
        }
    }

    pub fn eq(&self, other: &Selection) -> bool {
        match (self, other) {
            (Selection::Text { .. }, Selection::Text { .. }) => self.anchor() == other.anchor() && self.head() == other.head(),
            (Selection::Node { .. }, Selection::Node { .. }) => self.anchor() == other.anchor(),
            (Selection::All { .. }, Selection::All { .. }) => true,
            (Selection::Cell { anchor_cell: a, head_cell: h, .. }, Selection::Cell { anchor_cell: oa, head_cell: oh, .. }) => {
                a.pos == oa.pos && h.pos == oh.pos
            }
            _ => false,
        }
    }

    pub fn to_json(&self) -> Value {
        match self {
            Selection::Text { anchor, head } => json!({"type": "text", "anchor": anchor.pos, "head": head.pos}),
            Selection::Node { anchor, .. } => json!({"type": "node", "anchor": anchor.pos}),
            Selection::All { .. } => json!({"type": "all"}),
            Selection::Cell { anchor_cell, head_cell, .. } => json!({"type": "cell", "anchor": anchor_cell.pos, "head": head_cell.pos}),
        }
    }

    pub fn from_json(doc: &Node, json: &Value) -> Result<Selection> {
        let Some(kind) = json.get("type").filter(|t| crate::json::truthy(Some(t))) else { bail!("Invalid input for Selection.fromJSON") };
        let number = |key: &str, what: &str| -> Result<usize> {
            match json.get(key) {
                Some(Value::Number(n)) => match n.as_u64() {
                    Some(n) => Ok(n as usize),
                    None => bail!("Position {n} out of range"),
                },
                _ => bail!("Invalid input for {what}.fromJSON"),
            }
        };
        match kind.as_str() {
            Some("text") => {
                let anchor = number("anchor", "TextSelection")?;
                let head = number("head", "TextSelection")?;
                Ok(Selection::Text { anchor: doc.resolve(anchor)?, head: doc.resolve(head)? })
            }
            Some("node") => Selection::node(doc.resolve(number("anchor", "NodeSelection")?)?),
            Some("all") => Selection::all(doc),
            Some("cell") => {
                let anchor = json.get("anchor").and_then(Value::as_u64).map(|n| n as usize);
                let head = json.get("head").and_then(Value::as_u64).map(|n| n as usize);
                let (Some(anchor), Some(head)) = (anchor, head) else { bail!("Position out of range") };
                Selection::cell(doc.resolve(anchor)?, doc.resolve(head)?)
            }
            _ => bail!("No selection type {} defined", crate::json::stringify(kind)),
        }
    }

    /// `Selection.map`.
    pub fn map(&self, doc: &Node, mapping: &dyn Mappable) -> Result<Selection> {
        match self {
            Selection::Text { anchor, head } => {
                let h = doc.resolve(mapping.map_pos(head.pos, 1))?;
                if !h.parent().inline_content() {
                    return near(&h, 1);
                }
                let a = doc.resolve(mapping.map_pos(anchor.pos, 1))?;
                Ok(Selection::Text { anchor: if a.parent().inline_content() { a } else { h.clone() }, head: h })
            }
            Selection::Node { anchor, .. } => {
                let result = mapping.map_res(anchor.pos, 1);
                let pos = doc.resolve(result.pos)?;
                if result.deleted() {
                    return near(&pos, 1);
                }
                Selection::node(pos)
            }
            Selection::All { .. } => Selection::all(doc),
            Selection::Cell { anchor_cell, head_cell, .. } => {
                let a = doc.resolve(mapping.map_pos(anchor_cell.pos, 1))?;
                let h = doc.resolve(mapping.map_pos(head_cell.pos, 1))?;
                if points_at_cell(&a) && points_at_cell(&h) && in_same_table(&a, &h) {
                    let changed = !anchor_cell.node_rel(-1).ptr_eq(a.node_rel(-1));
                    if changed && self.is_row_selection()? {
                        return row_selection(a, h);
                    } else if changed && self.is_col_selection()? {
                        return col_selection(a, h);
                    }
                    return Selection::cell(a, h);
                }
                text_between(&a, &h, None)
            }
        }
    }

    pub fn is_col_selection(&self) -> Result<bool> {
        let Selection::Cell { anchor_cell, head_cell, .. } = self else { return Ok(false) };
        let anchor_top = anchor_cell.index(anchor_cell.depth - 1);
        let head_top = head_cell.index(head_cell.depth - 1);
        if anchor_top.min(head_top) > 0 {
            return Ok(false);
        }
        let span = |p: &ResolvedPos| p.node_after().map_or(0, |n| n.attr("rowspan").as_u64().unwrap_or(1) as usize);
        let anchor_bottom = anchor_top + span(anchor_cell);
        let head_bottom = head_top + span(head_cell);
        Ok(anchor_bottom.max(head_bottom) == head_cell.node_rel(-1).child_count())
    }

    pub fn is_row_selection(&self) -> Result<bool> {
        let Selection::Cell { anchor_cell, head_cell, .. } = self else { return Ok(false) };
        let table = anchor_cell.node_rel(-1);
        let map = TableMap::get(table)?;
        let start = anchor_cell.start(anchor_cell.depth - 1);
        let anchor_left = map.col_count(anchor_cell.pos - start)?;
        let head_left = map.col_count(head_cell.pos - start)?;
        if anchor_left.min(head_left) > 0 {
            return Ok(false);
        }
        let span = |p: &ResolvedPos| p.node_after().map_or(0, |n| n.attr("colspan").as_u64().unwrap_or(1) as usize);
        Ok((anchor_left + span(anchor_cell)).max(head_left + span(head_cell)) == map.width)
    }

    /// `Selection.replace`.
    pub fn replace(&self, tr: &mut Transaction, content: &Slice, is_empty_slice: bool) -> Result<()> {
        match self {
            Selection::All { .. } if is_empty_slice => {
                let size = tr.doc.content().size;
                tr.delete(0, size)?;
                let sel = at_start(&tr.doc.clone())?;
                if !sel.eq(&tr.selection()?) {
                    tr.set_selection(sel)?;
                }
                Ok(())
            }
            Selection::Cell { .. } => {
                let map_from = tr.steps.len();
                for (i, range) in self.ranges().iter().enumerate() {
                    let mapping = tr.mapping.slice(map_from, tr.mapping.maps.len());
                    let (from, to) = (mapping.map(range.from.pos, 1), mapping.map(range.to.pos, 1));
                    let empty = Slice::empty();
                    tr.replace(from, to, if i > 0 { &empty } else { content })?;
                }
                let at = tr.mapping.slice(map_from, tr.mapping.maps.len()).map(self.to(), 1);
                let doc = tr.doc.clone();
                if let Some(sel) = find_from(&doc.resolve(at)?, -1, false)? {
                    tr.set_selection(sel)?;
                }
                Ok(())
            }
            _ => {
                let mut last_node = content.content.last_child().cloned();
                let mut last_parent: Option<Node> = None;
                for _ in 0..content.open_end {
                    last_parent = last_node.clone();
                    last_node = last_node.and_then(|n| n.last_child().cloned());
                }
                let map_from = tr.steps.len();
                for (i, range) in self.ranges().iter().enumerate() {
                    let mapping = tr.mapping.slice(map_from, tr.mapping.maps.len());
                    let (from, to) = (mapping.map(range.from.pos, 1), mapping.map(range.to.pos, 1));
                    let empty = Slice::empty();
                    tr.replace_range(from, to, if i > 0 { &empty } else { content })?;
                    if i == 0 {
                        let inline = match &last_node {
                            Some(n) => n.is_inline(),
                            None => last_parent.as_ref().is_some_and(Node::is_textblock),
                        };
                        selection_to_insertion_end(tr, map_from, if inline { -1 } else { 1 })?;
                    }
                }
                if let Selection::Text { .. } = self
                    && is_empty_slice
                    && let Some(marks) = self.sel_from().marks_across(&self.sel_to())
                {
                    tr.ensure_marks(marks)?;
                }
                Ok(())
            }
        }
    }

    /// `Selection.replaceWith`.
    pub fn replace_with(&self, tr: &mut Transaction, node: Node) -> Result<()> {
        if let Selection::Cell { .. } = self {
            return self.replace(tr, &Slice::new(Fragment::from_node(node), 0, 0), false);
        }
        let map_from = tr.steps.len();
        for (i, range) in self.ranges().iter().enumerate() {
            let mapping = tr.mapping.slice(map_from, tr.mapping.maps.len());
            let (from, to) = (mapping.map(range.from.pos, 1), mapping.map(range.to.pos, 1));
            if i > 0 {
                tr.delete_range(from, to)?;
            } else {
                let inline = node.is_inline();
                tr.replace_range_with(from, to, node.clone())?;
                selection_to_insertion_end(tr, map_from, if inline { -1 } else { 1 })?;
            }
        }
        Ok(())
    }
}

fn selection_to_insertion_end(tr: &mut Transaction, start_len: usize, bias: i8) -> Result<()> {
    if tr.steps.len() <= start_len {
        return Ok(());
    }
    let last = tr.steps.len() - 1;
    if !matches!(tr.steps[last], Step::Replace { .. } | Step::ReplaceAround { .. }) {
        return Ok(());
    }
    let mut end = None;
    tr.mapping.maps[last].for_each(&mut |_, _, _, new_to| {
        if end.is_none() {
            end = Some(new_to);
        }
    });
    let doc = tr.doc.clone();
    let sel = near(&doc.resolve(end.unwrap_or(0))?, bias)?;
    tr.set_selection(sel)
}

pub fn is_selectable(node: &Node) -> bool {
    !node.is_text() && schema().nodes[node.ty()].selectable
}

fn find_selection_in(doc: &Node, node: &Node, pos: usize, index: usize, dir: i8, text: bool) -> Result<Option<Selection>> {
    if node.inline_content() {
        return Ok(Some(Selection::text_create(doc, pos, pos)?));
    }
    let mut pos = pos as isize;
    let mut i = index as isize - if dir > 0 { 0 } else { 1 };
    while if dir > 0 { i < node.child_count() as isize } else { i >= 0 } {
        let child = node.child(i as usize);
        if !child.is_atom() {
            let inner = find_selection_in(doc, child, (pos + dir as isize) as usize, if dir < 0 { child.child_count() } else { 0 }, dir, text)?;
            if inner.is_some() {
                return Ok(inner);
            }
        } else if !text && is_selectable(child) {
            return Ok(Some(Selection::node(doc.resolve((pos - if dir < 0 { child.node_size() as isize } else { 0 }) as usize)?)?));
        }
        pos += child.node_size() as isize * dir as isize;
        i += dir as isize;
    }
    Ok(None)
}

/// `Selection.findFrom`.
pub fn find_from(pos: &ResolvedPos, dir: i8, text_only: bool) -> Result<Option<Selection>> {
    let inner = if pos.parent().inline_content() {
        Some(Selection::Text { anchor: pos.clone(), head: pos.clone() })
    } else {
        find_selection_in(pos.doc(), pos.parent(), pos.pos, pos.index_here(), dir, text_only)?
    };
    if inner.is_some() {
        return Ok(inner);
    }
    for depth in (0..pos.depth).rev() {
        let found = if dir < 0 {
            find_selection_in(pos.doc(), pos.node(depth), pos.before(depth + 1)?, pos.index(depth), dir, text_only)?
        } else {
            find_selection_in(pos.doc(), pos.node(depth), pos.after(depth + 1)?, pos.index(depth) + 1, dir, text_only)?
        };
        if found.is_some() {
            return Ok(found);
        }
    }
    Ok(None)
}

/// `Selection.near`.
pub fn near(pos: &ResolvedPos, bias: i8) -> Result<Selection> {
    if let Some(found) = find_from(pos, bias, false)? {
        return Ok(found);
    }
    if let Some(found) = find_from(pos, -bias, false)? {
        return Ok(found);
    }
    Selection::all(pos.doc())
}

pub fn at_start(doc: &Node) -> Result<Selection> {
    match find_selection_in(doc, doc, 0, 0, 1, false)? {
        Some(sel) => Ok(sel),
        None => Selection::all(doc),
    }
}

/// `TextSelection.between`.
pub fn text_between(anchor: &ResolvedPos, head: &ResolvedPos, bias: Option<i8>) -> Result<Selection> {
    let d_pos = anchor.pos as isize - head.pos as isize;
    let mut bias = bias.unwrap_or(0);
    if bias == 0 || d_pos != 0 {
        bias = if d_pos >= 0 { 1 } else { -1 };
    }
    let mut head = head.clone();
    let mut anchor = anchor.clone();
    if !head.parent().inline_content() {
        let found = match find_from(&head, bias, true)? {
            Some(f) => Some(f),
            None => find_from(&head, -bias, true)?,
        };
        match found {
            Some(found) => head = found.head_r().clone(),
            None => return near(&head, bias),
        }
    }
    if !anchor.parent().inline_content() {
        if d_pos == 0 {
            anchor = head.clone();
        } else {
            let found = match find_from(&anchor, -bias, true)? {
                Some(f) => Some(f),
                None => find_from(&anchor, bias, true)?,
            };
            anchor = found.expect("a text position").anchor_r().clone();
            if (anchor.pos < head.pos) != (d_pos < 0) {
                anchor = head.clone();
            }
        }
    }
    Ok(Selection::Text { anchor, head })
}

/// `CellSelection.rowSelection`.
pub fn row_selection(anchor_cell: ResolvedPos, head_cell: ResolvedPos) -> Result<Selection> {
    let table = anchor_cell.node_rel(-1).clone();
    let map = TableMap::get(&table)?;
    let start = anchor_cell.start(anchor_cell.depth - 1);
    let a = map.find_cell(anchor_cell.pos - start)?;
    let h = map.find_cell(head_cell.pos - start)?;
    let doc = anchor_cell.doc().clone();
    let (mut anchor_cell, mut head_cell) = (anchor_cell, head_cell);
    if a.left <= h.left {
        if a.left > 0 {
            anchor_cell = doc.resolve(start + map.map[a.top * map.width])?;
        }
        if h.right < map.width {
            head_cell = doc.resolve(start + map.map[map.width * (h.top + 1) - 1])?;
        }
    } else {
        if h.left > 0 {
            head_cell = doc.resolve(start + map.map[h.top * map.width])?;
        }
        if a.right < map.width {
            anchor_cell = doc.resolve(start + map.map[map.width * (a.top + 1) - 1])?;
        }
    }
    Selection::cell(anchor_cell, head_cell)
}

/// `CellSelection.colSelection`.
pub fn col_selection(anchor_cell: ResolvedPos, head_cell: ResolvedPos) -> Result<Selection> {
    let table = anchor_cell.node_rel(-1).clone();
    let map = TableMap::get(&table)?;
    let start = anchor_cell.start(anchor_cell.depth - 1);
    let a = map.find_cell(anchor_cell.pos - start)?;
    let h = map.find_cell(head_cell.pos - start)?;
    let doc = anchor_cell.doc().clone();
    let (mut anchor_cell, mut head_cell) = (anchor_cell, head_cell);
    if a.top <= h.top {
        if a.top > 0 {
            anchor_cell = doc.resolve(start + map.map[a.left])?;
        }
        if h.bottom < map.height {
            head_cell = doc.resolve(start + map.map[map.width * (map.height - 1) + h.right - 1])?;
        }
    } else {
        if h.top > 0 {
            head_cell = doc.resolve(start + map.map[h.left])?;
        }
        if a.bottom < map.height {
            anchor_cell = doc.resolve(start + map.map[map.width * (map.height - 1) + a.right - 1])?;
        }
    }
    Selection::cell(anchor_cell, head_cell)
}

/// `Transaction`: a transform with a selection and stored marks.
pub struct Transaction {
    pub transform: Transform,
    selection: Selection,
    selection_for: usize,
    /// Stored marks and the step count they were set at; any later step
    /// clears them.
    stored: Option<(Vec<Mark>, usize)>,
}

impl std::ops::Deref for Transaction {
    type Target = Transform;
    fn deref(&self) -> &Transform {
        &self.transform
    }
}

impl std::ops::DerefMut for Transaction {
    fn deref_mut(&mut self) -> &mut Transform {
        &mut self.transform
    }
}

impl Transaction {
    pub fn new(doc: Node, selection: Selection, stored_marks: Option<Vec<Mark>>) -> Transaction {
        Transaction { transform: Transform::new(doc), selection, selection_for: 0, stored: stored_marks.map(|m| (m, 0)) }
    }

    pub fn selection(&mut self) -> Result<Selection> {
        if self.selection_for < self.steps.len() {
            let mapping = self.mapping.slice(self.selection_for, self.mapping.maps.len());
            self.selection = self.selection.map(&self.transform.doc, &mapping)?;
            self.selection_for = self.steps.len();
        }
        Ok(self.selection.clone())
    }

    pub fn set_selection(&mut self, selection: Selection) -> Result<()> {
        if !selection.sel_from().doc().ptr_eq(&self.doc) {
            bail!("Selection passed to setSelection must point at the current document");
        }
        self.selection = selection;
        self.selection_for = self.steps.len();
        self.stored = None;
        Ok(())
    }

    pub fn stored_marks(&self) -> Option<&Vec<Mark>> {
        self.stored.as_ref().filter(|(_, at)| *at == self.steps.len()).map(|(m, _)| m)
    }

    pub fn set_stored_marks(&mut self, marks: Option<Vec<Mark>>) {
        let at = self.steps.len();
        self.stored = marks.map(|m| (m, at));
    }

    pub fn ensure_marks(&mut self, marks: Vec<Mark>) -> Result<()> {
        let current = match self.stored_marks() {
            Some(m) => m.clone(),
            None => self.selection()?.sel_from().marks(),
        };
        if !same_mark_set(&current, &marks) {
            self.set_stored_marks(Some(marks));
        }
        Ok(())
    }

    /// `replaceSelectionWith(node, inheritMarks = true)`.
    pub fn replace_selection_with(&mut self, node: Node) -> Result<()> {
        let selection = self.selection()?;
        let marks = match self.stored_marks() {
            Some(m) => m.clone(),
            None if selection.empty() => selection.sel_from().marks(),
            None => selection.sel_from().marks_across(&selection.sel_to()).unwrap_or_default(),
        };
        selection.replace_with(self, node.mark(marks))
    }

    pub fn delete_selection(&mut self) -> Result<()> {
        let selection = self.selection()?;
        selection.replace(self, &Slice::empty(), true)
    }

    /// `insertText(text)` at the selection.
    pub fn insert_text(&mut self, text: &str) -> Result<()> {
        if text.is_empty() {
            return self.delete_selection();
        }
        self.replace_selection_with(Node::text_node(text, Vec::new())?)
    }
}
