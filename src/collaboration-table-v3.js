/** Optional relaymark-prosemirror-v3 table projection; no live profile admits it. */

const blockId = /^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/u;
const alignments = new Set([null, "left", "center", "right"]);
const maxRows = 256;
const maxColumns = 256;
const maxCells = 4096;

export function tableProseMirrorToRelayMark(prosemirror) {
  assertObject(prosemirror, "doc");
  onlyKeys(prosemirror, ["type", "content"], "doc");
  requireType(prosemirror, "doc");
  const seen = new Set();
  const blocks = children(prosemirror, "doc", 1).map(node => mapTable(node, seen));
  for (const block of blocks) validateGrid(block);
  return { type: "relaymark.document", version: 1, blocks };
}

export function relayMarkTableToProseMirror(document) {
  assertObject(document, "document");
  onlyKeys(document, ["type", "version", "blocks"], "document");
  if (document.type !== "relaymark.document" || document.version !== 1) {
    throw new TypeError("Expected a RelayMark v1 AST document");
  }
  const seen = new Set();
  const blocks = children({ content: document.blocks }, "document", 1);
  for (const block of blocks) validateGrid(block);
  return { type: "doc", content: blocks.map(block => unmapTable(block, seen)) };
}

function mapTable(node, seen) {
  checkNode(node, "table", seen);
  return { id: node.attrs.relaymarkId, type: "table", content: children(node, "table", 1)
    .map(row => mapRow(row, seen)) };
}

function mapRow(node, seen) {
  checkNode(node, "tableRow", seen);
  return { id: node.attrs.relaymarkId, type: "table_row", content: children(node, "tableRow", 1)
    .map(cell => mapCell(cell, seen)) };
}

function mapCell(node, seen) {
  assertObject(node, "table cell");
  if (node.type !== "tableCell" && node.type !== "tableHeader") {
    throw new TypeError(`Unsupported table child: ${String(node.type)}`);
  }
  checkNode(node, node.type, seen, ["colspan", "rowspan", "colwidth", "align"]);
  const { colspan, rowspan, colwidth, align } = node.attrs;
  checkCellProps({ colspan, rowspan, colwidth, align });
  return {
    id: node.attrs.relaymarkId,
    type: "table_cell",
    props: { header: node.type === "tableHeader", colspan, rowspan, colwidth, align },
    content: children(node, node.type, 1).map(paragraph => mapParagraph(paragraph, seen))
  };
}

function mapParagraph(node, seen) {
  checkNode(node, "paragraph", seen);
  return { id: node.attrs.relaymarkId, type: "paragraph", content: inlineChildren(node, "paragraph")
    .map(child => mapText(child)) };
}

function mapText(node) {
  assertObject(node, "text");
  onlyKeys(node, ["type", "text"], "text");
  requireType(node, "text");
  if (typeof node.text !== "string" || node.text.length === 0) {
    throw new TypeError("Text must be a nonempty string");
  }
  return { type: "text", text: node.text };
}

function unmapTable(block, seen) {
  checkBlock(block, "table", seen);
  return { type: "table", attrs: { relaymarkId: block.id }, content: children(block, "table", 1)
    .map(row => unmapRow(row, seen)) };
}

function unmapRow(block, seen) {
  checkBlock(block, "table_row", seen);
  return { type: "tableRow", attrs: { relaymarkId: block.id }, content: children(block, "table_row", 1)
    .map(cell => unmapCell(cell, seen)) };
}

function unmapCell(block, seen) {
  checkBlock(block, "table_cell", seen, true);
  const props = block.props;
  assertObject(props, "table_cell.props");
  onlyKeys(props, ["header", "colspan", "rowspan", "colwidth", "align"], "table_cell.props");
  if (typeof props.header !== "boolean") throw new TypeError("table_cell.header must be boolean");
  checkCellProps(props);
  return {
    type: props.header ? "tableHeader" : "tableCell",
    attrs: {
      relaymarkId: block.id,
      colspan: props.colspan,
      rowspan: props.rowspan,
      colwidth: props.colwidth,
      align: props.align
    },
    content: children(block, "table_cell", 1).map(paragraph => unmapParagraph(paragraph, seen))
  };
}

