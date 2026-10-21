/** Strict, identity-bearing Relay inline atoms. Presentation/hydration is host-owned. */
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const entityType = /^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$/u;
// A normalized Relay tag name (spec/relaymark/conformance/tag-names.json).
const tagName = /^[\p{Ll}\p{Lm}\p{Lo}\p{M}\p{N}_][\p{Ll}\p{Lm}\p{Lo}\p{M}\p{N}_-]*$/u;

function object(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`Invalid ${label}`);
  return value;
}

function only(value, allowed, label) {
  for (const key of Object.keys(object(value, label))) {
    if (!allowed.includes(key)) throw new TypeError(`Unsupported ${label} field: ${key}`);
  }
}

function identity(id) {
  if (typeof id !== 'string' || !uuid.test(id)) throw new TypeError('Invalid canonical atom UUID');
  return id;
}

export function buildEntityReferenceSource({entityType: type, entityId: id, label}) {
  if (typeof type !== 'string' || !entityType.test(type) || type === 'Tag' || typeof label !== 'string' || !label) {
    throw new TypeError('Invalid authored reference label or type');
  }
  const quoted = label !== label.trim() || /[\r\n\[\]"\\`*_<>!]/u.test(label);
  // Escaped UTF-16 JSON avoids CommonMark consuming syntax inside an atomic label.
  const encoded = quoted ? '"'+label.split('').map(c=>'\\u'+c.charCodeAt(0).toString(16).padStart(4,'0')).join('')+'"' : label;
  return `[[${type}: ${identity(id)} | ${encoded}]]`;
}
function referenceSource(type,id,label) { return buildEntityReferenceSource({entityType:type,entityId:id,label}); }

function tagSource(id, name) {
  if (typeof name !== 'string' || !tagName.test(name)) throw new TypeError('Invalid authored tag name');
  return `[[Tag: ${identity(id)} | #${name}]]`;
}

export function mapAtom(node) {
  only(node, ['type', 'attrs'], 'atom');
  if (node.type === 'relayReference') {
    only(node.attrs, ['entityType', 'entityId', 'label', 'source', 'status', 'subtitle'], 'reference attrs');
    const { entityType: type, entityId: id, label, source, status, subtitle } = node.attrs;
    if (status != null || subtitle != null || source !== referenceSource(type, id, label)) {
      throw new TypeError('Unsupported reference hydration or source');
    }
    return { type: 'relay.entity_ref', id, label, props: { entityType: type, source } };
  }
  if (node.type === 'relayTag') {
    only(node.attrs, ['id', 'name', 'color', 'source'], 'tag attrs');
    const { id, name, color, source } = node.attrs;
    if (color != null || source !== tagSource(id, name)) throw new TypeError('Unsupported tag color or source');
    return { type: 'relay.tag_ref', id, label: `#${name}`, props: { name, source } };
  }
  throw new TypeError(`Unsupported inline atom ${String(node.type)}`);
}

export function unmapAtom(node) {
  if (node?.type === 'relay.entity_ref') {
    only(node, ['type', 'id', 'label', 'props'], 'reference');
    only(node.props, ['entityType', 'source'], 'reference props');
    const { entityType: type, source } = node.props;
    if (source !== referenceSource(type, node.id, node.label)) throw new TypeError('Reference source mismatch');
    return { type: 'relayReference', attrs: { entityType: type, entityId: node.id,
      label: node.label, source } };
  }
  if (node?.type === 'relay.tag_ref') {
    only(node, ['type', 'id', 'label', 'props'], 'tag');
    only(node.props, ['name', 'source'], 'tag props');
    const { name, source } = node.props;
    if (node.label !== `#${name}` || source !== tagSource(node.id, name)) throw new TypeError('Tag source mismatch');
    return { type: 'relayTag', attrs: { id: node.id, name, source } };
  }
  throw new TypeError(`Unsupported inline atom ${String(node?.type)}`);
}

export function parseAtomSource(source) {
  if (typeof source !== 'string') return null;
  const tag = source.match(/^\[\[Tag: ([^ ]+) \| #([^\]]+)\]\]$/u);
  if (tag) {
    try { return mapAtom({ type: 'relayTag', attrs: { id: tag[1], name: tag[2], color: null, source } }); }
    catch { return null; }
  }
  const reference = source.match(/^\[\[([^:]+): ([^ ]+) \| ([\s\S]+)\]\]$/u);
  if (reference) {
    try { return mapAtom({ type: 'relayReference', attrs: { entityType: reference[1], entityId: reference[2],
      label: reference[3].startsWith('"') ? JSON.parse(reference[3]) : reference[3], source, status: null, subtitle: null } }); }
    catch { return null; }
  }
  return null;
}

export function sourceForAtom(node) {
  return unmapAtom(node).attrs.source;
}
