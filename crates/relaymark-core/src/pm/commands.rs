// Ported from prosemirror-commands 1.7.2 and prosemirror-schema-list 1.5.1.
// ProseMirror is Copyright (C) 2015-2017 by Marijn Haverbeke and others, used under the MIT License; see THIRD_PARTY_NOTICES.md.
//! The prosemirror-commands and prosemirror-schema-list commands the editor
//! runs. Each takes the state (document and selection, no stored marks) and
//! answers the transaction it would dispatch, or `None` when it does not apply.

use crate::error::Result;
use crate::json::Map;

use super::model::{Fragment, Node, NodeRange, Slice};
use super::schema::{MatchId, TypeId, schema};
use super::state::{Selection, Transaction, near};
use super::step::Step;
use super::transform::{TypeAttrs, can_join, can_split, lift_target};

pub struct State {
    pub doc: Node,
    pub selection: Selection,
}

impl State {
    pub fn tr(&self) -> Transaction {
        Transaction::new(self.doc.clone(), self.selection.clone(), None)
    }
}

fn default_block_at(matched: MatchId) -> Option<TypeId> {
    let s = schema();
    s.edges(matched).iter().map(|(ty, _)| *ty).find(|&ty| s.is_textblock(ty) && !s.has_required_attrs(ty))
}

/// `newlineInCode`.
pub fn newline_in_code(state: &State) -> Result<Option<Transaction>> {
    let head = state.selection.head_r();
    let anchor = state.selection.anchor_r();
    if !schema().nodes[head.parent().ty()].pre || !head.same_parent(anchor) {
        return Ok(None);
    }
    let mut tr = state.tr();
    tr.insert_text("\n")?;
    Ok(Some(tr))
}

/// `createParagraphNear`.
pub fn create_paragraph_near(state: &State) -> Result<Option<Transaction>> {
    let sel = &state.selection;
    let (from, to) = (sel.sel_from(), sel.sel_to());
    if matches!(sel, Selection::All { .. }) || from.parent().inline_content() || to.parent().inline_content() {
        return Ok(None);
    }
    let Some(ty) = default_block_at(to.parent().content_match_at(to.index_after(to.depth))?) else { return Ok(None) };
    if !schema().is_textblock(ty) {
        return Ok(None);
    }
    let side = if from.parent_offset == 0 && to.index_here() < to.parent().child_count() { from.pos } else { to.pos };
    let mut tr = state.tr();
    let node = Node::create_and_fill(ty, None, Fragment::empty(), Vec::new())?.expect("default block");
    tr.insert(side, Fragment::from_node(node))?;
    let sel = Selection::text_create(&tr.doc.clone(), side + 1, side + 1)?;
    tr.set_selection(sel)?;
    Ok(Some(tr))
}

/// `liftEmptyBlock`.
pub fn lift_empty_block(state: &State) -> Result<Option<Transaction>> {
    let Some(cursor) = state.selection.cursor().cloned() else { return Ok(None) };
    if cursor.parent().content().size > 0 {
        return Ok(None);
    }
    if cursor.depth > 1 && cursor.after(cursor.depth)? != cursor.end(cursor.depth - 1) {
        let before = cursor.before(cursor.depth)?;
        if can_split(&state.doc, before, 1, None)? {
            let mut tr = state.tr();
            tr.split(before, 1, None)?;
            return Ok(Some(tr));
        }
    }
    let Some(range) = cursor.block_range(&cursor, None) else { return Ok(None) };
    let Some(target) = lift_target(&range)? else { return Ok(None) };
    let mut tr = state.tr();
    tr.lift(&range, target)?;
    Ok(Some(tr))
}

/// `splitBlockKeepMarks` (`splitBlockAs()` keeping the marks at the cursor).
pub fn split_block_keep_marks(state: &State) -> Result<Option<Transaction>> {
    let Some(mut tr) = split_block(state)? else { return Ok(None) };
    let to = state.selection.sel_to();
    if to.parent_offset > 0 {
        tr.ensure_marks(state.selection.sel_from().marks())?;
    }
    Ok(Some(tr))
}