function unmapParagraph(block, seen) {
  checkBlock(block, "paragraph", seen);
  return { type: "paragraph", attrs: { relaymarkId: block.id },
    content: inlineChildren(block, "paragraph").map(text => unmapText(text)) };
}

function unmapText(node) {
  assertObject(node, "text");
  onlyKeys(node, ["type", "text"], "text");
  requireType(node, "text");
  if (typeof node.text !== "string" || node.text.length === 0) {
    throw new TypeError("Text must be a nonempty string");
  }
  return { type: "text", text: node.text };
}

function checkNode(node, type, seen, additionalAttrs = []) {
  assertObject(node, type);
  onlyKeys(node, ["type", "attrs", "content"], type);
  requireType(node, type);
  assertObject(node.attrs, `${type}.attrs`);
  onlyKeys(node.attrs, ["relaymarkId", ...additionalAttrs], `${type}.attrs`);
  checkId(node.attrs.relaymarkId, seen);
}

function checkBlock(block, type, seen, hasProps = false) {
  assertObject(block, type);
  onlyKeys(block, hasProps ? ["id", "type", "props", "content"] : ["id", "type", "content"], type);
  requireType(block, type);
  checkId(block.id, seen);
}

function checkCellProps(props) {
  if (!Number.isSafeInteger(props.colspan) || props.colspan < 1 ||
      !Number.isSafeInteger(props.rowspan) || props.rowspan < 1) {
    throw new TypeError("Cell spans must be positive safe integers");
  }
  if (props.colwidth !== null &&
      (!Array.isArray(props.colwidth) || props.colwidth.length !== props.colspan ||
       props.colwidth.some(width => !Number.isSafeInteger(width) || width < 1))) {
    throw new TypeError("Cell colwidth must be null or one positive width per spanned column");
  }
  if (!alignments.has(props.align)) {
    throw new TypeError("Cell align must be null, left, center, or right");
  }
}

function checkId(id, seen) {
  if (typeof id !== "string" || !blockId.test(id)) throw new TypeError("Missing or invalid relaymarkId");
  if (seen.has(id)) throw new TypeError(`Duplicate relaymarkId: ${id}`);
  seen.add(id);
}

function children(node, label, minimum = 0) {
  if (!Array.isArray(node.content) || node.content.length < minimum) {
    throw new TypeError(`${label} requires an array of at least ${minimum} children`);
  }
  return node.content;
}

function inlineChildren(node, label) {
  if (node.content === undefined) return [];
  return children(node, label);
}

function validateGrid(table) {
  const rows = table.content;
  if (rows.length > maxRows || rows.reduce((count, row) => count + row.content.length, 0) > maxCells) {
    throw new TypeError("Table exceeds the draft row/cell limit");
  }
  const occupied = [];
  let expectedWidth;
  for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    const slots = occupied[rowIndex] || [];
    let column = 0;
    for (const cell of rows[rowIndex].content) {
      while (slots[column]) column++;
      const { colspan, rowspan } = cell.props;
      if (colspan > maxColumns || column + colspan > maxColumns) {
        throw new TypeError("Table exceeds the draft column limit");
      }
      if (rowIndex + rowspan > rows.length) throw new TypeError("Cell rowspan exceeds table rows");
      for (let r = rowIndex; r < rowIndex + rowspan; r++) {
        occupied[r] ||= [];
        for (let c = column; c < column + colspan; c++) {
          if (occupied[r][c]) throw new TypeError("Overlapping table cells");
          occupied[r][c] = true;
        }
      }
      column += colspan;
    }
    const width = occupied[rowIndex].length;
    if (expectedWidth === undefined) expectedWidth = width;
    if (width !== expectedWidth || Array.from({ length: width }, (_, c) => occupied[rowIndex][c]).some(slot => !slot)) {
      throw new TypeError("Table rows must form a complete rectangle");
    }
  }
}

function requireType(node, type) {
  if (node.type !== type) throw new TypeError(`Expected ${type}, got ${String(node.type)}`);
}

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
}

function onlyKeys(object, allowed, label) {
  for (const key of Object.keys(object)) {
    if (!allowed.includes(key)) throw new TypeError(`Unsupported ${label} field: ${key}`);
  }
}
