import { copyFile, mkdir } from 'node:fs/promises'
import { build } from 'esbuild'
import { historyHookPlugin } from './yjs-history-hook.mjs'
await build({ plugins: [historyHookPlugin], entryPoints: ['adapters/collaboration/runtime.js'], bundle: true, format: 'iife', platform: 'browser', target: 'es2020', minify: true, legalComments: 'inline', outfile: 'adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js' })

// Ship caller-owned adapters as modules importing the host's single Yjs instance.
await mkdir('adapters/elixir/priv/collaboration', { recursive: true })
for (const name of ['text-items.js', 'prose-operation.js', 'prose-lineage.js', 'history-lineage.js', 'placement-lineage.js', 'format-attribution-cut.js', 'format-attribution.js']) {
  await copyFile(`adapters/collaboration/${name}`, `adapters/elixir/priv/collaboration/${name}`)
}
// Browser build tools must apply this same exact-version hook to host Yjs.
await copyFile('scripts/yjs-history-hook.mjs', 'adapters/elixir/priv/collaboration/yjs-history-hook.mjs')
