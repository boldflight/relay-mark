/** Canonical text-run mapping. Each mark wraps exactly one child, in schema order. */
import { safeLinkHref, linkAttributes, linkProperties, validateLinkAttributes } from './document-links.js';
import { mapAtom, unmapAtom } from './document-atoms.js';
export const textMarkNames = ["link", "bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript", "ai_authored"];
const markTypes = textMarkNames;
const inlineTypes = { link: "link", bold: "strong", code: "code_span",
  italic: "emphasis", strike: "strikethrough", underline: "underline",
  highlight: "highlight", superscript: "superscript", subscript: "subscript", ai_authored: "ai_authored" };
const pmTypes = Object.fromEntries(Object.entries(inlineTypes).map(([pm, ast]) => [ast, pm]));

function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError(`Invalid ${label}`);
  return value;
}

function keys(value, allowed, label) {
  for (const key of Object.keys(object(value, label))) {
    if (!allowed.includes(key)) throw new TypeError(`Unsupported ${label} field: ${key}`);
  }
}

// Text an agent run wrote carries its run (plan M5c). Only servers add it.
function runID(attrs) {
  keys(attrs, ["run_id"], "ai_authored attrs");
  if (typeof attrs.run_id !== "string" || !attrs.run_id || attrs.run_id.length > 64) throw new TypeError("Invalid ai_authored run_id");
  return attrs.run_id;
}

function href(value) {
  if (!safeLinkHref(value)) {
    throw new TypeError("Invalid link href");
  }
  return value;
}

/** Shared typing attributes use the same full rich mark/link validator as XML. */
export function validateTextAttributes(attributes){
 keys(attributes,markTypes,'typing attributes');
 const marks=markTypes.filter(type=>Object.hasOwn(attributes,type)).map(type=>{
  const value=object(attributes[type],'typing mark');
  if(type==='link'||type==='ai_authored')return {type,attrs:value};
  if(Object.keys(value).length)throw new TypeError('Unsupported typing mark attrs');
  return {type};
 });
 mapInline({type:'text',text:'x',marks});return true;
}

export function mapInline(node) {
  object(node, "inline");
  if (node.type === 'relayReference' || node.type === 'relayTag') return mapAtom(node);
  if (node.type === "hardBreak") {
    keys(node, ["type"], "hardBreak");
    return { type: "hard_break" };
  }
  keys(node, ["type", "text", "marks"], "text");
  if (node.type !== "text" || typeof node.text !== "string" || !node.text) {
    throw new TypeError("Expected nonempty text");
  }
  let result = { type: "text", text: node.text };
  const marks = node.marks ?? [];
  if (!Array.isArray(marks)) throw new TypeError("Invalid text marks");
  let previous = -1;
  for (const mark of marks) {
    keys(mark, ["type", "attrs"], "mark");
    const rank = markTypes.indexOf(mark.type);
    if (rank < 0 || rank <= previous || (mark.type === "code" && marks.length !== 1)) {
      throw new TypeError("Unsupported or noncanonical text marks");
    }
    previous = rank;
    if (mark.type === "link") {
      validateLinkAttributes(mark.attrs);
    } else if (mark.type === "ai_authored") {
      runID(mark.attrs);
    } else if (mark.attrs !== undefined) {
      throw new TypeError(`Unsupported ${mark.type} attrs`);
    }
  }
  for (const mark of marks.toReversed()) {
    result = { type: inlineTypes[mark.type],
      ...(mark.type === "link" ? { href: href(mark.attrs.href), ...(Object.keys(linkProperties(mark.attrs)).length ? {props:linkProperties(mark.attrs)} : {}) } : {}),
      ...(mark.type === "ai_authored" ? { run_id: runID(mark.attrs) } : {}), content: [result] };
  }
  return result;
}

export function unmapInline(node) {
  object(node, "inline");
  if (node.type === 'relay.entity_ref' || node.type === 'relay.tag_ref') return unmapAtom(node);
  if (node.type === "hard_break") {
    keys(node, ["type"], "hard_break");
    return { type: "hardBreak" };
  }
  const marks = [];
  let cursor = node;
  let previous = -1;
  while (cursor.type !== "text") {
    const pmType = pmTypes[cursor.type];
    const rank = markTypes.indexOf(pmType);
    if (rank < 0 || rank <= previous || (pmType === "code" && (marks.length || cursor.content?.[0]?.type !== "text"))) {
      throw new TypeError("Unsupported or noncanonical inline wrapper");
    }
    previous = rank;
    keys(cursor, pmType === "link" ? ["type", "href", "props", "content"] : pmType === "ai_authored" ? ["type", "run_id", "content"] : ["type", "content"], "inline wrapper");
    if (!Array.isArray(cursor.content) || cursor.content.length !== 1) throw new TypeError("Inline wrapper requires one child");
    marks.push(pmType === "link" ? { type: "link", attrs: linkAttributes(href(cursor.href), cursor.props) }
      : pmType === "ai_authored" ? { type: "ai_authored", attrs: { run_id: runID({ run_id: cursor.run_id }) } } : { type: pmType });
    cursor = object(cursor.content[0], "inline child");
  }
  keys(cursor, ["type", "text"], "text");
  if (typeof cursor.text !== "string" || !cursor.text) throw new TypeError("Expected nonempty text");
  return { type: "text", ...(marks.length ? { marks } : {}), text: cursor.text };
}
