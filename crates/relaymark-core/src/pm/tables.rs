//! prosemirror-tables 1.8: the table map, cell helpers, the table commands
//! the editor offers and `fixTables`.

use serde_json::{Value, json};

use crate::error::{Result, bail};
use crate::json::Map;

use super::model::{Fragment, Node, ResolvedPos};
use super::schema::{TypeId, schema};
use super::state::{Selection, Transaction};

#[derive(Clone, Debug)]
pub enum Problem {
    Collision { row: usize, pos: usize, n: usize },
    Missing { row: usize, n: usize },
    OverlongRowspan { pos: usize, n: usize },
    ColwidthMismatch { pos: usize, colwidth: Vec<Value> },
    ZeroSized,
}

#[derive(Clone, Copy, Debug)]
pub struct Rect {
    pub left: usize,
    pub top: usize,
    pub right: usize,
    pub bottom: usize,
}

#[derive(Clone, Debug)]
pub struct TableMap {
    pub width: usize,
    pub height: usize,
    pub map: Vec<usize>,
    pub problems: Option<Vec<Problem>>,
}

fn attr_usize(node: &Node, name: &str) -> usize {
    node.attr(name).as_f64().map_or(0, |n| n.max(0.0) as usize)
}

/// The node type for a table role.
pub fn role_type(role: &str) -> TypeId {
    let s = schema();
    (0..s.nodes.len()).find(|&t| s.nodes[t].table_role.as_deref() == Some(role)).expect("table role in schema")
}

pub fn table_role(node: &Node) -> Option<&'static str> {
    schema().nodes[node.ty()].table_role.as_deref()
}

impl TableMap {
    pub fn get(table: &Node) -> Result<TableMap> {
        compute_map(table)
    }

    pub fn find_cell(&self, pos: usize) -> Result<Rect> {
        for (i, &cur) in self.map.iter().enumerate() {
            if cur != pos {
                continue;
            }
            let left = i % self.width;
            let top = i / self.width;
            let mut right = left + 1;
            let mut bottom = top + 1;
            let mut j = 1;
            while right < self.width && self.map[i + j] == cur {
                right += 1;
                j += 1;
            }
            let mut j = 1;
            while bottom < self.height && self.map[i + self.width * j] == cur {
                bottom += 1;
                j += 1;
            }
            return Ok(Rect { left, top, right, bottom });
        }
        bail!("No cell with offset {pos} found")
    }

    pub fn col_count(&self, pos: usize) -> Result<usize> {
        match self.map.iter().position(|&p| p == pos) {
            Some(i) => Ok(i % self.width),
            None => bail!("No cell with offset {pos} found"),
        }
    }

    pub fn rect_between(&self, a: usize, b: usize) -> Result<Rect> {
        let ra = self.find_cell(a)?;
        let rb = self.find_cell(b)?;
        Ok(Rect { left: ra.left.min(rb.left), top: ra.top.min(rb.top), right: ra.right.max(rb.right), bottom: ra.bottom.max(rb.bottom) })
    }

    pub fn cells_in_rect(&self, rect: &Rect) -> Vec<usize> {
        let mut result = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for row in rect.top..rect.bottom {
            for col in rect.left..rect.right {
                let index = row * self.width + col;
                let pos = self.map[index];
                if !seen.insert(pos) {
                    continue;
                }
                if (col == rect.left && col > 0 && self.map[index - 1] == pos) || (row == rect.top && row > 0 && self.map[index - self.width] == pos) {
                    continue;
                }
                result.push(pos);
            }
        }
        result
    }

    pub fn position_at(&self, row: usize, col: usize, table: &Node) -> usize {
        let mut row_start = 0;
        for i in 0.. {
            let row_end = row_start + table.child(i).node_size();
            if i == row {
                let mut index = col + row * self.width;
                let row_end_index = (row + 1) * self.width;
                while index < row_end_index && self.map[index] < row_start {
                    index += 1;
                }
                return if index == row_end_index { row_end - 1 } else { self.map[index] };
            }
            row_start = row_end;
        }
        unreachable!()
    }
}

fn find_width(table: &Node) -> isize {
    let mut width: isize = -1;
    let mut has_row_span = false;
    for row in 0..table.child_count() {
        let row_node = table.child(row);
        let mut row_width = 0isize;
        if has_row_span {
            for j in 0..row {
                let prev = table.child(j);
                for cell in prev.content().iter() {
                    if j + attr_usize(cell, "rowspan") > row {
                        row_width += attr_usize(cell, "colspan") as isize;
                    }
                }
            }
        }
        for cell in row_node.content().iter() {
            row_width += attr_usize(cell, "colspan") as isize;
            if attr_usize(cell, "rowspan") > 1 {
                has_row_span = true;
            }
        }
        if width == -1 {
            width = row_width;
        } else if width != row_width {
            width = width.max(row_width);
        }
    }
    width
}

