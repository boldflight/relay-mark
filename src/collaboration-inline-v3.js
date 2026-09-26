/** Draft v3 text-run mapping. Each mark wraps exactly one child, in schema order. */
const markTypes = ["link", "bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript"];
const inlineTypes = { link: "link", bold: "strong", code: "code_span",
  italic: "emphasis", strike: "strikethrough", underline: "underline",
  highlight: "highlight", superscript: "superscript", subscript: "subscript" };
const pmTypes = Object.fromEntries(Object.entries(inlineTypes).map(([pm, ast]) => [ast, pm]));
const linkDefaults = { target: "_blank", rel: "noopener noreferrer nofollow", class: null, title: null };

function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError(`Invalid ${label}`);
  return value;
}

function keys(value, allowed, label) {
  for (const key of Object.keys(object(value, label))) {
    if (!allowed.includes(key)) throw new TypeError(`Unsupported ${label} field: ${key}`);
  }
}

function href(value) {
  if (typeof value !== "string" || !value || /[\u0000-\u001f\u007f<>]/u.test(value)) {
    throw new TypeError("Invalid link href");
  }
  return value;
}

export function mapV3Inline(node) {
  object(node, "inline");
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
      keys(mark.attrs, ["href", ...Object.keys(linkDefaults)], "link attrs");
      for (const [key, value] of Object.entries(linkDefaults)) {
        if (mark.attrs[key] !== value) throw new TypeError(`Unsupported link ${key}`);
      }
    } else if (mark.attrs !== undefined) {
      throw new TypeError(`Unsupported ${mark.type} attrs`);
    }
  }
  for (const mark of marks.toReversed()) {
    result = { type: inlineTypes[mark.type],
      ...(mark.type === "link" ? { href: href(mark.attrs.href) } : {}), content: [result] };
  }
  return result;
}

export function unmapV3Inline(node) {
  object(node, "inline");
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
    keys(cursor, pmType === "link" ? ["type", "href", "content"] : ["type", "content"], "inline wrapper");
    if (!Array.isArray(cursor.content) || cursor.content.length !== 1) throw new TypeError("Inline wrapper requires one child");
    marks.push(pmType === "link" ? { type: "link", attrs: { href: href(cursor.href), ...linkDefaults } } : { type: pmType });
    cursor = object(cursor.content[0], "inline child");
  }
  keys(cursor, ["type", "text"], "text");
  if (typeof cursor.text !== "string" || !cursor.text) throw new TypeError("Expected nonempty text");
  return { type: "text", ...(marks.length ? { marks } : {}), text: cursor.text };
}
