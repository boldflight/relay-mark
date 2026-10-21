// Ported from prosemirror-transform 1.12.2.
// ProseMirror is Copyright (C) 2015-2017 by Marijn Haverbeke and others, used under the MIT License; see THIRD_PARTY_NOTICES.md.
//! prosemirror-transform 1.12's structure helpers (structure.ts), slice
//! fitting (replace.ts, the `Fitter`) and the `Transform` methods built on
//! them.

use crate::error::{Result, bail};
use crate::json::Map;

use super::model::{Fragment, Mark, Node, NodeRange, ResolvedPos, Slice, allowed_marks, fill_before, match_fragment, valid_content};
use super::schema::{MatchId, TypeId, schema};
use super::step::{Step, Transform};

/// A wrapper or split type with optional attributes.
#[derive(Clone, Debug)]
pub struct TypeAttrs {
    pub ty: TypeId,
    pub attrs: Option<Map>,
}

fn can_cut(node: &Node, start: usize, end: usize) -> Result<bool> {
    Ok((start == 0 || node.can_replace(start, node.child_count(), &Fragment::empty(), 0, 0)?)
        && (end == node.child_count() || node.can_replace(0, end, &Fragment::empty(), 0, 0)?))
}

/// `liftTarget`.
pub fn lift_target(range: &NodeRange) -> Result<Option<usize>> {
    let parent = range.parent();
    let content = parent.content().cut_by_index(range.start_index(), range.end_index());
    let mut content_before = 0;
    let mut content_after = 0;
    let mut depth = range.depth as isize;
    loop {
        let d = depth as usize;
        let node = range.from.node(d);
        let index = range.from.index(d) + content_before;
        let end_index = range.to.index_after(d) - content_after;
        if d < range.depth && node.can_replace(index, end_index, &content, 0, content.child_count())? {
            return Ok(Some(d));
        }
        if d == 0 || schema().nodes[node.ty()].isolating || !can_cut(node, index, end_index)? {
            break;
        }
        if index > 0 {
            content_before = 1;
        }
        if end_index < node.child_count() {
            content_after = 1;
        }
        depth -= 1;
    }
    Ok(None)
}

/// `findWrapping`.
pub fn find_wrapping(range: &NodeRange, ty: TypeId, attrs: Option<Map>, inner_range: Option<&NodeRange>) -> Result<Option<Vec<TypeAttrs>>> {
    let Some(around) = find_wrapping_outside(range, ty)? else { return Ok(None) };
    let Some(inner) = find_wrapping_inside(inner_range.unwrap_or(range), ty) else { return Ok(None) };
    let mut result: Vec<TypeAttrs> = around.into_iter().map(|ty| TypeAttrs { ty, attrs: None }).collect();
    result.push(TypeAttrs { ty, attrs });
    result.extend(inner.into_iter().map(|ty| TypeAttrs { ty, attrs: None }));
    Ok(Some(result))
}

fn find_wrapping_outside(range: &NodeRange, ty: TypeId) -> Result<Option<Vec<TypeId>>> {
    let parent = range.parent();
    let Some(around) = schema().find_wrapping(parent.content_match_at(range.start_index())?, ty) else { return Ok(None) };
    let outer = around.first().copied().unwrap_or(ty);
    Ok(if parent.can_replace_with(range.start_index(), range.end_index(), outer, None)? { Some(around) } else { None })
}

fn find_wrapping_inside(range: &NodeRange, ty: TypeId) -> Option<Vec<TypeId>> {
    let s = schema();
    let parent = range.parent();
    let inner = parent.child(range.start_index());
    let inside = s.find_wrapping(s.nodes[ty].content, inner.ty())?;
    let last = inside.last().copied().unwrap_or(ty);
    let mut matched = Some(s.nodes[last].content);
    for i in range.start_index()..range.end_index() {
        matched = matched.and_then(|m| s.match_type(m, parent.child(i).ty()));
    }
    matched.filter(|&m| s.valid_end(m)).map(|_| inside)
}

/// `canSplit`.
pub fn can_split(doc: &Node, pos: usize, depth: usize, types_after: Option<&[Option<TypeAttrs>]>) -> Result<bool> {
    let s = schema();
    let rp = doc.resolve(pos)?;
    let base = rp.depth as isize - depth as isize;
    let parent = rp.parent();
    let inner_type = types_after.and_then(|t| t.last().cloned().flatten()).map_or(parent.ty(), |t| t.ty);
    if base < 0
        || s.nodes[parent.ty()].isolating
        || !parent.can_replace(rp.index_here(), parent.child_count(), &Fragment::empty(), 0, 0)?
        || !valid_content(inner_type, &parent.content().cut_by_index(rp.index_here(), parent.child_count()))
    {
        return Ok(false);
    }
    let base = base as usize;
    let mut i = depth as isize - 2;
    let mut d = rp.depth as isize - 1;
    while d > base as isize {
        let du = d as usize;
        let node = rp.node(du);
        let index = rp.index(du);
        if s.nodes[node.ty()].isolating {
            return Ok(false);
        }
        let mut rest = node.content().cut_by_index(index, node.child_count());
        if let Some(Some(over)) = types_after.and_then(|t| t.get((i + 1) as usize)) {
            rest = rest.replace_child(0, Node::create(over.ty, over.attrs.as_ref(), Fragment::empty(), Vec::new())?);
        }
        let after = types_after.and_then(|t| if i >= 0 { t.get(i as usize).cloned().flatten() } else { None }).map_or(node.ty(), |t| t.ty);
        if !node.can_replace(index + 1, node.child_count(), &Fragment::empty(), 0, 0)? || !valid_content(after, &rest) {
            return Ok(false);
        }
        d -= 1;
        i -= 1;
    }
    let index = rp.index_after(base);
    let base_type = types_after.and_then(|t| t.first().cloned().flatten()).map_or(rp.node(base + 1).ty(), |t| t.ty);
    rp.node(base).can_replace_with(index, index, base_type, None)
}