fn compute_map(table: &Node) -> Result<TableMap> {
    if table_role(table) != Some("table") {
        bail!("Not a table node: {}", table.type_name());
    }
    let width = find_width(table).max(0) as usize;
    let height = table.child_count();
    let mut map = vec![0usize; width * height];
    let mut map_pos = 0;
    let mut problems: Option<Vec<Problem>> = None;
    let mut col_widths: Vec<Option<f64>> = Vec::new();
    let mut col_counts: Vec<usize> = Vec::new();
    let mut pos = 0;
    for row in 0..height {
        let row_node = table.child(row);
        pos += 1;
        let mut i = 0;
        loop {
            while map_pos < map.len() && map[map_pos] != 0 {
                map_pos += 1;
            }
            if i == row_node.child_count() {
                break;
            }
            let cell = row_node.child(i);
            let colspan = attr_usize(cell, "colspan");
            let rowspan = attr_usize(cell, "rowspan");
            let colwidth = cell.attr("colwidth").as_array().cloned();
            for h in 0..rowspan {
                if h + row >= height {
                    problems.get_or_insert_with(Vec::new).push(Problem::OverlongRowspan { pos, n: rowspan - h });
                    break;
                }
                let start = map_pos + h * width;
                for w in 0..colspan {
                    if start + w < map.len() && map[start + w] == 0 {
                        map[start + w] = pos;
                    } else {
                        problems.get_or_insert_with(Vec::new).push(Problem::Collision { row, pos, n: colspan - w });
                    }
                    let col_w = colwidth.as_ref().and_then(|c| c.get(w)).and_then(Value::as_f64).filter(|w| *w != 0.0);
                    if let Some(col_w) = col_w {
                        let index = (start + w) % width.max(1);
                        if col_widths.len() <= index {
                            col_widths.resize(index + 1, None);
                            col_counts.resize(index + 1, 0);
                        }
                        let prev = col_widths[index];
                        if prev.is_none() || (prev != Some(col_w) && col_counts[index] == 1) {
                            col_widths[index] = Some(col_w);
                            col_counts[index] = 1;
                        } else if prev == Some(col_w) {
                            col_counts[index] += 1;
                        }
                    }
                }
            }
            map_pos += colspan;
            pos += cell.node_size();
            i += 1;
        }
        let expected = (row + 1) * width;
        let mut missing = 0;
        while map_pos < expected {
            if map[map_pos] == 0 {
                missing += 1;
            }
            map_pos += 1;
        }
        if missing > 0 {
            problems.get_or_insert_with(Vec::new).push(Problem::Missing { row, n: missing });
        }
        pos += 1;
    }
    if width == 0 || height == 0 {
        problems.get_or_insert_with(Vec::new).push(Problem::ZeroSized);
    }
    let mut table_map = TableMap { width, height, map, problems };
    let bad = col_widths.iter().zip(&col_counts).any(|(w, c)| w.is_some() && *c < height);
    if bad {
        find_bad_col_widths(&mut table_map, &col_widths, table)?;
    }
    Ok(table_map)
}

fn find_bad_col_widths(map: &mut TableMap, col_widths: &[Option<f64>], table: &Node) -> Result<()> {
    let mut seen = std::collections::HashSet::new();
    let mut found: Vec<Problem> = Vec::new();
    for i in 0..map.map.len() {
        let pos = map.map[i];
        if !seen.insert(pos) {
            continue;
        }
        let Some(node) = table.node_at(pos) else { bail!("No cell with offset {pos} found") };
        let colspan = attr_usize(&node, "colspan");
        let existing = node.attr("colwidth").as_array().cloned();
        let mut updated: Option<Vec<Value>> = None;
        for j in 0..colspan {
            let index = (i + j) % map.width;
            if let Some(Some(col_width)) = col_widths.get(index)
                && existing.as_ref().and_then(|c| c.get(j)).and_then(Value::as_f64) != Some(*col_width)
            {
                let target = updated.get_or_insert_with(|| existing.clone().unwrap_or_else(|| vec![json!(0); colspan]));
                if target.len() <= j {
                    target.resize(j + 1, Value::Null);
                }
                target[j] = crate::source::js_number(*col_width);
            }
        }
        if let Some(colwidth) = updated {
            found.push(Problem::ColwidthMismatch { pos, colwidth });
        }
    }
    let problems = map.problems.get_or_insert_with(Vec::new);
    // `unshift` each in turn: the last found comes first.
    for problem in found {
        problems.insert(0, problem);
    }
    Ok(())
}

pub fn cell_around(pos: &ResolvedPos) -> Result<Option<ResolvedPos>> {
    for d in (1..pos.depth).rev() {
        if table_role(pos.node(d)) == Some("row") {
            return Ok(Some(pos.doc().resolve(pos.before(d + 1)?)?));
        }
    }
    Ok(None)
}

fn cell_wrapping(pos: &ResolvedPos) -> Option<Node> {
    (1..=pos.depth).rev().map(|d| pos.node(d)).find(|n| matches!(table_role(n), Some("cell" | "header_cell"))).cloned()
}

