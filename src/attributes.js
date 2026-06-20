export function parseAttributes(raw) {
  const text = raw.trim();

  if (!text) {
    return {};
  }

  const attributes = {};

  for (const part of splitTopLevel(text, ",")) {
    const trimmed = part.trim();

    if (!trimmed) {
      continue;
    }

    const colon = findTopLevelColon(trimmed);

    if (colon === -1) {
      throw new Error(`Invalid attribute '${trimmed}'`);
    }

    const key = trimmed.slice(0, colon).trim();
    const value = trimmed.slice(colon + 1).trim();

    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      throw new Error(`Invalid attribute name '${key}'`);
    }

    attributes[key] = parseValue(value);
  }

  return attributes;
}

function parseValue(value) {
  if (value === "true") return true;
  if (value === "false") return false;
  if (value === "null") return null;

  if (/^-?\d+(\.\d+)?$/.test(value)) {
    return Number(value);
  }

  if (value.startsWith('"') && value.endsWith('"')) {
    return JSON.parse(value);
  }

  if (value.startsWith("[") && value.endsWith("]")) {
    const inner = value.slice(1, -1).trim();
    return inner ? splitTopLevel(inner, ",").map((item) => parseValue(item.trim())) : [];
  }

  if (value.startsWith("{") && value.endsWith("}")) {
    const inner = value.slice(1, -1).trim();
    const object = {};

    for (const part of inner ? splitTopLevel(inner, ",") : []) {
      const colon = findTopLevelColon(part);

      if (colon === -1) {
        throw new Error(`Invalid object entry '${part}'`);
      }

      const key = part.slice(0, colon).trim().replace(/^"|"$/g, "");
      object[key] = parseValue(part.slice(colon + 1).trim());
    }

    return object;
  }

  throw new Error(`Unsupported attribute value '${value}'`);
}

function splitTopLevel(text, delimiter) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let quote = false;
  let escape = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

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

    if (quote) {
      continue;
    }

    if (char === "[" || char === "{" || char === "(") depth += 1;
    if (char === "]" || char === "}" || char === ")") depth -= 1;

    if (char === delimiter && depth === 0) {
      parts.push(text.slice(start, index));
      start = index + 1;
    }
  }

  parts.push(text.slice(start));
  return parts;
}

function findTopLevelColon(text) {
  let depth = 0;
  let quote = false;
  let escape = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

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

    if (quote) {
      continue;
    }

    if (char === "[" || char === "{" || char === "(") depth += 1;
    if (char === "]" || char === "}" || char === ")") depth -= 1;
    if (char === ":" && depth === 0) return index;
  }

  return -1;
}