/// `canJoin`.
pub fn can_join(doc: &Node, pos: usize) -> Result<bool> {
    let rp = doc.resolve(pos)?;
    let index = rp.index_here();
    Ok(joinable(rp.node_before().as_ref(), rp.node_after().as_ref())? && rp.parent().can_replace(index, index + 1, &Fragment::empty(), 0, 0)?)
}

fn can_append_with_substituted_linebreaks(a: &Node, b: &Node) -> Result<bool> {
    let s = schema();
    let linebreak = (0..s.nodes.len()).find(|&t| s.nodes[t].linebreak_replacement);
    let mut matched = Some(a.content_match_at(a.child_count())?);
    for child in b.content().iter() {
        let ty = if Some(child.ty()) == linebreak { s.text } else { child.ty() };
        matched = matched.and_then(|m| s.match_type(m, ty));
        if matched.is_none() {
            return Ok(false);
        }
        if !super::model::allows_marks(a.ty(), child.marks()) {
            return Ok(false);
        }
    }
    Ok(matched.is_some_and(|m| s.valid_end(m)))
}

fn joinable(a: Option<&Node>, b: Option<&Node>) -> Result<bool> {
    match (a, b) {
        (Some(a), Some(b)) if !a.is_leaf() => can_append_with_substituted_linebreaks(a, b),
        _ => Ok(false),
    }
}

/// `insertPoint`.
pub fn insert_point(doc: &Node, pos: usize, ty: TypeId) -> Result<Option<usize>> {
    let rp = doc.resolve(pos)?;
    if rp.parent().can_replace_with(rp.index_here(), rp.index_here(), ty, None)? {
        return Ok(Some(pos));
    }
    if rp.parent_offset == 0 {
        for d in (0..rp.depth).rev() {
            let index = rp.index(d);
            if rp.node(d).can_replace_with(index, index, ty, None)? {
                return Ok(Some(rp.before(d + 1)?));
            }
            if index > 0 {
                return Ok(None);
            }
        }
    }
    if rp.parent_offset == rp.parent().content().size {
        for d in (0..rp.depth).rev() {
            let index = rp.index_after(d);
            if rp.node(d).can_replace_with(index, index, ty, None)? {
                return Ok(Some(rp.after(d + 1)?));
            }
            if index < rp.node(d).child_count() {
                return Ok(None);
            }
        }
    }
    Ok(None)
}

/// `replaceStep`.
pub fn replace_step(doc: &Node, from: usize, to: usize, slice: &Slice) -> Result<Option<Step>> {
    if from == to && slice.size() == 0 {
        return Ok(None);
    }
    let rf = doc.resolve(from)?;
    let rt = doc.resolve(to)?;
    if fits_trivially(&rf, &rt, slice)? {
        return Ok(Some(Step::Replace { from, to, slice: slice.clone(), structure: false }));
    }
    Fitter::new(rf, rt, slice.clone())?.fit()
}

fn fits_trivially(rf: &ResolvedPos, rt: &ResolvedPos, slice: &Slice) -> Result<bool> {
    Ok(slice.open_start == 0
        && slice.open_end == 0
        && rf.start(rf.depth) == rt.start(rt.depth)
        && rf.parent().can_replace(rf.index_here(), rt.index_here(), &slice.content, 0, slice.content.child_count())?)
}

struct Fittable {
    slice_depth: usize,
    frontier_depth: usize,
    parent: Option<Node>,
    inject: Option<Fragment>,
    wrap: Option<Vec<TypeId>>,
}

struct Frontier {
    ty: TypeId,
    /// `null` once an opened node did not fit, as upstream tolerates until
    /// the match is next used.
    matched: Option<MatchId>,
}

fn null_match() -> crate::Error {
    crate::Error::new("Cannot read properties of null (reading 'matchType')")
}

impl Frontier {
    fn m(&self) -> Result<MatchId> {
        self.matched.ok_or_else(null_match)
    }
}

struct Fitter {
    from: ResolvedPos,
    to: ResolvedPos,
    unplaced: Slice,
    frontier: Vec<Frontier>,
    placed: Fragment,
}

fn content_at(fragment: &Fragment, depth: usize) -> Fragment {
    let mut fragment = fragment.clone();
    for _ in 0..depth {
        fragment = fragment.first_child().expect("open content").content().clone();
    }
    fragment
}

fn drop_from_fragment(fragment: &Fragment, depth: usize, count: usize) -> Fragment {
    if depth == 0 {
        return fragment.cut_by_index(count, fragment.child_count());
    }
    let first = fragment.first_child().expect("first child");
    fragment.replace_child(0, first.copy(drop_from_fragment(first.content(), depth - 1, count)))
}

fn add_to_fragment(fragment: &Fragment, depth: usize, content: &Fragment) -> Fragment {
    if depth == 0 {
        return fragment.append(content);
    }
    let last = fragment.last_child().expect("last child");
    fragment.replace_child(fragment.child_count() - 1, last.copy(add_to_fragment(last.content(), depth - 1, content)))
}

