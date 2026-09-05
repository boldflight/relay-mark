import { build } from 'esbuild'
await build({ entryPoints: ['adapters/collaboration/runtime.js'], bundle: true, format: 'iife', platform: 'browser', target: 'es2020', minify: true, legalComments: 'inline', outfile: 'adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js' })