pub fn is_in_table(selection: &Selection) -> bool {
    let head = selection.head_r();
    (1..=head.depth).rev().any(|d| table_role(head.node(d)) == Some("row"))
}

fn cell_near(pos: &ResolvedPos) -> Result<Option<ResolvedPos>> {
    let mut after = pos.node_after();
    let mut p = pos.pos;
    while let Some(node) = after {
        if matches!(table_role(&node), Some("cell" | "header_cell")) {
            return Ok(Some(pos.doc().resolve(p)?));
        }
        after = node.first_child().cloned();
        p += 1;
    }
    let mut before = pos.node_before();
    let mut p = pos.pos as isize;
    while let Some(node) = before {
        if matches!(table_role(&node), Some("cell" | "header_cell")) {
            return Ok(Some(pos.doc().resolve((p - node.node_size() as isize) as usize)?));
        }
        before = node.last_child().cloned();
        p -= 1;
    }
    Ok(None)
}

pub fn selection_cell(selection: &Selection) -> Result<ResolvedPos> {
    if let Selection::Cell { anchor_cell, head_cell, .. } = selection {
        return Ok(if anchor_cell.pos > head_cell.pos { anchor_cell.clone() } else { head_cell.clone() });
    }
    if let Selection::Node { node, anchor, .. } = selection
        && table_role(node) == Some("cell")
    {
        return Ok(anchor.clone());
    }
    let head = selection.head_r();
    if let Some(cell) = cell_around(head)? {
        return Ok(cell);
    }
    if let Some(cell) = cell_near(head)? {
        return Ok(cell);
    }
    bail!("No cell found around position {}", head.pos)
}

pub fn points_at_cell(pos: &ResolvedPos) -> bool {
    table_role(pos.parent()) == Some("row") && pos.node_after().is_some()
}

pub fn in_same_table(a: &ResolvedPos, b: &ResolvedPos) -> bool {
    a.depth == b.depth && b.depth >= 1 && a.pos >= b.start(b.depth - 1) && a.pos <= b.end(b.depth - 1)
}

fn with_attr(attrs: &Map, name: &str, value: Value) -> Map {
    let mut out = attrs.clone();
    out.insert(name.to_owned(), value);
    out
}

pub fn remove_col_span(attrs: &Map, pos: usize, n: usize) -> Map {
    let colspan = attrs.get("colspan").and_then(Value::as_f64).unwrap_or(1.0);
    let mut result = with_attr(attrs, "colspan", crate::source::js_number(colspan - n as f64));
    if let Some(widths) = attrs.get("colwidth").and_then(Value::as_array) {
        let mut widths = widths.clone();
        let end = (pos + n).min(widths.len());
        if pos < widths.len() {
            widths.drain(pos..end);
        }
        let any = widths.iter().any(|w| w.as_f64().is_some_and(|w| w > 0.0));
        result.insert("colwidth".into(), if any { Value::Array(widths) } else { Value::Null });
    }
    result
}

pub fn add_col_span(attrs: &Map, pos: usize, n: isize) -> Map {
    let colspan = attrs.get("colspan").and_then(Value::as_f64).unwrap_or(1.0);
    let mut result = with_attr(attrs, "colspan", crate::source::js_number(colspan + n as f64));
    if let Some(widths) = attrs.get("colwidth").and_then(Value::as_array) {
        let mut widths = widths.clone();
        for _ in 0..n.max(0) {
            let at = pos.min(widths.len());
            widths.insert(at, json!(0));
        }
        result.insert("colwidth".into(), Value::Array(widths));
    }
    result
}

fn column_is_header(map: &TableMap, table: &Node, col: usize) -> bool {
    let header = role_type("header_cell");
    (0..map.height).all(|row| table.node_at(map.map[col + row * map.width]).is_some_and(|n| n.ty() == header))
}

fn row_is_header(map: &TableMap, table: &Node, row: usize) -> bool {
    let header = role_type("header_cell");
    (0..map.width).all(|col| map.map.get(col + row * map.width).and_then(|&p| table.node_at(p)).is_some_and(|n| n.ty() == header))
}

/// `selectedRect`.
pub struct SelectedRect {
    pub rect: Rect,
    pub table_start: usize,
    pub map: TableMap,
    pub table: Node,
}

pub fn selected_rect(selection: &Selection) -> Result<SelectedRect> {
    let pos = selection_cell(selection)?;
    let table = pos.node_rel(-1).clone();
    let table_start = pos.start(pos.depth - 1);
    let map = TableMap::get(&table)?;
    let rect = match selection {
        Selection::Cell { anchor_cell, head_cell, .. } => map.rect_between(anchor_cell.pos - table_start, head_cell.pos - table_start)?,
        _ => map.find_cell(pos.pos - table_start)?,
    };
    Ok(SelectedRect { rect, table_start, map, table })
}