fn close_node_start(node: &Node, open_start: isize, open_end: isize) -> Result<Node> {
    if open_start <= 0 {
        return Ok(node.clone());
    }
    let start_match = schema().nodes[node.ty()].content;
    let mut frag = node.content().clone();
    if open_start > 1 {
        let first = frag.first_child().expect("first child").clone();
        frag = frag.replace_child(0, close_node_start(&first, open_start - 1, if frag.child_count() == 1 { open_end - 1 } else { 0 })?);
    }
    let Some(before) = fill_before(start_match, &frag, false, 0)? else { bail!("Cannot read properties of null (reading 'append')") };
    frag = before.append(&frag);
    if open_end <= 0 {
        let after = match_fragment(start_match, &frag, 0, frag.child_count()).map(|m| fill_before(m, &Fragment::empty(), true, 0)).transpose()?.flatten();
        let Some(after) = after else { bail!("Cannot read properties of null (reading 'fillBefore')") };
        frag = frag.append(&after);
    }
    Ok(node.copy(frag))
}

fn content_after_fits(to: &ResolvedPos, depth: usize, ty: TypeId, matched: MatchId, open: bool) -> Result<Option<Fragment>> {
    let s = schema();
    let node = to.node(depth);
    let index = if open { to.index_after(depth) } else { to.index(depth) };
    if index == node.child_count() && !s.compatible_content(ty, node.ty()) {
        return Ok(None);
    }
    let fit = fill_before(matched, node.content(), true, index)?;
    Ok(fit.filter(|_| !invalid_marks(ty, node.content(), index)))
}

fn invalid_marks(ty: TypeId, fragment: &Fragment, start: usize) -> bool {
    (start..fragment.child_count()).any(|i| !super::model::allows_marks(ty, fragment.child(i).marks()))
}

fn max_open_side(frag: &Fragment, start: bool) -> usize {
    let mut frag = frag.clone();
    let mut count = 0;
    loop {
        let child = if start { frag.first_child() } else { frag.last_child() };
        match child {
            Some(ch) if !ch.is_atom() => {
                let next = ch.content().clone();
                frag = next;
                count += 1;
            }
            _ => return count,
        }
    }
}

impl Fitter {
    fn new(from: ResolvedPos, to: ResolvedPos, unplaced: Slice) -> Result<Fitter> {
        let mut frontier = Vec::new();
        for i in 0..=from.depth {
            let node = from.node(i);
            frontier.push(Frontier { ty: node.ty(), matched: Some(node.content_match_at(from.index_after(i))?) });
        }
        let mut placed = Fragment::empty();
        for i in (1..=from.depth).rev() {
            placed = Fragment::from_node(from.node(i).copy(placed));
        }
        Ok(Fitter { from, to, unplaced, frontier, placed })
    }

    fn depth(&self) -> usize {
        self.frontier.len() - 1
    }

    fn fit(mut self) -> Result<Option<Step>> {
        while self.unplaced.size() > 0 {
            match self.find_fittable()? {
                Some(fit) => self.place_nodes(fit)?,
                None => {
                    if !self.open_more() {
                        self.drop_node();
                    }
                }
            }
        }
        let move_inline = self.must_move_inline()?;
        let placed_size = self.placed.size as isize - self.depth() as isize - self.from.depth as isize;
        let from = self.from.clone();
        let target = match move_inline {
            Some(pos) => from.doc().resolve(pos)?,
            None => self.to.clone(),
        };
        let Some(to) = self.close(target)? else { return Ok(None) };
        let mut content = self.placed.clone();
        let mut open_start = from.depth;
        let mut open_end = to.depth;
        while open_start > 0 && open_end > 0 && content.child_count() == 1 {
            content = content.first_child().expect("child").content().clone();
            open_start -= 1;
            open_end -= 1;
        }
        let slice = Slice::new(content, open_start, open_end);
        if let Some(move_to) = move_inline {
            return Ok(Some(Step::ReplaceAround {
                from: from.pos,
                to: move_to,
                gap_from: self.to.pos,
                gap_to: self.to.end(self.to.depth),
                slice,
                insert: placed_size.max(0) as usize,
                structure: false,
            }));
        }
        if slice.size() != 0 || from.pos != self.to.pos {
            return Ok(Some(Step::Replace { from: from.pos, to: to.pos, slice, structure: false }));
        }
        Ok(None)
    }

    fn find_fittable(&self) -> Result<Option<Fittable>> {
        let s = schema();
        let mut start_depth = self.unplaced.open_start;
        {
            let mut cur = self.unplaced.content.clone();
            let mut open_end = self.unplaced.open_end;
            for d in 0..start_depth {
                let node = cur.first_child().expect("open child").clone();
                if cur.child_count() > 1 {
                    open_end = 0;
                }
                if s.nodes[node.ty()].isolating && open_end <= d {
                    start_depth = d;
                    break;
                }
                cur = node.content().clone();
            }
        }
        for pass in 1..=2 {
            let first_depth = if pass == 1 { start_depth } else { self.unplaced.open_start };
            for slice_depth in (0..=first_depth).rev() {
                let (fragment, parent) = if slice_depth > 0 {
                    let parent = content_at(&self.unplaced.content, slice_depth - 1).first_child().cloned();
                    (parent.as_ref().expect("parent").content().clone(), parent)
                } else {
                    (self.unplaced.content.clone(), None)
                };
                let first = fragment.first_child().cloned();
                for frontier_depth in (0..=self.depth()).rev() {
                    let ty = self.frontier[frontier_depth].ty;
                    let matched = self.frontier[frontier_depth].m()?;
                    if pass == 1 {
                        let found = match &first {
                            Some(first) => {
                                if s.match_type(matched, first.ty()).is_some() {
                                    Some(None)
                                } else {
                                    fill_before(matched, &Fragment::from_node(first.clone()), false, 0)?.map(Some)
                                }
                            }
                            None => parent.as_ref().filter(|p| s.compatible_content(ty, p.ty())).map(|_| None),
                        };
                        if let Some(inject) = found {
                            return Ok(Some(Fittable { slice_depth, frontier_depth, parent, inject, wrap: None }));
                        }
                    } else if let Some(first) = &first
                        && let Some(wrap) = s.find_wrapping(matched, first.ty())
                    {
                        return Ok(Some(Fittable { slice_depth, frontier_depth, parent, inject: None, wrap: Some(wrap) }));
                    }
                    if let Some(p) = &parent
                        && s.match_type(matched, p.ty()).is_some()
                    {
                        break;
                    }
                }
            }
        }
        Ok(None)
    }