fn split_block(state: &State) -> Result<Option<Transaction>> {
    if let Selection::Node { anchor, node, .. } = &state.selection
        && node.is_block()
    {
        if anchor.parent_offset == 0 || !can_split(&state.doc, anchor.pos, 1, None)? {
            return Ok(None);
        }
        let mut tr = state.tr();
        tr.split(anchor.pos, 1, None)?;
        return Ok(Some(tr));
    }
    if state.selection.sel_from().depth == 0 {
        return Ok(None);
    }
    let mut tr = state.tr();
    if !state.selection.empty() && matches!(state.selection, Selection::Text { .. } | Selection::All { .. }) {
        tr.delete_selection()?;
    }
    let from = tr.selection()?.sel_from();
    let map_from = tr.steps.len();
    let mut types: Vec<Option<TypeAttrs>> = Vec::new();
    let (split_depth, deflt, at_end, at_start);
    let mut d = from.depth;
    loop {
        let node = from.node(d);
        if node.is_block() {
            if d == 0 {
                // `$from.node(-1)` of a position directly in the document.
                crate::error::bail!("Cannot read properties of undefined (reading 'contentMatchAt')");
            }
            at_end = from.end(d) == from.pos + (from.depth - d);
            at_start = from.start(d) as isize == from.pos as isize - (from.depth - d) as isize;
            deflt = default_block_at(from.node(d - 1).content_match_at(from.index_after(d - 1))?);
            types.insert(0, if at_end { deflt.map(|ty| TypeAttrs { ty, attrs: None }) } else { None });
            split_depth = d;
            break;
        }
        if d == 1 {
            return Ok(None);
        }
        types.insert(0, None);
        d -= 1;
    }
    let split_pos = from.pos;
    let mut can = can_split(&tr.doc, split_pos, types.len(), Some(&types))?;
    if !can {
        types[0] = deflt.map(|ty| TypeAttrs { ty, attrs: None });
        can = can_split(&tr.doc, split_pos, types.len(), Some(&types))?;
    }
    if !can {
        return Ok(None);
    }
    tr.split(split_pos, types.len(), Some(&types))?;
    if !at_end && at_start && Some(from.node(split_depth).ty()) != deflt {
        let mapping = tr.mapping.slice(map_from, tr.mapping.maps.len());
        let first = mapping.map(from.before(split_depth)?, 1);
        let rfirst = tr.doc.resolve(first)?;
        if let Some(deflt) = deflt
            && from.node(split_depth - 1).can_replace_with(rfirst.index_here(), rfirst.index_here() + 1, deflt, None)?
        {
            let at = mapping.map(from.before(split_depth)?, 1);
            tr.set_node_markup(at, Some(deflt), None, None)?;
        }
    }
    Ok(Some(tr))
}

/// `splitListItemKeepMarks(itemType, itemAttrs)`.
pub fn split_list_item_keep_marks(state: &State, item_type: TypeId, item_attrs: Option<Map>) -> Result<Option<Transaction>> {
    let Some(mut tr) = split_list_item(state, item_type, item_attrs)? else { return Ok(None) };
    if state.selection.sel_to().parent_offset > 0 {
        tr.ensure_marks(state.selection.sel_from().marks())?;
    }
    Ok(Some(tr))
}

