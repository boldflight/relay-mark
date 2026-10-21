// Curates an HTML import oracle: keeps the recorded HTML import calls whose
// input linkedom (the reference runtime's DOM) parses to the same tree as the
// engine's HTML-standard parser. Tag soup the two build differently is a
// parser difference, not an engine one.
//
//   RELAYMARK_DOM_CALLS=calls.jsonl RELAYMARK_DOM_OUTPUT=doms.jsonl \
//     cargo test --release -p relaymark-core --lib dump_doms -- --ignored
//   node crates/relaymark-core/tools/html-dom.mjs calls.jsonl doms.jsonl kept.jsonl
import { readFileSync, writeFileSync } from 'node:fs';
import { DOMParser } from 'linkedom/worker';

const [callsPath, domsPath, outPath] = process.argv.slice(2);
const order = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
function dump(element) {
  const children = [];
  for (const child of element.childNodes) {
    if (child.nodeType === 3) {
      if (typeof children.at(-1) === 'string') children[children.length - 1] += child.textContent;
      else children.push(child.textContent);
    } else if (child.nodeType === 1) children.push(dump(child));
    else children.push(['#comment']);
  }
  const attributes = [...element.attributes].map(a => [a.name, a.value]).sort((a, b) => order(a[0], b[0]) || order(a[1], b[1]));
  return [element.localName, attributes, children];
}
const body = text => {
  const document = new DOMParser().parseFromString(text, 'text/html');
  return document.body ? dump(document.body) : null;
};
const doms = readFileSync(domsPath, 'utf8').split('\n');
const kept = [];
let index = 0, dropped = 0;
for (const line of readFileSync(callsPath, 'utf8').split('\n')) {
  if (!line) continue;
  const call = JSON.parse(line);
  if (!call.fn.startsWith('document-html.')) continue;
  const engine = JSON.parse(doms[index++] || 'null');
  const html = typeof call.args[0]?.html === 'string' ? call.args[0].html : '';
  const wrapped = body('<html><head></head><body>' + html + '</body></html>');
  const whole = call.fn.endsWith('importClipboardHTML') && /<html[\s>]/i.test(html);
  const raw = whole ? body(html) : wrapped;
  const same = engine && JSON.stringify(engine[0]) === JSON.stringify(wrapped) && JSON.stringify(engine[1]) === JSON.stringify(raw);
  if (same) kept.push(line); else dropped++;
}
writeFileSync(outPath, kept.join('\n') + '\n');
console.error(`html-dom: kept ${kept.length}, dropped ${dropped}`);
