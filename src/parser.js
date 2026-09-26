import { parseAttributes } from "./attributes.js";

export function parseRelayMark(source) {
  const normalized = source.replace(/\r\n?/g, "\n");
  const { frontmatter, body } = parseFrontmatter(normalized);
  const lines = body.split("\n");
  const skippedLines = normalized.slice(0, normalized.length - body.length).split("\n").length - 1;
  const state = { diagnostics: [], rawLines:
    (source.match(/[^\r\n]*(?:\r\n|\r|\n|$)/gu) || []).slice(skippedLines) };
  const { blocks } = parseBlocks(lines, 0, state, false);
  return { frontmatter, blocks, diagnostics: state.diagnostics };
}

function parseFrontmatter(source) {
  if (!source.startsWith("---\n")) {
    return { frontmatter: {}, body: source };
  }

  const end = source.indexOf("\n---", 4);

  if (end === -1) {
    return { frontmatter: {}, body: source };
  }

  const raw = source.slice(4, end).trim();
  const body = source.slice(end + 4).replace(/^\n/, "");
  const frontmatter = {};

  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/);

    if (match) {
      frontmatter[match[1]] = stripQuotes(match[2].trim());
    }
  }

  return { frontmatter, body };
}

function parseBlocks(lines, start, state, stopOnClose) {
  const blocks = [];
  let index = start;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();

    if (!trimmed) {
      index += 1;
      continue;
    }

    if (trimmed === "}") {
      if (stopOnClose) {
        return { blocks, index: index + 1 };
      }

      state.diagnostics.push(critical("relaymark.syntax.unexpected_closing", "Unexpected closing directive brace.", index + 1));
      index += 1;
      continue;
    }

    if (trimmed.startsWith("@")) {
      const parsed = parseDirective(lines, index, state);
      blocks.push(parsed.block);
      index = parsed.index;
      continue;
    }

    const heading = trimmed.match(/^(#{1,6})\s+(.+)$/);

    if (heading) {
      blocks.push({
        kind: "heading",
        level: heading[1].length,
        text: heading[2],
        line: index + 1
      });
      index += 1;
      continue;
    }

    const paragraphLines = [];
    const startLine = index + 1;

    while (index < lines.length) {
      const candidate = lines[index].trim();

      if (!candidate || candidate === "}" || candidate.startsWith("@") || /^(#{1,6})\s+/.test(candidate)) {
        break;
      }

      paragraphLines.push(candidate);
      index += 1;
    }

    blocks.push({
      kind: "paragraph",
      text: paragraphLines.join(" "),
      line: startLine
    });
  }

  if (stopOnClose) {
    state.diagnostics.push(critical("relaymark.syntax.missing_closing", "Directive is missing a closing brace.", lines.length));
  }

  return { blocks, index };
}

function parseDirective(lines, start, state) {
  const headerLines = [];
  let index = start;

  while (index < lines.length) {
    headerLines.push(lines[index].trim());

    if (hasDirectiveBodyOpen(headerLines.join(" "))) {
      break;
    }

    index += 1;
  }

  const header = headerLines.join(" ");
  const match = header.match(/^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$/);

  if (!match) {
    state.diagnostics.push(critical("relaymark.syntax.invalid_directive", `Invalid directive header '${header}'.`, start + 1));
    return {
      block: {
        kind: "invalid_directive",
        name: "Invalid",
        attrs: {},
        children: [],
        line: start + 1
      },
      index: index + 1
    };
  }

  let attrs = {};

  try {
    attrs = parseAttributes(match[2] || "");
  } catch (error) {
    state.diagnostics.push(critical("relaymark.syntax.invalid_attributes", error.message, start + 1));
  }

  const childResult = parseBlocks(lines, index + 1, state, true);

  return {
    block: {
      kind: "directive",
      name: match[1],
      attrs,
      children: childResult.blocks,
      source: state.rawLines.slice(start, childResult.index).join("").replace(/(?:\r\n|\r|\n)$/u, ""),
      line: start + 1
    },
    index: childResult.index
  };
}

function hasDirectiveBodyOpen(header) {
  let parentheses = 0;
  let quote = false;
  let escape = false;

  for (const char of header) {
    if (escape) {
      escape = false;
      continue;
    }

    if (char === "\\") {
      escape = true;
      continue;
    }

    if (char === '"') {
      quote = !quote;
      continue;
    }

    if (quote) continue;
    if (char === "(") parentheses += 1;
    if (char === ")") parentheses -= 1;
    if (char === "{" && parentheses === 0) return true;
  }

  return false;
}

function stripQuotes(value) {
  if (value.startsWith('"') && value.endsWith('"')) {
    return JSON.parse(value);
  }

  return value;
}

function critical(code, message, line) {
  return {
    level: "critical",
    code,
    message,
    location: { line, column: 1 }
  };
}