fn create_and_fill(ty: TypeId, attrs: Option<&Map>) -> Result<Option<Node>> {
    Node::create_and_fill(ty, attrs, Fragment::empty(), Vec::new())
}

fn add_column(tr: &mut Transaction, r: &SelectedRect, col: usize) -> Result<()> {
    let (map, table, table_start) = (&r.map, &r.table, r.table_start);
    let mut ref_column: Option<isize> = Some(if col > 0 { -1 } else { 0 });
    if column_is_header(map, table, (col as isize + ref_column.unwrap()) as usize) {
        ref_column = if col == 0 || col == map.width { None } else { Some(0) };
    }
    let mut row = 0;
    while row < map.height {
        let index = row * map.width + col;
        if col > 0 && col < map.width && map.map[index - 1] == map.map[index] {
            let pos = map.map[index];
            let cell = table.node_at(pos).expect("cell");
            let attrs = add_col_span(cell.attrs(), col - map.col_count(pos)?, 1);
            let at = tr.mapping.map(table_start + pos, 1);
            tr.set_node_markup(at, None, Some(&attrs), None)?;
            row += attr_usize(&cell, "rowspan").max(1) - 1;
        } else {
            let ty = match ref_column {
                None => role_type("cell"),
                Some(rc) => table.node_at(map.map[(index as isize + rc) as usize]).expect("cell").ty(),
            };
            let pos = map.position_at(row, col, table);
            let at = tr.mapping.map(table_start + pos, 1);
            let node = create_and_fill(ty, None)?.expect("cell");
            tr.insert(at, Fragment::from_node(node))?;
        }
        row += 1;
    }
    Ok(())
}

fn remove_column(tr: &mut Transaction, r: &SelectedRect, col: usize) -> Result<()> {
    let (map, table, table_start) = (&r.map, &r.table, r.table_start);
    let map_start = tr.mapping.maps.len();
    let mut row = 0;
    while row < map.height {
        let index = row * map.width + col;
        let pos = map.map[index];
        let cell = table.node_at(pos).expect("cell");
        let attrs = cell.attrs().clone();
        let mapping = tr.mapping.slice(map_start, tr.mapping.maps.len());
        if (col > 0 && map.map[index - 1] == pos) || (col + 1 < map.width && map.map[index + 1] == pos) {
            let next = remove_col_span(&attrs, col - map.col_count(pos)?, 1);
            tr.set_node_markup(mapping.map(table_start + pos, 1), None, Some(&next), None)?;
        } else {
            let start = mapping.map(table_start + pos, 1);
            tr.delete(start, start + cell.node_size())?;
        }
        row += attr_usize(&cell, "rowspan");
        if attr_usize(&cell, "rowspan") == 0 {
            break;
        }
    }
    Ok(())
}

fn add_row(tr: &mut Transaction, r: &SelectedRect, row: usize) -> Result<()> {
    let (map, table, table_start) = (&r.map, &r.table, r.table_start);
    let mut row_pos = table_start;
    for i in 0..row {
        row_pos += table.child(i).node_size();
    }
    let mut cells = Vec::new();
    let mut ref_row: Option<isize> = Some(if row > 0 { -1 } else { 0 });
    if row_is_header(map, table, (row as isize + ref_row.unwrap()) as usize) {
        ref_row = if row == 0 || row == map.height { None } else { Some(0) };
    }
    let mut col = 0;
    let mut index = map.width * row;
    while col < map.width {
        if row > 0 && row < map.height && map.map[index] == map.map[index - map.width] {
            let pos = map.map[index];
            let cell = table.node_at(pos).expect("cell");
            let rowspan = cell.attr("rowspan").as_f64().unwrap_or(1.0);
            let attrs = with_attr(cell.attrs(), "rowspan", crate::source::js_number(rowspan + 1.0));
            tr.set_node_markup(table_start + pos, None, Some(&attrs), None)?;
            // As upstream: the column skips the span, the map index does not.
            col += attr_usize(&cell, "colspan").max(1) - 1;
        } else {
            let ty = match ref_row {
                None => Some(role_type("cell")),
                Some(rr) => map.map.get((index as isize + rr * map.width as isize) as usize).and_then(|&p| table.node_at(p)).map(|n| n.ty()),
            };
            if let Some(ty) = ty
                && let Some(node) = create_and_fill(ty, None)?
            {
                cells.push(node);
            }
        }
        col += 1;
        index += 1;
    }
    let new_row = Node::create(role_type("row"), None, Fragment::from_array(cells), Vec::new())?;
    tr.insert(row_pos, Fragment::from_node(new_row))
}