fn split_list_item(state: &State, item_type: TypeId, item_attrs: Option<Map>) -> Result<Option<Transaction>> {
    let s = schema();
    let (from, to) = (state.selection.sel_from(), state.selection.sel_to());
    if let Selection::Node { node, .. } = &state.selection
        && node.is_block()
    {
        return Ok(None);
    }
    if from.depth < 2 || !from.same_parent(&to) {
        return Ok(None);
    }
    let grand_parent = from.node(from.depth - 1).clone();
    if grand_parent.ty() != item_type {
        return Ok(None);
    }
    if from.parent().content().size == 0 && from.node(from.depth - 1).child_count() == from.index_after(from.depth - 1) {
        if from.depth == 3 || from.node(from.depth - 3).ty() != item_type || from.index(from.depth - 2) != from.node(from.depth - 2).child_count() - 1 {
            return Ok(None);
        }
        let mut wrap = Fragment::empty();
        let depth_before = if from.index(from.depth - 1) > 0 {
            1
        } else if from.index(from.depth - 2) > 0 {
            2
        } else {
            3
        };
        for d in ((from.depth - 3)..=(from.depth - depth_before)).rev() {
            wrap = Fragment::from_node(from.node(d).copy(wrap));
        }
        let depth_after = if from.index_after(from.depth - 1) < from.node(from.depth - 2).child_count() {
            1
        } else if from.index_after(from.depth - 2) < from.node(from.depth - 3).child_count() {
            2
        } else {
            3
        };
        let item = Node::create_and_fill(item_type, None, Fragment::empty(), Vec::new())?.expect("list item");
        wrap = wrap.append(&Fragment::from_node(item));
        let start = from.before(from.depth - (depth_before - 1))?;
        let mut tr = state.tr();
        tr.replace(start, from.after(from.depth - depth_after)?, &Slice::new(wrap, 4 - depth_before, 0))?;
        let mut sel: Option<usize> = None;
        let doc = tr.doc.clone();
        doc.nodes_between(
            start,
            doc.content().size,
            &mut |node, pos, _, _| {
                if sel.is_some() {
                    return false;
                }
                if node.is_textblock() && node.content().size == 0 {
                    sel = Some(pos + 1);
                }
                true
            },
            0,
        );
        if let Some(sel) = sel {
            let selection = near(&doc.resolve(sel)?, 1)?;
            tr.set_selection(selection)?;
        }
        return Ok(Some(tr));
    }
    let next_type = if to.pos == from.end(from.depth) { s.default_type(grand_parent.content_match_at(0)?) } else { None };
    let mut tr = state.tr();
    tr.delete(from.pos, to.pos)?;
    let types: Option<Vec<Option<TypeAttrs>>> =
        next_type.map(|next| vec![item_attrs.map(|attrs| TypeAttrs { ty: item_type, attrs: Some(attrs) }), Some(TypeAttrs { ty: next, attrs: None })]);
    if !can_split(&tr.doc, from.pos, 2, types.as_deref())? {
        return Ok(None);
    }
    tr.split(from.pos, 2, types.as_deref())?;
    Ok(Some(tr))
}

fn list_range(state: &State, item_type: TypeId) -> Option<NodeRange> {
    let (from, to) = (state.selection.sel_from(), state.selection.sel_to());
    let pred = |node: &Node| node.child_count() > 0 && node.first_child().is_some_and(|c| c.ty() == item_type);
    from.block_range(&to, Some(&pred))
}

/// `liftListItem(itemType)`.
pub fn lift_list_item(state: &State, item_type: TypeId) -> Result<Option<Transaction>> {
    let Some(range) = list_range(state, item_type) else { return Ok(None) };
    let from = state.selection.sel_from();
    if range.depth >= 1 && from.node(range.depth - 1).ty() == item_type { lift_to_outer_list(state, item_type, range) } else { lift_out_of_list(state, range) }
}

