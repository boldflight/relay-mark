// Module hooks that wrap every exported function of the JavaScript reference
// runtime (`src/*.js`) so each outermost call is recorded with its arguments
// and its result or error. Used by `record.mjs`; never loaded in production.
const SRC = new URL('../../../src/', import.meta.url).href;

export async function load(url, context, nextLoad) {
  const result = await nextLoad(url, context);
  if (!url.startsWith(SRC) || !url.endsWith('.js')) return result;
  const module = url.slice(SRC.length, -3);
  let source = String(result.source);
  const names = [];
  source = source.replace(/(^|\n)export function\s+([A-Za-z_$][\w$]*)/g, (_, lead, name) => {
    names.push(name);
    return `${lead}function ${name}`;
  });
  if (!names.length) return result;
  source += '\n' + names.map(name =>
    `const __rec_${name}=globalThis.__relaymarkRecord(${JSON.stringify(`${module}.${name}`)},${name});export{__rec_${name} as ${name}};`
  ).join('\n');
  return { ...result, source, shortCircuit: true };
}