    fn open_more(&mut self) -> bool {
        let Slice { content, open_start, mut open_end } = self.unplaced.clone();
        if max_open_side(&content, true) <= open_start {
            return false;
        }
        if self.unplaced.size() > 1 && max_open_side(&content, false) > open_end {
            open_end += 1;
        }
        self.unplaced = Slice::new(content, open_start + 1, open_end);
        true
    }

    fn drop_node(&mut self) {
        let Slice { content, open_start, open_end } = self.unplaced.clone();
        let inner = content_at(&content, open_start);
        if inner.child_count() <= 1 && open_start > 0 {
            let open_at_end = content.size as isize - open_start as isize <= (open_start + inner.size) as isize;
            self.unplaced = Slice::new(drop_from_fragment(&content, open_start - 1, 1), open_start - 1, if open_at_end { open_start - 1 } else { open_end });
        } else {
            self.unplaced = Slice::new(drop_from_fragment(&content, open_start, 1), open_start, open_end);
        }
    }

    fn place_nodes(&mut self, fit: Fittable) -> Result<()> {
        let s = schema();
        let Fittable { slice_depth, frontier_depth, parent, inject, wrap } = fit;
        while self.depth() > frontier_depth {
            self.close_frontier_node()?;
        }
        if let Some(wrap) = &wrap {
            for &ty in wrap {
                self.open_frontier_node(ty, None, None)?;
            }
        }
        let slice = self.unplaced.clone();
        let fragment = parent.as_ref().map_or(slice.content.clone(), |p| p.content().clone());
        let open_start = slice.open_start as isize - slice_depth as isize;
        let mut taken = 0;
        let mut add: Vec<Node> = Vec::new();
        let ty = self.frontier[frontier_depth].ty;
        let mut matched = self.frontier[frontier_depth].m()?;
        if let Some(inject) = &inject {
            add.extend(inject.iter().cloned());
            matched = match_fragment(matched, inject, 0, inject.child_count()).ok_or_else(null_match)?;
        }
        let mut open_end_count = (fragment.size + slice_depth) as isize - (slice.content.size as isize - slice.open_end as isize);
        while taken < fragment.child_count() {
            let next = fragment.child(taken);
            let Some(matches) = s.match_type(matched, next.ty()) else { break };
            taken += 1;
            if taken > 1 || open_start == 0 || next.content().size > 0 {
                matched = matches;
                let marked = next.mark(allowed_marks(ty, next.marks()));
                add.push(close_node_start(
                    &marked,
                    if taken == 1 { open_start } else { 0 },
                    if taken == fragment.child_count() { open_end_count } else { -1 },
                )?);
            }
        }
        let to_end = taken == fragment.child_count();
        if !to_end {
            open_end_count = -1;
        }
        self.placed = add_to_fragment(&self.placed, frontier_depth, &Fragment::from_array(add));
        self.frontier[frontier_depth].matched = Some(matched);
        if to_end && open_end_count < 0 && parent.as_ref().is_some_and(|p| p.ty() == self.frontier[self.depth()].ty) && self.frontier.len() > 1 {
            self.close_frontier_node()?;
        }
        let mut cur = fragment.clone();
        for _ in 0..open_end_count.max(0) {
            let node = cur.last_child().expect("open end").clone();
            self.frontier.push(Frontier { ty: node.ty(), matched: Some(node.content_match_at(node.child_count())?) });
            cur = node.content().clone();
        }
        self.unplaced = if !to_end {
            Slice::new(drop_from_fragment(&slice.content, slice_depth, taken), slice.open_start, slice.open_end)
        } else if slice_depth == 0 {
            Slice::empty()
        } else {
            Slice::new(
                drop_from_fragment(&slice.content, slice_depth - 1, 1),
                slice_depth - 1,
                if open_end_count < 0 { slice.open_end } else { slice_depth - 1 },
            )
        };
        Ok(())
    }

    fn must_move_inline(&self) -> Result<Option<usize>> {
        let s = schema();
        if !self.to.parent().is_textblock() {
            return Ok(None);
        }
        let top = &self.frontier[self.depth()];
        if !s.is_textblock(top.ty) || content_after_fits(&self.to, self.to.depth, top.ty, top.m()?, false)?.is_none() {
            return Ok(None);
        }
        if self.to.depth == self.depth()
            && let Some(level) = self.find_close_level(&self.to)?
            && level.0 == self.depth()
        {
            return Ok(None);
        }
        let mut depth = self.to.depth;
        let mut after = self.to.after(depth)?;
        while depth > 1 {
            depth -= 1;
            if after != self.to.end(depth) {
                break;
            }
            after += 1;
        }
        Ok(Some(after))
    }