fn lift_to_outer_list(state: &State, item_type: TypeId, range: NodeRange) -> Result<Option<Transaction>> {
    let mut tr = state.tr();
    let end = range.end();
    let end_of_list = range.to.end(range.depth);
    let mut range = range;
    if end < end_of_list {
        let wrapped = Node::create(item_type, None, Fragment::from_node(range.parent().copy(Fragment::empty())), Vec::new())?;
        tr.step(Step::ReplaceAround {
            from: end - 1,
            to: end_of_list,
            gap_from: end,
            gap_to: end_of_list,
            slice: Slice::new(Fragment::from_node(wrapped), 1, 0),
            insert: 1,
            structure: true,
        })?;
        let doc = tr.doc.clone();
        range = NodeRange { from: doc.resolve(range.from.pos)?, to: doc.resolve(end_of_list)?, depth: range.depth };
    }
    let Some(target) = lift_target(&range)? else { return Ok(None) };
    tr.lift(&range, target)?;
    let after = tr.doc.resolve(tr.mapping.map(end, -1) - 1)?;
    if can_join(&tr.doc, after.pos)?
        && let (Some(before_node), Some(after_node)) = (after.node_before(), after.node_after())
        && before_node.ty() == after_node.ty()
    {
        tr.join(after.pos, 1)?;
    }
    Ok(Some(tr))
}

fn lift_out_of_list(state: &State, range: NodeRange) -> Result<Option<Transaction>> {
    let mut tr = state.tr();
    let list = range.parent().clone();
    let mut pos = range.end();
    let mut i = range.end_index() as isize - 1;
    while i > range.start_index() as isize {
        pos -= list.child(i as usize).node_size();
        tr.delete(pos - 1, pos + 1)?;
        i -= 1;
    }
    let start_pos = tr.doc.resolve(range.start())?;
    let item = start_pos.node_after().expect("list item");
    if tr.mapping.map(range.end(), 1) != range.start() + item.node_size() {
        return Ok(None);
    }
    let at_start = range.start_index() == 0;
    let at_end = range.end_index() == list.child_count();
    let parent = start_pos.node(start_pos.depth - 1);
    let index_before = start_pos.index(start_pos.depth - 1);
    let replacement = item.content().append(&if at_end { Fragment::empty() } else { Fragment::from_node(list.clone()) });
    if !parent.can_replace(index_before + if at_start { 0 } else { 1 }, index_before + 1, &replacement, 0, replacement.child_count())? {
        return Ok(None);
    }
    let start = start_pos.pos;
    let end = start + item.node_size();
    let before = if at_start { Fragment::empty() } else { Fragment::from_node(list.copy(Fragment::empty())) };
    let after = if at_end { Fragment::empty() } else { Fragment::from_node(list.copy(Fragment::empty())) };
    tr.step(Step::ReplaceAround {
        from: start - usize::from(at_start),
        to: end + usize::from(at_end),
        gap_from: start + 1,
        gap_to: end - 1,
        slice: Slice::new(before.append(&after), if at_start { 0 } else { 1 }, if at_end { 0 } else { 1 }),
        insert: if at_start { 0 } else { 1 },
        structure: false,
    })?;
    Ok(Some(tr))
}

/// `sinkListItem(itemType)`.
pub fn sink_list_item(state: &State, item_type: TypeId) -> Result<Option<Transaction>> {
    let Some(range) = list_range(state, item_type) else { return Ok(None) };
    let start_index = range.start_index();
    if start_index == 0 {
        return Ok(None);
    }
    let parent = range.parent().clone();
    let node_before = parent.child(start_index - 1).clone();
    if node_before.ty() != item_type {
        return Ok(None);
    }
    let nested_before = node_before.last_child().is_some_and(|c| c.ty() == parent.ty());
    let inner = if nested_before { Fragment::from_node(Node::create(item_type, None, Fragment::empty(), Vec::new())?) } else { Fragment::empty() };
    let list = Node::create(parent.ty(), None, inner, Vec::new())?;
    let wrapped = Node::create(item_type, None, Fragment::from_node(list), Vec::new())?;
    let slice = Slice::new(Fragment::from_node(wrapped), if nested_before { 3 } else { 1 }, 0);
    let (before, after) = (range.start(), range.end());
    let mut tr = state.tr();
    tr.step(Step::ReplaceAround {
        from: before - if nested_before { 3 } else { 1 },
        to: after,
        gap_from: before,
        gap_to: after,
        slice,
        insert: 1,
        structure: true,
    })?;
    Ok(Some(tr))
}