fn remove_row(tr: &mut Transaction, r: &SelectedRect, row: usize) -> Result<()> {
    let (map, table, table_start) = (&r.map, &r.table, r.table_start);
    let mut row_pos = 0;
    for i in 0..row {
        row_pos += table.child(i).node_size();
    }
    let next_row = row_pos + table.child(row).node_size();
    let map_from = tr.mapping.maps.len();
    tr.delete(row_pos + table_start, next_row + table_start)?;
    let mut seen = std::collections::HashSet::new();
    let mut col = 0;
    let mut index = row * map.width;
    while col < map.width {
        let pos = map.map[index];
        if seen.insert(pos) {
            if row > 0 && pos == map.map[index - map.width] {
                let cell = table.node_at(pos).expect("cell");
                let rowspan = cell.attr("rowspan").as_f64().unwrap_or(1.0);
                let attrs = with_attr(cell.attrs(), "rowspan", crate::source::js_number(rowspan - 1.0));
                let at = tr.mapping.slice(map_from, tr.mapping.maps.len()).map(pos + table_start, 1);
                tr.set_node_markup(at, None, Some(&attrs), None)?;
                col += attr_usize(&cell, "colspan").max(1) - 1;
            } else if row < map.height && map.map.get(index + map.width) == Some(&pos) {
                let cell = table.node_at(pos).expect("cell");
                let rowspan = cell.attr("rowspan").as_f64().unwrap_or(1.0);
                let attrs = with_attr(cell.attrs(), "rowspan", crate::source::js_number(rowspan - 1.0));
                let copy = Node::create(cell.ty(), Some(&attrs), cell.content().clone(), Vec::new())?;
                let new_pos = map.position_at(row + 1, col, table);
                let at = tr.mapping.slice(map_from, tr.mapping.maps.len()).map(table_start + new_pos, 1);
                tr.insert(at, Fragment::from_node(copy))?;
                col += attr_usize(&cell, "colspan").max(1) - 1;
            }
        }
        col += 1;
        index += 1;
    }
    Ok(())
}

fn table_at(tr: &Transaction, table_start: usize) -> Result<Node> {
    let table = if table_start > 0 { tr.doc.node_at(table_start - 1) } else { Some(tr.doc.clone()) };
    match table {
        Some(table) => Ok(table),
        None => bail!("No table found"),
    }
}

fn is_empty_cell(cell: &Node) -> bool {
    let c = cell.content();
    c.child_count() == 1 && c.child(0).is_textblock() && c.child(0).child_count() == 0
}

fn cells_overlap_rectangle(map: &TableMap, rect: &Rect) -> bool {
    let (width, height, m) = (map.width, map.height, &map.map);
    let mut index_top = rect.top * width + rect.left;
    let mut index_left = index_top;
    let mut index_bottom = (rect.bottom - 1) * width + rect.left;
    let mut index_right = index_top + (rect.right - rect.left - 1);
    for _ in rect.top..rect.bottom {
        if (rect.left > 0 && m[index_left] == m[index_left - 1]) || (rect.right < width && m[index_right] == m[index_right + 1]) {
            return true;
        }
        index_left += width;
        index_right += width;
    }
    for _ in rect.left..rect.right {
        if (rect.top > 0 && m[index_top] == m[index_top - width]) || (rect.bottom < height && m[index_bottom] == m[index_bottom + width]) {
            return true;
        }
        index_top += 1;
        index_bottom += 1;
    }
    false
}

