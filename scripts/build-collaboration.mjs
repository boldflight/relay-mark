import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { build } from 'esbuild'
import { historyHookPlugin } from './yjs-history-hook.mjs'
const directives = await Promise.all((await readdir('spec/relaymark/directives')).filter(name => name.endsWith('.json')).sort().map(async name => JSON.parse(await readFile('spec/relaymark/directives/'+name,'utf8'))))
await writeFile('src/directive-registry.js', '// Generated from spec/relaymark/directives. Never edit independently.\nexport const directiveSpecifications = '+JSON.stringify(directives)+';\n')
await build({ plugins: [historyHookPlugin], entryPoints: ['adapters/collaboration/runtime.js'], bundle: true, format: 'iife', platform: 'browser', target: 'es2020', minify: true, legalComments: 'inline', outfile: 'adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js' })

// Ship caller-owned adapters as modules importing the host's single Yjs instance.
await mkdir('adapters/elixir/priv/collaboration', { recursive: true })
for (const name of ['text-items.js', 'prose-operation.js', 'prose-lineage.js', 'history-lineage.js', 'placement-lineage.js', 'format-attribution-cut.js', 'format-attribution.js', 'format-attribution-replay.js', 'attribution-record-codec.js', 'collaboration-runtime.js']) {
  await copyFile(`adapters/collaboration/${name}`, `adapters/elixir/priv/collaboration/${name}`)
}
// Browser build tools must apply this same exact-version hook to host Yjs.
await copyFile('scripts/yjs-history-hook.mjs', 'adapters/elixir/priv/collaboration/yjs-history-hook.mjs')

// Canonical portable contract/grammar adapters are shipped, not imported from a Git checkout's src tree.
for (const name of ['contract.js', 'document-directives.js', 'registry.js', 'directive-registry.js', 'document-adapter.js', 'document-inline.js', 'document-links.js', 'document-atoms.js', 'document-reference.js', 'document-controls.js', 'document-suggestion.js']) {
  await copyFile(`src/${name}`, `adapters/elixir/priv/collaboration/${name}`)
}

await build({ entryPoints: ['src/document-source.js'], bundle: true, format: 'esm', platform: 'browser', target: 'es2023', supported: { 'template-literal': false }, external: ['./document-adapter.js'], minify: true, legalComments: 'inline', outfile: 'adapters/elixir/priv/collaboration/document-source.js' })

await mkdir('adapters/swift/Sources/RelayMarkSwift/Resources', { recursive: true })
await build({ entryPoints: ['src/document-source.js'], bundle: true, format: 'iife', globalName: 'RelayMarkSourceRuntime', platform: 'browser', target: 'es2023', supported: { 'template-literal': false }, minify: true, legalComments: 'inline', outfile: 'adapters/swift/Sources/RelayMarkSwift/Resources/document-source.js' })

await build({ entryPoints: ['src/document-url.js'], bundle: true, format: 'esm', platform: 'browser', target: 'es2023', minify: true, legalComments: 'inline', outfile: 'adapters/elixir/priv/collaboration/document-url.js' })