    /// (depth, fit, move).
    fn find_close_level(&self, to: &ResolvedPos) -> Result<Option<(usize, Fragment, ResolvedPos)>> {
        'scan: for i in (0..=self.depth().min(to.depth)).rev() {
            let (ty, matched) = (self.frontier[i].ty, self.frontier[i].m()?);
            let drop_inner = i < to.depth && to.end(i + 1) == to.pos + (to.depth - (i + 1));
            let Some(fit) = content_after_fits(to, i, ty, matched, drop_inner)? else { continue };
            for d in (0..i).rev() {
                let (ty, matched) = (self.frontier[d].ty, self.frontier[d].m()?);
                match content_after_fits(to, d, ty, matched, true)? {
                    Some(m) if m.child_count() == 0 => {}
                    _ => continue 'scan,
                }
            }
            let mv = if drop_inner { to.doc().resolve(to.after(i + 1)?)? } else { to.clone() };
            return Ok(Some((i, fit, mv)));
        }
        Ok(None)
    }

    fn close(&mut self, to: ResolvedPos) -> Result<Option<ResolvedPos>> {
        let Some((depth, fit, mv)) = self.find_close_level(&to)? else { return Ok(None) };
        while self.depth() > depth {
            self.close_frontier_node()?;
        }
        if fit.child_count() > 0 {
            self.placed = add_to_fragment(&self.placed, depth, &fit);
        }
        let to = mv;
        for d in depth + 1..=to.depth {
            let node = to.node(d).clone();
            let add = fill_before(schema().nodes[node.ty()].content, node.content(), true, to.index(d))?.expect("fillable content");
            self.open_frontier_node(node.ty(), Some((**node.attrs()).clone()), Some(add))?;
        }
        Ok(Some(to))
    }

    fn open_frontier_node(&mut self, ty: TypeId, attrs: Option<Map>, content: Option<Fragment>) -> Result<()> {
        let s = schema();
        let depth = self.depth();
        let top = &mut self.frontier[depth];
        top.matched = s.match_type(top.m()?, ty);
        let node = Node::create(ty, attrs.as_ref(), content.unwrap_or_else(Fragment::empty), Vec::new())?;
        self.placed = add_to_fragment(&self.placed, depth, &Fragment::from_node(node));
        self.frontier.push(Frontier { ty, matched: Some(s.nodes[ty].content) });
        Ok(())
    }

    fn close_frontier_node(&mut self) -> Result<()> {
        let open = self.frontier.pop().expect("frontier");
        let add = fill_before(open.m()?, &Fragment::empty(), true, 0)?.ok_or_else(null_match)?;
        if add.child_count() > 0 {
            self.placed = add_to_fragment(&self.placed, self.frontier.len(), &add);
        }
        Ok(())
    }
}

/// `closeFragment` of `replaceRange`.
fn close_fragment(fragment: &Fragment, depth: usize, old_open: usize, new_open: usize, parent: Option<&Node>) -> Result<Fragment> {
    let mut fragment = fragment.clone();
    if depth < old_open {
        let first = fragment.first_child().expect("open child").clone();
        fragment = fragment.replace_child(0, first.copy(close_fragment(first.content(), depth + 1, old_open, new_open, Some(&first))?));
    }
    if depth > new_open {
        let matched = parent.expect("parent").content_match_at(0)?;
        let start = fill_before(matched, &fragment, false, 0)?.expect("fillable").append(&fragment);
        let end =
            match_fragment(matched, &start, 0, start.child_count()).and_then(|m| fill_before(m, &Fragment::empty(), true, 0).ok().flatten()).expect("closable");
        fragment = start.append(&end);
    }
    Ok(fragment)
}

/// `coveredDepths`.
fn covered_depths(rf: &ResolvedPos, rt: &ResolvedPos) -> Vec<usize> {
    let s = schema();
    let mut result = Vec::new();
    for d in (0..=rf.depth.min(rt.depth)).rev() {
        let start = rf.start(d);
        if (start as isize) < rf.pos as isize - (rf.depth - d) as isize
            || rt.end(d) > rt.pos + (rt.depth - d)
            || s.nodes[rf.node(d).ty()].isolating
            || s.nodes[rt.node(d).ty()].isolating
        {
            break;
        }
        if start == rt.start(d)
            || (d == rf.depth && d == rt.depth && rf.parent().inline_content() && rt.parent().inline_content() && d > 0 && rt.start(d - 1) == start - 1)
        {
            result.push(d);
        }
    }
    result
}

impl Transform {
    pub fn replace(&mut self, from: usize, to: usize, slice: &Slice) -> Result<()> {
        if let Some(step) = replace_step(&self.doc, from, to, slice)? {
            self.step(step)?;
        }
        Ok(())
    }

    pub fn replace_with(&mut self, from: usize, to: usize, content: Fragment) -> Result<()> {
        self.replace(from, to, &Slice::new(content, 0, 0))
    }

    pub fn delete(&mut self, from: usize, to: usize) -> Result<()> {
        self.replace(from, to, &Slice::empty())
    }

    pub fn insert(&mut self, pos: usize, content: Fragment) -> Result<()> {
        self.replace_with(pos, pos, content)
    }