/// Runs a named table command; `Ok(false)` when it does not apply.
pub fn table_command(name: &str, tr: &mut Transaction, selection: &Selection) -> Result<bool> {
    match name {
        "addColumnBefore" | "addColumnAfter" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let r = selected_rect(selection)?;
            let col = if name == "addColumnBefore" { r.rect.left } else { r.rect.right };
            add_column(tr, &r, col)?;
            Ok(true)
        }
        "addRowBefore" | "addRowAfter" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let r = selected_rect(selection)?;
            let row = if name == "addRowBefore" { r.rect.top } else { r.rect.bottom };
            add_row(tr, &r, row)?;
            Ok(true)
        }
        "deleteColumn" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let mut r = selected_rect(selection)?;
            if r.rect.left == 0 && r.rect.right == r.map.width {
                return Ok(false);
            }
            let mut i = r.rect.right - 1;
            loop {
                remove_column(tr, &r, i)?;
                if i == r.rect.left {
                    break;
                }
                r.table = table_at(tr, r.table_start)?;
                r.map = TableMap::get(&r.table)?;
                i -= 1;
            }
            Ok(true)
        }
        "deleteRow" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let mut r = selected_rect(selection)?;
            if r.rect.top == 0 && r.rect.bottom == r.map.height {
                return Ok(false);
            }
            let mut i = r.rect.bottom - 1;
            loop {
                remove_row(tr, &r, i)?;
                if i == r.rect.top {
                    break;
                }
                r.table = table_at(tr, r.table_start)?;
                r.map = TableMap::get(&r.table)?;
                i -= 1;
            }
            Ok(true)
        }
        "mergeCells" => merge_cells(tr, selection),
        "splitCell" => split_cell(tr, selection),
        // The editor uses the current header toggles for rows and columns,
        // and the deprecated one for cells.
        "toggleHeaderRow" | "toggleHeaderColumn" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let r = selected_rect(selection)?;
            let (header, cell) = (role_type("header_cell"), role_type("cell"));
            let enabled = |row: bool| {
                let probe = Rect { left: 0, top: 0, right: if row { r.map.width } else { 1 }, bottom: if row { 1 } else { r.map.height } };
                r.map.cells_in_rect(&probe).iter().all(|&p| r.table.node_at(p).is_none_or(|n| n.ty() == header))
            };
            let (row_enabled, column_enabled) = (enabled(true), enabled(false));
            let column = name == "toggleHeaderColumn";
            let starts_at = usize::from(if column { row_enabled } else { column_enabled });
            let rect = if column {
                Rect { left: 0, top: starts_at, right: 1, bottom: r.map.height }
            } else {
                Rect { left: starts_at, top: 0, right: r.map.width, bottom: 1 }
            };
            let new_type = if (column && column_enabled) || (!column && row_enabled) { cell } else { header };
            for rel in r.map.cells_in_rect(&rect) {
                let pos = rel + r.table_start;
                if let Some(node) = tr.doc.node_at(pos) {
                    tr.set_node_markup(pos, Some(new_type), Some(node.attrs()), None)?;
                }
            }
            Ok(true)
        }
        "toggleHeaderCell" => {
            if !is_in_table(selection) {
                return Ok(false);
            }
            let r = selected_rect(selection)?;
            let cells = r.map.cells_in_rect(&r.rect);
            let nodes: Vec<Node> = cells.iter().map(|&p| r.table.node_at(p).expect("cell")).collect();
            let (header, cell) = (role_type("header_cell"), role_type("cell"));
            for (pos, node) in cells.iter().zip(&nodes) {
                if node.ty() == header {
                    tr.set_node_markup(r.table_start + pos, Some(cell), Some(node.attrs()), None)?;
                }
            }
            if tr.steps.is_empty() {
                for (pos, node) in cells.iter().zip(&nodes) {
                    tr.set_node_markup(r.table_start + pos, Some(header), Some(node.attrs()), None)?;
                }
            }
            Ok(true)
        }
        "deleteTable" => {
            let pos = selection.anchor_r();
            for d in (1..=pos.depth).rev() {
                if table_role(pos.node(d)) == Some("table") {
                    let (from, to) = (pos.before(d)?, pos.after(d)?);
                    tr.delete(from, to)?;
                    return Ok(true);
                }
            }
            Ok(false)
        }
        _ => bail!("Unknown canonical editor command"),
    }
}

fn merge_cells(tr: &mut Transaction, selection: &Selection) -> Result<bool> {
    let Selection::Cell { anchor_cell, head_cell, .. } = selection else { return Ok(false) };
    if anchor_cell.pos == head_cell.pos {
        return Ok(false);
    }
    let r = selected_rect(selection)?;
    if cells_overlap_rectangle(&r.map, &r.rect) {
        return Ok(false);
    }
    let mut seen = std::collections::HashSet::new();
    let mut content = Fragment::empty();
    let mut merged: Option<(usize, Node)> = None;
    for row in r.rect.top..r.rect.bottom {
        for col in r.rect.left..r.rect.right {
            let cell_pos = r.map.map[row * r.map.width + col];
            let Some(cell) = r.table.node_at(cell_pos) else { continue };
            if !seen.insert(cell_pos) {
                continue;
            }
            if merged.is_none() {
                merged = Some((cell_pos, cell));
            } else {
                if !is_empty_cell(&cell) {
                    content = content.append(cell.content());
                }
                let mapped = tr.mapping.map(cell_pos + r.table_start, 1);
                tr.delete(mapped, mapped + cell.node_size())?;
            }
        }
    }
    let Some((merged_pos, merged_cell)) = merged else { return Ok(true) };
    let colspan = attr_usize(&merged_cell, "colspan");
    let attrs = add_col_span(merged_cell.attrs(), colspan, (r.rect.right - r.rect.left) as isize - colspan as isize);
    let attrs = with_attr(&attrs, "rowspan", json!(r.rect.bottom - r.rect.top));
    tr.set_node_markup(merged_pos + r.table_start, None, Some(&attrs), None)?;
    if content.size > 0 {
        let end = merged_pos + 1 + merged_cell.content().size;
        let start = if is_empty_cell(&merged_cell) { merged_pos + 1 } else { end };
        tr.replace_with(start + r.table_start, end + r.table_start, content)?;
    }
    let doc = tr.doc.clone();
    let at = doc.resolve(merged_pos + r.table_start)?;
    tr.set_selection(Selection::cell(at.clone(), at)?)?;
    Ok(true)
}

