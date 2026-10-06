/** Authored Paper controls. Execution, destinations and hydration belong to hosts. */
const fields = { button: ['label', 'kind', 'target'], anchor: ['name'], connection: ['provider'] };
const names = { button: 'Button', anchor: 'Anchor', connection: 'Connection' };
const nodeNames = { button: 'relayButton', anchor: 'relayAnchor', connection: 'relayConnection' };
const anchorName = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}(?![\s\S])/u;
const providerName = /^[a-z][a-z0-9_-]*(?![\s\S])/u;
const command = /^\/[a-z][a-z0-9._-]*(?: [^\u0000-\u001f\u007f]+)?(?![\s\S])/u;
const safeLink = value => !/[\s\u0000-\u001f\u007f\\]/u.test(value) &&
  (/^\/(?!\/)/u.test(value) || /^https?:\/\/[^/?#]+/iu.test(value) || /^mailto:[^?]+/iu.test(value));

function object(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('Invalid paper control');
}

export function canonicalPaperControlSource(control, authored) {
  object(authored);
  const allowed = fields[control];
  if (!allowed || Object.keys(authored).length !== allowed.length ||
      Object.keys(authored).some(key => !allowed.includes(key)) ||
      allowed.some(key => typeof authored[key] !== 'string')) throw new TypeError('Invalid paper control fields');
  if (control === 'button' && (!authored.label.trim() || !['anchor', 'link', 'command'].includes(authored.kind) ||
      !(authored.kind === 'anchor' ? anchorName.test(authored.target) :
        authored.kind === 'link' ? safeLink(authored.target) : command.test(authored.target)))) {
    throw new TypeError('Invalid paper button');
  }
  if (control === 'anchor' && !anchorName.test(authored.name)) throw new TypeError('Invalid paper anchor');
  if (control === 'connection' && !providerName.test(authored.provider)) throw new TypeError('Invalid paper connection');
  const source = `@${names[control]}(${allowed.map(key => `${key}: ${JSON.stringify(authored[key])}`).join(', ')})`;
  if (source.length > 16_384) throw new TypeError('Paper control source exceeds the draft limit');
  return source;
}

export function assertPaperControlProps(props) {
  object(props);
  const { control, source, ...authored } = props;
  if (typeof source !== 'string' || source !== canonicalPaperControlSource(control, authored)) {
    throw new TypeError('Paper control source/fields mismatch');
  }
  return { control, authored, source };
}

export function paperControlNodeName(control) { return nodeNames[control]; }
export function paperControlKind(nodeName) { return Object.keys(nodeNames).find(key => nodeNames[key] === nodeName); }

export function parsePaperControlSource(source) {
  if (typeof source !== 'string' || source.length > 16_384) return null;
  const match = source.trim().match(/^@(Button|Anchor|Connection)\s*\(([\s\S]*)\)$/u);
  if (!match) return null;
  const control = Object.keys(names).find(key => names[key] === match[1]);
  const attrs = {};
  let rest = match[2].trim();
  while (rest) {
    const pair = rest.match(/^([a-z]+)\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*/u);
    if (!pair || Object.hasOwn(attrs, pair[1])) return null;
    try {
      attrs[pair[1]] = pair[2][0] === '"' ? JSON.parse(pair[2]) :
        pair[2].slice(1, -1).replace(/\\(['\\])/gu, '$1');
    } catch { return null; }
    rest = rest.slice(pair[0].length);
    if (!rest) break;
    if (!rest.startsWith(',')) return null;
    rest = rest.slice(1).trimStart();
    if (!rest) return null;
  }
  try {
    return { control, attrs, source: canonicalPaperControlSource(control, attrs) };
  } catch { return null; }
}

/** Original paper destinations by canonical tree ordinal. Names are interpreted
 * once in the original document; they never discover copied nodes by text. */
export function paperDocumentDestinations(document) {
  const nodes = [];
  const visit = (node, path) => {
    nodes.push({ node, path });
    (node.content || []).forEach((child, index) => visit(child, [...path, index]));
  };
  visit(document, []);
  const anchors = nodes.filter(({ node }) => node.type === 'relayAnchor' && typeof node.attrs?.name === 'string' && anchorName.test(node.attrs.name))
    .map(({ node, path }) => ({ source_path: path, kind: 'anchor', name: node.attrs.name }));
  const used = new Set(anchors.map(entry => entry.name));
  const text = node => node.type === 'text' ? node.text : (node.content || []).map(text).join('');
  const headings = nodes.filter(({ node }) => node.type === 'heading').map(({ node, path }) => {
    const base = text(node).trim().toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 110) || 'section';
    let name = typeof node.attrs?.headingId === 'string' && anchorName.test(node.attrs.headingId) ? node.attrs.headingId : base;
    const identity = name; let suffix = 2;
    while (used.has(name)) name = `${identity}-${suffix++}`;
    used.add(name);
    return { source_path: path, kind: 'heading', name };
  });
  return [...anchors, ...headings];
}