    /// `replaceRange`.
    pub fn replace_range(&mut self, from: usize, to: usize, slice: &Slice) -> Result<()> {
        let s = schema();
        if slice.size() == 0 {
            return self.delete_range(from, to);
        }
        let rf = self.doc.resolve(from)?;
        let rt = self.doc.resolve(to)?;
        if fits_trivially(&rf, &rt, slice)? {
            return self.step(Step::Replace { from, to, slice: slice.clone(), structure: false });
        }
        let mut target_depths: Vec<isize> = covered_depths(&rf, &rt).into_iter().map(|d| d as isize).collect();
        if target_depths.last() == Some(&0) {
            target_depths.pop();
        }
        let mut preferred_target = -(rf.depth as isize + 1);
        target_depths.insert(0, preferred_target);
        let mut pos = rf.pos as isize - 1;
        for d in (1..=rf.depth).rev() {
            let spec = &s.nodes[rf.node(d).ty()];
            if spec.defining || spec.isolating {
                break;
            }
            if target_depths.contains(&(d as isize)) {
                preferred_target = d as isize;
            } else if rf.before(d)? as isize == pos {
                target_depths.insert(1, -(d as isize));
            }
            pos -= 1;
        }
        let preferred_target_index = target_depths.iter().position(|&t| t == preferred_target).expect("preferred");
        let mut left_nodes: Vec<Node> = Vec::new();
        let mut preferred_depth = slice.open_start;
        {
            let mut content = slice.content.clone();
            let mut i = 0;
            loop {
                let node = content.first_child().expect("left node").clone();
                left_nodes.push(node.clone());
                if i == slice.open_start {
                    break;
                }
                content = node.content().clone();
                i += 1;
            }
        }
        for d in (0..preferred_depth).rev() {
            let left = &left_nodes[d];
            let def = s.nodes[left.ty()].defining;
            if def && !left.same_markup(rf.node((preferred_target.unsigned_abs()) - 1)) {
                preferred_depth = d;
            } else if def || !left.is_textblock() {
                break;
            }
        }
        for j in (0..=slice.open_start).rev() {
            let open_depth = (j + preferred_depth + 1) % (slice.open_start + 1);
            let Some(insert) = left_nodes.get(open_depth) else { continue };
            for i in 0..target_depths.len() {
                let mut target_depth = target_depths[(i + preferred_target_index) % target_depths.len()];
                let mut expand = true;
                if target_depth < 0 {
                    expand = false;
                    target_depth = -target_depth;
                }
                let target_depth = target_depth as usize;
                let parent = rf.node(target_depth - 1);
                let index = rf.index(target_depth - 1);
                if parent.can_replace_with(index, index, insert.ty(), Some(insert.marks()))? {
                    let content = close_fragment(&slice.content, 0, slice.open_start, open_depth, None)?;
                    return self.replace(
                        rf.before(target_depth)?,
                        if expand { rt.after(target_depth)? } else { to },
                        &Slice::new(content, open_depth, slice.open_end),
                    );
                }
            }
        }
        let start_steps = self.steps.len();
        let (mut from, mut to) = (from, to);
        for i in (0..target_depths.len()).rev() {
            self.replace(from, to, slice)?;
            if self.steps.len() > start_steps {
                break;
            }
            let depth = target_depths[i];
            if depth < 0 {
                continue;
            }
            from = rf.before(depth as usize)?;
            to = rt.after(depth as usize)?;
        }
        Ok(())
    }

    /// `replaceRangeWith`.
    pub fn replace_range_with(&mut self, from: usize, to: usize, node: Node) -> Result<()> {
        let (mut from, mut to) = (from, to);
        if !node.is_inline()
            && from == to
            && self.doc.resolve(from)?.parent().content().size > 0
            && let Some(point) = insert_point(&self.doc, from, node.ty())?
        {
            from = point;
            to = point;
        }
        self.replace_range(from, to, &Slice::new(Fragment::from_node(node), 0, 0))
    }

    /// `deleteRange`.
    pub fn delete_range(&mut self, from: usize, to: usize) -> Result<()> {
        let s = schema();
        let (mut from, mut to) = (from, to);
        let mut rf = self.doc.resolve(from)?;
        let mut rt = self.doc.resolve(to)?;
        if rf.parent().is_textblock()
            && rt.parent().is_textblock()
            && rf.start(rf.depth) != rt.start(rt.depth)
            && rf.parent_offset == 0
            && rt.parent_offset == 0
        {
            let shared = rf.shared_depth(to);
            let mut isolated = false;
            for d in (shared + 1..=rf.depth).rev() {
                if s.nodes[rf.node(d).ty()].isolating {
                    isolated = true;
                }
            }
            for d in (shared + 1..=rt.depth).rev() {
                if s.nodes[rt.node(d).ty()].isolating {
                    isolated = true;
                }
            }
            if !isolated {
                let mut d = rf.depth;
                while d > 0 && from == rf.start(d) {
                    from = rf.before(d)?;
                    d -= 1;
                }
                let mut d = rt.depth;
                while d > 0 && to == rt.start(d) {
                    to = rt.before(d)?;
                    d -= 1;
                }
                rf = self.doc.resolve(from)?;
                rt = self.doc.resolve(to)?;
            }
        }
        let covered = covered_depths(&rf, &rt);
        for (i, &depth) in covered.iter().enumerate() {
            let last = i == covered.len() - 1;
            if (last && depth == 0) || s.valid_end(s.nodes[rf.node(depth).ty()].content) {
                return self.delete(rf.start(depth), rt.end(depth));
            }
            if depth > 0 && (last || rf.node(depth - 1).can_replace(rf.index(depth - 1), rt.index_after(depth - 1), &Fragment::empty(), 0, 0)?) {
                return self.delete(rf.before(depth)?, rt.after(depth)?);
            }
        }
        let mut d = 1;
        while d <= rf.depth && d <= rt.depth {
            if from - rf.start(d) == rf.depth - d
                && to > rf.end(d)
                && rt.end(d) as isize - to as isize != (rt.depth - d) as isize
                && rf.start(d - 1) == rt.start(d - 1)
                && rf.node(d - 1).can_replace(rf.index(d - 1), rt.index(d - 1), &Fragment::empty(), 0, 0)?
            {
                return self.delete(rf.before(d)?, to);
            }
            d += 1;
        }
        self.delete(from, to)
    }