fn split_cell(tr: &mut Transaction, selection: &Selection) -> Result<bool> {
    let (cell_node, cell_pos) = match selection {
        Selection::Cell { anchor_cell, head_cell, .. } => {
            if anchor_cell.pos != head_cell.pos {
                return Ok(false);
            }
            (anchor_cell.node_after(), Some(anchor_cell.pos))
        }
        _ => {
            let from = selection.sel_from();
            let Some(node) = cell_wrapping(&from) else { return Ok(false) };
            (Some(node), cell_around(&from)?.map(|p| p.pos))
        }
    };
    let (Some(cell_node), Some(cell_pos)) = (cell_node, cell_pos) else { return Ok(false) };
    if attr_usize(&cell_node, "colspan") == 1 && attr_usize(&cell_node, "rowspan") == 1 {
        return Ok(false);
    }
    let mut base = (**cell_node.attrs()).clone();
    let colwidth = base.get("colwidth").and_then(Value::as_array).cloned();
    if attr_usize(&cell_node, "rowspan") > 1 {
        base.insert("rowspan".into(), json!(1));
    }
    if attr_usize(&cell_node, "colspan") > 1 {
        base.insert("colspan".into(), json!(1));
    }
    let r = selected_rect(selection)?;
    let mut attrs: Vec<Map> = Vec::new();
    for i in 0..r.rect.right - r.rect.left {
        attrs.push(match &colwidth {
            Some(widths) => {
                let w = widths.get(i).filter(|w| crate::json::truthy(Some(w)));
                with_attr(&base, "colwidth", w.map_or(Value::Null, |w| json!([w])))
            }
            None => base.clone(),
        });
    }
    let role = table_role(&cell_node).unwrap_or("cell");
    let ty = role_type(role);
    let mut last_cell = None;
    for row in r.rect.top..r.rect.bottom {
        let mut pos = r.map.position_at(row, r.rect.left, &r.table);
        if row == r.rect.top {
            pos += cell_node.node_size();
        }
        for (i, col) in (r.rect.left..r.rect.right).enumerate() {
            if col == r.rect.left && row == r.rect.top {
                continue;
            }
            let at = tr.mapping.map(pos + r.table_start, 1);
            last_cell = Some(at);
            let node = create_and_fill(ty, Some(&attrs[i]))?.expect("cell");
            tr.insert(at, Fragment::from_node(node))?;
        }
    }
    tr.set_node_markup(cell_pos, Some(ty), Some(&attrs[0]), None)?;
    if let Selection::Cell { anchor_cell, .. } = selection {
        let doc = tr.doc.clone();
        let anchor = doc.resolve(anchor_cell.pos)?;
        let head = match last_cell {
            Some(p) => doc.resolve(p)?,
            None => anchor.clone(),
        };
        tr.set_selection(Selection::cell(anchor, head)?)?;
    }
    Ok(true)
}

/// `changedDescendants`.
fn changed_descendants(old: &Node, cur: &Node, offset: usize, f: &mut dyn FnMut(&Node, usize)) {
    let old_size = old.child_count();
    let mut j = 0;
    let mut offset = offset;
    'outer: for i in 0..cur.child_count() {
        let child = cur.child(i);
        let mut scan = j;
        while scan < old_size.min(i + 3) {
            if old.child(scan).ptr_eq(child) {
                j = scan + 1;
                offset += child.node_size();
                continue 'outer;
            }
            scan += 1;
        }
        f(child, offset);
        if j < old_size && old.child(j).same_markup(child) {
            changed_descendants(old.child(j), child, offset + 1, f);
        } else {
            child.nodes_between(
                0,
                child.content().size,
                &mut |node, pos, _, _| {
                    f(node, pos);
                    true
                },
                offset + 1,
            );
        }
        offset += child.node_size();
    }
}

/// `fixTables(state, oldState)`: the steps of the fixing transaction, made
/// from `doc` (the changed document), or `None` when no table needed fixing.
pub fn fix_tables(doc: &Node, old_doc: &Node) -> Result<Option<Vec<super::step::Step>>> {
    let mut tables: Vec<(Node, usize)> = Vec::new();
    if !doc.ptr_eq(old_doc) {
        changed_descendants(old_doc, doc, 0, &mut |node, pos| {
            if table_role(node) == Some("table") {
                tables.push((node.clone(), pos));
            }
        });
    }
    let mut tr: Option<Transaction> = None;
    for (table, pos) in tables {
        if TableMap::get(&table)?.problems.is_none() {
            continue;
        }
        let tr = match &mut tr {
            Some(tr) => tr,
            None => tr.insert(Transaction::new(doc.clone(), Selection::all(doc)?, None)),
        };
        fix_table(tr, &table, pos)?;
    }
    Ok(tr.map(|tr| tr.transform.steps))
}

