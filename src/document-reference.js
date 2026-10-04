/** Bounded authored EntityRef source shared by the optional v3 projection. */
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const projections = new Set(['link', 'chip', 'card']);

export function parseEntityReferenceSource(source) {
  if (typeof source !== 'string' || source.length > 16_384) return null;
  const match = source.match(/^@EntityRef\s*\(([\s\S]*?)\)\s*\{(?:\r\n|\n|\r)  ([^\r\n{}]+)(?:\r\n|\n|\r)\}$/u);
  if (!match) return null;
  const attrs = {};
  let rest = match[1].trim();
  while (rest) {
    const key = rest.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*/u);
    if (!key || !['id', 'label', 'projection'].includes(key[1]) || Object.hasOwn(attrs, key[1])) return null;
    rest = rest.slice(key[0].length);
    const value = rest.match(/^"(?:\\.|[^"\\])*"/u);
    if (!value) return null;
    try { attrs[key[1]] = JSON.parse(value[0]); } catch { return null; }
    if (typeof attrs[key[1]] !== 'string') return null;
    rest = rest.slice(value[0].length).trimStart();
    if (!rest) break;
    if (!rest.startsWith(',')) return null;
    rest = rest.slice(1).trimStart();
    if (!rest) return null;
  }
  if (typeof attrs.id !== 'string' || !attrs.id.startsWith('entity:')) return null;
  const entityId = attrs.id.slice('entity:'.length);
  if (!uuid.test(entityId)) return null;
  const projection = attrs.projection || 'link';
  if (!projections.has(projection)) return null;
  const body = match[2];
  if (body !== body.trim() || /\[\[|\]\]|\]\(relay:|^[@#]/u.test(body)) return null;
  const label = attrs.label || body;
  if (!label || label !== label.trim() || /[\r\n]/u.test(label)) return null;
  return { id: attrs.id, entityId, label, projection, body, source };
}

export function assertEntityReferenceProps(props) {
  if (!props || typeof props !== 'object' || Array.isArray(props) ||
      Object.keys(props).some(key => !['id', 'label', 'projection', 'source'].includes(key))) {
    throw new TypeError('Unsupported entity reference props');
  }
  const parsed = parseEntityReferenceSource(props.source);
  if (!parsed || parsed.id !== props.id || parsed.label !== props.label ||
      parsed.projection !== props.projection) {
    throw new TypeError('Entity reference source/identity mismatch');
  }
  return parsed;
}