    /// `lift`.
    pub fn lift(&mut self, range: &NodeRange, target: usize) -> Result<()> {
        let (rf, rt, depth) = (&range.from, &range.to, range.depth);
        let gap_start = rf.before(depth + 1)?;
        let gap_end = rt.after(depth + 1)?;
        let (mut start, mut end) = (gap_start, gap_end);
        let mut before = Fragment::empty();
        let mut open_start = 0;
        let mut splitting = false;
        for d in (target + 1..=depth).rev() {
            if splitting || rf.index(d) > 0 {
                splitting = true;
                before = Fragment::from_node(rf.node(d).copy(before));
                open_start += 1;
            } else {
                start -= 1;
            }
        }
        let mut after = Fragment::empty();
        let mut open_end = 0;
        let mut splitting = false;
        for d in (target + 1..=depth).rev() {
            if splitting || rt.after(d + 1)? < rt.end(d) {
                splitting = true;
                after = Fragment::from_node(rt.node(d).copy(after));
                open_end += 1;
            } else {
                end += 1;
            }
        }
        let insert = before.size - open_start;
        self.step(Step::ReplaceAround {
            from: start,
            to: end,
            gap_from: gap_start,
            gap_to: gap_end,
            slice: Slice::new(before.append(&after), open_start, open_end),
            insert,
            structure: true,
        })
    }

    /// `wrap`.
    pub fn wrap(&mut self, range: &NodeRange, wrappers: &[TypeAttrs]) -> Result<()> {
        let s = schema();
        let mut content = Fragment::empty();
        for wrapper in wrappers.iter().rev() {
            if content.size > 0 {
                let matched = match_fragment(s.nodes[wrapper.ty].content, &content, 0, content.child_count());
                if !matched.is_some_and(|m| s.valid_end(m)) {
                    bail!("Wrapper type given to Transform.wrap does not form valid content of its parent wrapper");
                }
            }
            content = Fragment::from_node(Node::create(wrapper.ty, wrapper.attrs.as_ref(), content, Vec::new())?);
        }
        let (start, end) = (range.start(), range.end());
        self.step(Step::ReplaceAround {
            from: start,
            to: end,
            gap_from: start,
            gap_to: end,
            slice: Slice::new(content, 0, 0),
            insert: wrappers.len(),
            structure: true,
        })
    }

    /// `split`.
    pub fn split(&mut self, pos: usize, depth: usize, types_after: Option<&[Option<TypeAttrs>]>) -> Result<()> {
        let rp = self.doc.resolve(pos)?;
        let mut before = Fragment::empty();
        let mut after = Fragment::empty();
        let mut i = depth as isize - 1;
        let e = rp.depth as isize - depth as isize;
        let mut d = rp.depth as isize;
        while d > e {
            let du = d as usize;
            before = Fragment::from_node(rp.node(du).copy(before));
            let type_after = types_after.and_then(|t| if i >= 0 { t.get(i as usize).cloned().flatten() } else { None });
            after = Fragment::from_node(match type_after {
                Some(t) => Node::create(t.ty, t.attrs.as_ref(), after, Vec::new())?,
                None => rp.node(du).copy(after),
            });
            d -= 1;
            i -= 1;
        }
        self.step(Step::Replace { from: pos, to: pos, slice: Slice::new(before.append(&after), depth, depth), structure: true })
    }

    /// `setNodeMarkup`.
    pub fn set_node_markup(&mut self, pos: usize, ty: Option<TypeId>, attrs: Option<&Map>, marks: Option<Vec<Mark>>) -> Result<()> {
        let Some(node) = self.doc.node_at(pos) else { bail!("No node at given position") };
        let ty = ty.unwrap_or(node.ty());
        let new_node = Node::create(ty, attrs, Fragment::empty(), marks.unwrap_or_else(|| node.marks().to_vec()))?;
        if node.is_leaf() {
            return self.replace_with(pos, pos + node.node_size(), Fragment::from_node(new_node));
        }
        if !valid_content(ty, node.content()) {
            bail!("Invalid content for node type {}", schema().nodes[ty].name);
        }
        self.step(Step::ReplaceAround {
            from: pos,
            to: pos + node.node_size(),
            gap_from: pos + 1,
            gap_to: pos + node.node_size() - 1,
            slice: Slice::new(Fragment::from_node(new_node), 0, 0),
            insert: 1,
            structure: true,
        })
    }

    /// `clearIncompatible`.
    pub fn clear_incompatible(&mut self, pos: usize, parent_type: TypeId, matched: Option<MatchId>, clear_newlines: bool) -> Result<()> {
        let s = schema();
        let Some(node) = self.doc.node_at(pos) else { bail!("No node at position {pos}") };
        let mut matched = matched.unwrap_or(s.nodes[parent_type].content);
        let mut repl: Vec<Step> = Vec::new();
        let mut cur = pos + 1;
        for child in node.content().iter() {
            let end = cur + child.node_size();
            match s.match_type(matched, child.ty()) {
                None => repl.push(Step::Replace { from: cur, to: end, slice: Slice::empty(), structure: false }),
                Some(allowed) => {
                    matched = allowed;
                    for mark in child.marks() {
                        if !s.allows_mark(parent_type, mark.ty) {
                            self.step(Step::RemoveMark { from: cur, to: end, mark: mark.clone() })?;
                        }
                    }
                    if clear_newlines
                        && let Some(units) = child.text_units()
                        && !s.nodes[parent_type].pre
                    {
                        let (cr, lf) = (u16::from(b'\r'), u16::from(b'\n'));
                        let mut i = 0;
                        while i < units.len() {
                            if units[i] == cr || units[i] == lf {
                                let len = if units[i] == cr && units.get(i + 1) == Some(&lf) { 2 } else { 1 };
                                let space = Node::text_node(" ", allowed_marks(parent_type, child.marks()))?;
                                repl.push(Step::Replace {
                                    from: cur + i,
                                    to: cur + i + len,
                                    slice: Slice::new(Fragment::from_node(space), 0, 0),
                                    structure: false,
                                });
                                i += len;
                                continue;
                            }
                            i += 1;
                        }
                    }
                }
            }
            cur = end;
        }
        if !s.valid_end(matched) {
            let fill = fill_before(matched, &Fragment::empty(), true, 0)?.expect("fillable");
            self.replace(cur, cur, &Slice::new(fill, 0, 0))?;
        }
        for step in repl.into_iter().rev() {
            self.step(step)?;
        }
        Ok(())
    }
}