fn fix_table(tr: &mut Transaction, table: &Node, table_pos: usize) -> Result<bool> {
    let map = TableMap::get(table)?;
    let Some(problems) = &map.problems else { return Ok(false) };
    let mut must_add = vec![0usize; map.height];
    for problem in problems {
        match problem {
            Problem::Collision { row, pos, n } => {
                let Some(cell) = table.node_at(*pos) else { continue };
                for j in 0..attr_usize(&cell, "rowspan") {
                    if let Some(slot) = must_add.get_mut(row + j) {
                        *slot += n;
                    }
                }
                let colspan = attr_usize(&cell, "colspan");
                let attrs = remove_col_span(cell.attrs(), colspan.saturating_sub(*n), *n);
                let at = tr.mapping.map(table_pos + 1 + pos, 1);
                tr.set_node_markup(at, None, Some(&attrs), None)?;
            }
            Problem::Missing { row, n } => must_add[*row] += n,
            Problem::OverlongRowspan { pos, n } => {
                let Some(cell) = table.node_at(*pos) else { continue };
                let rowspan = cell.attr("rowspan").as_f64().unwrap_or(1.0);
                let attrs = with_attr(cell.attrs(), "rowspan", crate::source::js_number(rowspan - *n as f64));
                let at = tr.mapping.map(table_pos + 1 + pos, 1);
                tr.set_node_markup(at, None, Some(&attrs), None)?;
            }
            Problem::ColwidthMismatch { pos, colwidth } => {
                let Some(cell) = table.node_at(*pos) else { continue };
                let attrs = with_attr(cell.attrs(), "colwidth", Value::Array(colwidth.clone()));
                let at = tr.mapping.map(table_pos + 1 + pos, 1);
                tr.set_node_markup(at, None, Some(&attrs), None)?;
            }
            Problem::ZeroSized => {
                let pos = tr.mapping.map(table_pos, 1);
                tr.delete(pos, pos + table.node_size())?;
            }
        }
    }
    let (mut first, mut last) = (None, None);
    for (i, &add) in must_add.iter().enumerate() {
        if add > 0 {
            first.get_or_insert(i);
            last = Some(i);
        }
    }
    let mut pos = table_pos + 1;
    for (i, &add) in must_add.iter().enumerate() {
        let row = table.child(i);
        let end = pos + row.node_size();
        if add > 0 {
            let role = row.first_child().and_then(table_role).unwrap_or("cell");
            let mut nodes = Vec::new();
            for _ in 0..add {
                if let Some(node) = create_and_fill(role_type(role), None)? {
                    nodes.push(node);
                }
            }
            let side = if (i == 0 || first == Some(i - 1)) && last == Some(i) { pos + 1 } else { end - 1 };
            let at = tr.mapping.map(side, 1);
            tr.insert(at, Fragment::from_array(nodes))?;
        }
        pos = end;
    }
    Ok(true)
}

/// `removeCoveredContentEditTableRow` (editor-table.js): an empty row whose
/// columns are all covered by row spans from above is removed.
pub fn remove_covered_row(tr: &mut Transaction) -> Result<bool> {
    let doc = tr.doc.clone();
    let mut found: Option<(Node, usize)> = None;
    let mut failure: Option<crate::Error> = None;
    doc.descendants(&mut |table, table_pos, _, _| {
        if found.is_some() || failure.is_some() {
            return false;
        }
        if table_role(table) != Some("table") {
            return true;
        }
        let map = match TableMap::get(table) {
            Ok(m) => m,
            Err(e) => {
                failure = Some(e);
                return false;
            }
        };
        let mut row_start = 0;
        for row in 0..table.child_count() {
            let node = table.child(row);
            if node.child_count() == 0 && row > 0 && row < map.height {
                let covering: Vec<usize> = {
                    let mut seen = Vec::new();
                    for col in 0..map.width {
                        let p = map.map[row * map.width + col];
                        if !seen.contains(&p) {
                            seen.push(p);
                        }
                    }
                    seen
                };
                if covering.iter().all(|&p| p < row_start) {
                    found = Some((table.clone(), table_pos));
                    return false;
                }
            }
            row_start += node.node_size();
        }
        true
    });
    if let Some(e) = failure {
        return Err(e);
    }
    let Some((table, table_pos)) = found else { return Ok(false) };
    let map = TableMap::get(&table)?;
    let mut row_start = 0;
    for row in 0..table.child_count() {
        let node = table.child(row);
        if node.child_count() == 0 && row > 0 && row < map.height {
            let mut covering = Vec::new();
            for col in 0..map.width {
                let p = map.map[row * map.width + col];
                if !covering.contains(&p) {
                    covering.push(p);
                }
            }
            if covering.iter().all(|&p| p < row_start) {
                for &p in &covering {
                    let cell = table.node_at(p).expect("cell");
                    let rowspan = cell.attr("rowspan").as_f64().unwrap_or(1.0);
                    let attrs = with_attr(cell.attrs(), "rowspan", crate::source::js_number(rowspan - 1.0));
                    tr.set_node_markup(table_pos + 1 + p, None, Some(&attrs), None)?;
                }
                tr.delete(table_pos + 1 + row_start, table_pos + 1 + row_start + node.node_size())?;
                return Ok(true);
            }
        }
        row_start += node.node_size();
    }
    Ok(false)
}
