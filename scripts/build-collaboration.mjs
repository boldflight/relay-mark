import { copyFile, mkdir } from 'node:fs/promises'
import { build } from 'esbuild'
await build({ entryPoints: ['adapters/collaboration/runtime.js'], bundle: true, format: 'iife', platform: 'browser', target: 'es2020', minify: true, legalComments: 'inline', outfile: 'adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js' })

// Ship the pure identity adapter without bundling a second Yjs runtime.
await mkdir('adapters/elixir/priv/collaboration', { recursive: true })
await copyFile('adapters/collaboration/text-items.js', 'adapters/elixir/priv/collaboration/text-items.js')