impl Transform {
    /// `join`, with prosemirror-transform's line break conversion.
    pub fn join(&mut self, pos: usize, depth: usize) -> Result<()> {
        let s = schema();
        let linebreak = (0..s.nodes.len()).find(|&t| s.nodes[t].linebreak_replacement);
        let rb = self.doc.resolve(pos - depth)?;
        let before_node = rb.node(rb.depth).clone();
        let before_type = before_node.ty();
        let mut convert: Option<bool> = None;
        if let Some(lb) = linebreak
            && s.inline_content(before_type)
        {
            let pre = s.nodes[before_type].pre;
            let support = s.match_type(s.nodes[before_type].content, lb).is_some();
            if pre && !support {
                convert = Some(false);
            } else if !pre && support {
                convert = Some(true);
            }
        }
        let map_from = self.steps.len();
        if convert == Some(false) {
            let ra = self.doc.resolve(pos + depth)?;
            let node = ra.node(ra.depth).clone();
            self.replace_linebreaks(&node, ra.before(ra.depth)?, map_from)?;
        }
        if s.inline_content(before_type) {
            let matched = before_node.content_match_at(rb.index_here())?;
            self.clear_incompatible(pos + depth - 1, before_type, Some(matched), convert.is_none())?;
        }
        let mapping = self.mapping.slice(map_from, self.mapping.maps.len());
        let start = mapping.map(pos - depth, 1);
        let end = mapping.map(pos + depth, -1);
        self.step(Step::Replace { from: start, to: end, slice: Slice::empty(), structure: true })?;
        if convert == Some(true) {
            let full = self.doc.resolve(start)?;
            let node = full.node(full.depth).clone();
            let steps = self.steps.len();
            self.replace_newlines(&node, full.before(full.depth)?, steps)?;
        }
        Ok(())
    }

    fn replace_linebreaks(&mut self, node: &Node, pos: usize, map_from: usize) -> Result<()> {
        let mut offset = 0;
        for child in node.content().iter() {
            if schema().nodes[child.ty()].linebreak_replacement {
                let start = self.mapping.slice(map_from, self.mapping.maps.len()).map(pos + 1 + offset, 1);
                self.replace_with(start, start + 1, Fragment::from_node(Node::text_node("\n", Vec::new())?))?;
            }
            offset += child.node_size();
        }
        Ok(())
    }

    fn replace_newlines(&mut self, node: &Node, pos: usize, map_from: usize) -> Result<()> {
        let s = schema();
        let Some(lb) = (0..s.nodes.len()).find(|&t| s.nodes[t].linebreak_replacement) else { return Ok(()) };
        let mut offset = 0;
        for child in node.content().iter() {
            if let Some(units) = child.text_units() {
                let (cr, lf) = (u16::from(b'\r'), u16::from(b'\n'));
                let mut i = 0;
                while i < units.len() {
                    if units[i] == cr || units[i] == lf {
                        let start = self.mapping.slice(map_from, self.mapping.maps.len()).map(pos + 1 + offset + i, 1);
                        let line_break = Node::create(lb, None, Fragment::empty(), Vec::new())?;
                        self.replace_with(start, start + 1, Fragment::from_node(line_break))?;
                        i += if units[i] == cr && units.get(i + 1) == Some(&lf) { 2 } else { 1 };
                        continue;
                    }
                    i += 1;
                }
            }
            offset += child.node_size();
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::io::Read;

    /// Replace fitting against prosemirror-transform, recorded by
    /// `tools/fitter-corpus.mjs` (see there): the same steps, or a refusal.
    #[test]
    fn fits_slices_as_the_reference() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/reference/fitter-corpus.jsonl.gz");
        let mut text = String::new();
        flate2::read::GzDecoder::new(std::fs::File::open(path).unwrap()).read_to_string(&mut text).unwrap();
        let mut lines = text.lines().map(|line| serde_json::from_str::<Value>(line).unwrap());
        let papers: Vec<Node> = lines.next().unwrap()["papers"].as_array().unwrap().iter().map(|doc| Node::from_json(doc).unwrap()).collect();
        let mut mismatches = Vec::new();
        for (n, case) in lines.enumerate() {
            let at = |key: &str| case[key].as_u64().unwrap() as usize;
            let mut tr = Transform::new(papers[at("paper")].clone());
            let slice = Slice::from_json(Some(&case["slice"])).unwrap();
            let actual = tr.replace(at("from"), at("to"), &slice).map(|()| Value::Array(tr.steps.iter().map(Step::to_json).collect()));
            let same = match (&actual, case.get("steps")) {
                // Byte for byte: key order is part of the step encoding.
                (Ok(steps), Some(expected)) => serde_json::to_string(steps).unwrap() == serde_json::to_string(expected).unwrap(),
                (Err(_), None) => true,
                _ => false,
            };
            if !same {
                mismatches.push(n + 1);
            }
        }
        assert!(mismatches.is_empty(), "fitter mismatches at cases {mismatches:?}");
    }
}
