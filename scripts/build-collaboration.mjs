import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { build } from 'esbuild'
import {writeContractBindings} from './canonical-contract-bindings.mjs'
await writeContractBindings()
const attributeEncoding = JSON.parse(await readFile('spec/relaymark/xml-attribute-encoding.json','utf8'))
await writeFile('src/document-attribute-policy.js', "import {canonicalEditorSchema} from './editor-schema.js';\nimport {canonicalPhysicalSchemaHash} from './document-physical-schema.js';\n// Generated from spec/relaymark/xml-attribute-encoding.json.\nexport const xmlAttributeEncodingPolicy=Object.freeze("+JSON.stringify(attributeEncoding)+");\nexport function physicalAttributeSchemaHash(){return canonicalPhysicalSchemaHash(canonicalEditorSchema,xmlAttributeEncodingPolicy); }\n")
await copyFile('spec/relaymark/xml-attribute-encoding.json','adapters/elixir/priv/relaymark/xml-attribute-encoding.json')
const editorSchema = JSON.parse(await readFile('spec/relaymark/editor-schema.json','utf8'))
await writeFile('src/editor-schema.js', '// Generated from spec/relaymark/editor-schema.json. Never edit independently.\nexport const canonicalEditorSchema = '+JSON.stringify(editorSchema)+';\n')
await copyFile('spec/relaymark/editor-schema.json','adapters/elixir/priv/relaymark/editor-schema.json')
await writeFile('adapters/swift/Sources/RelayMarkModel/PMSchema.swift', 'import Foundation\n\n/// Generated from spec/relaymark/editor-schema.json. Never edit independently.\npackage enum RelayMarkNativeProseMirrorSchema {\n    package static let json = #"'+JSON.stringify(editorSchema)+'"#\n    package static let nodeAttributeOrder: [String: [String]] = '+JSON.stringify(Object.fromEntries(editorSchema.nodes.map(node=>[node.name,Object.keys(node.attrs??{})]))).replaceAll('{','[').replaceAll('}',']')+'\n    package static let markAttributeOrder: [String: [String]] = '+JSON.stringify(Object.fromEntries(editorSchema.marks.map(mark=>[mark.name,Object.keys(mark.attrs??{})]))).replaceAll('{','[').replaceAll('}',']')+'\n}\n')
const directives = await Promise.all((await readdir('spec/relaymark/directives')).filter(name => name.endsWith('.json')).sort().map(async name => JSON.parse(await readFile('spec/relaymark/directives/'+name,'utf8'))))
await writeFile('src/directive-registry.js', '// Generated from spec/relaymark/directives. Never edit independently.\nexport const directiveSpecifications = '+JSON.stringify(directives)+';\n')

await mkdir('adapters/elixir/priv/collaboration', { recursive: true })

// Canonical portable contract/grammar adapters are shipped, not imported from a Git checkout's src tree.
for (const name of ['document-html-rules.js', 'editor-schema.js', 'contract.js', 'document-directives.js', 'registry.js', 'directive-registry.js', 'document-adapter.js', 'document-inline.js', 'document-links.js', 'document-atoms.js', 'document-reference.js', 'document-controls.js', 'document-suggestion.js']) {
  await copyFile(`src/${name}`, `adapters/elixir/priv/collaboration/${name}`)
}

await build({ entryPoints: ['src/document-source.js'], bundle: true, format: 'esm', platform: 'browser', target: 'es2023', supported: { 'template-literal': false }, external: ['./document-adapter.js'], minify: true, legalComments: 'inline', outfile: 'adapters/elixir/priv/collaboration/document-source.js' })

// Editor-only schema and table helpers for stock-binding TipTap hosts. The
// shipped schema and HTML rules modules stay shared siblings, not inlined.
await build({ entryPoints: ['src/editor.js'], bundle: true, format: 'esm', platform: 'browser', target: 'es2020', external: ['prosemirror-model', 'prosemirror-tables', './document-html-rules.js', './editor-schema.js'], minify: true, legalComments: 'inline', outfile: 'adapters/elixir/priv/collaboration/editor.js' })

await build({ entryPoints: ['src/document-url.js'], bundle: true, format: 'esm', platform: 'browser', target: 'es2023', minify: true, legalComments: 'inline', outfile: 'adapters/elixir/priv/collaboration/document-url.js' })
